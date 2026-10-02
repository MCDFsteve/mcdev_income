/*
 * Wine 11 client-surface adapter for DXMT 0.80's legacy macdrv ABI.
 *
 * Copyright 2026 MCDev contributors
 *
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or (at
 * your option) any later version.
 */

#if 0
#pragma makedep unix
#endif

#include "config.h"
#include <stddef.h>
#include <stdlib.h>
#include "macdrv.h"

/* DXMT 0.80 only reads the first four pointers. Never expose Wine 11's
 * macdrv_win_data directly: offset 24 is now a RECT, not a Cocoa view. */
struct dxmt_win_data
{
    HWND hwnd;
    macdrv_window cocoa_window;
    macdrv_view cocoa_view;
    macdrv_view client_cocoa_view;
    struct macdrv_client_surface *surface;
};

_Static_assert(offsetof(struct dxmt_win_data, client_cocoa_view) == 3 * sizeof(void *),
               "DXMT 0.80 legacy window ABI");

static struct dxmt_win_data *dxmt_get_win_data(HWND hwnd)
{
    struct dxmt_win_data *compat = calloc(1, sizeof(*compat));
    struct macdrv_win_data *data;

    if (!compat) return NULL;
    compat->hwnd = hwnd;
    if (!(data = get_win_data(hwnd))) return compat;
    compat->cocoa_window = data->cocoa_window;
    release_win_data(data);

    /* A dedicated surface participates in Wine's resize/destroy tracking.
     * The legacy view argument is opaque and consumed by our paired wrapper,
     * rather than borrowing the unrelated OpenGL client's view. */
    if ((compat->surface = macdrv_client_surface_create(hwnd)))
        compat->client_cocoa_view = (macdrv_view)compat->surface;
    return compat;
}

static void dxmt_release_win_data(struct dxmt_win_data *compat)
{
    if (!compat) return;
    if (compat->surface) client_surface_release(&compat->surface->client);
    free(compat);
}

static macdrv_metal_view dxmt_create_metal_view(macdrv_view opaque, macdrv_metal_device device)
{
    struct macdrv_client_surface *surface = (struct macdrv_client_surface *)opaque;

    if (!surface || !device) return NULL;
    if (!(surface->metal_view = macdrv_view_create_metal_view(surface->cocoa_view, device)))
        return NULL;
    /* Keep the surface alive after DXMT releases the temporary legacy data.
     * Surface destruction releases its metal view; the device belongs to DXMT. */
    client_surface_add_ref(&surface->client);
    return (macdrv_metal_view)surface;
}

static macdrv_metal_layer dxmt_get_metal_layer(macdrv_metal_view opaque)
{
    struct macdrv_client_surface *surface = (struct macdrv_client_surface *)opaque;
    return surface ? macdrv_view_get_metal_layer(surface->metal_view) : NULL;
}

static void dxmt_release_metal_view(macdrv_metal_view opaque)
{
    struct macdrv_client_surface *surface = (struct macdrv_client_surface *)opaque;
    if (surface) client_surface_release(&surface->client);
}

/* Exact function-pointer order from DXMT 0.80 winemetal_unix.c. Its unused
 * display-init / main-thread entries stay NULL. Do not export get_win_data. */
struct dxmt_macdrv_functions
{
    void (*init_display_devices)(BOOL);
    struct dxmt_win_data *(*get_win_data)(HWND);
    void (*release_win_data)(struct dxmt_win_data *);
    macdrv_window (*get_cocoa_window)(HWND, BOOL);
    macdrv_metal_device (*create_metal_device)(void);
    void (*release_metal_device)(macdrv_metal_device);
    macdrv_metal_view (*create_metal_view)(macdrv_view, macdrv_metal_device);
    macdrv_metal_layer (*get_metal_layer)(macdrv_metal_view);
    void (*release_metal_view)(macdrv_metal_view);
    void (*on_main_thread)(void *);
};

__attribute__((visibility("default")))
const struct dxmt_macdrv_functions macdrv_functions =
{
    .get_win_data = dxmt_get_win_data,
    .release_win_data = dxmt_release_win_data,
    .get_cocoa_window = macdrv_get_cocoa_window,
    .create_metal_device = macdrv_create_metal_device,
    .release_metal_device = macdrv_release_metal_device,
    .create_metal_view = dxmt_create_metal_view,
    .get_metal_layer = dxmt_get_metal_layer,
    .release_metal_view = dxmt_release_metal_view,
};
