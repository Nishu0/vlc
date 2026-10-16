/*****************************************************************************
 * VLCOnboardingWindowController.m: Native first-launch onboarding
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCOnboardingWindowController.h"
#import "VLCRedesignAppearance.h"
#import "extensions/NSString+Helpers.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryWindow.h"
#import "main/VLCMain.h"
#import <CoreText/CoreText.h>
#import <vlc_configuration.h>

static NSString * const VLCOnboardingCompletedKey = @"VLCRedesignOnboardingCompleted";

@interface VLCOnboardingSurface : NSView
@property (copy) void (^appearanceChanged)(void);
@end

@implementation VLCOnboardingSurface
- (BOOL)mouseDownCanMoveWindow { return YES; }
- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    if (self.appearanceChanged)
        self.appearanceChanged();
}
@end

@interface VLCOnboardingWindow : NSWindow
@end
@implementation VLCOnboardingWindow
- (void)cancelOperation:(id)sender { [self performClose:sender]; }
@end

/* These are native controls with the geometry and colors of the design. */
@interface VLCOnboardingButton : NSButton
@property BOOL primary;
@property NSFontWeight titleWeight;
@end

@implementation VLCOnboardingButton
- (void)drawRect:(NSRect)dirtyRect
{
    NSColor *background = self.primary ? VLCRedesignAppearance.accentColor : VLCRedesignAppearance.panelColor;
    [(self.highlighted ? [background colorWithAlphaComponent:.75] : background) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6] fill];
    NSDictionary *attributes = @{
        NSFontAttributeName: [VLCRedesignAppearance fontOfSize:16 weight:self.titleWeight],
        NSForegroundColorAttributeName: self.primary ? [VLCRedesignAppearance colorWithRGB:0x161616] :
                                                       VLCRedesignAppearance.subduedColor
    };
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:self.title attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)title);
    /* Center visible glyphs, excluding the font's asymmetric line-box padding. */
    CGRect inkBounds = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(context);
    if (self.flipped) {
        CGContextTranslateCTM(context, 0, NSMinY(self.bounds) + NSMaxY(self.bounds));
        CGContextScaleCTM(context, 1, -1);
    }
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextPosition(context, NSMidX(self.bounds) - CGRectGetMidX(inkBounds),
                            NSMidY(self.bounds) - CGRectGetMidY(inkBounds));
    CTLineDraw(line, context);
    CGContextRestoreGState(context);
    CFRelease(line);
    if (self.window.firstResponder == self) {
        [VLCRedesignAppearance.accentColor setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1)
                                                          xRadius:6 yRadius:6];
        ring.lineWidth = 2;
        [ring stroke];
    }
}
@end

@interface VLCOnboardingThemeButton : NSButton
@property NSInteger themeIndex;
@property BOOL selectedTheme;
@end

@implementation VLCOnboardingThemeButton
- (void)drawRect:(NSRect)dirtyRect
{
    NSRect tile = NSMakeRect(8, 8, 100, 100);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:tile xRadius:12 yRadius:12];
    [[VLCRedesignAppearance colorWithRGB:self.themeIndex == 0 ? 0xafafaf : 0x222222] setFill];
    [path fill];
    if (self.themeIndex == 2) {
        [NSGraphicsContext saveGraphicsState];
        [path addClip];
        [[VLCRedesignAppearance colorWithRGB:0xafafaf] setFill];
        NSBezierPath *half = [NSBezierPath bezierPath];
        [half moveToPoint:NSMakePoint(NSMinX(tile) + 16, NSMinY(tile))];
        [half lineToPoint:NSMakePoint(NSMaxX(tile), NSMinY(tile))];
        [half lineToPoint:NSMakePoint(NSMaxX(tile), NSMaxY(tile))];
        [half lineToPoint:NSMakePoint(NSMaxX(tile) - 16, NSMaxY(tile))];
        [half closePath];
        [half fill];
        [NSGraphicsContext restoreGraphicsState];
    }
    if (self.selectedTheme || self.window.firstResponder == self) {
        [VLCRedesignAppearance.accentColor setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(tile, -8, -8)
                                                          xRadius:19 yRadius:19];
        ring.lineWidth = 4;
        [ring stroke];
    }
    NSDictionary *attributes = @{
        NSFontAttributeName: [VLCRedesignAppearance fontOfSize:16 weight:NSFontWeightLight],
        NSForegroundColorAttributeName: VLCRedesignAppearance.subduedColor
    };
    NSSize size = [self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint((NSWidth(self.bounds) - size.width) / 2, 138)
            withAttributes:attributes];
}
@end

