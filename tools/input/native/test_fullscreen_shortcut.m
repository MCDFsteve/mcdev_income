#import <AppKit/AppKit.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static NSUInteger event_flags(NSUInteger flags)
{
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeFlagsChanged
        location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0
        context:nil characters:@"" charactersIgnoringModifiers:@""
        isARepeat:NO keyCode:56];
    assert(event);
    return event.modifierFlags;
}

/* WineWindow flagsChanged: posts Shift before Command. Check every intermediate
 * key state, not just each event's final flags: releasing Command after posting
 * Shift would otherwise briefly recreate the game's Alt+Shift chord. */
static void verify_wine_transitions(BOOL enabled, const NSUInteger *transitions,
    unsigned count)
{
    const NSUInteger ordered_masks[] = {
        NX_DEVICELSHIFTKEYMASK, NX_DEVICERSHIFTKEYMASK,
        NX_DEVICELCTLKEYMASK, NX_DEVICERCTLKEYMASK,
        NX_DEVICELALTKEYMASK, NX_DEVICERALTKEYMASK,
        NX_DEVICELCMDKEYMASK, NX_DEVICERCMDKEYMASK,
    };
    const NSUInteger shift_mask = NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK;
    const NSUInteger command_mask = NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK;
    NSUInteger last = 0;
    BOOL observed_chord = NO;
    for (unsigned t = 0; t < count; t++) {
        NSUInteger flags = event_flags(transitions[t]);
        NSUInteger changed = last ^ flags;
        for (unsigned i = 0; i < sizeof(ordered_masks)/sizeof(ordered_masks[0]); i++) {
            if (!(changed & ordered_masks[i])) continue;
            last ^= ordered_masks[i];
            BOOL chord = (last & shift_mask) && (last & command_mask);
            if (!enabled) assert(!chord);
            observed_chord |= chord;
        }
        last = flags;
    }
    assert(observed_chord == enabled);
    assert(last == 0);
}

int main(void)
{
    @autoreleasepool {
        BOOL enabled = getenv("MCDEV_FULLSCREEN_SHORTCUT") &&
            !strcmp(getenv("MCDEV_FULLSCREEN_SHORTCUT"), "1");
        const NSUInteger command = NSEventModifierFlagCommand | NX_DEVICELCMDKEYMASK;
        const NSUInteger shift = NSEventModifierFlagShift | NX_DEVICELSHIFTKEYMASK;
        const NSUInteger both = command | shift;
        assert(event_flags(0) == 0);
        assert(event_flags(command) == command);
        assert(event_flags(shift) == shift);
        assert(event_flags(both) == (enabled ? both : 0));
        assert(event_flags(both | NSEventModifierFlagControl) ==
            (enabled ? both : 0) + NSEventModifierFlagControl);
        const NSUInteger right = NSEventModifierFlagCommand | NX_DEVICERCMDKEYMASK |
            NSEventModifierFlagShift | NX_DEVICERSHIFTKEYMASK;
        assert(event_flags(right) == (enabled ? right : 0));
        /* Exercise both press/release orders; ordinary Command works again
         * immediately after Shift is released, with no sticky modifiers. */
        const NSUInteger transitions[] = {0, command, both, shift, 0, shift, both, command, 0};
        for (unsigned i = 0; i < sizeof(transitions)/sizeof(transitions[0]); i++) {
            NSUInteger f = transitions[i];
            assert(event_flags(f) == (!enabled && f == both ? 0 : f));
        }
        verify_wine_transitions(enabled, transitions, sizeof(transitions)/sizeof(transitions[0]));
        const NSUInteger right_command = NSEventModifierFlagCommand | NX_DEVICERCMDKEYMASK;
        const NSUInteger right_shift = NSEventModifierFlagShift | NX_DEVICERSHIFTKEYMASK;
        const NSUInteger right_transitions[] = {
            0, right_command, right, right_shift, 0,
            right_shift, right, right_command, 0,
        };
        verify_wine_transitions(enabled, right_transitions,
            sizeof(right_transitions)/sizeof(right_transitions[0]));
        puts(enabled ? "Original modifier behavior verified" : "Fullscreen shortcut guard verified");
    }
}
