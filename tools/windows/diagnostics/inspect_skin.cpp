// Read-only check for official skin pixels decoded in our test process.
// A match proves decoding only; it does not prove the player's selected skin.
// Does not capture the screen or write process memory. Never emits memory data.
#include <windows.h>
#include <algorithm>
#include <cstdio>
#include <cwchar>
#include <fstream>
#include <iterator>
#include <vector>

int wmain(int argc, wchar_t** argv) {
  if (argc != 3) return 1;
  const DWORD pid = wcstoul(argv[1], nullptr, 10);
  HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
                               FALSE, pid);
  if (!process) return 2;
  wchar_t path[32768] = {};
  DWORD size = 32768;
  if (!QueryFullProcessImageNameW(process, 0, path, &size)) return 3;
  const wchar_t* filename = wcsrchr(path, L'\\');
  if (!filename || _wcsicmp(filename + 1, L"Minecraft.Windows.exe")) return 4;
  std::ifstream input(argv[2], std::ios::binary);
  const std::vector<unsigned char> pixels((std::istreambuf_iterator<char>(input)),
                                          std::istreambuf_iterator<char>());
  if (pixels.size() != 64 * 64 * 4) return 5;
  auto bgra = pixels;
  for (size_t i = 0; i < bgra.size(); i += 4) std::swap(bgra[i], bgra[i + 2]);
  constexpr size_t block = 1024 * 1024;
  std::vector<unsigned char> bytes(block + pixels.size());
  MEMORY_BASIC_INFORMATION info = {};
  size_t decoded_rgba = 0, decoded_bgra = 0;
  for (uintptr_t address = 0;
       VirtualQueryEx(process, reinterpret_cast<void*>(address), &info,
                      sizeof(info));) {
    const uintptr_t end = reinterpret_cast<uintptr_t>(info.BaseAddress) + info.RegionSize;
    if (end <= address) break;
    if (info.State == MEM_COMMIT && !(info.Protect & (PAGE_NOACCESS | PAGE_GUARD))) {
      for (uintptr_t offset = address; offset < end; offset += block) {
        SIZE_T count = 0;
        ReadProcessMemory(process, reinterpret_cast<void*>(offset), bytes.data(),
                          (std::min)(bytes.size(), size_t(end - offset)), &count);
        if (count < pixels.size()) continue;
        const auto last = bytes.begin() + count;
        decoded_rgba += std::search(bytes.begin(), last, pixels.begin(), pixels.end()) != last;
        decoded_bgra += std::search(bytes.begin(), last, bgra.begin(), bgra.end()) != last;
      }
    }
    address = end;
  }
  CloseHandle(process);
  printf("skin_decoded_rgba=%zu skin_decoded_bgra=%zu\n", decoded_rgba, decoded_bgra);
  return decoded_rgba + decoded_bgra ? 0 : 6;
}
