/* Host-native transaction checks: no Wine or game process is started. */
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef unsigned char BYTE;
typedef uint32_t DWORD;
#define PAGE_EXECUTE_READWRITE 0x40
#define MCDEV_LAN_PATCH_TEST
static int protect_calls, flush_calls, change_signature_on_protect;
static uint32_t fail_protect_calls, fail_flush_calls;
static struct {
    BYTE *site;
    size_t span;
    DWORD protection;
} regions[2];
static int region_count;

static int region_index(const void *site, size_t length) {
    for (int i = 0; i < region_count; ++i) {
        if (site == regions[i].site) {
            assert(length == regions[i].span);
            return i;
        }
    }
    assert(!"unknown memory region");
    return -1;
}
static int VirtualProtect(void *site, size_t length, DWORD protection, DWORD *old) {
    int i = region_index(site, length);
    ++protect_calls;
    if (fail_protect_calls & (1u << protect_calls)) return 0;
    if (protect_calls == change_signature_on_protect) ((BYTE *)site)[0] ^= 1;
    *old = regions[i].protection;
    regions[i].protection = protection;
    return 1;
}
static void *GetCurrentProcess(void) { return NULL; }
static int FlushInstructionCache(void *process, const void *site, size_t length) {
    (void)process;
    region_index(site, length);
    return !(fail_flush_calls & (1u << ++flush_calls));
}
#include "lan_patch.c"

static void reset_calls(void) {
    protect_calls = flush_calls = change_signature_on_protect = 0;
    fail_protect_calls = fail_flush_calls = 0;
}
static void reset_host(BYTE *site) {
    memset(site, 0xab, PATCH_SPAN);
    memcpy(site, first_original, sizeof(first_original));
    memcpy(site + SECOND_OFFSET, second_original, sizeof(second_original));
    reset_calls();
    region_count = 1;
    regions[0].site = site;
    regions[0].span = PATCH_SPAN;
    regions[0].protection = 0x20;
}
static void assert_middle(const BYTE *site) {
    for (int i = 4; i < SECOND_OFFSET; ++i) assert(site[i] == 0xab);
}
static void reset_guest(BYTE *site) {
    memcpy(site, guest_original, sizeof(guest_original));
    reset_calls();
    region_count = 1;
    regions[0].site = site;
    regions[0].span = sizeof(guest_original);
    regions[0].protection = 0x20;
}
static void assert_readonly(void) {
    for (int i = 0; i < region_count; ++i) assert(regions[i].protection == 0x20);
}
static void assert_guest_originals(const BYTE *site) {
    assert(guest_originals_match(site));
    assert_readonly();
}

int main(void) {
    BYTE site[PATCH_SPAN], original[PATCH_SPAN];
    reset_host(site);
    assert(patch_transport(site) == PATCH_READY);
    assert(!memcmp(site, nops, 4) && !memcmp(site + SECOND_OFFSET, nops, 4));
    assert_readonly();
    assert(protect_calls == 2 && flush_calls == 1);
    assert_middle(site);

    reset_host(site); site[SECOND_OFFSET] ^= 1;
    memcpy(original, site, sizeof(site));
    assert(patch_transport(site) == PATCH_SIGNATURE);
    assert(!memcmp(site, original, sizeof(site)) && protect_calls == 0);

    for (int failure = 0; failure < 3; ++failure) {
        reset_host(site);
        if (failure == 0) fail_protect_calls = 1u << 1;
        if (failure == 1) fail_flush_calls = 1u << 1;
        if (failure == 2) fail_protect_calls = 1u << 2;
        assert(patch_transport(site) ==
               (failure == 0 ? PATCH_PROTECT : failure == 1 ? PATCH_FLUSH : PATCH_RESTORE));
        assert(originals_match(site));
        assert_readonly();
        assert_middle(site);
    }
    reset_host(site); change_signature_on_protect = 1;
    memcpy(original, site, sizeof(site)); original[0] ^= 1;
    assert(patch_transport(site) == PATCH_SIGNATURE);
    assert(!memcmp(site, original, sizeof(site)));
    assert_readonly();

    assert(parse_role(L"host") == LAN_ROLE_HOST);
    assert(parse_role(L"guest") == LAN_ROLE_GUEST);
    assert(parse_role(L"") == LAN_ROLE_INVALID);
    assert(parse_role(L"Guest") == LAN_ROLE_INVALID);
    assert(parse_role(L"host-extra") == LAN_ROLE_INVALID);

    BYTE guest[sizeof(guest_original)];
    reset_guest(guest);
    assert(patch_guest_profile(guest) == PATCH_READY);
    assert(guest[GUEST_BRANCH_OFFSET] == 0xeb);
    for (size_t i = 0; i < sizeof(guest); ++i)
        if (i != GUEST_BRANCH_OFFSET) assert(guest[i] == guest_original[i]);
    assert_readonly();
    assert(protect_calls == 2 && flush_calls == 1);

    /* Every byte of the signature must pass before writing. */
    for (size_t byte = 0; byte < sizeof(guest); ++byte) {
        reset_guest(guest);
        guest[byte] ^= 1;
        assert(patch_guest_profile(guest) == PATCH_SIGNATURE);
        assert(protect_calls == 0 && flush_calls == 0);
        guest[byte] ^= 1;
        assert_guest_originals(guest);
    }
    for (int failure = 0; failure < 3; ++failure) {
        reset_guest(guest);
        if (failure == 0) fail_protect_calls = 1u << 1;
        if (failure == 1) fail_flush_calls = 1u << 1;
        if (failure == 2) fail_protect_calls = 1u << 2;
        assert(patch_guest_profile(guest) ==
               (failure == 0 ? PATCH_PROTECT : failure == 1 ? PATCH_FLUSH : PATCH_RESTORE));
        assert_guest_originals(guest);
    }
    reset_guest(guest); change_signature_on_protect = 1;
    assert(patch_guest_profile(guest) == PATCH_SIGNATURE);
    guest[0] ^= 1;
    assert_guest_originals(guest);
    assert(flush_calls == 0);

    puts("LAN host/guest: exact signatures, single-page writes and rollback checks passed");
    return 0;
}
