// Read-only inspection of a managed Windows game after a crash.
// No input injection, process suspension, symbol downloads or memory writes.
#include <windows.h>
#include <dbghelp.h>
#include <cstdio>
#include <cwchar>
#include <string>

static BOOL CALLBACK window_info(HWND window, LPARAM param) {
  DWORD pid = 0;
  const DWORD thread = GetWindowThreadProcessId(window, &pid);
  if (pid != static_cast<DWORD>(param)) return TRUE;
  wchar_t title[512] = {}, type[128] = {};
  GetWindowTextW(window, title, 512);
  GetClassNameW(window, type, 128);
  RECT rect = {};
  GetWindowRect(window, &rect);
  const HWND frame = GetAncestor(window, GA_ROOT);
  DWORD frame_pid = 0; GetWindowThreadProcessId(frame, &frame_pid);
  wchar_t frame_title[512] = {};
  GetWindowTextW(frame, frame_title, 512);
  DWORD_PTR icon = 0;
  SendMessageTimeout(frame, WM_GETICON, ICON_BIG, 0, SMTO_ABORTIFHUNG, 100, &icon);
  wprintf(L"embedded=%d borderless=%d frame_pid=%lu frame_icon=%d foreground=%d frame_title=%s\n",
          frame != window, (GetWindowLongW(window, GWL_STYLE) & WS_CAPTION) == 0,
          frame_pid, icon != 0, GetForegroundWindow() == frame, frame_title);
  wprintf(L"window=%p thread=%lu visible=%d enabled=%d hung=%d style=%08lx exstyle=%08lx owner=%p rect=%ld,%ld,%ld,%ld class=%s title=%s\n",
          window, thread, IsWindowVisible(window), IsWindowEnabled(window),
          IsHungAppWindow(window), GetWindowLongW(window, GWL_STYLE),
          GetWindowLongW(window, GWL_EXSTYLE), GetWindow(window, GW_OWNER),
          rect.left, rect.top, rect.right, rect.bottom, type, title);
  return TRUE;
}

static BOOL CALLBACK inspect_tree(HWND window, LPARAM param) {
  window_info(window, param);
  EnumChildWindows(window, window_info, param);
  return TRUE;
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 2 && argc != 3) {
    fwprintf(stderr, L"Usage: mcdev_game_diagnostics PID [CRASH_DUMP]\n");
    return 1;
  }
  const DWORD pid = wcstoul(argv[1], nullptr, 10);
  HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
  if (!process) return 2;
  wchar_t image[32768] = {};
  DWORD size = 32768;
  if (!QueryFullProcessImageNameW(process, 0, image, &size)) return 3;
  const wchar_t* filename = wcsrchr(image, L'\\');
  if (!filename || _wcsicmp(filename + 1, L"Minecraft.Windows.exe")) return 4;
  wprintf(L"image=%s\n", image);
  EnumWindows(inspect_tree, pid);
  if (argc == 2) { CloseHandle(process); return 0; }
  HANDLE file = CreateFileW(argv[2], GENERIC_READ, FILE_SHARE_READ, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return 5;
  HANDLE mapping = CreateFileMappingW(file, nullptr, PAGE_READONLY, 0, 0, nullptr);
  if (!mapping) return 6;
  void* data = MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);
  PMINIDUMP_DIRECTORY directory = nullptr;
  void* stream = nullptr;
  ULONG stream_size = 0;
  if (!data || !MiniDumpReadDumpStream(data, ExceptionStream, &directory,
                                      &stream, &stream_size)) return 7;
  auto* exception = static_cast<MINIDUMP_EXCEPTION_STREAM*>(stream);
  CONTEXT context = *reinterpret_cast<CONTEXT*>(
      static_cast<BYTE*>(data) + exception->ThreadContext.Rva);
  wprintf(L"exception=%08lx thread=%lu address=%016llx read_write=%llu target=%016llx\n",
          exception->ExceptionRecord.ExceptionCode, exception->ThreadId,
          exception->ExceptionRecord.ExceptionAddress,
          exception->ExceptionRecord.ExceptionInformation[0],
          exception->ExceptionRecord.ExceptionInformation[1]);
  std::wstring search(image, filename - image);
  search += L";C:\\Windows\\System32";
  SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS |
                SYMOPT_FAIL_CRITICAL_ERRORS | SYMOPT_NO_PROMPTS);
  if (!SymInitializeW(process, search.c_str(), TRUE)) return 8;
  STACKFRAME64 frame = {};
  frame.AddrPC.Offset = context.Rip;
  frame.AddrStack.Offset = context.Rsp;
  frame.AddrFrame.Offset = context.Rbp;
  frame.AddrPC.Mode = frame.AddrStack.Mode = frame.AddrFrame.Mode = AddrModeFlat;
  for (int i = 0; i < 48; ++i) {
    IMAGEHLP_MODULE64 module = {};
    module.SizeOfStruct = sizeof(module);
    const DWORD64 pc = frame.AddrPC.Offset;
    const bool found = SymGetModuleInfo64(process, pc, &module) != FALSE;
    char buffer[sizeof(SYMBOL_INFO) + MAX_SYM_NAME] = {};
    auto* symbol = reinterpret_cast<SYMBOL_INFO*>(buffer);
    symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
    symbol->MaxNameLen = MAX_SYM_NAME;
    DWORD64 displacement = 0;
    const bool named = SymFromAddr(process, pc, &displacement, symbol) != FALSE;
    printf("frame %02d %s+0x%llx %s+0x%llx\n", i,
           found ? module.ModuleName : "unknown",
           found ? pc - module.BaseOfImage : pc,
           named ? symbol->Name : "?", named ? displacement : 0);
    if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, nullptr, &frame,
                     &context, nullptr, SymFunctionTableAccess64,
                     SymGetModuleBase64, nullptr) || !frame.AddrPC.Offset) break;
  }
  SymCleanup(process);
  UnmapViewOfFile(data);
  CloseHandle(mapping);
  CloseHandle(file);
  CloseHandle(process);
  return 0;
}
