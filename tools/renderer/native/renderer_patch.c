/* Version-scoped RenderDragon / DXMT adapter. MIT, MCDev contributors 2026.
 * Leaves the downloaded game unchanged. Native capability checks remain active. */
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#define COBJMACROS
#include <d3d11.h>
#include "MinHook.h"

static FILE *log_file;
static BYTE *image;
static int vibrant_requested;
static int capability_logged;
static void *(*original_init)(void *,void *,void *);
static int (*original_deferred)(void);
static void (*original_shader_destroy)(void *);
static void (*original_structured_create)(void *,WORD,UINT,UINT,WORD);
static void (*original_structured_update)(void *,WORD,const void *);
static int structured_upload_logged;
static ID3D11DeviceContext *immediate_context;
static HRESULT (WINAPI *original_create_device)(IDXGIAdapter *,D3D_DRIVER_TYPE,HMODULE,UINT,
    const D3D_FEATURE_LEVEL *,UINT,UINT,ID3D11Device **,D3D_FEATURE_LEVEL *,ID3D11DeviceContext **);

static int renderer_type(void);
/* BGFX's 3.10 D3D11 structured table has 4096 32-byte entries. These
 * offsets are only used after the exact executable and entry signatures pass. */
typedef struct {
    ID3D11Buffer *buffer;
    ID3D11ShaderResourceView *srv;
    ID3D11UnorderedAccessView *uav;
    UINT byte_width;
    WORD flags;
    BYTE dynamic;
    BYTE padding;
} StructuredBuffer;
typedef struct { const void *data; UINT size; } BufferMemory;
static StructuredBuffer *structured_entry(void *renderer,WORD handle) {
    return (StructuredBuffer *)((BYTE *)renderer+0x55448)+(UINT)handle;
}
static void create_structured(void *renderer,WORD handle,UINT size,UINT stride,WORD flags) {
    /* This backend receives flags=0 for the deferred storage buffers. Its
     * default path creates a CPU-writable SRV without a UAV, although official
     * histogram/grid shaders bind them for compute writes. COMPUTE_WRITE
     * selects DEFAULT usage and creates both views using the original stride.
     * Do not add 0x400: that is DRAW_INDIRECT, not a compute access flag. */
    original_structured_create(renderer,handle,size,stride,flags|0x200);
    StructuredBuffer *entry=structured_entry(renderer,handle);
    fprintf(log_file,"{\"structured_buffer\":\"%s\",\"bytes\":%u,\"stride\":%u}\n",
        entry->buffer && entry->srv && entry->uav ? "ready":"failed",size,stride);
    fflush(log_file);
}
static void update_structured(void *renderer,WORD handle,const void *memory) {
    StructuredBuffer *entry=structured_entry(renderer,handle);
    const BufferMemory *source=memory;
    if(!entry->uav) {
        original_structured_update(renderer,handle,memory);
        return;
    }
    /* A DEFAULT/UAV resource cannot use the original WRITE_DISCARD upload.
     * UpdateSubresource copies the supplied bytes before returning and preserves
     * GPU ordering. Use a byte-range box so a short update keeps the tail. */
    ID3D11DeviceContext *context=*(ID3D11DeviceContext **)((BYTE *)renderer+0x350);
    if(source && source->size && source->data && source->size<=entry->byte_width) {
        D3D11_BOX box={0,0,0,source->size,1,1};
        ID3D11DeviceContext_UpdateSubresource(context,(ID3D11Resource *)entry->buffer,
            0,&box,source->data,0,0);
        if(!structured_upload_logged) {
            structured_upload_logged=1;
            fprintf(log_file,"{\"structured_upload\":\"default_resource\"}\n");fflush(log_file);
        }
    } else if(source && source->size) {
        fprintf(log_file,"{\"structured_upload\":\"invalid_range\"}\n");fflush(log_file);
    }
}

