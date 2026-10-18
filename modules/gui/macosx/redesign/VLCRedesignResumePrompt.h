/*****************************************************************************
 * VLCRedesignResumePrompt.h: Resume notification beside the player controls
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface VLCRedesignResumePrompt : NSView
- (instancetype)initWithPosition:(NSInteger)seconds choice:(void (^)(BOOL continuePlayback))choice;
- (void)dismiss:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
