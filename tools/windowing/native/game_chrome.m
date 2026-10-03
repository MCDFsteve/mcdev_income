#import <AppKit/AppKit.h>
#import <FlutterMacOS/FlutterMacOS.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include <stdio.h>

static const CGFloat chromeHeight = 48;
static const void *chromeKey = &chromeKey;

static NSString *game_display_name(void)
{
    const char *value = getenv("MCDEV_CHROME_DISPLAY_NAME");
    return value && value[0] ? @(value) : @"我的世界测试";
}

@interface NSWindow (MCDevWineInput)
- (void)postKeyEvent:(NSEvent *)event;
@end

@interface NSObject (MCDevWineFocus)
+ (id)sharedController;
- (void)windowGotFocus:(NSWindow *)window;
@end

static BOOL chrome_accepts_focus(id owner, SEL selector, NSView *view)
{
    (void)owner; (void)selector; (void)view;
    // The titlebar has no text fields. Keep keyboard focus with the Wine view
    // even when Flutter's focus manager or an accessibility action requests it.
    return NO;
}

static void deliver_game_key(NSWindow *window, NSEvent *event)
{
    if ([window respondsToSelector:@selector(postKeyEvent:)])
        [window postKeyEvent:event];
    else [NSApp postEvent:event atStart:NO]; // Standalone Cocoa fixture.
}

@interface MCDevDragView : NSView
@end
@implementation MCDevDragView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (void)mouseDown:(NSEvent *)event
{
    if (event.clickCount == 2) [self.window performZoom:nil];
    else [self.window performWindowDragWithEvent:event];
}
@end

@interface MCDevGameChrome : NSObject
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) FlutterEngine *engine;
@property(nonatomic, strong) FlutterViewController *flutter;
@property(nonatomic, strong) FlutterMethodChannel *channel;
@property(nonatomic, strong) NSView *container;
@property(nonatomic, weak) NSView *titlebar;
@property(nonatomic, strong) NSTitlebarAccessoryViewController *accessory;
@property(nonatomic, strong) NSMutableArray *observations;
@property(nonatomic, strong) MCDevDragView *dragView;
@property(nonatomic) NSRect dragRegion;
@property(nonatomic) BOOL layingOut;
- (BOOL)attach:(NSWindow *)window;
- (void)layout;
- (void)updateTitle;
- (void)sendKey:(NSString *)key;
@end

@implementation MCDevGameChrome
- (void)sendKey:(NSString *)key
{
    static const unsigned short functionCodes[] = {122,120,99,118,96,97,98,100,101,109,103,111};
    unsigned short code;
    NSString *characters;
    NSEventModifierFlags flags = 0;
    NSInteger function = [key hasPrefix:@"F"] ? [[key substringFromIndex:1] integerValue] : 0;
    if (function >= 1 && function <= 12 && [key isEqualToString:[NSString stringWithFormat:@"F%ld", (long)function]]) {
        code = functionCodes[function - 1];
        unichar character = NSF1FunctionKey + function - 1;
        characters = [NSString stringWithCharacters:&character length:1];
        flags = NSEventModifierFlagFunction;
    } else if ([key isEqualToString:@"escape"]) { code = 53; characters = @"\x1b"; }
    else if ([key isEqualToString:@"inventory"]) { code = 14; characters = @"e"; }
    else if ([key isEqualToString:@"chat"]) { code = 17; characters = @"t"; }
    else if ([key isEqualToString:@"command"]) { code = 44; characters = @"/"; }
    else return;

    NSWindow *window = self.window;
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:window.contentView];
    // Wine's makeKeyAndOrderFront skips its Windows focus notification when
    // Cocoa already considers the window key. A native menu can reach that
    // state before the game receives a content click, so synchronize both.
    Class controllerClass = NSClassFromString(@"WineApplicationController");
    if ([controllerClass respondsToSelector:@selector(sharedController)]) {
        id controller = [controllerClass sharedController];
        if ([controller respondsToSelector:@selector(windowGotFocus:)])
            [controller windowGotFocus:window];
    }
    // Use Wine's own event queue, never a system-wide keyboard event.
    for (NSNumber *pressed in @[@YES, @NO]) {
        // Menu tracking and Wine focus changes complete asynchronously. Keep a
        // short pulse long enough for the game's polled keyboard state too.
        int delay = pressed.boolValue ? 100 : 350;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            NSEvent *event = [NSEvent keyEventWithType:pressed.boolValue ? NSEventTypeKeyDown : NSEventTypeKeyUp
                location:NSZeroPoint modifierFlags:flags timestamp:NSProcessInfo.processInfo.systemUptime
                windowNumber:window.windowNumber context:nil characters:characters
                charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
            deliver_game_key(window, event);
        });
    }
    fprintf(stderr, "[MCDev chrome] key %s\n", key.UTF8String);
}

