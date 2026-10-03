/* Local LAN transport adapter for the exact 3.10.0.420447 x64 image.
 * MCDev contributors 2026, MIT. The launcher validates the original executable
 * SHA-256 before injection. Downloaded game files are never rewritten.
 *
 * This release selects NetherNet when MultiplayerServiceID2 is absent, even
 * for the launcher's local LAN room. Preserve the already initialized RakNet
 * transport by removing only the two conditional moves in that selection.
 * Managed guest processes connect to localhost through the direct-IP path;
 * select the same native local-LAN peer profile as the host/official LAN hooks.
 * Authentication and incoming packet validation remain unchanged.
 */
#ifndef MCDEV_LAN_PATCH_TEST
#include <windows.h>
#endif
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

#define FIRST_RVA 0x07153710
#define SECOND_OFFSET 0x13
#define PATCH_SPAN (SECOND_OFFSET + 4)
static const BYTE first_original[] = {0x41, 0x0f, 0x44, 0xdc};
static const BYTE second_original[] = {0x41, 0x0f, 0x45, 0xdc};
static const BYTE nops[] = {0x90, 0x90, 0x90, 0x90};

#define GUEST_RVA 0x064cc033
/* NetworkSystem::onNewOutgoingConnection: NetSafeAndFast || isLocal. */
static const BYTE guest_original[] = {
    0x80, 0xbe, 0xc1, 0x00, 0x00, 0x00, 0x00, /* cmp byte [rsi+c1],0 */
    0x75, 0x09,                               /* jne local_profile */
    0x45, 0x84, 0xf6, 0x75, 0x04,             /* test isLocal; jne */
    0x32, 0xc9, 0xeb, 0x02,                   /* cl=0; jmp store */
    0xb1, 0x01,                               /* local_profile: cl=1 */
    0x88, 0x4c, 0x24, 0x50                    /* store: [rsp+50]=cl */
};
#define GUEST_BRANCH_OFFSET 7
#define GUEST_SIGNATURE_SPAN sizeof(guest_original)

enum LanRole { LAN_ROLE_INVALID, LAN_ROLE_HOST, LAN_ROLE_GUEST };

static enum LanRole parse_role(const wchar_t *role) {
    if (!wcscmp(role, L"host")) return LAN_ROLE_HOST;
    if (!wcscmp(role, L"guest")) return LAN_ROLE_GUEST;
    return LAN_ROLE_INVALID;
}

enum PatchStatus {
    PATCH_READY = 0,
    PATCH_SIGNATURE = 1,
    PATCH_PROTECT = 2,
    PATCH_FLUSH = 3,
    PATCH_RESTORE = 4
};

static int originals_match(const BYTE *site) {
    return !memcmp(site, first_original, sizeof(first_original)) &&
           !memcmp(site + SECOND_OFFSET, second_original, sizeof(second_original));
}

/* Both sites occupy one page. Preflight both before obtaining write access;
 * every failure after a write restores both originals before returning. */
static enum PatchStatus patch_transport(BYTE *site) {
    DWORD old_protection, ignored;
    if (!originals_match(site)) return PATCH_SIGNATURE;
    if (!VirtualProtect(site, PATCH_SPAN, PAGE_EXECUTE_READWRITE, &old_protection))
        return PATCH_PROTECT;
    if (!originals_match(site)) {
        VirtualProtect(site, PATCH_SPAN, old_protection, &ignored);
        return PATCH_SIGNATURE;
    }
    memcpy(site, nops, sizeof(nops));
    memcpy(site + SECOND_OFFSET, nops, sizeof(nops));
    enum PatchStatus status = PATCH_READY;
    if (!FlushInstructionCache(GetCurrentProcess(), site, PATCH_SPAN))
        status = PATCH_FLUSH;
    else if (!VirtualProtect(site, PATCH_SPAN, old_protection, &ignored))
        status = PATCH_RESTORE;
    if (status != PATCH_READY) {
        memcpy(site, first_original, sizeof(first_original));
        memcpy(site + SECOND_OFFSET, second_original, sizeof(second_original));
        FlushInstructionCache(GetCurrentProcess(), site, PATCH_SPAN);
        VirtualProtect(site, PATCH_SPAN, old_protection, &ignored);
    }
    return status;
}

static int guest_originals_match(const BYTE *site) {
    return !memcmp(site, guest_original, sizeof(guest_original));
}

/* Choose the local peer profile immediately before the outgoing connection is
 * constructed. It uses the official LAN recorder chain; the public-server
 * profile instead adds a batch length prefix that the local host does not use.
 * NetworkType, join callbacks, NetherNet's profile reset, authentication and
 * packet validation are not modified. Injection is limited to exact-version
 * managed localhost guests by the launcher and role guard.
 */
