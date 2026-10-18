/*****************************************************************************
 * fullscreen-controls.m: fullscreen edge and open-panel visibility checks
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <dlfcn.h>

@interface PointerWindow : NSWindow
@property NSPoint testPointer;
@end
@implementation PointerWindow
- (BOOL)isVisible { return YES; }
- (NSPoint)mouseLocationOutsideOfEventStream { return _testPointer; }
@end

@interface FullscreenPlayer : NSObject
@property BOOL fullscreen;
@end
@implementation FullscreenPlayer
@end

static FullscreenPlayer *player;
static id TestPlayer(id self, SEL selector)
{
    (void)self;
    (void)selector;
    return player;
}

@protocol ChromeVisibility <NSObject>
- (void)updateVisibility;
@end

static BOOL Check(BOOL condition, const char *description)
{
    fprintf(stderr, "%s: %s\n", description, condition ? "PASS" : "FAIL");
    return condition;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc != 2)
            return 1;
        [NSApplication sharedApplication];
        if (!dlopen(argv[1], RTLD_NOW | RTLD_LOCAL)) {
            fprintf(stderr, "%s\n", dlerror());
            return 1;
        }
        Class testClass = objc_allocateClassPair(NSClassFromString(@"VLCRedesignPlayerChrome"),
                                                "VLCFullscreenVisibilityTest", 0);
        class_addMethod(testClass, @selector(player), (IMP)TestPlayer, "@@:");
        objc_registerClassPair(testClass);
        /* Bypass the live-player initializer; exercise the real visibility
         * method with native AppKit geometry and an injected pointer source. */
        NSView<ChromeVisibility> *chrome = [[testClass alloc] initWithFrame:NSMakeRect(0, 0, 1000, 700)];
        PointerWindow *window = [[PointerWindow alloc] initWithContentRect:chrome.bounds
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.contentView = chrome;
        NSView *top = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 40)];
        NSView *bottom = [[NSView alloc] initWithFrame:NSMakeRect(0, 646, 1000, 54)];
        [chrome setValue:top forKey:@"topBar"];
        [chrome setValue:bottom forKey:@"bottomBar"];
        player = [[FullscreenPlayer alloc] init];
        player.fullscreen = YES;
        window.testPointer = [chrome convertPoint:NSMakePoint(500, 350) toView:nil];
        [chrome updateVisibility];
        BOOL passed = Check(top.hidden && bottom.hidden, "Fullscreen hides chrome away from the edges");
        window.testPointer = [chrome convertPoint:NSMakePoint(500, 20) toView:nil];
        [chrome updateVisibility];
        passed &= Check(!top.hidden && bottom.hidden, "The top edge reveals title controls");
        window.testPointer = [chrome convertPoint:NSMakePoint(500, 680) toView:nil];
        [chrome updateVisibility];
        passed &= Check(top.hidden && !bottom.hidden, "The bottom edge reveals transport");
        window.testPointer = [chrome convertPoint:NSMakePoint(-1, 680) toView:nil];
        [chrome updateVisibility];
        passed &= Check(top.hidden && bottom.hidden, "Leaving the window hides both bars");
        for (NSString *key in @[@"trackPanel", @"queuePanel", @"inspector", @"resumePrompt"]) {
            [chrome setValue:[[NSView alloc] init] forKey:key];
            [chrome updateVisibility];
            passed &= Check(!top.hidden && !bottom.hidden, "An open player panel keeps controls visible");
            [chrome setValue:nil forKey:key];
        }
        player.fullscreen = NO;
        [chrome updateVisibility];
        passed &= Check(!top.hidden && !bottom.hidden, "Windowed controls remain visible");
        return passed ? 0 : 1;
    }
}
