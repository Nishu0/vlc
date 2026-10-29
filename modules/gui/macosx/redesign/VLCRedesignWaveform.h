/*****************************************************************************
 * VLCRedesignWaveform.h: Waveform seek bar for music playback
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface VLCRedesignWaveform : NSView

@property (nonatomic) double position;
@property (nonatomic, readonly) BOOL dragging;
@property (nonatomic) BOOL enabled;
// Called with each position the user picks; finished is YES on mouse up
@property (nonatomic, copy, nullable) void (^seek)(double position, BOOL finished);

// Decodes the file in the background; non-file or unreadable media keeps flat bars
- (void)loadURL:(nullable NSURL *)url;

@end

NS_ASSUME_NONNULL_END
