/*****************************************************************************
 * VLCRedesignPlayerChrome.h: Native redesigned playback surface
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class VLCMainVideoViewController;

/* Owns only presentation and action bindings. VLC keeps ownership of the vout. */
@interface VLCRedesignPlayerChrome : NSView
- (instancetype)initWithVideoController:(VLCMainVideoViewController *)controller;
- (void)mountVideoView:(NSView *)videoView;
- (void)updatePlayer;
- (void)showResumeAtPosition:(NSInteger)seconds choice:(void (^)(BOOL continuePlayback))choice;
- (void)cancelResumePrompt;
- (void)updateVisibility;
@property (readonly) BOOL mouseOnControls;
@end

NS_ASSUME_NONNULL_END
