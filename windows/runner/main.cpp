#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <dbghelp.h>
#include <filesystem>
#include <string>
#include <system_error>

#include "flutter_window.h"
#include "utils.h"

namespace {
std::wstring GetCrashDumpDir() {
  wchar_t buffer[MAX_PATH];
  DWORD len = ::GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return L".";
  }
  std::wstring dir(buffer);
  dir += L"\\ConsMelt\\crash_dumps";
  return dir;
}

std::wstring BuildDumpPath(const std::wstring& dir) {
  SYSTEMTIME st;
  ::GetLocalTime(&st);
  wchar_t name[64];
  swprintf_s(name, L"cons_melt_%04d%02d%02d_%02d%02d%02d.dmp",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
  std::wstring path(dir);
  path += L"\\";
  path += name;
  return path;
}

void WriteMiniDump(EXCEPTION_POINTERS* exception_info) {
  const std::wstring dir = GetCrashDumpDir();
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  const std::wstring path = BuildDumpPath(dir);
  HANDLE file = ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }

  MINIDUMP_EXCEPTION_INFORMATION dump_info;
  dump_info.ThreadId = ::GetCurrentThreadId();
  dump_info.ExceptionPointers = exception_info;
  dump_info.ClientPointers = FALSE;

  ::MiniDumpWriteDump(::GetCurrentProcess(), ::GetCurrentProcessId(), file,
                      MiniDumpWithFullMemory, &dump_info, nullptr, nullptr);
  ::CloseHandle(file);
}

LONG WINAPI CrashHandler(EXCEPTION_POINTERS* exception_info) {
  WriteMiniDump(exception_info);
  return EXCEPTION_EXECUTE_HANDLER;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  ::SetUnhandledExceptionFilter(CrashHandler);
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Cons Melt", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