- (void)updateTitle
{
    NSWindow *window = self.window;
    if (!window) return;
    // Wine can update the Windows caption after the native chrome attaches.
    // Keep the macOS window switcher and minimized window label tied to this
    // test session too, not just the visible Flutter titlebar.
    NSString *displayName = game_display_name();
    if (![window.title isEqualToString:displayName]) window.title = displayName;
    if (![window.miniwindowTitle isEqualToString:displayName]) window.miniwindowTitle = displayName;
}

- (void)layout
{
    NSWindow *window = self.window;
    if (!window || self.layingOut) return;
    BOOL fullscreen = (window.styleMask & NSWindowStyleMaskFullScreen) != 0;
    BOOL titled = (window.styleMask & NSWindowStyleMaskTitled) != 0;
    self.container.hidden = fullscreen || !titled;
    if (self.container.hidden) return;
    self.layingOut = YES;
    NSView *frame = window.contentView.superview;
    CGFloat occupied = NSHeight(frame.bounds) - NSMaxY(window.contentView.frame);
    CGFloat accessoryHeight = NSHeight(self.accessory.view.frame);
    CGFloat correctedHeight = MAX(0, accessoryHeight + chromeHeight - occupied);
    if (fabs(correctedHeight - accessoryHeight) > 0.5) {
        [self.accessory.view setFrameSize:NSMakeSize(NSWidth(self.accessory.view.frame), correctedHeight)];
        [frame layoutSubtreeIfNeeded];
    }
    NSView *titlebar = self.titlebar;
    if (self.container.superview != titlebar) [titlebar addSubview:self.container];
    self.container.frame = [titlebar convertRect:NSMakeRect(0, NSHeight(frame.bounds) - chromeHeight,
        NSWidth(frame.bounds), chromeHeight) fromView:frame];
    self.flutter.view.frame = self.container.bounds;
    NSRect drag = self.dragRegion;
    if (!self.container.isFlipped) drag.origin.y = NSHeight(self.container.bounds) - NSMaxY(drag);
    self.dragView.frame = drag;
    NSInteger index = 0;
    for (NSNumber *type in @[@(NSWindowCloseButton), @(NSWindowMiniaturizeButton), @(NSWindowZoomButton)]) {
        NSButton *button = [window standardWindowButton:type.integerValue];
        if (button) {
            if (button.superview != self.container) [self.container addSubview:button];
            button.frame = NSMakeRect(12 + index * 20, (chromeHeight - NSHeight(button.frame)) / 2,
                                     NSWidth(button.frame), NSHeight(button.frame));
        }
        index++;
    }
    self.layingOut = NO;
}

