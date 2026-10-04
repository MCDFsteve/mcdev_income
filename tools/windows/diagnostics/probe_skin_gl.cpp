// Opt-in graphics test instrumentation. Reads uploaded 64x64 textures; does
// not capture a framebuffer, change rendering, or interact with the desktop.
#include <windows.h>
#include <gl/GL.h>
#include <cstdio>
#include <share.h>
#include <vector>
#include "MinHook.h"

static void (APIENTRY *original_image)(GLenum, GLint, GLint, GLsizei, GLsizei,
                                       GLint, GLenum, GLenum, const void*);
static void (APIENTRY *original_subimage)(GLenum, GLint, GLint, GLint, GLsizei,
                                          GLsizei, GLenum, GLenum, const void*);
static std::vector<unsigned char> expected(64 * 64 * 4);
static std::vector<unsigned char> dummy(64 * 64 * 4);
static FILE* log_file;
static GLuint skin_texture;
static unsigned skin_binds;
static GLuint dummy_texture;
static unsigned dummy_binds;
static void (APIENTRY *original_bind)(GLenum, GLuint);
static void APIENTRY inspect_bind(GLenum target, GLuint texture) {
  if (texture && texture == skin_texture && (skin_binds++ < 4 || skin_binds % 300 == 0)) {
    fprintf(log_file, "skin_texture_bound=%u\n", skin_binds); fflush(log_file);
  }
  if (texture && texture == dummy_texture && (dummy_binds++ < 4 || dummy_binds % 300 == 0)) {
    fprintf(log_file, "dummy_texture_bound=%u\n", dummy_binds); fflush(log_file);
  }
  original_bind(target, texture);
}
static void inspect(GLsizei width, GLsizei height, GLenum format, GLenum type,
                    const void* data) {
  if (width != 64 || height != 64) return;
  fprintf(log_file, "skin_gpu_format=%x type=%x\n", format, type); fflush(log_file);
  if ((type != GL_UNSIGNED_BYTE && type != 0x8367) ||
      (format != GL_RGBA && format != 0x80E1) || reinterpret_cast<uintptr_t>(data) < 65536) return;
  unsigned char pixels[64 * 64 * 4];
  SIZE_T size = 0;
  if (!ReadProcessMemory(GetCurrentProcess(), data, pixels, sizeof(pixels), &size)
      || size != sizeof(pixels)) return;
  bool rgb = true, exact = true, dummy_match = true;
  if (format == 0x80E1) {
    for (size_t i = 0; i < sizeof(pixels); i += 4) std::swap(pixels[i], pixels[i + 2]);
  }
  for (size_t i = 0; i < expected.size(); ++i) {
    exact &= pixels[i] == expected[i];
    if (i % 4 != 3 && dummy[(i / 4) * 4 + 3]) dummy_match &= pixels[i] == dummy[i];
    if (i % 4 != 3 && expected[(i / 4) * 4 + 3]) rgb &= pixels[i] == expected[i];
  }
  fprintf(log_file, "skin_gpu_upload rgb_match=%d exact_match=%d\n", rgb, exact);
  if (rgb) {
    GLint texture = 0; glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture);
    skin_texture = static_cast<GLuint>(texture);
  }
  if (dummy_match) {
    GLint texture = 0; glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture);
    dummy_texture = static_cast<GLuint>(texture);
    fprintf(log_file, "dummy_gpu_upload=1\n");
  }
  fflush(log_file);
}

static void APIENTRY inspect_image(GLenum target, GLint level, GLint internal,
  GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type,
  const void* data) {
  inspect(width, height, format, type, data);
  original_image(target, level, internal, width, height, border, format, type, data);
}

static void APIENTRY inspect_subimage(GLenum target, GLint level, GLint x, GLint y,
  GLsizei width, GLsizei height, GLenum format, GLenum type, const void* data) {
  inspect(width, height, format, type, data);
  original_subimage(target, level, x, y, width, height, format, type, data);
}