@interface VLCOnboardingAccentButton : NSButton
@property BOOL selectedAccent;
@end

@implementation VLCOnboardingAccentButton
- (void)drawRect:(NSRect)dirtyRect
{
    [self.image drawInRect:self.bounds];
    if (self.selectedAccent || self.window.firstResponder == self) {
        [[VLCRedesignAppearance.accentColor colorWithAlphaComponent:.45] setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(self.bounds, 2, 2)];
        ring.lineWidth = 4;
        [ring stroke];
    }
}
@end

@interface VLCOnboardingWindowController ()
@property VLCOnboardingSurface *surface;
@property NSTextField *folderField;
@property NSTextField *folderError;
@property (copy) NSString *folderPath;
@property NSInteger step;
@end

@implementation VLCOnboardingWindowController

+ (BOOL)completed
{
    return [NSUserDefaults.standardUserDefaults boolForKey:VLCOnboardingCompletedKey];
}

- (instancetype)init
{
    NSWindow *window = [[VLCOnboardingWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1090, 759)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        window.title = _NS("Welcome to VLC");
        window.titleVisibility = NSWindowTitleHidden;
        window.titlebarAppearsTransparent = YES;
        window.movableByWindowBackground = YES;
        window.opaque = NO;
        window.backgroundColor = NSColor.clearColor;
        window.contentMinSize = NSMakeSize(960, 680);
        window.releasedWhenClosed = NO;
        [window standardWindowButton:NSWindowCloseButton].hidden = YES;
        [window standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
        [window standardWindowButton:NSWindowZoomButton].hidden = YES;
        [window center];

        _surface = [[VLCOnboardingSurface alloc] initWithFrame:NSMakeRect(0, 0, 1090, 759)];
        _surface.wantsLayer = YES;
        _surface.layer.cornerRadius = 14;
        _surface.layer.masksToBounds = YES;
        window.contentView = _surface;
        NSString *movies = NSSearchPathForDirectoriesInDomains(NSMoviesDirectory, NSUserDomainMask, YES).firstObject;
        BOOL isDirectory = NO;
        _folderPath = movies && [NSFileManager.defaultManager fileExistsAtPath:movies isDirectory:&isDirectory] &&
                      isDirectory ? [movies stringByAbbreviatingWithTildeInPath] : @"";

        __weak typeof(self) weakSelf = self;
        _surface.appearanceChanged = ^{
            if ([VLCRedesignAppearance.theme isEqualToString:@"system"]) {
                dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf buildStep]; });
            }
        };
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appearanceChanged:)
                                                  name:VLCRedesignAppearanceChanged object:nil];
        [self buildStep];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)showWindow:(id)sender
{
    if (!self.window.visible && self.step != 0) {
        self.step = 0;
        [self buildStep];
    }
    [super showWindow:sender];
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color
{
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [VLCRedesignAppearance fontOfSize:size weight:weight];
    label.textColor = color;
    return label;
}

- (NSStackView *)stack:(NSArray<NSView *> *)views vertical:(BOOL)vertical spacing:(CGFloat)spacing
{
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = vertical ? NSLayoutAttributeCenterX : NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    return stack;
}

- (NSView *)spacer:(CGFloat)height
{
    NSView *spacer = [[NSView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer.heightAnchor constraintEqualToConstant:height].active = YES;
    return spacer;
}

- (NSImageView *)image:(NSString *)name
{
    NSImage *image = [NSImage imageNamed:name];
    NSImageView *view = [NSImageView imageViewWithImage:image ?: [[NSImage alloc] initWithSize:NSZeroSize]];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [view.widthAnchor constraintEqualToConstant:image.size.width],
        [view.heightAnchor constraintEqualToConstant:image.size.height]
    ]];
    [view setAccessibilityElement:NO];
    return view;
}

- (VLCOnboardingButton *)button:(NSString *)title primary:(BOOL)primary action:(SEL)action
{
    VLCOnboardingButton *button = [[VLCOnboardingButton alloc] initWithFrame:NSZeroRect];
    button.title = title;
    button.target = self;
    button.action = action;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bordered = NO;
    button.primary = primary;
    button.titleWeight = NSFontWeightSemibold;
    [button.heightAnchor constraintEqualToConstant:32].active = YES;
    return button;
}

- (void)appearanceChanged:(NSNotification *)notification
{
    [self buildStep];
}

