// Standalone Cocoa fixture for the Flutter/Wine window bridge. No game or login.
#import <AppKit/AppKit.h>

@interface WineWindow : NSWindow
@end
@implementation WineWindow
- (void)sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeKeyDown || event.type == NSEventTypeKeyUp)
        fprintf(stderr, "[probe] key %hu %s\n", event.keyCode, event.type == NSEventTypeKeyDown ? "down" : "up");
    [super sendEvent:event];
}
@end

@interface ProbeContent : NSView
@end
@implementation ProbeContent
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)event { (void)event; }
- (void)keyUp:(NSEvent *)event { (void)event; }
- (void)drawRect:(NSRect)rect {
    (void)rect;
    [[NSColor colorWithRed:0.15 green:0.28 blue:0.2 alpha:1] setFill];
    NSRectFill(self.bounds);
    [@"GAME CONTENT — native view" drawAtPoint:NSMakePoint(20, NSHeight(self.bounds) - 35)
        withAttributes:@{NSForegroundColorAttributeName:NSColor.whiteColor,
                         NSFontAttributeName:[NSFont systemFontOfSize:18]}];
    [[NSColor colorWithWhite:0.6 alpha:1] setStroke];
    NSFrameRect(NSInsetRect(self.bounds, 2, 2));
}
@end

@interface ProbeDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@end
@implementation ProbeDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    self.window = [[WineWindow alloc] initWithContentRect:NSMakeRect(160, 200, 1000, 600)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Minecraft — Chrome Probe";
    self.window.releasedWhenClosed = NO;
    self.window.delegate = self;
    self.window.contentView = [[ProbeContent alloc] initWithFrame:NSMakeRect(0,0,1000,600)];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
- (void)windowDidMove:(NSNotification *)note {
    (void)note;
    fprintf(stderr, "[probe] moved %.0f %.0f\n", self.window.frame.origin.x, self.window.frame.origin.y);
}
- (void)windowDidResize:(NSNotification *)note {
    (void)note;
    fprintf(stderr, "[probe] resized %.0f %.0f\n", self.window.frame.size.width, self.window.frame.size.height);
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
        ProbeDelegate *delegate = [ProbeDelegate new];
        NSApp.delegate = delegate;
        [NSApp run];
    }
    return 0;
}
