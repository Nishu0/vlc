/*****************************************************************************
 * file-drop.m: macOS file-drop parser regression checks
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#include <dlfcn.h>

/* Load the parser from the built interface module, without starting VLC's UI. */
@interface NSObject (VLCFileDropTest)
+ (NSArray *)inputMetadataFromPasteboard:(NSPasteboard *)pasteboard;
@end

/* AppKit rejects malformed legacy data while publishing it. Supply those
 * values directly so the parser's validation is exercised independently. */
@interface VLCMalformedPasteboard : NSObject
@property (nonatomic, strong) id payload;
@end

@implementation VLCMalformedPasteboard
- (NSArray *)pasteboardItems
{
    return @[];
}

- (id)propertyListForType:(NSString *)type
{
    (void)type;
    return self.payload;
}
@end

static BOOL CheckPayload(Class parser, NSPasteboard *pasteboard, NSString *type,
                         id payload, NSString *expectedURL)
{
    [pasteboard clearContents];
    NSPasteboard *input = pasteboard;
    if ([type isEqualToString:@"NSFilenamesPboardType"]) {
        VLCMalformedPasteboard *legacy = [[VLCMalformedPasteboard alloc] init];
        legacy.payload = payload;
        input = (NSPasteboard *)legacy;
    } else if (payload) {
        NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
        [item setString:payload forType:type];
        [pasteboard writeObjects:@[item]];
    }
    NSArray *items = [parser inputMetadataFromPasteboard:input];
    BOOL passed = expectedURL ? items.count == 1 &&
        [[items.firstObject valueForKey:@"MRLString"] isEqualToString:expectedURL] : items.count == 0;
    fprintf(stderr, "%s: %s\n", type.UTF8String, passed ? "PASS" : "FAIL");
    return passed;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "Usage: %s /path/to/libmacosx_plugin.dylib\n", argv[0]);
            return 1;
        }
        [NSApplication sharedApplication];
        if (!dlopen(argv[1], RTLD_NOW | RTLD_LOCAL)) {
            fprintf(stderr, "%s\n", dlerror());
            return 1;
        }
        Class parser = NSClassFromString(@"VLCFileDragRecognisingView");
        if (!parser || ![parser respondsToSelector:@selector(inputMetadataFromPasteboard:)])
            return 1;

        NSString *name = [NSString stringWithFormat:@"VLC file-drop %@.mp4", NSUUID.UUID.UUIDString];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        if (![NSData.data writeToFile:path atomically:YES])
            return 1;
        NSString *fileURL = [NSURL fileURLWithPath:path].absoluteString;
        NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
        BOOL passed = YES;
        for (NSString *type in @[NSPasteboardTypeFileURL, NSPasteboardTypeString])
            passed &= CheckPayload(parser, pasteboard, type, fileURL, fileURL);
        passed &= CheckPayload(parser, pasteboard, NSPasteboardTypeURL,
                               @"https://example.invalid/stream", @"https://example.invalid/stream");
        passed &= CheckPayload(parser, pasteboard, NSPasteboardTypeString, path, fileURL);
        passed &= CheckPayload(parser, pasteboard, NSPasteboardTypeString, @"relative.mp4", nil);
        passed &= CheckPayload(parser, pasteboard, NSPasteboardTypeString, nil, nil);

        /* Keep testing the legacy format accepted from older drag sources. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSString *legacyType = NSFilenamesPboardType;
#pragma clang diagnostic pop
        passed &= CheckPayload(parser, pasteboard, legacyType, @[path], fileURL);
        passed &= CheckPayload(parser, pasteboard, legacyType,
                               @[@42, @"relative.mp4", @{}, path], fileURL);
        passed &= CheckPayload(parser, pasteboard, legacyType, @[@42, @"relative.mp4"], nil);
        passed &= CheckPayload(parser, pasteboard, legacyType, @{@"path": path}, nil);
        passed &= CheckPayload(parser, pasteboard, legacyType, path, nil);
        passed &= CheckPayload(parser, pasteboard, legacyType, @[], nil);
        [pasteboard releaseGlobally];
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        return passed ? 0 : 1;
    }
}