- (void)buildStep
{
    if (self.step == 0 && self.folderField)
        self.folderPath = self.folderField.stringValue;
    self.folderField = nil;
    self.folderError = nil;
    for (NSView *view in self.surface.subviews.copy)
        [view removeFromSuperview];
    self.surface.layer.backgroundColor = VLCRedesignAppearance.backgroundColor.CGColor;

    VLCOnboardingButton *next = [self button:self.step == 2 ? _NS("Finish") : _NS("Next")
                                      primary:YES action:@selector(next:)];
    next.keyEquivalent = @"\r";
    [self.surface addSubview:next];
    [NSLayoutConstraint activateConstraints:@[
        [next.widthAnchor constraintEqualToConstant:100],
        [next.trailingAnchor constraintEqualToAnchor:self.surface.trailingAnchor constant:-62],
        [next.bottomAnchor constraintEqualToAnchor:self.surface.bottomAnchor constant:-56]
    ]];

    VLCOnboardingButton *back = nil;
    if (self.step > 0) {
        back = [self button:_NS("Back") primary:NO action:@selector(back:)];
        [self.surface addSubview:back];
        [NSLayoutConstraint activateConstraints:@[
            [back.widthAnchor constraintEqualToConstant:100],
            [back.trailingAnchor constraintEqualToAnchor:next.leadingAnchor constant:-8],
            [back.centerYAnchor constraintEqualToAnchor:next.centerYAnchor]
        ]];
    }
    if (self.step == 0)
        [self buildWelcome];
    else if (self.step == 1)
        [self buildAppearanceBeforeButton:back];
    else
        [self buildShortcuts];
}

- (void)buildWelcome
{
    NSImageView *cone = [self image:@"VLC-redesign-cone"];
    NSTextField *title = [self label:_NS("Welcome to VLC!") size:32 weight:NSFontWeightLight
                             color:VLCRedesignAppearance.foregroundColor];
    title.alignment = NSTextAlignmentCenter;
    NSTextField *description = [self label:_NS("VLC is a free and open source cross-platform multimedia player and framework that plays most multimedia files as well as DVDs, Audio CDs, VCDs, and various streaming protocols.")
                                       size:16 weight:NSFontWeightLight color:VLCRedesignAppearance.subduedColor];
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.minimumLineHeight = paragraph.maximumLineHeight = 28;
    description.attributedStringValue = [[NSAttributedString alloc] initWithString:description.stringValue
        attributes:@{NSFontAttributeName:description.font, NSForegroundColorAttributeName:description.textColor,
                     NSParagraphStyleAttributeName:paragraph}];

    NSTextField *caption = [self label:_NS("Choose a Media Folder to get started with")
                                  size:14 weight:NSFontWeightRegular color:VLCRedesignAppearance.subduedColor];
    self.folderField = [[NSTextField alloc] init];
    self.folderField.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderField.font = [VLCRedesignAppearance fontOfSize:16 weight:NSFontWeightRegular];
    self.folderField.textColor = VLCRedesignAppearance.secondaryColor;
    self.folderField.drawsBackground = NO;
    self.folderField.bordered = NO;
    self.folderField.stringValue = self.folderPath;
    self.folderField.placeholderString = _NS("Choose a media folder (optional)");
    [self.folderField setAccessibilityLabel:_NS("Media folder")];
    NSView *fieldContainer = [[NSView alloc] init];
    fieldContainer.translatesAutoresizingMaskIntoConstraints = NO;
    fieldContainer.wantsLayer = YES;
    fieldContainer.layer.backgroundColor = VLCRedesignAppearance.recessedColor.CGColor;
    fieldContainer.layer.cornerRadius = 6;
    fieldContainer.layer.borderWidth = 2;
    fieldContainer.layer.borderColor = VLCRedesignAppearance.panelColor.CGColor;
    [fieldContainer addSubview:self.folderField];
    VLCOnboardingButton *browse = [self button:_NS("Browse") primary:NO action:@selector(browse:)];
    browse.titleWeight = NSFontWeightRegular;
    NSStackView *row = [self stack:@[fieldContainer, browse] vertical:NO spacing:10];
    NSStackView *folder = [self stack:@[caption, row] vertical:YES spacing:16];
    folder.alignment = NSLayoutAttributeLeading;
    [NSLayoutConstraint activateConstraints:@[
        [fieldContainer.heightAnchor constraintEqualToConstant:36],
        [self.folderField.leadingAnchor constraintEqualToAnchor:fieldContainer.leadingAnchor constant:12],
        [self.folderField.trailingAnchor constraintEqualToAnchor:fieldContainer.trailingAnchor constant:-12],
        [self.folderField.centerYAnchor constraintEqualToAnchor:fieldContainer.centerYAnchor],
        [browse.widthAnchor constraintEqualToConstant:114],
        [row.widthAnchor constraintEqualToAnchor:folder.widthAnchor]
    ]];
    self.folderError = [self label:@"" size:12 weight:NSFontWeightRegular color:NSColor.systemRedColor];
    self.folderError.hidden = YES;
    NSStackView *content = [self stack:@[cone, [self spacer:29], title, [self spacer:37], description,
                                       [self spacer:54], folder] vertical:YES spacing:0];
    [self.surface addSubview:content];
    [self.surface addSubview:self.folderError];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:self.surface.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:self.surface.centerYAnchor constant:-37],
        [content.widthAnchor constraintEqualToConstant:595],
        [description.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [description.heightAnchor constraintEqualToConstant:84],
        [folder.widthAnchor constraintEqualToAnchor:content.widthAnchor],
        [self.folderError.leadingAnchor constraintEqualToAnchor:folder.leadingAnchor],
        [self.folderError.topAnchor constraintEqualToAnchor:folder.bottomAnchor constant:8],
        [self.folderError.trailingAnchor constraintEqualToAnchor:folder.trailingAnchor]
    ]];
}

