#include "game_window_host.h"
#include "resource.h"
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <filesystem>
#include <shellapi.h>
#include <shobjidl.h>

namespace {
constexpr UINT_PTR kPollTimer = 0x4d43;
void Status(const char* text) {
  DWORD written = 0;
  WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), text, static_cast<DWORD>(strlen(text)), &written, nullptr);
}
}

GameWindowHost::GameWindowHost(DWORD pid, const std::wstring& executable)
    : pid_(pid) {
  HANDLE candidate = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION |
      SYNCHRONIZE | PROCESS_TERMINATE, FALSE, pid);
  if (!candidate) return;
  wchar_t path[32768]; DWORD length = 32768;
  std::error_code error;
  const bool exact = QueryFullProcessImageNameW(candidate, 0, path, &length) &&
      std::filesystem::equivalent(path, executable, error) && !error &&
      _wcsicmp(std::filesystem::path(path).filename().c_str(),
               L"Minecraft.Windows.exe") == 0;
  if (exact) process_ = candidate;
  else CloseHandle(candidate);
}

GameWindowHost::~GameWindowHost() {
  if (frame_) KillTimer(frame_, kPollTimer);
  // A host failure must leave a usable native game window.
  if (game_ && IsWindow(game_) && !ending_) {
    SetParent(game_, nullptr);
    SetWindowLongPtr(game_, GWL_STYLE, original_style_);
    SetWindowLongPtr(game_, GWL_EXSTYLE, original_ex_style_);
    SetWindowPos(game_, nullptr, 80, 80, 1280, 720,
                 SWP_NOZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  }
  if (process_) CloseHandle(process_);
}

void GameWindowHost::Initialize(HWND frame, flutter::BinaryMessenger* messenger) {
  frame_ = frame;
  started_ = GetTickCount64();
  const auto icon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_GAME_ICON));
  SendMessage(frame, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(icon));
  SendMessage(frame, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(icon));
  // Separate taskbar identity from the manager; each host represents one test.
  SetCurrentProcessExplicitAppUserModelID(L"MCDev.TestGame");
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "mcdev_income/game_host", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "focus") Focus();
    else if (call.method_name() == "close") CloseGame();
    else if (call.method_name() == "sendKey") {
      const auto key = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (key && *key == "escape" && game_) {
        Focus();
        const LPARAM scan = static_cast<LPARAM>(MapVirtualKey(VK_ESCAPE, MAPVK_VK_TO_VSC)) << 16;
        PostMessage(game_, WM_KEYDOWN, VK_ESCAPE, 1 | scan);
        PostMessage(game_, WM_KEYUP, VK_ESCAPE, 1 | scan | (3LL << 30));
      }
    } else { result->NotImplemented(); return; }
    result->Success();
  });
  SetTimer(frame_, kPollTimer, 100, nullptr);
}

BOOL CALLBACK GameWindowHost::FindWindow(HWND window, LPARAM context) {
  auto self = reinterpret_cast<GameWindowHost*>(context);
  DWORD owner = 0; GetWindowThreadProcessId(window, &owner);
  if (owner != self->pid_ || GetWindow(window, GW_OWNER) || !IsWindowVisible(window)) return TRUE;
  wchar_t name[128]{}; GetClassName(window, name, 128);
  RECT area{}; GetClientRect(window, &area);
  // The game's OGLES/renderer window, never a crash dialog or SDK popup.
  if (area.right < 200 || area.bottom < 100 ||
      (wcsstr(name, L"OGLES") == nullptr && wcsstr(name, L"Minecraft") == nullptr)) return TRUE;
  DWORD_PTR response = 0;
  if (!SendMessageTimeout(window, WM_NULL, 0, 0, SMTO_ABORTIFHUNG, 50, &response)) return TRUE;
  self->game_ = window;
  return FALSE;
}

void GameWindowHost::Poll() {
  if (WaitForSingleObject(process_, 0) == WAIT_OBJECT_0) {
    ending_ = true; DestroyWindow(frame_); return;
  }
  if (closing_ && GetTickCount64() - closing_ > 20000) {
    // The handle remains bound to the owned process even if its PID is reused.
    TerminateProcess(process_, 1); return;
  }
  if (!game_) {
    EnumWindows(FindWindow, reinterpret_cast<LPARAM>(this));
    if (!game_) {
      if (GetTickCount64() - started_ > 120000) CloseGame();
      return;
    }
    original_style_ = GetWindowLongPtr(game_, GWL_STYLE);
    original_ex_style_ = GetWindowLongPtr(game_, GWL_EXSTYLE);
    ShowWindowAsync(game_, SW_RESTORE);
    SetWindowLongPtr(game_, GWL_STYLE,
        (original_style_ & ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME | WS_SYSMENU |
          WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_MINIMIZE | WS_MAXIMIZE)) |
          WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS);
    SetWindowLongPtr(game_, GWL_EXSTYLE,
        original_ex_style_ & ~(WS_EX_APPWINDOW | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE));
    SetLastError(0);
    SetParent(game_, frame_);
    if (GetLastError() != 0 && GetParent(game_) != frame_) {
      SetWindowLongPtr(game_, GWL_STYLE, original_style_);
      SetWindowLongPtr(game_, GWL_EXSTYLE, original_ex_style_);
      game_ = nullptr; CloseGame(); return;
    }
    SendMessageTimeout(game_, WM_CHANGEUISTATE, MAKEWPARAM(UIS_INITIALIZE, 0),
                        0, SMTO_ABORTIFHUNG, 100, nullptr);
    Layout();
    SetForegroundWindow(frame_);
    Focus();
    Status("MCDEV_WINDOW_READY\n");
  }
  Layout();
}

void GameWindowHost::Layout() {
  if (!game_ || !IsWindow(game_)) return;
  RECT area{}; GetClientRect(frame_, &area);
  const int top = MulDiv(48, GetDpiForWindow(frame_), 96);
  area.top = top;
  if (EqualRect(&area, &bounds_)) return;
  bounds_ = area;
  SetWindowPos(game_, HWND_TOP, 0, top, std::max(1L, area.right),
      std::max(1L, area.bottom - top), SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_ASYNCWINDOWPOS);
}

void GameWindowHost::Focus() {
  if (!game_) return;
  const DWORD thread = GetWindowThreadProcessId(game_, nullptr);
  const DWORD current = GetCurrentThreadId();
  if (thread != current) AttachThreadInput(current, thread, TRUE);
  SetFocus(game_);
  if (thread != current) AttachThreadInput(current, thread, FALSE);
}

void GameWindowHost::CloseGame() {
  if (closing_) return;
  closing_ = GetTickCount64();
  if (game_) PostMessage(game_, WM_CLOSE, 0, 0);
  else TerminateProcess(process_, 1);
}

bool GameWindowHost::HandleMessage(UINT message, WPARAM wparam, LPARAM) {
  if (message == WM_TIMER && wparam == kPollTimer) { Poll(); return true; }
  if (message == WM_CLOSE && !ending_) { CloseGame(); return true; }
  if (message == WM_ACTIVATE && LOWORD(wparam) != WA_INACTIVE && game_) {
    Focus(); return true;
  }
  return false;
}
