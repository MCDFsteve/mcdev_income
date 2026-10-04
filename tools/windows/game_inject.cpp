/* Windows PID-scoped injector for the 3.10.0.420447 LAN adapter.
 * MCDev contributors 2026, MIT. The executable hash is checked by Dart first. */
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <stdlib.h>
#include <filesystem>
int wmain(int argc, wchar_t **argv) {
    if (argc != 4) return 1;
    wchar_t *end = NULL;
    DWORD pid = wcstoul(argv[3], &end, 10);
    if (!pid || !end || *end) return 3;
    HANDLE process = OpenProcess(SYNCHRONIZE|PROCESS_CREATE_THREAD|PROCESS_QUERY_INFORMATION|PROCESS_VM_OPERATION|PROCESS_VM_WRITE|PROCESS_VM_READ, FALSE, pid);
    if (!process) return 4;
    wchar_t image[32768];DWORD length=32768;
    std::error_code path_error;
    if(!QueryFullProcessImageNameW(process,0,image,&length) ||
       !std::filesystem::equivalent(image,argv[2],path_error) || path_error){
        fprintf(stderr,"Game path mismatch; refusing injection.\n");CloseHandle(process);return 9;
    }
    /* Wait for normal initialization, without loading a DLL into the packed
     * startup path. ReadProcessMemory safely rejects uncommitted pages. */
    int ready=0;
    for(int attempt=0;attempt<360 && !ready;attempt++){
        if(WaitForSingleObject(process,0)==WAIT_OBJECT_0){CloseHandle(process);return 3;}
        HANDLE modules=CreateToolhelp32Snapshot(TH32CS_SNAPMODULE|TH32CS_SNAPMODULE32,pid);
        MODULEENTRY32W module={}; module.dwSize=sizeof(module);BYTE *base=NULL;
        if(Module32FirstW(modules,&module))do{
            if(!_wcsicmp(module.szModule,L"Minecraft.Windows.exe"))base=module.modBaseAddr;
        }while(Module32NextW(modules,&module));CloseHandle(modules);
        const BYTE signature[]={0x48,0x89,0x5c,0x24,0x20,0x55,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57,0x48,0x8d,0xac,0x24,0xe0,0xfd,0xff,0xff};
        BYTE bytes[sizeof(signature)];SIZE_T got=0;MEMORY_BASIC_INFORMATION region;
        BYTE *target=base ? base+0x0e65ac00 : NULL;
        if(target && VirtualQueryEx(process,target,&region,sizeof(region)) &&
           region.State==MEM_COMMIT &&
           (region.Protect & (PAGE_EXECUTE|PAGE_EXECUTE_READ|PAGE_EXECUTE_READWRITE|PAGE_EXECUTE_WRITECOPY)) &&
           ReadProcessMemory(process,target,bytes,sizeof(bytes),&got) && got==sizeof(bytes) &&
           !memcmp(bytes,signature,sizeof(signature)))ready=1;
        else Sleep(250);
    }
    if(!ready){fprintf(stderr,"Supported RenderDragon layout not ready; no injection.\n");CloseHandle(process);return 10;}
    SIZE_T size = (wcslen(argv[1])+1)*sizeof(wchar_t), written;
    void *remote = VirtualAllocEx(process,NULL,size,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    if (!remote || !WriteProcessMemory(process,remote,argv[1],size,&written) || written != size) {
        if(remote)VirtualFreeEx(process,remote,0,MEM_RELEASE);
        CloseHandle(process);return 5;
    }
    HANDLE thread = CreateRemoteThread(process,NULL,0,(LPTHREAD_START_ROUTINE)GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"LoadLibraryW"),remote,0,NULL);
    if (!thread) {
        fprintf(stderr,"CreateRemoteThread: %lu\n",GetLastError());
        VirtualFreeEx(process,remote,0,MEM_RELEASE);CloseHandle(process);return 6;
    }
    if (WaitForSingleObject(thread,15000) != WAIT_OBJECT_0) {
        /* The remote load may still use its path. Do not free it prematurely. */
        CloseHandle(thread);CloseHandle(process);return 7;
    }
    DWORD result = 0; GetExitCodeThread(thread,&result);
    printf("Local renderer DLL load result: %lx\n",result);
    VirtualFreeEx(process,remote,0,MEM_RELEASE);CloseHandle(thread);CloseHandle(process);
    return result ? 0 : 8;
}