- (NSView *)wrappedImage:(NSString *)name width:(CGFloat)width
{
    NSView *wrapper = [[NSView alloc] init];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    NSImageView *image = [self image:name];
    [wrapper addSubview:image];
    [NSLayoutConstraint activateConstraints:@[
        [wrapper.widthAnchor constraintEqualToConstant:width],
        [wrapper.heightAnchor constraintEqualToConstant:17.6],
        [image.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor],
        [image.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor]
    ]];
    return wrapper;
}

- (NSTextField *)previewTime:(NSString *)time
{
    NSTextField *label = [self label:time size:8.25 weight:NSFontWeightRegular
                             color:VLCRedesignAppearance.subduedColor];
    label.alignment = NSTextAlignmentCenter;
    [label.widthAnchor constraintEqualToConstant:41.8].active = YES;
    return label;
}

- (NSView *)preview
{
    NSView *preview = [[NSView alloc] init];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    preview.wantsLayer = YES;
    preview.layer.backgroundColor = VLCRedesignAppearance.recessedColor.CGColor;
    NSView *header = [[NSView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.wantsLayer = YES;
    header.layer.backgroundColor = VLCRedesignAppearance.panelColor.CGColor;
    [preview addSubview:header];
    NSImageView *cone = [self image:@"VLC-redesign-preview-cone"];
    if (@available(macOS 10.14, *)) {
        NSImage *template = cone.image.copy;
        template.template = YES;
        cone.image = template;
        cone.contentTintColor = VLCRedesignAppearance.accentColor;
    }
    [header addSubview:cone];
    NSStackView *decorations = [self stack:@[
        [self wrappedImage:@"VLC-redesign-preview-minimize" width:19.8],
        [self wrappedImage:@"VLC-redesign-preview-maximize" width:19.8],
        [self wrappedImage:@"VLC-redesign-preview-fullscreen" width:19.8],
        [self wrappedImage:@"VLC-redesign-preview-close" width:19.8]
    ] vertical:NO spacing:0];
    [header addSubview:decorations];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:preview.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor],
        [header.topAnchor constraintEqualToAnchor:preview.topAnchor],
        [header.heightAnchor constraintEqualToConstant:22],
        [cone.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:7],
        [cone.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [decorations.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-3.3],
        [decorations.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]
    ]];
    NSView *bar = [[NSView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.wantsLayer = YES;
    bar.layer.backgroundColor = VLCRedesignAppearance.panelColor.CGColor;
    [preview addSubview:bar];
    NSView *play = [[NSView alloc] init];
    play.translatesAutoresizingMaskIntoConstraints = NO;
    play.wantsLayer = YES;
    play.layer.backgroundColor = VLCRedesignAppearance.accentColor.CGColor;
    play.layer.cornerRadius = 4;
    NSImageView *playIcon = [self image:@"VLC-redesign-preview-play"];
    [play addSubview:playIcon];
    [NSLayoutConstraint activateConstraints:@[
        [play.widthAnchor constraintEqualToConstant:29.7], [play.heightAnchor constraintEqualToConstant:15.4],
        [playIcon.centerXAnchor constraintEqualToAnchor:play.centerXAnchor],
        [playIcon.centerYAnchor constraintEqualToAnchor:play.centerYAnchor]
    ]];
    NSStackView *transport = [self stack:@[[self wrappedImage:@"VLC-redesign-preview-previous" width:16.5], play,
                                          [self wrappedImage:@"VLC-redesign-preview-next" width:16.5]] vertical:NO spacing:4.4];
    NSView *seek = [[NSView alloc] init];
    seek.translatesAutoresizingMaskIntoConstraints = NO;
    seek.wantsLayer = YES;
    seek.layer.backgroundColor = VLCRedesignAppearance.recessedColor.CGColor;
    seek.layer.cornerRadius = 3;
    NSView *progress = [[NSView alloc] init];
    progress.translatesAutoresizingMaskIntoConstraints = NO;
    progress.wantsLayer = YES;
    progress.layer.backgroundColor = VLCRedesignAppearance.accentIndex == 0 ?
        [VLCRedesignAppearance colorWithRGB:VLCRedesignAppearance.dark ? 0x371f06 : 0xd8ba9a].CGColor :
        [VLCRedesignAppearance.accentColor colorWithAlphaComponent:.25].CGColor;
    progress.layer.cornerRadius = 4;
    [seek addSubview:progress];
    NSView *thumb = [[NSView alloc] init];
    thumb.translatesAutoresizingMaskIntoConstraints = NO;
    thumb.wantsLayer = YES;
    thumb.layer.backgroundColor = VLCRedesignAppearance.accentColor.CGColor;
    thumb.layer.cornerRadius = 2;
    [seek addSubview:thumb];
    NSStackView *timeGroup = [self stack:@[[self previewTime:@"00:02:10"], seek,
                                           [self previewTime:@"00:25:40"]] vertical:NO spacing:4.4];
    [timeGroup setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSImageView *speaker = [self image:@"VLC-redesign-preview-speaker"];
    speaker.wantsLayer = YES;
    speaker.layer.affineTransform = CGAffineTransformMakeScale(-1, 1);
    NSStackView *volume = [self stack:@[speaker, [self image:@"VLC-redesign-preview-volume"]] vertical:NO spacing:4.4];
    NSStackView *tools = [self stack:@[
        [self wrappedImage:@"VLC-redesign-preview-audio" width:16.5],
        [self wrappedImage:@"VLC-redesign-preview-subtitles" width:16.5],
        [self wrappedImage:@"VLC-redesign-preview-settings" width:16.5]
    ] vertical:NO spacing:6.6];
    NSStackView *row = [self stack:@[transport, timeGroup, volume, tools,
                                    [self wrappedImage:@"VLC-redesign-preview-queue" width:16.5]]
                          vertical:NO spacing:11];
    row.distribution = NSStackViewDistributionFill;
    [bar addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:preview.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:preview.bottomAnchor],
        [bar.heightAnchor constraintEqualToConstant:29.7],
        [row.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:11],
        [row.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-11],
        [row.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [seek.heightAnchor constraintEqualToConstant:15.4],
        [seek.widthAnchor constraintGreaterThanOrEqualToConstant:30],
        [progress.leadingAnchor constraintEqualToAnchor:seek.leadingAnchor constant:1.1],
        [progress.topAnchor constraintEqualToAnchor:seek.topAnchor constant:1.1],
        [progress.bottomAnchor constraintEqualToAnchor:seek.bottomAnchor constant:-1.1],
        [progress.widthAnchor constraintEqualToConstant:53.9],
        [thumb.leadingAnchor constraintEqualToAnchor:seek.leadingAnchor constant:50.6],
        [thumb.topAnchor constraintEqualToAnchor:seek.topAnchor constant:1.1],
        [thumb.bottomAnchor constraintEqualToAnchor:seek.bottomAnchor constant:-1.1],
        [thumb.widthAnchor constraintEqualToConstant:4.4]
    ]];
    [preview setAccessibilityElement:NO];
    return preview;
}

- (void)buildAppearanceBeforeButton:(NSButton *)back
{
    NSView *preview = [self preview];
    [self.surface addSubview:preview positioned:NSWindowBelow relativeTo:nil];
    NSLayoutConstraint *preferredPreviewWidth =
        [preview.widthAnchor constraintEqualToAnchor:self.surface.widthAnchor constant:-34];
    /* A stronger preference becomes part of NSWindow's minimum fitting size. */
    preferredPreviewWidth.priority = NSLayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
        preferredPreviewWidth,
        [preview.widthAnchor constraintLessThanOrEqualToAnchor:self.surface.widthAnchor constant:-34],
        [preview.centerXAnchor constraintEqualToAnchor:self.surface.centerXAnchor],
        [preview.topAnchor constraintGreaterThanOrEqualToAnchor:self.surface.topAnchor constant:18],
        [preview.heightAnchor constraintEqualToAnchor:preview.widthAnchor multiplier:9. / 16.],
        [preview.centerYAnchor constraintEqualToAnchor:self.surface.centerYAnchor constant:-63.5]
    ]];
    NSTextField *prompt = [self label:_NS("Select your preferred theme and color.") size:24
                               weight:NSFontWeightLight color:VLCRedesignAppearance.subduedColor];
    [self.surface addSubview:prompt];
    [NSLayoutConstraint activateConstraints:@[
        [prompt.centerXAnchor constraintEqualToAnchor:self.surface.centerXAnchor],
        [prompt.topAnchor constraintEqualToAnchor:self.surface.centerYAnchor constant:-206.5]
    ]];
    NSMutableArray *choices = [NSMutableArray array];
    NSArray *themes = @[@"light", @"dark", @"system"];
    NSArray *titles = @[_NS("Light"), _NS("Dark"), _NS("System")];
    for (NSInteger i = 0; i < 3; i++) {
        VLCOnboardingThemeButton *button = [[VLCOnboardingThemeButton alloc] initWithFrame:NSZeroRect];
        button.title = titles[i];
        button.target = self;
        button.action = @selector(selectTheme:);
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.bordered = NO;
        button.themeIndex = button.tag = i;
        button.selectedTheme = [VLCRedesignAppearance.theme isEqualToString:themes[i]];
        [button setAccessibilityValue:button.selectedTheme ? @1 : @0];
        [button.widthAnchor constraintEqualToConstant:116].active = YES;
        [button.heightAnchor constraintEqualToConstant:158].active = YES;
        [choices addObject:button];
    }
    NSStackView *themeRow = [self stack:choices vertical:NO spacing:40];
    [self.surface addSubview:themeRow];
    [NSLayoutConstraint activateConstraints:@[
        [themeRow.centerXAnchor constraintEqualToAnchor:self.surface.centerXAnchor],
        [themeRow.topAnchor constraintEqualToAnchor:self.surface.centerYAnchor constant:-93.5]
    ]];
    NSArray *colors = @[@"orange", @"red", @"yellow", @"green", @"cyan", @"blue", @"purple", @"pink", @"gray"];
    NSArray *colorNames = @[_NS("Orange"), _NS("Red"), _NS("Yellow"), _NS("Green"), _NS("Cyan"),
                            _NS("Blue"), _NS("Purple"), _NS("Pink"), _NS("Gray")];
    NSMutableArray *swatches = [NSMutableArray array];
    for (NSInteger i = 0; i < 9; i++) {
        VLCOnboardingAccentButton *button = [[VLCOnboardingAccentButton alloc] initWithFrame:NSZeroRect];
        button.title = @"";
        button.target = self;
        button.action = @selector(selectAccent:);
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.bordered = NO;
        button.tag = i;
        button.image = [NSImage imageNamed:[@"VLC-redesign-" stringByAppendingString:colors[i]]];
        button.selectedAccent = VLCRedesignAppearance.accentIndex == i;
        [button setAccessibilityLabel:colorNames[i]];
        [button setAccessibilityValue:button.selectedAccent ? @1 : @0];
        [button.widthAnchor constraintEqualToConstant:64].active = YES;
        [button.heightAnchor constraintEqualToConstant:64].active = YES;
        [swatches addObject:button];
    }
    NSStackView *palette = [self stack:swatches vertical:NO spacing:0];
    palette.distribution = NSStackViewDistributionEqualSpacing;
    [self.surface addSubview:palette];
    NSLayoutConstraint *preferredWidth = [palette.widthAnchor constraintEqualToConstant:704];
    preferredWidth.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        preferredWidth,
        [palette.leadingAnchor constraintEqualToAnchor:self.surface.leadingAnchor constant:41],
        [palette.trailingAnchor constraintLessThanOrEqualToAnchor:back.leadingAnchor constant:-20],
        [palette.bottomAnchor constraintEqualToAnchor:self.surface.bottomAnchor constant:-40]
    ]];
}