- (BOOL)attach:(NSWindow *)window
{
    const char *frameworkPath = getenv("MCDEV_CHROME_FLUTTER");
    const char *appPath = getenv("MCDEV_CHROME_APP");
    if (!frameworkPath || !appPath || !dlopen(frameworkPath, RTLD_NOW | RTLD_GLOBAL)) {
        fprintf(stderr, "[MCDev chrome] Flutter framework unavailable\n");
        return NO;
    }
    NSBundle *bundle = [NSBundle bundleWithPath:@(appPath)];
    if (!bundle) return NO;
    FlutterDartProject *project = [[NSClassFromString(@"FlutterDartProject") alloc] initWithPrecompiledDartBundle:bundle];
    project.dartEntrypointArguments = @[
        @(getenv("MCDEV_CHROME_VERSION") ?: ""),
        @(getenv("MCDEV_CHROME_RENDERER") ?: ""),
        game_display_name()
    ];
    self.engine = [[NSClassFromString(@"FlutterEngine") alloc] initWithName:@"mcdev-game-chrome"
        project:project allowHeadlessExecution:YES];
    Class controllerClass = NSClassFromString(@"MCDevGameTitlebarController");
    if (!controllerClass) {
        Class base = NSClassFromString(@"FlutterViewController");
        controllerClass = objc_allocateClassPair(base, "MCDevGameTitlebarController", 0);
        SEL focusSelector = NSSelectorFromString(@"viewShouldAcceptFirstResponder:");
        Method focusMethod = class_getInstanceMethod(base, focusSelector);
        if (focusMethod) class_addMethod(controllerClass, focusSelector, (IMP)chrome_accepts_focus,
            method_getTypeEncoding(focusMethod));
        objc_registerClassPair(controllerClass);
    }
    self.flutter = [[controllerClass alloc] initWithEngine:self.engine nibName:nil bundle:nil];
    self.channel = [NSClassFromString(@"FlutterMethodChannel") methodChannelWithName:@"mcdev_income/window_chrome"
        binaryMessenger:self.engine.binaryMessenger];
    self.window = window;
    __weak MCDevGameChrome *weakSelf = self;
    [self.channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
        MCDevGameChrome *owner = weakSelf;
        NSWindow *target = owner.window;
        if ([call.method isEqualToString:@"sendKey"] && [call.arguments isKindOfClass:NSString.class])
            [owner sendKey:call.arguments];
        else if ([call.method isEqualToString:@"setDragRegion"] && [call.arguments isKindOfClass:NSDictionary.class]) {
            NSDictionary *rect = call.arguments;
            owner.dragRegion = NSMakeRect([rect[@"x"] doubleValue], [rect[@"y"] doubleValue],
                [rect[@"width"] doubleValue], [rect[@"height"] doubleValue]);
            [owner layout];
        } else if ([call.method isEqualToString:@"minimize"]) [target performMiniaturize:nil];
        else if ([call.method isEqualToString:@"zoom"]) [target performZoom:nil];
        else if ([call.method isEqualToString:@"fullscreen"]) [target toggleFullScreen:nil];
        else if ([call.method isEqualToString:@"close"]) [target performClose:nil];
        else if ([call.method isEqualToString:@"hide"]) [NSApp hide:nil];
        else if ([call.method isEqualToString:@"showAll"]) [NSApp unhideAllApplications:nil];
        else if ([call.method isEqualToString:@"about"]) [NSApp orderFrontStandardAboutPanelWithOptions:@{
            NSAboutPanelOptionApplicationName: game_display_name(),
            NSAboutPanelOptionApplicationVersion: @(getenv("MCDEV_CHROME_VERSION") ?: ""),
        }];
        result(nil);
    }];
    if (![self.engine runWithEntrypoint:@"gameChromeMain"]) return NO;

    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    if (@available(macOS 11.0, *)) window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    CGFloat originalHeight = NSHeight(window.frame) - NSHeight([window contentRectForFrameRect:window.frame]);
    self.accessory = [NSTitlebarAccessoryViewController new];
    self.accessory.layoutAttribute = NSLayoutAttributeBottom;
    self.accessory.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, MAX(0, chromeHeight - originalHeight))];
    self.accessory.fullScreenMinHeight = 0;
    [window addTitlebarAccessoryViewController:self.accessory];
    // Keep Flutter's layer tree and clipping inside the native titlebar,
    // separate from Wine's OpenGL/Metal content view.
    self.titlebar = [window standardWindowButton:NSWindowCloseButton].superview;
    self.container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(window.frame), chromeHeight)];
    self.container.wantsLayer = YES;
    self.container.layer.masksToBounds = YES;
    self.container.layer.backgroundColor = [NSColor colorWithWhite:0.15 alpha:1].CGColor;
    self.flutter.view.frame = self.container.bounds;
    self.flutter.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.container addSubview:self.flutter.view];
    self.dragView = [MCDevDragView new];
    [self.container addSubview:self.dragView];
    [self layout];
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf layout]; });
    [window makeFirstResponder:window.contentView];
    self.observations = [NSMutableArray new];
    [self updateTitle];
    // Do not relayout Flutter for every Wine window update; only repair its
    // label when Wine changes the caption after startup.
    [self.observations addObject:[NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowDidUpdateNotification object:window
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            [weakSelf updateTitle];
        }]];
    for (NSString *name in @[NSWindowDidResizeNotification, NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification]) {
        id token = [NSNotificationCenter.defaultCenter addObserverForName:name object:window queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            [weakSelf layout];
        }];
        [self.observations addObject:token];
    }
    // Bring the game itself back to the foreground after starting the embedded
    // engine. Wine can otherwise defer its first drawable until a content click.
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    fprintf(stderr, "[MCDev chrome] attached; frame=%.0fx%.0f content=%.0fx%.0f layout=%.0fx%.0f\n",
        NSWidth(window.frame), NSHeight(window.frame), NSWidth(window.contentView.frame), NSHeight(window.contentView.frame),
        NSWidth(window.contentLayoutRect), NSHeight(window.contentLayoutRect));
    return YES;
}

- (void)dealloc
{
    for (id token in self.observations) [NSNotificationCenter.defaultCenter removeObserver:token];
    [self.engine shutDownEngine];
}
@end

__attribute__((constructor))
static void install_game_chrome(void)
{
    const char *expected = getenv("MCDEV_CHROME_LOADER");
    if (!expected) return;
    char executable[4096];
    char resolvedExecutable[4096], resolvedExpected[4096];
    uint32_t length = sizeof(executable);
    if (_NSGetExecutablePath(executable, &length) ||
        !realpath(executable, resolvedExecutable) || !realpath(expected, resolvedExpected) ||
        strcmp(resolvedExecutable, resolvedExpected)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        __block id observer;
        observer = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidUpdateNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                NSWindow *window = note.object;
                Class wineClass = NSClassFromString(@"WineWindow");
                if (!wineClass || ![window isKindOfClass:wineClass] || window.parentWindow ||
                    !window.visible || ![window.title containsString:@"Minecraft"] ||
                    NSWidth(window.frame) < 320 || objc_getAssociatedObject(window, chromeKey)) return;
                MCDevGameChrome *chrome = [MCDevGameChrome new];
                objc_setAssociatedObject(window, chromeKey, chrome, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [NSNotificationCenter.defaultCenter removeObserver:observer];
                observer = nil;
                // Finish Wine's current window update before starting Flutter
                // and changing content geometry; engine startup can run AppKit.
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (window.visible && ![chrome attach:window])
                        fprintf(stderr, "[MCDev chrome] initialization failed\n");
                });
            }];
    });
}
