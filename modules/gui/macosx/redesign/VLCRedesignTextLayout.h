/*****************************************************************************
 * VLCRedesignTextLayout.h: Text alignment for redesigned native controls
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/* Center visible text vertically, respecting line wrapping and horizontal alignment. */
void VLCDrawAlignedText(NSAttributedString *text, NSRect bounds, BOOL flipped, NSTextAlignment alignment);

/* A non-editable native label for text centered within a control or row. */
@interface VLCRedesignAlignedLabel : NSTextField
@end

NS_ASSUME_NONNULL_END
