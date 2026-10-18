/*****************************************************************************
 * pip-container.m: PiP callbacks must not constrain the returned video view
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#include <dlfcn.h>

@protocol PiPContainerTest <NSObject>
- (instancetype)initWithVideoView:(NSView *)videoView;
@property (readonly) NSView *videoView;
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
        Class pipClass = NSClassFromString(@"PIPVoutViewController");
        if (![pipClass instancesRespondToSelector:@selector(initWithVideoView:)])
            return 1;
        NSView *video = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 360)];
        NSViewController<PiPContainerTest> *controller = (id)[(id<PiPContainerTest>)[pipClass alloc]
            initWithVideoView:video];
        BOOL passed = Check(controller.view != video && controller.videoView == video &&
                            video.superview == controller.view,
                            "PiP owns a container around the transferable video");
        NSView *pipHost = [[NSView alloc] initWithFrame:video.bounds];
        [pipHost addSubview:controller.view];
        controller.view.translatesAutoresizingMaskIntoConstraints = NO;
        [controller viewWillAppear];
        [pipHost layoutSubtreeIfNeeded];
        passed &= Check(NSEqualRects(video.frame, controller.view.bounds),
                        "Video fills the PiP container");

        NSView *player = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 700)];
        [video removeFromSuperview];
        video.autoresizingMask = NSViewNotSizable;
        NSRect target = NSMakeRect(10, 40, 980, 606);
        video.frame = target;
        [player addSubview:video];
        /* PiP can deliver this appearance callback after the real video has
         * been mounted in the player. It must only constrain its own container. */
        [controller viewWillAppear];
        [controller viewDidLayout];
        [player layoutSubtreeIfNeeded];
        passed &= Check(player.constraints.count == 0,
                        "A late PiP callback does not add fill constraints to the player");
        passed &= Check(NSEqualRects(video.frame, target) && NSEqualSizes(player.frame.size, NSMakeSize(1000, 700)),
                        "The returned video and player retain their geometry");
        return passed ? 0 : 1;
    }
}