static enum PatchStatus patch_guest_profile(BYTE *site) {
    DWORD old_protection, ignored;
    if (!guest_originals_match(site)) return PATCH_SIGNATURE;
    if (!VirtualProtect(site, GUEST_SIGNATURE_SPAN, PAGE_EXECUTE_READWRITE,
                        &old_protection)) return PATCH_PROTECT;
    if (!guest_originals_match(site)) {
        VirtualProtect(site, GUEST_SIGNATURE_SPAN, old_protection, &ignored);
        return PATCH_SIGNATURE;
    }
    site[GUEST_BRANCH_OFFSET] = 0xeb;
    enum PatchStatus status = PATCH_READY;
    if (!FlushInstructionCache(GetCurrentProcess(), site, GUEST_SIGNATURE_SPAN))
        status = PATCH_FLUSH;
    else if (!VirtualProtect(site, GUEST_SIGNATURE_SPAN, old_protection, &ignored))
        status = PATCH_RESTORE;
    if (status != PATCH_READY) {
        site[GUEST_BRANCH_OFFSET] = guest_original[GUEST_BRANCH_OFFSET];
        FlushInstructionCache(GetCurrentProcess(), site, GUEST_SIGNATURE_SPAN);
        VirtualProtect(site, GUEST_SIGNATURE_SPAN, old_protection, &ignored);
    }
    return status;
}

#ifndef MCDEV_LAN_PATCH_TEST
static void report(FILE *log_file, const char *state, const char *reason) {
    fprintf(log_file, "{\"lan_patch\":\"%s\",\"reason\":\"%s\"}\n", state, reason);
    fflush(log_file);
}

static int executable_read(BYTE *site, BYTE *observed, SIZE_T span) {
    MEMORY_BASIC_INFORMATION region;
    SIZE_T received = 0;
    return VirtualQuery(site, &region, sizeof(region)) &&
        region.State == MEM_COMMIT && !(region.Protect & PAGE_GUARD) &&
        (region.Protect & (PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE |
                           PAGE_EXECUTE_WRITECOPY)) &&
        ReadProcessMemory(GetCurrentProcess(), site, observed, span, &received) &&
        received == span;
}

static DWORD WINAPI setup(void *unused) {
    (void)unused;
    wchar_t path[32768];
    DWORD length = GetEnvironmentVariableW(L"MCDEV_LAN_PATCH_LOG", path, 32768);
    if (!length || length >= 32768) return 1;
    FILE *log_file = _wfopen(path, L"w");
    if (!log_file) return 1;
    wchar_t role_name[16];
    length = GetEnvironmentVariableW(L"MCDEV_LAN_ROLE", role_name, 16);
    enum LanRole role = length && length < 16
        ? parse_role(role_name) : LAN_ROLE_INVALID;
    if (role == LAN_ROLE_INVALID) {
        report(log_file, "unsupported", "managed_role_required");
        fclose(log_file);
        return 2;
    }
    BYTE *image = (BYTE *)GetModuleHandleW(NULL);
    IMAGE_DOS_HEADER *dos = (void *)image;
    if (!image || dos->e_magic != IMAGE_DOS_SIGNATURE ||
        dos->e_lfanew <= 0 || dos->e_lfanew > 0x100000) {
        report(log_file, "unsupported", "image_header");
        fclose(log_file);
        return 2;
    }
    IMAGE_NT_HEADERS64 *nt = (void *)(image + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE ||
        nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64 ||
        nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC ||
        nt->OptionalHeader.SizeOfImage != 0x1d28e000) {
        report(log_file, "unsupported", "image_layout");
        fclose(log_file);
        return 2;
    }
    BYTE *site = image + (role == LAN_ROLE_HOST ? FIRST_RVA : GUEST_RVA);
    SIZE_T signature_span = role == LAN_ROLE_HOST ? PATCH_SPAN : GUEST_SIGNATURE_SPAN;
    for (int attempt = 0; attempt < 6000; attempt++) {
        BYTE observed[PATCH_SPAN > GUEST_SIGNATURE_SPAN
                          ? PATCH_SPAN : GUEST_SIGNATURE_SPAN];
        if (executable_read(site, observed, signature_span) &&
            (role == LAN_ROLE_HOST ? originals_match(observed)
                                   : guest_originals_match(observed))) {
            enum PatchStatus status = role == LAN_ROLE_HOST
                ? patch_transport(site) : patch_guest_profile(site);
            static const char *reasons[] = {
                "raknet", "signature_changed", "protect_failed",
                "cache_flush_failed", "protect_restore_failed"
            };
            const char *reason = status == PATCH_READY && role == LAN_ROLE_GUEST
                ? "local_lan_profile" : reasons[status];
            report(log_file, status == PATCH_READY ? "ready" : "failed", reason);
            fclose(log_file);
            return (DWORD)status;
        }
        Sleep(10);
    }
    report(log_file, "unsupported", "signature_timeout");
    fclose(log_file);
    return 3;
}

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, void *reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(module);
        HANDLE thread = CreateThread(NULL, 0, setup, NULL, 0, NULL);
        if (thread) CloseHandle(thread);
    }
    return TRUE;
}
#endif
