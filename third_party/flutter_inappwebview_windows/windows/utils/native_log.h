#pragma once

#include <windows.h>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace flutter_inappwebview_plugin {
inline std::string NativeLogPath() {
  static std::string path;
  if (!path.empty()) {
    return path;
  }

  char buffer[MAX_PATH];
  DWORD len = ::GetEnvironmentVariableA("LOCALAPPDATA", buffer, MAX_PATH);
  std::string dir;
  if (len > 0 && len < MAX_PATH) {
    dir = std::string(buffer) + "\\ConsMelt\\logs";
  } else {
    dir = ".";
  }

  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  path = dir + "\\inappwebview_native.log";
  return path;
}

inline void NativeLog(const std::string& message) {
  try {
    const auto now = std::chrono::system_clock::now();
    const auto tt = std::chrono::system_clock::to_time_t(now);
    tm local_tm{};
    localtime_s(&local_tm, &tt);
    char timebuf[32];
    std::strftime(timebuf, sizeof(timebuf), "%Y-%m-%dT%H:%M:%S", &local_tm);

    std::ostringstream line;
    line << "[" << timebuf << "] " << message << "\n";

    const auto path = NativeLogPath();
    std::ofstream file(path, std::ios::app);
    if (file) {
      file << line.str();
      file.flush();
    }

    ::OutputDebugStringA(line.str().c_str());
  } catch (...) {
  }
}
}  // namespace flutter_inappwebview_plugin
