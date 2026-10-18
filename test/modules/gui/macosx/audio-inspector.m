/*****************************************************************************
 * audio-inspector.m: inline filter controls against a real dummy audio output
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <vlc_common.h>
#include <vlc_aout.h>
#include <vlc_configuration.h>
#include "lib/libvlc_internal.h"
#include "lib/media_player_internal.h"

@protocol AudioInspectorTest <NSObject>
- (void)buildAudio;
@end
@protocol AudioNumberTest <NSObject>
- (void)controlTextDidEndEditing:(NSNotification *)notification;
@end
@protocol AudioButtonTest <NSObject>
@property (copy) void (^activate)(void);
@end

@interface InspectorAudioPlayer : NSObject
@property vlc_player_t *player;
- (audio_output_t *)mainAudioOutput;
@end
@implementation InspectorAudioPlayer
- (audio_output_t *)mainAudioOutput { return vlc_player_aout_Hold(_player); }
@end

static InspectorAudioPlayer *testPlayer;
static id Player(id self, SEL selector) { (void)self; (void)selector; return testPlayer; }
static void Refresh(id self, SEL selector) { (void)self; (void)selector; }

static BOOL Check(BOOL condition, const char *description)
{
    fprintf(stderr, "%s: %s\n", description, condition ? "PASS" : "FAIL");
    return condition;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc != 3)
            return 1;
        [NSApplication sharedApplication];
        if (!dlopen(argv[1], RTLD_NOW | RTLD_LOCAL)) {
            fprintf(stderr, "%s\n", dlerror());
            return 1;
        }
        const char *options[] = { "--ignore-config", "--quiet", "--no-media-library", "--aout=dummy", "--input-repeat=10" };
        libvlc_instance_t *vlc = libvlc_new(ARRAY_SIZE(options), options);
        if (!vlc)
            return 1;
        libvlc_media_player_t *mediaPlayer = libvlc_media_player_new(vlc, NULL, NULL);
        libvlc_media_t *media = libvlc_media_new_path(argv[2]);
        libvlc_media_player_set_media(mediaPlayer, media);
        libvlc_media_release(media);
        libvlc_media_player_play(mediaPlayer);
        testPlayer = [[InspectorAudioPlayer alloc] init];
        testPlayer.player = mediaPlayer->player;
        audio_output_t *aout = NULL;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!aout && deadline.timeIntervalSinceNow > 0) {
            aout = testPlayer.mainAudioOutput;
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        }
        if (!aout)
            return 1;
        /* Bypass the native interface initializer and its timers. The controls
         * and applyNumber binding are production methods; only the player
         * accessor points at this test's isolated, silent libVLC instance. */
        Class inspectorClass = objc_allocateClassPair(NSClassFromString(@"VLCRedesignInspector"),
                                                       "VLCInlineAudioInspectorTest", 0);
        class_addMethod(inspectorClass, @selector(player), (IMP)Player, "@@:");
        class_addMethod(inspectorClass, @selector(refresh), (IMP)Refresh, "v@:");
        objc_registerClassPair(inspectorClass);
        NSView<AudioInspectorTest> *inspector = [[inspectorClass alloc] initWithFrame:NSMakeRect(0, 0, 400, 800)];
        for (NSString *key in @[@"numberRows", @"popups", @"toggles", @"audioParameters", @"audioGroups"])
            [inspector setValue:[NSMutableDictionary dictionary] forKey:key];
        [inspector setValue:[NSMutableSet set] forKey:@"expandedAudioGroups"];
        [inspector setValue:[NSMutableArray array] forKey:@"content"];
        [inspector buildAudio];
        NSDictionary *parameters = [inspector valueForKey:@"audioParameters"];
        NSDictionary *rows = [inspector valueForKey:@"numberRows"];
        NSDictionary *groups = [inspector valueForKey:@"audioGroups"];
        NSArray<NSView *> *content = [inspector valueForKey:@"content"];
        BOOL passed = Check(parameters.count == 16, "All 16 module-backed parameters are available");
        NSArray *keys = @[@"compressor-attack", @"spatializer-wet", @"stereowiden-dry-mix"];
        NSArray<NSNumber *> *values = @[@75, @.75, @.2];
        for (NSUInteger i = 0; i < keys.count; i++) {
            NSString *key = keys[i];
            NSString *filter = parameters[key];
            vlc_player_aout_EnableFilter(testPlayer.player, filter.UTF8String, true);
            NSView<AudioNumberTest> *row = rows[key];
            NSTextField *field = [row valueForKey:@"field"];
            field.enabled = YES;
            NSSlider *slider = [row valueForKey:@"slider"];
            slider.enabled = YES;
            NSNumberFormatter *formatter = [row valueForKey:@"formatter"];
            field.stringValue = [formatter stringFromNumber:values[i]];
            [(id<AudioNumberTest>)row controlTextDidEndEditing:
                [NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:field]];
            passed &= Check(fabs(var_GetFloat(aout, key.UTF8String) - values[i].doubleValue) < .0001,
                            "Numeric edit updates the current audio output");
            passed &= Check(row.hidden, "Parameter section starts collapsed");
            NSView *first = ((NSArray *)groups[filter]).firstObject;
            NSUInteger firstIndex = [content indexOfObject:first];
            id<AudioButtonTest> disclosure = (id)content[firstIndex - 1];
            disclosure.activate();
            passed &= Check(!row.hidden, "Expand Settings reveals the filter parameters");
            disclosure.activate();
            passed &= Check(row.hidden, "Collapse Settings hides the filter parameters");
            id<AudioButtonTest> reset = ((NSArray *)groups[filter]).lastObject;
            reset.activate();
            module_config_t *option = config_FindConfig(key.UTF8String);
            passed &= Check(fabs(var_GetFloat(aout, key.UTF8String) - option->orig.f) < .0001,
                            "Reset restores the module's default on the active output");
        }
        aout_Release(aout);
        libvlc_media_player_stop_async(mediaPlayer);
        libvlc_media_player_release(mediaPlayer);
        libvlc_release(vlc);
        return passed ? 0 : 1;
    }
}
