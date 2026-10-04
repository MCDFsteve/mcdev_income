/* 3.10.0.420447's hash-pinned FMOD output adapter. No game/SDK offsets.
 * Export names and x64 ABIs were verified in the shipped fmod64.dll.
 * NOSOUND (2) keeps the normal mixer clock without opening an audio device.
 * All FMOD calls run on the game's calling thread, never on the log worker. */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "MinHook.h"

typedef int (*SystemUpdate)(void *);
typedef int (*SystemInit)(void *, int, unsigned int, void *);
typedef int (*SystemOutput)(void *, int);
typedef int (*SystemGetOutput)(void *, int *);
typedef int (*SystemPlay)(void *, void *, void *, unsigned char, void **);
static SystemUpdate original_update;
static SystemInit original_init;
static SystemOutput original_output;
static SystemGetOutput get_output;
static SystemPlay original_play_sound, original_play_dsp;
static volatile LONG updates, changes, failures, last_result, armed;
static wchar_t log_path[32768], temporary_path[32768];

static int silence(void *system) {
    int output = -1;
    int result = get_output(system, &output);
    if (!result && output != 2) {
        result = original_output(system, 2);
        if (!result) {
            InterlockedIncrement(&changes);
            result = get_output(system, &output);
        }
    }
    if (!result && output != 2) result = -1;
    if (result) {
        InterlockedExchange(&last_result, result);
        InterlockedIncrement(&failures);
    }
    return result;
}
static int set_output(void *system, int requested) {
    (void)requested;
    return original_output(system, 2);
}
static int set_output_plugin(void *system, unsigned int plugin) {
    (void)plugin;
    return original_output(system, 2);
}
static int init(void *system, int channels, unsigned int flags, void *extra) {
    int result = original_output(system, 2);
    if (result) return result;
    return original_init(system, channels, flags, extra);
}
static int update(void *system) {
    int result = silence(system);
    if (result) return result;
    InterlockedIncrement(&updates);
    return original_update(system);
}
static int play_sound(void *system, void *sound, void *group,
                      unsigned char paused, void **channel) {
    int result = silence(system);
    return result ? result : original_play_sound(system, sound, group, paused, channel);
}
static int play_dsp(void *system, void *dsp, void *group,
                    unsigned char paused, void **channel) {
    int result = silence(system);
    return result ? result : original_play_dsp(system, dsp, group, paused, channel);
}
static void report(const char *state, const char *reason) {
    FILE *log = _wfopen(temporary_path, L"w");
    if (!log) return;
    fprintf(log, "{\"state\":\"%s\",\"reason\":\"%s\",\"output\":%d,"
        "\"updates\":%ld,\"changes\":%ld,\"failures\":%ld,\"result\":%ld}\n",
        state, reason, updates > 0 ? 2 : -1,
        updates, changes, failures, last_result);
    fclose(log);
    MoveFileExW(temporary_path, log_path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
}
static int matches(void *target, const BYTE *bytes, SIZE_T size) {
    BYTE actual[8]; SIZE_T count = 0;
    return target && size <= sizeof(actual) &&
        ReadProcessMemory(GetCurrentProcess(), target, actual, size, &count) &&
        count == size && !memcmp(actual, bytes, size);
}
static DWORD WINAPI setup(void *unused) {
    (void)unused;
    DWORD n = GetEnvironmentVariableW(L"MCDEV_SOUND_LOG", log_path, 32768);
    if (!n || n >= 32760) return 1;
    swprintf(temporary_path, 32768, L"%ls.tmp", log_path);
    HMODULE fmod = NULL;
    for (int i = 0; i < 6000 && !fmod; ++i) {
        fmod = GetModuleHandleW(L"fmod64.dll");
        if (!fmod) Sleep(10);
    }
    if (!fmod) { report("failed", "fmod_missing"); return 2; }
    BYTE *base = (BYTE *)fmod;
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)base;
    IMAGE_NT_HEADERS64 *nt = (IMAGE_NT_HEADERS64 *)(base + dos->e_lfanew);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || nt->Signature != IMAGE_NT_SIGNATURE ||
        nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64 ||
        nt->FileHeader.TimeDateStamp != 0x58eba7f0 || nt->OptionalHeader.SizeOfImage != 0x1ec000) {
        report("failed", "fmod_layout"); return 3;
    }
    void *update_target = (void *)GetProcAddress(fmod, "?update@System@FMOD@@QEAA?AW4FMOD_RESULT@@XZ");
    void *init_target = (void *)GetProcAddress(fmod, "?init@System@FMOD@@QEAA?AW4FMOD_RESULT@@HIPEAX@Z");
    void *output_target = (void *)GetProcAddress(fmod, "?setOutput@System@FMOD@@QEAA?AW4FMOD_RESULT@@W4FMOD_OUTPUTTYPE@@@Z");
    void *plugin_target = (void *)GetProcAddress(fmod, "?setOutputByPlugin@System@FMOD@@QEAA?AW4FMOD_RESULT@@I@Z");
    void *play_target = (void *)GetProcAddress(fmod, "?playSound@System@FMOD@@QEAA?AW4FMOD_RESULT@@PEAVSound@2@PEAVChannelGroup@2@_NPEAPEAVChannel@2@@Z");
    void *dsp_target = (void *)GetProcAddress(fmod, "?playDSP@System@FMOD@@QEAA?AW4FMOD_RESULT@@PEAVDSP@2@PEAVChannelGroup@2@_NPEAPEAVChannel@2@@Z");
    get_output = (SystemGetOutput)(void *)GetProcAddress(fmod, "?getOutput@System@FMOD@@QEAA?AW4FMOD_RESULT@@PEAW4FMOD_OUTPUTTYPE@@@Z");
    const BYTE update_bytes[] = {0x48,0x89,0x5c,0x24,0x10,0x57};
    const BYTE init_bytes[] = {0x40,0x53,0x55,0x56,0x41,0x56};
    const BYTE output_bytes[] = {0x48,0x89,0x5c,0x24,0x18,0x48,0x89,0x74};
    if (!get_output || !plugin_target || !play_target || !dsp_target ||
        !matches(update_target, update_bytes, sizeof(update_bytes)) ||
        !matches(init_target, init_bytes, sizeof(init_bytes)) ||
        !matches(output_target, output_bytes, sizeof(output_bytes))) {
        report("failed", "fmod_signature"); return 4;
    }
    MH_STATUS status = MH_Initialize();
    if (status == MH_OK) status = MH_CreateHook(output_target, set_output, (void **)&original_output);
    if (status == MH_OK) status = MH_CreateHook(init_target, init, (void **)&original_init);
    if (status == MH_OK) status = MH_CreateHook(update_target, update, (void **)&original_update);
    if (status == MH_OK) status = MH_CreateHook(plugin_target, set_output_plugin, NULL);
    if (status == MH_OK) status = MH_CreateHook(play_target, play_sound, (void **)&original_play_sound);
    if (status == MH_OK) status = MH_CreateHook(dsp_target, play_dsp, (void **)&original_play_dsp);
    if (status == MH_OK) status = MH_EnableHook(MH_ALL_HOOKS);
    if (status != MH_OK) {
        MH_Uninitialize(); report("failed", MH_StatusToString(status)); return 5;
    }
    InterlockedExchange(&armed, 1);
    for (;;) {
        report(failures ? "failed" : updates ? "ready" : "armed", failures ? "output_switch" : "nosound");
        Sleep(500);
    }
}
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, void *reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
        HANDLE thread = CreateThread(NULL, 0, setup, NULL, 0, NULL);
        if (thread) CloseHandle(thread);
    }
    /* DLL stays loaded until process exit; active hooks must never be unloaded. */
    return TRUE;
}