static HRESULT WINAPI capture_device(IDXGIAdapter *adapter,D3D_DRIVER_TYPE type,HMODULE software,UINT flags,
    const D3D_FEATURE_LEVEL *levels,UINT count,UINT sdk,ID3D11Device **device,D3D_FEATURE_LEVEL *selected,
    ID3D11DeviceContext **context) {
    HRESULT result=original_create_device(adapter,type,software,flags,levels,count,sdk,device,selected,context);
    // Borrow the renderer's context. Retaining it would itself break BGFX's
    // shutdown reference-count checks. Shader destruction precedes its release.
    if(SUCCEEDED(result) && context && *context)immediate_context=*context;
    return result;
}
static void destroy_shader(void *object) {
    void *shader=*(void **)object;
    int removed=0;
    // DXMT holds public references to bound shaders. BGFX requires Release=0
    // when it destroys one, so detach only this dying shader from its stage.
    // Keep every original Release and assertion; never falsify a refcount.
    if(immediate_context && shader) {
#define UNBIND(stage,type) do { \
        type *bound=NULL; \
        ID3D11DeviceContext_##stage##GetShader(immediate_context,&bound,NULL,NULL); \
        if(bound) { \
            if((void *)bound==shader) { \
                ID3D11DeviceContext_##stage##SetShader(immediate_context,NULL,NULL,0);removed++; \
            } \
            bound->lpVtbl->Release(bound); \
        } \
    } while(0)
        UNBIND(VS,ID3D11VertexShader);UNBIND(PS,ID3D11PixelShader);UNBIND(GS,ID3D11GeometryShader);
        UNBIND(HS,ID3D11HullShader);UNBIND(DS,ID3D11DomainShader);UNBIND(CS,ID3D11ComputeShader);
#undef UNBIND
    }
    if(removed) {
        fprintf(log_file,"{\"shader_cleanup_stages\":%d}\n",removed);fflush(log_file);
    }
    original_shader_destroy(object);
}