- (NSMenuItem *)itemWithAction:(SEL)action inMenu:(NSMenu *)menu
{
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == action)
            return item;
        NSMenuItem *child = item.submenu ? [self itemWithAction:action inMenu:item.submenu] : nil;
        if (child)
            return child;
    }
    return nil;
}

- (NSView *)keycap:(NSString *)option
{
    NSString *raw = @"";
    if ([option hasPrefix:@"menu:"]) {
        NSMenuItem *item = [self itemWithAction:NSSelectorFromString([option substringFromIndex:5])
                                      inMenu:NSApp.mainMenu];
        if (item.keyEquivalent.length) {
            NSMutableArray *parts = [NSMutableArray array];
            if (item.keyEquivalentModifierMask & NSEventModifierFlagCommand) [parts addObject:@"Command"];
            if (item.keyEquivalentModifierMask & NSEventModifierFlagControl) [parts addObject:@"Ctrl"];
            if (item.keyEquivalentModifierMask & NSEventModifierFlagOption) [parts addObject:@"Alt"];
            if (item.keyEquivalentModifierMask & NSEventModifierFlagShift) [parts addObject:@"Shift"];
            [parts addObject:item.keyEquivalent];
            raw = [parts componentsJoinedByString:@"+"];
        }
    } else if (config_GetType(option.UTF8String)) {
        char *value = config_GetPsz(option.UTF8String);
        raw = value ? toNSStr(value) : @"";
        free(value);
    }
    raw = [raw componentsSeparatedByString:@"\t"].firstObject;
    NSString *display = raw.length ? OSXStringKeyToString(raw) : _NS("Not Set");
    NSTextField *label = [self label:display size:16 weight:NSFontWeightLight
                             color:VLCRedesignAppearance.secondaryColor];
    label.alignment = NSTextAlignmentCenter;
    NSView *cap = [[NSView alloc] init];
    cap.translatesAutoresizingMaskIntoConstraints = NO;
    cap.wantsLayer = YES;
    cap.layer.backgroundColor = VLCRedesignAppearance.panelColor.CGColor;
    cap.layer.cornerRadius = 11;
    cap.layer.borderColor = VLCRedesignAppearance.borderColor.CGColor;
    cap.layer.borderWidth = 3;
    [cap addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [cap.heightAnchor constraintEqualToConstant:44],
        [cap.widthAnchor constraintGreaterThanOrEqualToConstant:44],
        [label.leadingAnchor constraintEqualToAnchor:cap.leadingAnchor constant:12],
        [label.trailingAnchor constraintEqualToAnchor:cap.trailingAnchor constant:-12],
        [label.centerYAnchor constraintEqualToAnchor:cap.centerYAnchor]
    ]];
    return cap;
}

