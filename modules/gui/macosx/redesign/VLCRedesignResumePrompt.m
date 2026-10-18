/*****************************************************************************
 * VLCRedesignResumePrompt.m: Resume notification beside the player controls
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignResumePrompt.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignPanelButton.h"
#import "VLCRedesignTextLayout.h"
#import "extensions/NSString+Helpers.h"

@interface VLCResumePromptButton : NSButton
@property BOOL primary;
@end

@implementation VLCResumePromptButton

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSColor *background = self.primary ? VLCRedesignAppearance.accentColor
                                       : [VLCRedesignAppearance colorWithRGB:self.highlighted ? 0x333333 : 0x191919];
    [background setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill];
    if (self.image) {
        NSSize size = self.image.size;
        [self.image drawInRect:NSMakeRect(NSMidX(self.bounds) - size.width / 2, NSMidY(self.bounds) - size.height / 2,
                                          size.width, size.height)
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1
                respectFlipped:YES
                         hints:nil];
    } else {
        NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
        paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
        NSAttributedString *title = [[NSAttributedString alloc]
            initWithString:self.title
                attributes:@{
                    NSFontAttributeName : [VLCRedesignAppearance fontOfSize:13 weight:NSFontWeightRegular],
                    NSForegroundColorAttributeName : NSColor.blackColor,
                    NSParagraphStyleAttributeName : paragraph
                }];
        VLCDrawAlignedText(title, NSInsetRect(self.bounds, 8, 0), YES, NSTextAlignmentCenter);
    }
    if (self.window.firstResponder == self) {
        [NSColor.whiteColor setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2, 2) xRadius:3 yRadius:3] stroke];
    }
}

@end

@interface VLCRedesignResumePrompt ()
@property VLCRedesignAlignedLabel *message;
@property VLCResumePromptButton *continueButton;
@property VLCResumePromptButton *dismissButton;
@property NSString *positionText;
@property NSString *fullMessage;
@property (nonatomic, copy) void (^choice)(BOOL);
- (void)finishWithChoice:(BOOL)continuePlayback;
@end

@implementation VLCRedesignResumePrompt

- (BOOL)isFlipped
{
    return YES;
}

- (instancetype)initWithPosition:(NSInteger)seconds choice:(void (^)(BOOL))choice
{
    self = [super initWithFrame:NSMakeRect(0, 0, 550, 52)];
    if (!self)
        return nil;
    _choice = [choice copy];
    self.wantsLayer = YES;
    self.layer.cornerRadius = 16;
    self.layer.backgroundColor = [[VLCRedesignAppearance colorWithRGB:0x161616] colorWithAlphaComponent:.96].CGColor;
    seconds = MAX(0, seconds);
    NSString *time = [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)(seconds / 3600),
                                                (long)((seconds / 60) % 60), (long)(seconds % 60)];
    NSString *text = [NSString stringWithFormat:_NS("You already watched till %@"), time];
    _positionText = time;
    _fullMessage = text;
    _message = [VLCRedesignAlignedLabel labelWithString:text];
    _message.font = [VLCRedesignAppearance fontOfSize:14 weight:NSFontWeightRegular];
    _message.textColor = [VLCRedesignAppearance colorWithRGB:0xBBBBBB];
    _message.lineBreakMode = NSLineBreakByTruncatingTail;
    _message.toolTip = text;
    [self addSubview:_message];
    _continueButton = [[VLCResumePromptButton alloc] init];
    _continueButton.primary = YES;
    _continueButton.title = _continueButton.accessibilityLabel = _NS("Continue Watching");
    _continueButton.toolTip = _continueButton.title;
    _continueButton.bordered = NO;
    _continueButton.target = self;
    _continueButton.action = @selector(continueWatching:);
    [self addSubview:_continueButton];
    _dismissButton = [[VLCResumePromptButton alloc] init];
    _dismissButton.title = @"";
    _dismissButton.image = VLCRedesignPanelImage(@"VLC-redesign-player-dark-close");
    _dismissButton.accessibilityLabel = _NS("Dismiss resume prompt");
    _dismissButton.bordered = NO;
    _dismissButton.target = self;
    _dismissButton.action = @selector(dismiss:);
    [self addSubview:_dismissButton];
    self.accessibilityRole = NSAccessibilityGroupRole;
    self.accessibilityLabel = text;
    return self;
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (self.window) {
        NSAccessibilityPostNotificationWithUserInfo(self, NSAccessibilityAnnouncementRequestedNotification, @{
            NSAccessibilityAnnouncementKey : self.accessibilityLabel,
            NSAccessibilityPriorityKey : @(NSAccessibilityPriorityHigh)
        });
    }
}

- (void)finishWithChoice:(BOOL)continuePlayback
{
    void (^choice)(BOOL) = _choice;
    _choice = nil;
    if (choice)
        choice(continuePlayback);
}

- (void)continueWatching:(id)sender
{
    [self finishWithChoice:YES];
}

- (void)dismiss:(id)sender
{
    [self finishWithChoice:NO];
}

- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds);
    BOOL compact = width < 400;
    CGFloat continueWidth = compact ? (width < 280 ? 88 : 100) : 170;
    _dismissButton.frame = NSMakeRect(MAX(0, width - 42), 10, 32, 32);
    _continueButton.frame = NSMakeRect(MAX(0, NSMinX(_dismissButton.frame) - continueWidth - 8), 10,
                                     continueWidth, 32);
    _continueButton.title = compact ? _NS("Continue") : _NS("Continue Watching");
    _message.frame = NSMakeRect(12, 10, MAX(0, NSMinX(_continueButton.frame) - 24), 32);
    _message.font = [VLCRedesignAppearance fontOfSize:compact ? 12 : 14 weight:NSFontWeightRegular];
    NSDictionary *attributes = @{ NSFontAttributeName : _message.font };
    NSString *text = _fullMessage;
    if ([text sizeWithAttributes:attributes].width > NSWidth(_message.frame))
        text = [NSString stringWithFormat:_NS("Resume at %@"), _positionText];
    if ([text sizeWithAttributes:attributes].width > NSWidth(_message.frame))
        text = _positionText;
    _message.stringValue = text;
}

@end