static int renderer_type(void) { return ((int (*)(void))(image+0x0e703540))(); }
static int deferred_supported(void) {
    int result=original_deferred();
    BYTE *caps=((void *(*)(void))(image+0x0e702f20))();
    uint64_t feature=((uint64_t (*)(void))(image+0x0e703550))();
    uint32_t mask=caps ? *(uint32_t *)(caps+0x238) : 0;
    /* This release excludes D3D11 in its backend whitelist. It ships official
     * SM5 bytecode for all deferred passes. Use the same native capability bit
     * as its Metal backend and require a real D3D11 feature level >= 11.0. */
    if(renderer_type()==2 && feature>=0xb000 && (mask & (1u<<20)))result=1;
    if(!capability_logged && renderer_type()==2) {
        capability_logged=1;
        fprintf(log_file,"{\"vibrant_supported\":%s,\"feature_level\":%llu,\"native_mask\":%lu}\n",
            result?"true":"false",(unsigned long long)feature,(unsigned long)mask);
        fflush(log_file);
    }
    return result;
}
static void *request_d3d11(void *context,void *state,void *description) {
    BYTE *desc=description;
    desc[16]=1;desc[17]=1; /* Existing RenderAPI::Direct3D11 selection. */
    void *result=original_init(context,state,description);
    int renderer=renderer_type();
    int deferred=renderer==2 ? deferred_supported() : 0;
    fprintf(log_file,"{\"renderer_patch\":\"%s\",\"backend\":%d,\"vibrant_requested\":%s,\"vibrant_supported\":%s}\n",
        renderer==2?"active":"failed",renderer,vibrant_requested?"true":"false",deferred?"true":"false");
    fflush(log_file);
    return result;
}
static int executable_signature(BYTE *address,const BYTE *bytes,size_t length) {
    MEMORY_BASIC_INFORMATION info;
    if(!VirtualQuery(address,&info,sizeof(info)) || info.State!=MEM_COMMIT ||
       !(info.Protect & (PAGE_EXECUTE|PAGE_EXECUTE_READ|PAGE_EXECUTE_READWRITE|PAGE_EXECUTE_WRITECOPY)))return 0;
    return !memcmp(address,bytes,length);
}
static DWORD WINAPI setup(void *module) {
    wchar_t path[32768];
    if(!GetEnvironmentVariableW(L"MCDEV_RENDERER_LOG",path,32768))return 1;
    log_file=_wfopen(path,L"w");if(!log_file)return 1;
    char flag[8]={0};GetEnvironmentVariableA("MCDEV_VIBRANT",flag,sizeof(flag));vibrant_requested=!strcmp(flag,"1");
    image=(BYTE *)GetModuleHandleW(NULL);
    IMAGE_NT_HEADERS64 *nt=(void *)(image+((IMAGE_DOS_HEADER *)image)->e_lfanew);
    if(nt->OptionalHeader.SizeOfImage!=0x1d28e000) {
        fprintf(log_file,"{\"renderer_patch\":\"unsupported\"}\n");fflush(log_file);return 2;
    }
    const BYTE init_signature[]={0x48,0x89,0x5c,0x24,0x20,0x55,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57,0x48,0x8d,0xac,0x24,0xe0,0xfd,0xff,0xff};
    const BYTE deferred_signature[]={0x40,0x53,0x48,0x83,0xec,0x30,0xe8,0x75,0x12,0x11,0x00};
    const BYTE destroy_signature[]={0x48,0x89,0x5c,0x24,0x10,0x56,0x48,0x83,0xec,0x30,0x48,0x8b,0x51,0x18};
    const BYTE structured_create_signature[]={0x48,0x83,0xec,0x38,0x0f,0xb7,0xc2,0x45,0x8b,0xd0,0x48,0xc1,0xe0,0x05,0x48,0x81,0xc1,0x48,0x54,0x05,0x00};
    const BYTE structured_update_signature[]={0x48,0x83,0xec,0x38,0x4d,0x8b,0x08,0x48,0x81,0xc1,0x48,0x54,0x05,0x00,0x45,0x8b,0x40,0x08};
    BYTE *init=image+0x0e65ac00,*deferred=image+0x0e5f1ca0,*destroy=image+0x0e736fc0,*structured_create=image+0x0e7366c0,*structured_update=image+0x0e745e40;
    for(int i=0;i<6000;i++) {
        if(executable_signature(init,init_signature,sizeof(init_signature)) &&
           executable_signature(deferred,deferred_signature,sizeof(deferred_signature)) &&
           executable_signature(destroy,destroy_signature,sizeof(destroy_signature)) &&
           executable_signature(structured_create,structured_create_signature,sizeof(structured_create_signature)) &&
           executable_signature(structured_update,structured_update_signature,sizeof(structured_update_signature))) {
            HMODULE d3d11=LoadLibraryW(L"d3d11.dll");
            void *create=d3d11 ? (void *)GetProcAddress(d3d11,"D3D11CreateDevice") : NULL;
            if(!create) {
                fprintf(log_file,"{\"renderer_patch\":\"failed\",\"reason\":\"d3d11_unavailable\"}\n");
                fflush(log_file);return 4;
            }
            MH_STATUS status=MH_Initialize();
            if(status==MH_OK)status=MH_CreateHook(create,capture_device,(void **)&original_create_device);
            if(status==MH_OK)status=MH_CreateHook(init,request_d3d11,(void **)&original_init);
            if(status==MH_OK)status=MH_CreateHook(deferred,deferred_supported,(void **)&original_deferred);
            if(status==MH_OK)status=MH_CreateHook(destroy,destroy_shader,(void **)&original_shader_destroy);
            if(status==MH_OK)status=MH_CreateHook(structured_create,create_structured,(void **)&original_structured_create);
            if(status==MH_OK)status=MH_CreateHook(structured_update,update_structured,(void **)&original_structured_update);
            if(status==MH_OK)status=MH_QueueEnableHook(create);
            if(status==MH_OK)status=MH_QueueEnableHook(init);
            if(status==MH_OK)status=MH_QueueEnableHook(deferred);
            if(status==MH_OK)status=MH_QueueEnableHook(destroy);
            if(status==MH_OK)status=MH_QueueEnableHook(structured_create);
            if(status==MH_OK)status=MH_QueueEnableHook(structured_update);
            if(status==MH_OK)status=MH_ApplyQueued();
            fprintf(log_file,"{\"renderer_patch\":\"%s\",\"hook_status\":%d}\n",status==MH_OK?"ready":"failed",status);
            fflush(log_file);return status!=MH_OK;
        }
        Sleep(10);
    }
    fprintf(log_file,"{\"renderer_patch\":\"unsupported\",\"reason\":\"signature_timeout\"}\n");fflush(log_file);return 3;
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,void *reserved) {
    if(reason==DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
        HANDLE thread=CreateThread(NULL,0,setup,module,0,NULL);if(thread)CloseHandle(thread);
    }
    return TRUE;
}
