/* mcdev graphics patch v1; tested exclusively with 3.8.0.313229 x64.
 * Avoid synchronous writes to a GPU-in-use streaming buffer. The complete
 * contents are preserved in a CPU mirror and resubmitted into fresh storage.
 * No authentication, game rules, script execution, or error reporting changes.
 */
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "MinHook.h"

static void (WINAPI *buffer_data)(unsigned,intptr_t,const void*,unsigned);
static void (WINAPI *buffer_subdata)(unsigned,intptr_t,intptr_t,const void*);
static void (WINAPI *bind_buffer)(unsigned,unsigned);
static void (WINAPI *delete_buffers)(int,const unsigned*);
static void* (WINAPI *map_buffer)(unsigned,unsigned);
static void* (WINAPI *map_range)(unsigned,intptr_t,intptr_t,unsigned);
static unsigned char (WINAPI *unmap_buffer)(unsigned);
static void (WINAPI *copy_buffer)(unsigned,unsigned,intptr_t,intptr_t,intptr_t);
static void (WINAPI *end_feedback)(void);
static void (WINAPI *get_buffer)(unsigned,unsigned,int*);
static void (WINAPI *read_buffer)(unsigned,intptr_t,intptr_t,void*);
static PROC (WINAPI *get_proc)(LPCSTR);
static void (WINAPI *get_integer)(unsigned,int*);
static HGLRC (WINAPI *get_context)(void);
static BOOL (WINAPI *swap_buffers)(HDC);
static BOOL (WINAPI *qpc)(LARGE_INTEGER*);
static LARGE_INTEGER frequency;
static volatile LONG render_thread;
static HGLRC render_context;
static unsigned array_buffer;
static BYTE *mirror;
static int capacity,usage;
static volatile LONG dirty=1;
static FILE *log_file;
static LONG64 previous,frame,uploads,upload_ticks;
static double frame_times[120];
static int sample_count;
static int pace60=1;
static int ready,context_setup_attempted;