- (NSView *)keys:(NSArray<NSString *> *)options
{
    NSMutableArray *views = [NSMutableArray array];
    for (NSString *option in options) {
        if (views.count)
            [views addObject:[self label:@"/" size:16 weight:NSFontWeightLight color:VLCRedesignAppearance.subduedColor]];
        [views addObject:[self keycap:option]];
    }
    return [self stack:views vertical:NO spacing:10];
}

- (void)buildShortcuts
{
    NSTextField *title = [self label:_NS("Learn the basic keyboard shortcuts.") size:24
                              weight:NSFontWeightLight color:VLCRedesignAppearance.subduedColor];
    [self.surface addSubview:title];
    [NSLayoutConstraint activateConstraints:@[
        [title.centerXAnchor constraintEqualToAnchor:self.surface.centerXAnchor],
        [title.topAnchor constraintEqualToAnchor:self.surface.topAnchor constant:70]
    ]];
    NSArray *leftLabels = @[_NS("Play / Pause"), _NS("Seek Backward / Forward"), _NS("Previous / Next Item"),
                            _NS("Previous / Next Frame"), _NS("Cycle Subtitle Track"), _NS("Cycle Audio Track")];
    NSArray *leftKeys = @[@[@"key-play-pause"], @[@"key-jump-extrashort", @"key-jump+extrashort"],
                          @[@"key-prev", @"key-next"], @[@"key-frame-previous", @"key-frame-next"],
                          @[@"key-subtitle-track"], @[@"key-audio-track"]];
    NSArray *rightLabels = @[_NS("Toggle Fullscreen"), _NS("Increase / Decrease Volume"), _NS("Show / Hide Queue"),
                             _NS("Show / Hide File Browser"), _NS("Take a Snapshot"), _NS("Record")];
    NSArray *rightKeys = @[@[@"key-toggle-fullscreen"], @[@"key-vol-up", @"key-vol-down"],
                           @[@"menu:showPlayQueue:"], @[], @[@"key-snapshot"], @[@"key-record"]];
    NSMutableArray *columns = [NSMutableArray array];
    for (NSInteger column = 0; column < 2; column++) {
        NSMutableArray *rows = [NSMutableArray array];
        NSArray *labels = column == 0 ? leftLabels : rightLabels;
        NSArray *keys = column == 0 ? leftKeys : rightKeys;
        for (NSInteger row = 0; row < 6; row++) {
            NSView *caps = [keys[row] count] ? [self keys:keys[row]] :
                [self label:_NS("Not Set") size:14 weight:NSFontWeightLight color:VLCRedesignAppearance.subduedColor];
            [rows addObject:@[[self label:labels[row] size:16 weight:NSFontWeightLight
                                    color:VLCRedesignAppearance.subduedColor], caps]];
        }
        NSGridView *grid = [NSGridView gridViewWithViews:rows];
        grid.translatesAutoresizingMaskIntoConstraints = NO;
        grid.rowSpacing = 16;
        grid.columnSpacing = 22;
        grid.yPlacement = NSGridCellPlacementCenter;
        for (NSInteger row = 0; row < 6; row++)
            [grid rowAtIndex:row].height = 64;
        [columns addObject:grid];
    }
    NSStackView *content = [self stack:columns vertical:NO spacing:120];
    content.distribution = NSStackViewDistributionFillEqually;
    [self.surface addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:self.surface.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:self.surface.centerYAnchor constant:3],
        [content.widthAnchor constraintEqualToAnchor:self.surface.widthAnchor constant:-124],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.surface.leadingAnchor constant:45],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:self.surface.trailingAnchor constant:-45]
    ]];
    NSTextField *hint = [self label:_NS("Find the full list in the menu.") size:16
                             weight:NSFontWeightLight color:VLCRedesignAppearance.subduedColor];
    [self.surface addSubview:hint];
    [NSLayoutConstraint activateConstraints:@[
        [hint.leadingAnchor constraintEqualToAnchor:self.surface.leadingAnchor constant:62],
        [hint.bottomAnchor constraintEqualToAnchor:self.surface.bottomAnchor constant:-65]
    ]];
}

