/* Opt-in integration probe against the game's actual fmod64.dll, not a mock.
 * Run in an isolated Wine prefix or on Windows. No FMOD SDK is required. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define API(type, name, symbol) type name = (void *)GetProcAddress(fmod, symbol)
typedef int (*Create)(void **);
typedef int (*Init)(void *, int, unsigned int, void *);
typedef int (*Output)(void *, int);
typedef int (*GetOutput)(void *, int *);
typedef int (*Update)(void *);
typedef int (*Release)(void *);
static int check(int result, const char *operation) {
    if (result) { fprintf(stderr, "%s failed: %d\n", operation, result); return 0; }
    return 1;
}
int main(int argc, char **argv) {
    if (argc != 4) return 1;
    HMODULE fmod = LoadLibraryA(argv[1]);
    if (!fmod) return 2;
    API(Create, create, "FMOD_System_Create");
    API(Init, init, "FMOD_System_Init");
    API(Output, set_output, "FMOD_System_SetOutput");
    API(GetOutput, get_output, "FMOD_System_GetOutput");
    API(Update, update, "FMOD_System_Update");
    API(Release, release, "FMOD_System_Release");
    void *first = NULL, *second = NULL; int output = -1;
    int late = !strcmp(argv[3], "late");
    if (late) {
        if (!check(create(&first), "create before injection") ||
            !check(init(first, 32, 0, NULL), "init before injection") ||
            !check(get_output(first, &output), "get output before injection")) return 3;
        printf("before injection: output=%d\n", output); fflush(stdout);
        if (output == 2) return 4;
    }
    if (!LoadLibraryA(argv[2])) return 5;
    wchar_t log_path[32768];
    if (!GetEnvironmentVariableW(L"MCDEV_SOUND_LOG", log_path, 32768)) return 6;
    int armed = 0;
    for (int i = 0; i < 100; ++i) {
        FILE *file = _wfopen(log_path, L"r"); char record[512] = {0};
        if (file) { if (fgets(record, sizeof(record), file)) armed = strstr(record, "\"armed\"") != NULL; fclose(file); }
        if (armed) break;
        Sleep(100);
    }
    if (!armed) {fprintf(stderr, "DLL did not arm\n"); return 7;}
    if (!late && (!check(create(&first), "create after injection") ||
                  !check(init(first, 32, 0, NULL), "init after injection"))) return 8;
    if (!check(update(first), "update first") || !check(get_output(first, &output), "get first") || output != 2) return 9;
    printf("after injection: output=%d\n", output);
    if (!check(set_output(first, 0), "request automatic hardware output") ||
        !check(get_output(first, &output), "get after output change") || output != 2) return 10;
    printf("after hardware-output request: output=%d\n", output);
    if (!check(create(&second), "create second") || !check(init(second, 32, 0, NULL), "init second") ||
        !check(get_output(second, &output), "get second") || output != 2) return 11;
    printf("second audio system: output=%d\n", output);
    for (int i = 0; i < 100; ++i) {
        if (!check(update(first), "update first") || !check(update(second), "update second")) return 12;
        Sleep(10);
    }
    if (!check(release(second), "release second") || !check(release(first), "release first")) return 13;
    printf("PASS: silent backend, output-change interception, two audio systems\n");
    return 0;
}
