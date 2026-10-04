#ifndef RUNNER_GAME_WINDOW_HOST_H_
#define RUNNER_GAME_WINDOW_HOST_H_
#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <string>

// Win32 implementation of the game frame boundary. No global Minecraft search:
// retain a validated process handle and only accept windows of that exact PID.
class GameWindowHost {
 public:
  GameWindowHost(DWORD pid, const std::wstring& executable);
  ~GameWindowHost();
  bool valid() const { return process_ != nullptr; }
  void Initialize(HWND frame, flutter::BinaryMessenger* messenger);
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  static BOOL CALLBACK FindWindow(HWND window, LPARAM context);
  void Poll();
  void Layout();
  void Focus();
  void CloseGame();
  DWORD pid_;
  HANDLE process_ = nullptr;
  HWND frame_ = nullptr;
  HWND game_ = nullptr;
  LONG_PTR original_style_ = 0;
  LONG_PTR original_ex_style_ = 0;
  RECT bounds_{};
  ULONGLONG started_ = 0;
  ULONGLONG closing_ = 0;
  bool ending_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
