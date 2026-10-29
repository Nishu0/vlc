/*****************************************************************************
 * VLCRedesignCompactBrowser.h: Compact media library beside the video
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class VLCMediaSource;

typedef NS_ENUM(NSInteger, VLCRedesignBrowserSection) {
    VLCRedesignBrowserSectionHome,
    VLCRedesignBrowserSectionVideos,
    VLCRedesignBrowserSectionMusic,
    VLCRedesignBrowserSectionNetwork,
    VLCRedesignBrowserSectionPlaylists,
    VLCRedesignBrowserSectionRecent,
    VLCRedesignBrowserSectionOpenMedia,
};

@interface VLCRedesignCompactBrowser : NSView

@property (nonatomic, copy, nullable) void (^expandLibrary)
    (NSURL *_Nullable folder, VLCRedesignBrowserSection section, BOOL grid);
@property (nonatomic, copy, nullable) void (^openNetworkSource)(VLCMediaSource *source);
@property (nonatomic, readonly, nullable) NSURL *currentFolderURL;
// Full-window library: labelled sidebar, breadcrumbs, large grid and Home sections
@property (nonatomic) BOOL fullLibrary;

- (void)browseFolder:(NSURL *)url;
- (void)showSection:(VLCRedesignBrowserSection)section;
- (void)setGridMode:(BOOL)grid;
- (void)reload;

@end

NS_ASSUME_NONNULL_END