- (void)selectTheme:(NSButton *)sender
{
    VLCRedesignAppearance.theme = @[@"light", @"dark", @"system"][sender.tag];
}

- (void)selectAccent:(NSButton *)sender
{
    VLCRedesignAppearance.accentIndex = sender.tag;
}

- (void)browse:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.prompt = _NS("Choose Folder");
    panel.directoryURL = self.folderField.stringValue.length ?
        [NSURL fileURLWithPath:self.folderField.stringValue.stringByExpandingTildeInPath] : nil;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK && panel.URL) {
            self.folderPath = panel.URL.path.stringByAbbreviatingWithTildeInPath;
            self.folderField.stringValue = self.folderPath;
            self.folderError.hidden = YES;
        }
    }];
}

- (void)next:(id)sender
{
    if (self.step == 0) {
        self.folderPath = [self.folderField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL isDirectory = NO;
        if (self.folderPath.length &&
            (![NSFileManager.defaultManager fileExistsAtPath:self.folderPath.stringByExpandingTildeInPath
                                               isDirectory:&isDirectory] || !isDirectory)) {
            self.folderError.stringValue = _NS("Choose an existing folder, or leave this blank to add media later.");
            self.folderError.hidden = NO;
            [self.window makeFirstResponder:self.folderField];
            return;
        }
    }
    if (self.step < 2) {
        self.step++;
        [self buildStep];
        return;
    }
    if (self.folderPath.length) {
        NSURL *url = [NSURL fileURLWithPath:self.folderPath.stringByExpandingTildeInPath isDirectory:YES];
        int result = [VLCMain.sharedInstance.libraryController addFolderWithFileURL:url];
        if (result != VLC_SUCCESS) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = _NS("VLC could not add this media folder.");
            alert.informativeText = _NS("Go back to choose another folder, or leave the folder empty to add media later.");
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
            return;
        }
    }
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:VLCOnboardingCompletedKey];
    [self.window close];
    [VLCMain.sharedInstance.libraryWindow makeKeyAndOrderFront:nil];
}

- (void)back:(id)sender
{
    if (self.step > 0) {
        self.step--;
        [self buildStep];
    }
}

@end
