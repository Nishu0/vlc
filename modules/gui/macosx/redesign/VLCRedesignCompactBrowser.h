/*****************************************************************************
 * VLCRedesignCompactBrowser.h: Compact media library beside the video
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#import <Cocoa/Cocoa.h>
@class VLCMediaSource;
@interface VLCRedesignCompactBrowser : NSView
@property (copy) void (^expandLibrary)(NSURL *folder, NSInteger section, BOOL grid);
@property (copy) void (^openNetworkSource)(VLCMediaSource *source);
@property (copy) void (^folderChanged)(NSURL *folder);
@property (readonly) NSURL *currentFolderURL;
- (void)browseFolder:(NSURL *)url;
- (void)reload;
@end