static DWORD WINAPI initialize(void*) {
  wchar_t path[32768];
  if (!GetEnvironmentVariableW(L"MCDEV_SKIN_PROBE_PIXELS", path, 32768)) return 1;
  FILE* input = nullptr;
  if (_wfopen_s(&input, path, L"rb") || !input) return 2;
  const auto size = fread(expected.data(), 1, expected.size(), input);
  fclose(input);
  if (size != expected.size()) return 3;
  if (!GetEnvironmentVariableW(L"MCDEV_SKIN_PROBE_DUMMY", path, 32768)) return 3;
  if (_wfopen_s(&input, path, L"rb") || !input) return 3;
  fread(dummy.data(), 1, dummy.size(), input); fclose(input);
  if (!GetEnvironmentVariableW(L"MCDEV_SKIN_PROBE_LOG", path, 32768)) return 4;
  log_file = _wfsopen(path, L"w", _SH_DENYNO);
  if (!log_file) return 5;
  if (MH_Initialize() != MH_OK) return 6;
  // BGFX caches the driver's dispatch pointers, bypassing opengl32 exports.
  // Obtain those pointers from an invisible offscreen diagnostic context.
  WNDCLASSW wc = {};
  wc.lpfnWndProc = DefWindowProcW;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"MCDevSkinProbe";
  wc.style = CS_OWNDC;
  RegisterClassW(&wc);
  HWND window = CreateWindowW(wc.lpszClassName, L"", 0, 0, 0, 1, 1,
                              nullptr, nullptr, wc.hInstance, nullptr);
  HDC dc = GetDC(window);
  PIXELFORMATDESCRIPTOR pfd = {};
  pfd.nSize = sizeof(pfd); pfd.nVersion = 1;
  pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL;
  pfd.iPixelType = PFD_TYPE_RGBA; pfd.cColorBits = 32;
  SetPixelFormat(dc, ChoosePixelFormat(dc, &pfd), &pfd);
  HGLRC context = wglCreateContext(dc);
  wglMakeCurrent(dc, context);
  auto image = wglGetProcAddress("glTexImage2D");
  auto subimage = wglGetProcAddress("glTexSubImage2D");
  auto bind = wglGetProcAddress("glBindTexture");
  fprintf(log_file, "skin_gpu_driver_dispatch=%d,%d\n", image != nullptr, subimage != nullptr);
  wglMakeCurrent(nullptr, nullptr); wglDeleteContext(context);
  ReleaseDC(window, dc); DestroyWindow(window);
  if (!image) image = GetProcAddress(GetModuleHandleW(L"opengl32.dll"), "glTexImage2D");
  if (!subimage) subimage = GetProcAddress(GetModuleHandleW(L"opengl32.dll"), "glTexSubImage2D");
  if (!bind) bind = GetProcAddress(GetModuleHandleW(L"opengl32.dll"), "glBindTexture");
  if (MH_CreateHook(reinterpret_cast<void*>(image),
      reinterpret_cast<void*>(inspect_image),
      reinterpret_cast<void**>(&original_image)) != MH_OK) return 7;
  if (MH_CreateHook(reinterpret_cast<void*>(subimage),
      reinterpret_cast<void*>(inspect_subimage),
      reinterpret_cast<void**>(&original_subimage)) != MH_OK) return 8;
  if (MH_CreateHook(reinterpret_cast<void*>(bind), reinterpret_cast<void*>(inspect_bind),
      reinterpret_cast<void**>(&original_bind)) != MH_OK) return 9;
  fprintf(log_file, "skin_gpu_probe=ready\n"); fflush(log_file);
  return MH_EnableHook(MH_ALL_HOOKS) == MH_OK ? 0 : 9;
}

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, void*) {
  if (reason == DLL_PROCESS_ATTACH) {
    DisableThreadLibraryCalls(module);
    HANDLE thread = CreateThread(nullptr, 0, initialize, nullptr, 0, nullptr);
    if (thread) CloseHandle(thread);
  }
  return TRUE;
}
