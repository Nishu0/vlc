/*****************************************************************************
 * Native controls shared by the redesigned player panels
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NSImage *_Nullable VLCRedesignPanelImage(NSString *name);

@interface VLCRedesignPanelButton : NSButton
@property (nonatomic, copy, nullable) void (^activate)(void);
@property BOOL tab;
@property BOOL footer;
@property BOOL highlightedSelection;
@property (nonatomic, strong, nullable) NSImage *selectionImage;
@property (nonatomic, strong, nullable) NSImage *underlineImage;
@end

NS_ASSUME_NONNULL_END
