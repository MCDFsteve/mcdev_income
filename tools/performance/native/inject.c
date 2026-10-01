/* Inject only our local graphics DLL into one local test game. */
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
int wmain(int argc, wchar_t **argv) {
    if (argc != 3) return 1;
    DWORD pid = 0;
    /* Process.start can return before Wine has registered the Windows image. */
    for (int attempt=0; attempt<40 && !pid; attempt++) {
        HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snapshot == INVALID_HANDLE_VALUE) { Sleep(250); continue; }
        PROCESSENTRY32W p = { .dwSize = sizeof(p) };
        if (Process32FirstW(snapshot, &p)) do {
            if (!_wcsicmp(p.szExeFile, L"Minecraft.Windows.exe")) {
                if (pid) {
                    CloseHandle(snapshot);
                    fprintf(stderr,"Multiple games; refusing injection.\n"); return 2;
                }
                pid = p.th32ProcessID;
            }
        } while (Process32NextW(snapshot, &p));
        CloseHandle(snapshot);
        if (!pid) Sleep(250);
    }
    if (!pid) return 3;
    HANDLE process = OpenProcess(SYNCHRONIZE|PROCESS_CREATE_THREAD|PROCESS_QUERY_INFORMATION|PROCESS_VM_OPERATION|PROCESS_VM_WRITE|PROCESS_VM_READ, FALSE, pid);
    if (!process) return 4;
    wchar_t image[32768];DWORD length=32768;
    if(!QueryFullProcessImageNameW(process,0,image,&length) || _wcsicmp(image,argv[2])){
        fprintf(stderr,"Game path mismatch; refusing injection.\n");CloseHandle(process);return 9;
    }
    /* Wait for normal initialization, without loading a DLL into the packed
     * startup path. ReadProcessMemory safely rejects uncommitted pages. */
    int ready=0;
    for(int attempt=0;attempt<360 && !ready;attempt++){
        if(WaitForSingleObject(process,0)==WAIT_OBJECT_0){CloseHandle(process);return 3;}
        HANDLE modules=CreateToolhelp32Snapshot(TH32CS_SNAPMODULE|TH32CS_SNAPMODULE32,pid);
        MODULEENTRY32W module={.dwSize=sizeof(module)};BYTE *base=NULL,*gl=NULL;
        if(Module32FirstW(modules,&module))do{
            if(!_wcsicmp(module.szModule,L"Minecraft.Windows.exe"))base=module.modBaseAddr;
            if(!_wcsicmp(module.szModule,L"opengl32.dll"))gl=module.modBaseAddr;
        }while(Module32NextW(modules,&module));CloseHandle(modules);
        BYTE bytes[6];SIZE_T got=0;void *pointer=NULL;
        if(base && gl && ReadProcessMemory(process,base+0x5c162e9,bytes,6,&got) && got==6 &&
           !memcmp(bytes,"\xff\x15\x39\x70\x23\x10",6) &&
           ReadProcessMemory(process,base+0x15e4d168,&pointer,sizeof(pointer),&got) &&
           pointer==gl+0x2d2a0)ready=1;
        else Sleep(250);
    }
    if(!ready){fprintf(stderr,"Supported graphics layout not ready; no injection.\n");CloseHandle(process);return 10;}
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
    printf("Local graphics DLL load result: %lx\n",result);
    VirtualFreeEx(process,remote,0,MEM_RELEASE);CloseHandle(thread);CloseHandle(process);
    return result ? 0 : 8;
}
