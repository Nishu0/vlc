/*****************************************************************************
 * window-commands.m: video window commands must leave the main queue available
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <vlc_common.h>
#include <vlc_player.h>
#include "lib/libvlc_internal.h"

@protocol WindowCommandTest <NSObject>
- (void)enqueueVideoOutputCommand:(void (^)(vout_thread_t *))command
                  forVideoOutput:(vout_thread_t *)vout;
@end

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
        const char *options[] = { "--ignore-config", "--quiet", "--no-media-library" };
        libvlc_instance_t *vlc = libvlc_new(ARRAY_SIZE(options), options);
        if (!vlc)
            return 1;
        vlc_player_t *player = vlc_player_New(VLC_OBJECT(vlc->p_libvlc_int), VLC_PLAYER_LOCK_NORMAL);
        vout_thread_t *vout = vlc_player_vout_Hold(player);
        /* This method owns no controller state. Do not initialize the native
         * interface, remote controls, preferences or the user's player. */
        id<WindowCommandTest> controller = [[NSClassFromString(@"VLCPlayerController") alloc] init];
        if (![controller respondsToSelector:@selector(enqueueVideoOutputCommand:forVideoOutput:)])
            return 1;
        __block BOOL firstFinished = NO;
        __block BOOL mainServiced = NO;
        __block BOOL serial = NO;
        __block BOOL finished = NO;
        __block BOOL background = NO;
        [controller enqueueVideoOutputCommand:^(vout_thread_t *output) {
            background = !NSThread.isMainThread && output == vout;
            /* Model WindowEnable waiting synchronously for AppKit while a
             * window-state command is in flight. */
            dispatch_sync(dispatch_get_main_queue(), ^{ mainServiced = YES; });
            firstFinished = YES;
        } forVideoOutput:vout];
        [controller enqueueVideoOutputCommand:^(vout_thread_t *output) {
            serial = firstFinished && output == vout;
            dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
        } forVideoOutput:vout];
        vout_Release(vout);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!finished && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        BOOL passed = finished && mainServiced && serial && background;
        fprintf(stderr, "Main queue remains available; commands run serially on held outputs: %s\n",
                passed ? "PASS" : "FAIL");
        if (!finished)
            return 1;
        vlc_player_Delete(player);
        libvlc_release(vlc);
        return passed ? 0 : 1;
    }
}
