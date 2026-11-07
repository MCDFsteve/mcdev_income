/* Code signatures shared by the injector and the adapter, so neither depends on
 * the addresses of one game build. "??" marks bytes that differ between builds.
 * Verified against a running 3.9.0.401155, 3.10.0.420447 and 3.10.0.448891; check
 * another build with tools/renderer/scan_signatures.ps1. */
#ifndef MCDEV_RENDERER_SIGNATURES_H
#define MCDEV_RENDERER_SIGNATURES_H
#include <stddef.h>
#include <stdint.h>

#define SIGNATURE_INIT "48 89 5c 24 20 55 56 57 41 54 41 55 41 56 41 57 48 8d ac 24 ?? ?? ff ff 48 81 ec ?? ?? 00 00 48 8b 05 ?? ?? ?? ?? 48 33 c4 48 89 85 ?? ?? 00 00 ?? ?? ?? ?? ?? ?? ?? ?? ?? 48 89 54 24 48 45 33 ed 4c 8b 39 4d 8b 67 18 b9 ?? ?? 00 00 e8"
#define SIGNATURE_DEFERRED "40 53 48 83 ec 30 e8 ?? ?? ?? ?? 48 8b d8 48 85 c0 75 ?? 48 8d 05 ?? ?? ?? ?? 41 b8 ?? 00 00 00 4c 8d 0d ?? ?? ?? ?? 48 89 44 24 20 48 8d 15 ?? ?? ?? ?? 48 8d 0d ?? ?? ?? ?? e8 ?? ?? ?? ?? 84 c0 74 05 e8 ?? ?? ?? ?? e8 ?? ?? ?? ?? 83 c0 fd 83 f8"
#define SIGNATURE_DESTROY "48 89 5c 24 10 56 48 83 ec 30 48 8b 51 18 33 f6 48 8b d9 48 85 d2 74 ?? 48 8b 0d ?? ?? ?? ?? 48 85 c9 74 ?? 48 8b 01 45 33 c9 89 74 24 28 45 33 c0 48 89 74 24 20 ff 50 08 48 89 73 18 48 8b 4b 10"
#define SIGNATURE_STRUCTURED_CREATE "48 83 ec 38 0f b7 c2 45 8b d0 48 c1 e0 05 48 81 c1 ?? ?? ?? ?? c7 44 24 28 02 00 00 00 48 03 c8 44 89 4c 24 20 45 33 c0 44 0f b7 4c 24 60 41 8b d2 e8"
#define SIGNATURE_STRUCTURED_UPDATE "48 83 ec 38 4d 8b 08 48 81 c1 ?? ?? ?? ?? 45 8b 40 08 0f b7 c2 33 d2 48 c1 e0 05 48 03 c8 c6 44 24 28 00 c6 44 24 20 01 e8"
/* The first call in the deferred check returns the address of BGFX's Caps. */
#define SIGNATURE_CAPS_GETTER "48 8d 05 ?? ?? ?? ?? c3"

enum { SIGNATURE_MAX = 128 };
typedef struct {
    uint8_t bytes[SIGNATURE_MAX];
    uint8_t known[SIGNATURE_MAX];
    size_t length;
} Signature;

static int signature_digit(char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}

static int signature_parse(const char *text, Signature *signature) {
    signature->length = 0;
    while (*text) {
        if (signature->length == SIGNATURE_MAX) return 0;
        if (text[0] == '?' && text[1] == '?') {
            signature->bytes[signature->length] = 0;
            signature->known[signature->length] = 0;
        } else {
            int high = signature_digit(text[0]);
            int low = high < 0 ? -1 : signature_digit(text[1]);
            if (low < 0) return 0;
            signature->bytes[signature->length] = (uint8_t)(high * 16 + low);
            signature->known[signature->length] = 1;
        }
        signature->length++;
        text += 2;
        if (*text == ' ') text++;
        else if (*text) return 0;
    }
    return signature->length > 0;
}

static int signature_matches(const uint8_t *at, const Signature *signature) {
    for (size_t i = 0; i < signature->length; i++) {
        if (signature->known[i] && at[i] != signature->bytes[i]) return 0;
    }
    return 1;
}

/* Counts matches and keeps the first in *found. Every signature starts with a
 * known byte, so most positions are rejected by the first comparison. */
static int signature_search(const uint8_t *start, size_t size,
                            const Signature *signature, const uint8_t **found) {
    int hits = 0;
    if (size < signature->length) return 0;
    for (size_t i = 0; i <= size - signature->length; i++) {
        if (start[i] == signature->bytes[0] && signature_matches(start + i, signature)) {
            if (!hits++ && found) *found = start + i;
        }
    }
    return hits;
}
#endif
