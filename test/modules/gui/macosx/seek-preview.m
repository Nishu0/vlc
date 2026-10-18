/*****************************************************************************
 * seek-preview.m: native seek preview cancellation and real decoding checks
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#import "redesign/VLCRedesignSeekPreview.h"
#include <vlc_common.h>
#include <vlc_input_item.h>
#include <vlc_preparser.h>
#include "lib/libvlc_internal.h"

/* Link the production view objects without starting the interface or touching
 * the user's playback. Supply only its interface-owned thumbnailer and string
 * conversion helper. The preparser and decoders below are real VLC modules. */
static vlc_preparser_t *thumbnailer;
vlc_preparser_t *getThumbnailer(void) { return thumbnailer; }
NSString *toNSStr(const char *text)
{
    return text ? [NSString stringWithUTF8String:text] : @"";
}

@interface PreviewInput : NSObject
@property (readonly) input_item_t *vlcInputItem;
- (instancetype)initWithURL:(NSURL *)url;
@end
@implementation PreviewInput
- (instancetype)initWithURL:(NSURL *)url
{
    self = [super init];
    if (self)
        _vlcInputItem = input_item_New(url.absoluteString.UTF8String, "Seek preview test");
    return self;
}
- (void)dealloc
{
    if (_vlcInputItem)
        input_item_Release(_vlcInputItem);
}
@end

@protocol PreviewRequest <NSObject>
@property (readonly) vlc_preparser_req *handle;
@property (readonly) NSString *path;
@end

static BOOL Check(BOOL condition, const char *description)
{
    fprintf(stderr, "%s: %s\n", description, condition ? "PASS" : "FAIL");
    return condition;
}

static BOOL Await(BOOL (^condition)(void), NSTimeInterval timeout)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode
                           beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return condition();
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "Usage: %s /path/to/video-with-changing-frames\n", argv[0]);
            return 1;
        }
        [NSApplication sharedApplication];
        const char *options[] = { "--ignore-config", "--quiet", "--no-media-library" };
        libvlc_instance_t *vlc = libvlc_new(ARRAY_SIZE(options), options);
        if (!vlc)
            return 1;
        const struct vlc_preparser_cfg config = {
            .types = VLC_PREPARSER_TYPE_THUMBNAIL_TO_FILES,
            .max_thumbnailer_threads = 1,
            .timeout = VLC_TICK_FROM_SEC(8),
        };
        thumbnailer = vlc_preparser_New(VLC_OBJECT(vlc->p_libvlc_int), &config);
        if (!thumbnailer) {
            libvlc_release(vlc);
            return 1;
        }
        PreviewInput *input = [[PreviewInput alloc] initWithURL:
            [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];
        VLCRedesignSeekPreview *preview = [[VLCRedesignSeekPreview alloc] init];
        NSImageView *imageView = [preview valueForKey:@"imageView"];
        NSTextField *label = [preview valueForKey:@"timeLabel"];
        [preview showInputItem:(id)input atTime:VLC_TICK_FROM_SEC(10)];
        BOOL passed = Check(Await(^BOOL { return imageView.image != nil; }, 10),
                            "Independent decoder produces a thumbnail at 10 seconds");
        NSImage *firstImage = imageView.image;
        NSData *first = firstImage.TIFFRepresentation;
        [preview showInputItem:(id)input atTime:VLC_TICK_FROM_SEC(80)];
        passed &= Check(Await(^BOOL { return imageView.image != nil; }, 10),
                        "A second timestamp decodes");
        passed &= Check(first && ![first isEqualToData:imageView.image.TIFFRepresentation],
                        "Different timestamps produce different frames");
        passed &= Check([label.stringValue isEqualToString:@"00:01:20"],
                        "The displayed timestamp matches the requested frame");
        [preview showInputItem:(id)input atTime:VLC_TICK_FROM_SEC(10)];
        passed &= Check(imageView.image == firstImage && ![preview valueForKey:@"request"],
                        "Revisiting a timestamp uses the bounded memory cache");

        [preview showInputItem:(id)input atTime:VLC_TICK_FROM_SEC(30)];
        passed &= Check(Await(^BOOL { return [preview valueForKey:@"request"] != nil; }, 2),
                        "An uncached timestamp submits a request");
        id<PreviewRequest> oldRequest = [preview valueForKey:@"request"];
        NSString *oldPath = oldRequest.path;
        [preview showInputItem:(id)input atTime:VLC_TICK_FROM_SEC(10)];
        passed &= Check(Await(^BOOL { return oldRequest.handle == NULL; }, 10),
                        "Superseded requests release their handles");
        passed &= Check(imageView.image == firstImage &&
                        ![NSFileManager.defaultManager fileExistsAtPath:oldPath],
                        "Stale completion cannot replace the image and leaves no temporary file");

        PreviewInput *replacement = [[PreviewInput alloc] initWithURL:
            [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];
        [preview showInputItem:(id)replacement atTime:VLC_TICK_FROM_SEC(10)];
        passed &= Check(!imageView.image, "Changing the input invalidates the previous cache");
        [preview cancel];
        passed &= Check(preview.hidden && ![preview valueForKey:@"request"] &&
                        ![preview valueForKey:@"debounceTimer"],
                        "Cancel hides the preview and invalidates its pending debounce");
        [preview showInputItem:(id)input atTime:VLC_TICK_FROM_SEC(40)];
        passed &= Check(Await(^BOOL { return [preview valueForKey:@"request"] != nil; }, 2),
                        "A request starts before owner teardown");
        oldRequest = [preview valueForKey:@"request"];
        oldPath = oldRequest.path;
        preview = nil;
        passed &= Check(Await(^BOOL { return oldRequest.handle == NULL; }, 10) &&
                        ![NSFileManager.defaultManager fileExistsAtPath:oldPath],
                        "Owner teardown cancels decoding and cleans its output");
        vlc_preparser_Delete(thumbnailer);
        thumbnailer = NULL;
        libvlc_release(vlc);
        return passed ? 0 : 1;
    }
}
