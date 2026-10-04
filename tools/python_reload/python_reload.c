/* Python safe-point adapter for the SHA-pinned 3.10.0.420447 x64 image.
 * The launcher-owned Python tick is inert until this DLL is injected. Only its
 * exact code name is intercepted, while CPython already owns the GIL/thread
 * state. Never run Python from DllMain or the injection worker. */
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "MinHook.h"

typedef struct { intptr_t refs; void *type; } PyObject;
typedef PyObject *(*EvalFrame)(void *, int);
typedef PyObject *(*RunString)(const char *, int, void *, void *, void *);
typedef void (*PrintError)(int);
static EvalFrame original_eval;
static RunString run_string;
static PrintError print_error;
static volatile LONG dispatching;
static const char sentinel[] = "_mcdev_native_reload_tick_310_v1";

static PyObject *eval_frame(void *frame, int throwflag) {
    /* PyFrameObject.f_code and PyCodeObject.co_name, verified in this build. */
    const BYTE *code = *(BYTE **)((BYTE *)frame + 0x20);
    const BYTE *name = *(BYTE **)(code + 0x58);
    if (!throwflag && *(intptr_t *)(name + 0x10) == sizeof(sentinel) - 1 &&
        !memcmp(name + 0x20, sentinel, sizeof(sentinel)) &&
        InterlockedCompareExchange(&dispatching, 1, 0) == 0) {
        void *globals = *(void **)((BYTE *)frame + 0x30);
        PyObject *result = run_string("_mcdev_dispatch()\n", 257, globals, globals, NULL);
        if (result) {
            if (--result->refs == 0) {
                void (*dealloc)(PyObject *) = *(void (**)(PyObject *))((BYTE *)result->type + 0x30);
                dealloc(result);
            }
        } else {
            print_error(0);
        }
        InterlockedExchange(&dispatching, 0);
    }
    return original_eval(frame, throwflag);
}

static int matches(BYTE *address, const BYTE *signature, SIZE_T size) {
    BYTE observed[32]; SIZE_T read = 0; MEMORY_BASIC_INFORMATION region;
    return size <= sizeof(observed) &&
        VirtualQuery(address, &region, sizeof(region)) &&
        region.State == MEM_COMMIT && !(region.Protect & PAGE_GUARD) &&
        (region.Protect & (PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)) &&
        ReadProcessMemory(GetCurrentProcess(), address, observed, size, &read) &&
        read == size && !memcmp(observed, signature, size);
}
static DWORD WINAPI setup(void *unused) {
    (void)unused;
    wchar_t log_path[32768];
    DWORD n = GetEnvironmentVariableW(L"MCDEV_PYTHON_RELOAD_LOG", log_path, 32768);
    if (!n || n >= 32768) return 1;
    FILE *log = _wfopen(log_path, L"w");
    if (!log) return 1;
    BYTE *base = (BYTE *)GetModuleHandleW(NULL);
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)base;
    if (!base || dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew < 0 || dos->e_lfanew > 0x1000) {
        fprintf(log, "{\"state\":\"unsupported\",\"reason\":\"image_header\"}\n");
        fclose(log); return 2;
    }
    IMAGE_NT_HEADERS64 *nt = (IMAGE_NT_HEADERS64 *)(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE ||
        nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64 ||
        nt->OptionalHeader.SizeOfImage != 0x1d28e000) {
        fprintf(log, "{\"state\":\"unsupported\",\"reason\":\"image_layout\"}\n");
        fclose(log); return 2;
    }
    const BYTE eval_signature[] = {0x40,0x55,0x56,0x41,0x57,0x48,0x8d,0x6c,0x24,0xb9,0x48,0x81,0xec,0x00,0x01,0x00};
    const BYTE run_signature[] = {0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x48,0x89,0x7c,0x24,0x20};
    const BYTE error_signature[] = {0x48,0x89,0x5c,0x24,0x18,0x55,0x48,0x8b,0xec,0x48,0x83,0xec,0x60};
    /* All Python entry points must be unpacked before any hook is installed. */
    int ready = 0;
    for (int attempt = 0; attempt < 6000; ++attempt) {
        if (matches(base + 0x0f7c0090, eval_signature, sizeof(eval_signature)) &&
            matches(base + 0x0f7dbc90, run_signature, sizeof(run_signature)) &&
            matches(base + 0x0f7da6e0, error_signature, sizeof(error_signature))) {
            ready = 1; break;
        }
        Sleep(10);
    }
    if (!ready) {
        fprintf(log, "{\"state\":\"unsupported\",\"reason\":\"python_signature\"}\n");
        fclose(log); return 3;
    }
    run_string = (RunString)(base + 0x0f7dbc90);
    print_error = (PrintError)(base + 0x0f7da6e0);
    MH_STATUS status = MH_Initialize();
    if (status == MH_OK) status = MH_CreateHook(base + 0x0f7c0090, eval_frame, (void **)&original_eval);
    if (status == MH_OK) status = MH_EnableHook(base + 0x0f7c0090);
    fprintf(log, "{\"state\":\"%s\",\"reason\":\"%s\"}\n", status == MH_OK ? "ready" : "failed", MH_StatusToString(status));
    fclose(log);
    return status == MH_OK ? 0 : 4;
}
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, void *reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
        HANDLE worker = CreateThread(NULL, 0, setup, NULL, 0, NULL);
        if (worker) CloseHandle(worker);
    }
    return TRUE;
}
