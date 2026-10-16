/*****************************************************************************
 * VLCOnboardingWindowController.h: Native first-launch onboarding
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface VLCOnboardingWindowController : NSWindowController

@property (class, readonly) BOOL completed;

@end

NS_ASSUME_NONNULL_END
