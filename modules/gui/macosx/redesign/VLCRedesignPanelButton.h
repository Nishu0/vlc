/*****************************************************************************
 * Native controls shared by the redesigned player panels
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#import <Cocoa/Cocoa.h>

NSImage *VLCRedesignPanelImage(NSString *name);

@interface VLCRedesignPanelButton : NSButton
@property (copy) void (^activate)(void);
@property BOOL tab;
@property BOOL footer;
@property BOOL highlightedSelection;
@property NSImage *selectionImage;
@property NSImage *underlineImage;
@end