static LONG64 now(void){LARGE_INTEGER v;qpc(&v);return v.QuadPart;}
static void log_status(const char *state){if(log_file){fprintf(log_file,"{\"level\":\"INFO\",\"performance_patch\":\"%s\"}\n",state);fflush(log_file);}}
static int owner(void){return GetCurrentThreadId()==render_thread && get_context()==render_context;}
static void invalidate(void){InterlockedExchange(&dirty,1);}
static void WINAPI patch_bind(unsigned target,unsigned buffer){
    bind_buffer(target,buffer);
    if(owner() && target==0x8892)array_buffer=buffer;
}
static void WINAPI patch_data(unsigned target,intptr_t size,const void *data,unsigned hint){
    buffer_data(target,size,data,hint);invalidate();
}
static void WINAPI patch_delete(int count,const unsigned *ids){delete_buffers(count,ids);invalidate();}
static void* WINAPI patch_map(unsigned target,unsigned access){invalidate();return map_buffer(target,access);}
static void* WINAPI patch_map_range(unsigned target,intptr_t offset,intptr_t length,unsigned access){invalidate();return map_range(target,offset,length,access);}
static unsigned char WINAPI patch_unmap(unsigned target){invalidate();return unmap_buffer(target);}
static void WINAPI patch_copy(unsigned a,unsigned b,intptr_t x,intptr_t y,intptr_t size){copy_buffer(a,b,x,y,size);invalidate();}
static void WINAPI patch_end_feedback(void){end_feedback();invalidate();}
static void WINAPI patch_subdata(unsigned target,intptr_t offset,intptr_t size,const void *data){
    if(!ready || !owner() || target!=0x8892 || array_buffer!=1 || offset<0 || size<0 || !data){
        buffer_subdata(target,offset,size,data);
        /* Other contexts and buffer mutations must never leave stale mirrors. */
        if(target==0x8892)invalidate();
        return;
    }
    LONG64 start=now();
    if(InterlockedCompareExchange(&dirty,0,0)){
        int mapped=0,bytes=0;
        get_buffer(target,0x8764,&bytes);get_buffer(target,0x88bc,&mapped);
        if(bytes!=1048576 || mapped){buffer_subdata(target,offset,size,data);return;}
        if(!mirror)mirror=malloc(bytes);
        if(!mirror){buffer_subdata(target,offset,size,data);return;}
        capacity=bytes;get_buffer(target,0x8765,&usage);
        /* Exchange BEFORE readback: a concurrent modification stays dirty. */
        InterlockedExchange(&dirty,0);
        read_buffer(target,0,capacity,mirror);
    }
    if(size>capacity || offset>capacity-size){buffer_subdata(target,offset,size,data);invalidate();return;}
    if(InterlockedCompareExchange(&dirty,0,0)){buffer_subdata(target,offset,size,data);return;}
    memcpy(mirror+offset,data,size);
    buffer_data(target,capacity,mirror,usage);
    uploads++;upload_ticks+=now()-start;
}
static int compare_double(const void *a,const void *b){double x=*(const double*)a,y=*(const double*)b;return (x>y)-(x<y);}
static int hook(void *target,void *replacement,void **original);
static void setup_context_hooks(void){
    if(context_setup_attempted)return;context_setup_attempted=1;
    read_buffer=(void*)get_proc("glGetBufferSubData");
    if(!read_buffer ||
       !hook((void*)get_proc("glDeleteBuffers"),patch_delete,(void**)&delete_buffers) ||
       !hook((void*)get_proc("glMapBuffer"),patch_map,(void**)&map_buffer) ||
       !hook((void*)get_proc("glMapBufferRange"),patch_map_range,(void**)&map_range) ||
       !hook((void*)get_proc("glUnmapBuffer"),patch_unmap,(void**)&unmap_buffer) ||
       !hook((void*)get_proc("glCopyBufferSubData"),patch_copy,(void**)&copy_buffer) ||
       !hook((void*)get_proc("glEndTransformFeedback"),patch_end_feedback,(void**)&end_feedback) ||
       MH_EnableHook(MH_ALL_HOOKS)!=MH_OK){
        MH_DisableHook(MH_ALL_HOOKS);log_status("mutation_hooks_failed_normal_rendering_restored");return;
    }
    ready=1;log_status("active");
}
static BOOL WINAPI patch_swap(HDC dc){
    DWORD thread=GetCurrentThreadId();
    LONG existing=InterlockedCompareExchange(&render_thread,(LONG)thread,0);
    /* Secondary presentation threads keep their own original rendering path;
     * they must not race the mirror, frame statistics or the 60 Hz deadline. */
    if(existing && (DWORD)existing!=thread)return swap_buffers(dc);
    HGLRC context=get_context();
    if(context!=render_context){
        render_context=context;
        int current=0;
        get_integer(0x8894,&current);array_buffer=current;invalidate();previous=0;
    }
    if(context)setup_context_hooks();
    BOOL result=swap_buffers(dc);LONG64 end=now();
    if(ready && pace60 && previous){
        /* Wine's millisecond Sleep can introduce large deadline overshoots.
         * QPC pacing is bounded to the remaining part of one 60 Hz frame. */
        LONG64 deadline=previous+frequency.QuadPart/60;
        while(end<deadline){YieldProcessor();end=now();}
    }
    if(previous){
        frame_times[sample_count++]=(double)(end-previous)*1000/frequency.QuadPart;
        if(sample_count==120 && log_file){
            double sum=0;for(int n=0;n<120;n++)sum+=frame_times[n];
            int viewport[4]={0};get_integer(0x0ba2,viewport);
            qsort(frame_times,120,sizeof(double),compare_double);
            fprintf(log_file,"{\"level\":\"INFO\",\"frames\":120,\"fps\":%.3f,\"frame_ms_mean\":%.4f,\"frame_ms_p95\":%.4f,\"frame_ms_p99\":%.4f,\"upload_ms_per_frame\":%.4f,\"buffer_uploads\":%lld,\"viewport_width\":%d,\"viewport_height\":%d}\n",120000/sum,sum/120,frame_times[114],frame_times[118],(double)upload_ticks*1000/frequency.QuadPart/120,uploads,viewport[2],viewport[3]);
            fflush(log_file);sample_count=0;uploads=0;upload_ticks=0;
        } else if(sample_count==120){sample_count=0;uploads=0;upload_ticks=0;}
    }
    previous=end;frame++;return result;
}
static int hook(void *target,void *replacement,void **original){return target && MH_CreateHook(target,replacement,original)==MH_OK;}
static DWORD WINAPI initialize(void *unused){
    wchar_t path[32768];DWORD length=GetEnvironmentVariableW(L"MCDEV_PERFORMANCE_LOG",path,32768);
    if(!length){
        DWORD n=GetModuleFileNameW((HMODULE)unused,path,32768);
        if(n && n<32730){wchar_t *slash=wcsrchr(path,L'\\');if(slash){wcscpy(slash+1,L"performance.log");length=wcslen(path);}}
    }
    if(length && length<32768){log_file=_wfopen(path,L"w");if(log_file)setvbuf(log_file,NULL,_IOFBF,16384);}
    wchar_t limit[8];if(GetEnvironmentVariableW(L"MCDEV_PERFORMANCE_LIMIT",limit,8) && limit[0]==L'0')pace60=0;
    BYTE *base=(void*)GetModuleHandleW(NULL);HMODULE gl=NULL;
    for(int attempt=0;attempt<180;attempt++){
        gl=GetModuleHandleW(L"OPENGL32.dll");
        if(gl && !memcmp(base+0x5c162e9,"\xff\x15\x39\x70\x23\x10",6) &&
           *(void**)(base+0x15e4d2d8) && *(void**)(base+0x15e4d2e0) &&
           *(void**)(base+0x15e4d328) && *(void**)(base+0x15e4d168))break;
        Sleep(500);
    }
    if(!gl || memcmp(base+0x5c162e9,"\xff\x15\x39\x70\x23\x10",6) ||
       *(void**)(base+0x15e4d2d8)!=(BYTE*)gl+0xdbc0 ||
       *(void**)(base+0x15e4d2e0)!=(BYTE*)gl+0xd330 ||
       *(void**)(base+0x15e4d328)!=(BYTE*)gl+0x82d0 ||
       *(void**)(base+0x15e4d168)!=(BYTE*)gl+0x2d2a0){log_status("unsupported_runtime_layout");return 1;}
    get_proc=(void*)GetProcAddress(gl,"wglGetProcAddress");get_context=(void*)GetProcAddress(gl,"wglGetCurrentContext");
    get_integer=(void*)GetProcAddress(gl,"glGetIntegerv");
    qpc=QueryPerformanceCounter;QueryPerformanceFrequency(&frequency);
    get_buffer=*(void**)(base+0x15e4d168);
    /* The five verified core pointers are sufficient to attach safely. Additional
     * mutation hooks are installed on the GL thread before optimization starts. */
    if(MH_Initialize()!=MH_OK || !get_proc || !get_context || !get_integer || !get_buffer){log_status("hook_initialization_failed");return 2;}
    if(!hook(*(void**)(base+0x15e4d2d8),patch_subdata,(void**)&buffer_subdata) ||
       !hook(*(void**)(base+0x15e4d2e0),patch_data,(void**)&buffer_data) ||
       !hook(*(void**)(base+0x15e4d328),patch_bind,(void**)&bind_buffer) ||
       !hook(GetProcAddress(gl,"wglSwapBuffers"),patch_swap,(void**)&swap_buffers)){
        log_status("hook_creation_failed");return 3;
    }
    /* Readback and mutation functions need a current context. Their pointers
     * are captured through one initialization-only swap wrapper below. */
    log_status("waiting_for_gl_context");
    if(MH_EnableHook(MH_ALL_HOOKS)!=MH_OK){log_status("hook_enable_failed");return 4;}
    return 0;
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,void *reserved){
    if(reason==DLL_PROCESS_ATTACH){DisableThreadLibraryCalls(module);HANDLE thread=CreateThread(NULL,0,initialize,module,0,NULL);if(thread)CloseHandle(thread);}
    return TRUE;
}
