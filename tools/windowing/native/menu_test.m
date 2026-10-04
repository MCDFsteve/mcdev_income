// In-process regression tests; no game, Flutter engine, login or visible window.
#import "game_chrome.m"
#include <assert.h>

@interface WineApplicationController : NSObject
@property(nonatomic) CGEventSourceKeyboardType keyboardType;
+ (instancetype)sharedController;
@end
@implementation WineApplicationController
+ (instancetype)sharedController
{
    static WineApplicationController *controller;
    if (!controller) controller = [WineApplicationController new];
    return controller;
}
@end

@interface MenuTestWindow : NSObject
@property(nonatomic, strong) NSEvent *lastEvent;
- (void)postKeyEvent:(NSEvent *)event;
- (void)flagsChanged:(NSEvent *)event;
- (void)postKey:(uint16_t)code pressed:(BOOL)pressed modifiers:(NSUInteger)modifiers event:(NSEvent *)event;
@end
@implementation MenuTestWindow
- (void)flagsChanged:(NSEvent *)event { (void)event; }
- (void)postKey:(uint16_t)code pressed:(BOOL)pressed modifiers:(NSUInteger)modifiers event:(NSEvent *)event
{
    assert(code == event.keyCode && pressed == (event.type == NSEventTypeKeyDown) && modifiers == event.modifierFlags);
    self.lastEvent = event;
}
- (void)postKeyEvent:(NSEvent *)event
{
    self.lastEvent = event;
    // Match WineWindow's behavior, which must not reset the physical layout.
    [WineApplicationController sharedController].keyboardType =
        (CGEventSourceKeyboardType)CGEventGetIntegerValueField(event.CGEvent, kCGKeyboardEventKeyboardType);
}
@end

@interface MenuTestChrome : MCDevGameChrome
@property(nonatomic, strong) NSDictionary *lastCommand;
@end
@implementation MenuTestChrome
- (BOOL)performAction:(NSString *)action argument:(id)argument
{
    self.lastCommand = @{@"action": action, @"argument": argument ?: NSNull.null};
    return YES;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSApp.activationPolicy = NSApplicationActivationPolicyProhibited;
        MenuTestWindow *window = [MenuTestWindow new];
        for (NSNumber *pressed in @[@YES, @NO]) {
            [WineApplicationController sharedController].keyboardType = 45;
            NSEvent *event = [NSEvent keyEventWithType:pressed.boolValue ? NSEventTypeKeyDown : NSEventTypeKeyUp
                location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                windowNumber:0 context:nil characters:@"e" charactersIgnoringModifiers:@"e" isARepeat:NO keyCode:14];
            [window postKeyEvent:event];
            assert([WineApplicationController sharedController].keyboardType == 0);
            [WineApplicationController sharedController].keyboardType = 45;
            deliver_game_key((NSWindow *)(id)window, event);
            assert(window.lastEvent.keyCode == 14);
            assert([WineApplicationController sharedController].keyboardType == 45);
        }
        MenuTestChrome *chrome = [MenuTestChrome new];
        NSDictionary *key = @{@"label": @"物品栏", @"enabled": @YES, @"action": @"sendKey", @"argument": @"inventory"};
        NSMenuItem *item = [chrome menuItem:key];
        assert(item.target == chrome && item.action == @selector(menuItemSelected:) && item.enabled);
        [chrome menuItemSelected:item];
        assert(chrome.lastCommand == nil); // Action must leave menu tracking first.
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
        while (!chrome.lastCommand && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
        assert([chrome.lastCommand[@"action"] isEqual:@"sendKey"]);
        assert([chrome.lastCommand[@"argument"] isEqual:@"inventory"]);
        NSMenuItem *fullscreen = [chrome menuItem:@{@"label": @"全屏", @"enabled": @YES,
            @"action": @"fullscreen", @"shortcutTrigger": @102, @"shortcutModifiers": @9}];
        assert([fullscreen.keyEquivalent isEqual:@"f"]);
        assert(fullscreen.keyEquivalentModifierMask == (NSEventModifierFlagCommand | NSEventModifierFlagControl));
        [chrome setMenus:@{@"0": @[@{@"label": @"游戏", @"children": @[key, @{@"isDivider": @YES}]}]}];
        NSMenuItem *menu = [NSApp.mainMenu itemWithTitle:@"游戏"];
        assert(menu.enabled && menu.submenu.numberOfItems == 2);
        assert(!menu.submenu.autoenablesItems && menu.submenu.itemArray.lastObject.separatorItem);
        puts("Native game menu tests passed");
    }
    return 0;
}
