#import <AppKit/AppKit.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/* Wine maps Command to Windows Alt. The developer game treats Alt+Shift as
 * a fullscreen chord before the screenshot's number key reaches the app.
 * Change only the modifier flags visible to this game process. macOS still
 * receives the original screenshot shortcut. Hide BOTH modifiers while the
 * chord is held: Wine posts Shift transitions before Command transitions,
 * so hiding Command alone would briefly deliver Alt+Shift if Command was
 * pressed first. Individual modifiers work again after the chord ends. */
static NSUInteger (*original_flags)(id, SEL);

static NSUInteger guarded_flags(id event, SEL selector)
{
    NSUInteger flags = original_flags(event, selector);
    NSUInteger chord = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    if ((flags & chord) == chord)
        flags &= ~(chord | NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK |
            NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK);
    return flags;
}

__attribute__((constructor))
static void configure_fullscreen_shortcut(void)
{
    const char *enabled = getenv("MCDEV_FULLSCREEN_SHORTCUT");
    if (enabled && !strcmp(enabled, "1")) return;
    Method method = class_getInstanceMethod([NSEvent class], @selector(modifierFlags));
    if (!method) {
        fprintf(stderr, "[MCDev input] fullscreen shortcut guard unavailable\n");
        return;
    }
    original_flags = (void *)method_setImplementation(method, (IMP)guarded_flags);
    fprintf(stderr, "[MCDev input] Command+Shift fullscreen shortcut disabled\n");
}
