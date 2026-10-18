/*****************************************************************************
 * VLCRedesignInspector.m: Tools that remain available during playback
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import "VLCRedesignInspector.h"
#import "VLCRedesignAppearance.h"
#import "VLCRedesignPanelButton.h"
#import "VLCRedesignTextLayout.h"
#import "VLCRedesignSubtitleControls.h"
#import "extensions/NSString+Helpers.h"
#import "library/VLCInputItem.h"
#import "main/VLCMain.h"
#import "menus/VLCMainMenu.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import <vlc_aout.h>
#import <vlc_configuration.h>
#import <vlc_vout.h>
#import "../../../audio_filter/equalizer_presets.h"

static NSString *const VLCInspectorSleepTimerChanged = @"VLCInspectorSleepTimerChanged";

/* The timer belongs to playback, not to the transient inspector view. Closing
 * the sidebar must not cancel it. A deadline also handles time spent asleep. */
@interface VLCPlaybackSleepTimer : NSObject
@property (nonatomic, copy) NSDate *deadline;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) void (^expirationHandler)(void);
- (instancetype)initWithExpirationHandler:(void (^)(void))handler;
+ (instancetype)sharedTimer;
@end

@implementation VLCPlaybackSleepTimer

+ (instancetype)sharedTimer
{
    static VLCPlaybackSleepTimer *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] initWithExpirationHandler:^{
            [VLCMain.sharedInstance.playQueueController.playerController stop];
        }];
    });
    return instance;
}

- (instancetype)initWithExpirationHandler:(void (^)(void))handler
{
    self = [super init];
    if (self) {
        _expirationHandler = [handler copy];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                           selector:@selector(checkDeadline:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:nil];
    }
    return self;
}

- (void)dealloc
{
    [_timer invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}

- (void)setDeadline:(NSDate *)deadline
{
    [_timer invalidate];
    _timer = nil;
    _deadline = [deadline copy];
    if (deadline) {
        __weak typeof(self) weakSelf = self;
        _timer = [[NSTimer alloc] initWithFireDate:deadline
                                          interval:0
                                           repeats:NO
                                             block:^(NSTimer *__unused timer) {
                                                 [weakSelf checkDeadline:nil];
                                             }];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:VLCInspectorSleepTimerChanged object:self];
}

- (void)checkDeadline:(NSNotification *)notification
{
    if (_deadline && _deadline.timeIntervalSinceNow <= 0) {
        self.deadline = nil;
        if (_expirationHandler)
            _expirationHandler();
    }
}

@end

@interface VLCInspectorDocument : NSView
@end
@implementation VLCInspectorDocument

- (BOOL)isFlipped
{
    return YES;
}

@end

@interface VLCInspectorSliderCell : NSSliderCell
@end
@implementation VLCInspectorSliderCell

- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped
{
    NSRect bar = NSMakeRect(NSMinX(rect), NSMidY(rect) - 4, NSWidth(rect), 8);
    [NSColor.blackColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:4 yRadius:4] fill];
    double progress = (self.doubleValue - self.minValue) / MAX(DBL_EPSILON, self.maxValue - self.minValue);
    bar.size.width *= MAX(0, MIN(1, progress));
    [[VLCRedesignAppearance.accentColor colorWithAlphaComponent:self.enabled ? .3 : .1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:4 yRadius:4] fill];
}

- (void)drawKnob:(NSRect)rect
{
    NSColor *color = self.enabled ? VLCRedesignAppearance.accentColor : NSColor.darkGrayColor;
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMidX(rect) - 3, NSMidY(rect) - 9, 6, 18) xRadius:3
                                     yRadius:3] fill];
}

@end

@interface VLCInspectorToggle : NSButton
@end
@implementation VLCInspectorToggle

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    CGFloat width = NSWidth(self.bounds);
    NSAttributedString *title = [[NSAttributedString alloc]
        initWithString:self.title
            attributes:@{
                NSFontAttributeName : [VLCRedesignAppearance fontOfSize:13 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName : [VLCRedesignAppearance colorWithRGB:self.enabled ? 0x969696 : 0x555555]
            }];
    VLCDrawAlignedText(title, NSMakeRect(0, 0, MAX(0, width - 62), NSHeight(self.bounds)), YES, NSTextAlignmentLeft);
    NSRect track = NSMakeRect(width - 52, (NSHeight(self.bounds) - 24) / 2, 52, 24);
    [NSColor.blackColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:track xRadius:4 yRadius:4] fill];
    BOOL on = self.state == NSControlStateValueOn;
    NSColor *color = on && self.enabled ? VLCRedesignAppearance.accentColor : NSColor.darkGrayColor;
    [color setFill];
    NSRect knob = NSMakeRect(NSMinX(track) + (on ? 28 : 3), NSMinY(track) + 3, 21, 18);
    [[NSBezierPath bezierPathWithRoundedRect:knob xRadius:2 yRadius:2] fill];
    NSAttributedString *value = [[NSAttributedString alloc]
        initWithString:on ? _NS("ON") : _NS("OFF")
            attributes:@{
                NSFontAttributeName : [VLCRedesignAppearance fontOfSize:9 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName : [VLCRedesignAppearance colorWithRGB:0x969696]
            }];
    NSRect text = NSMakeRect(NSMinX(track) + (on ? 2 : 27), NSMinY(track), 23, NSHeight(track));
    VLCDrawAlignedText(value, text, YES, NSTextAlignmentCenter);
    if (self.window.firstResponder == self) {
        [VLCRedesignAppearance.accentColor setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(track, -2, -2) xRadius:5 yRadius:5] stroke];
    }
}

@end

@interface VLCInspectorPopupCell : NSPopUpButtonCell
@end
@implementation VLCInspectorPopupCell

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
    [[VLCRedesignAppearance colorWithRGB:self.highlighted ? 0x222222 : 0x090909] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:frame xRadius:4 yRadius:4] fill];
    NSAttributedString *title = [[NSAttributedString alloc]
        initWithString:self.title
            attributes:@{
                NSFontAttributeName : [VLCRedesignAppearance fontOfSize:12 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName : [VLCRedesignAppearance colorWithRGB:self.enabled ? 0x969696 : 0x555555]
            }];
    VLCDrawAlignedText(title,
                       NSMakeRect(NSMinX(frame) + 10, NSMinY(frame), MAX(0, NSWidth(frame) - 34), NSHeight(frame)),
                       view.flipped, NSTextAlignmentLeft);
    NSImage *arrow = VLCRedesignPanelImage(@"VLC-redesign-inspector-chevron");
    NSSize size = arrow.size;
    [arrow drawInRect:NSMakeRect(NSMaxX(frame) - size.width - 7, NSMidY(frame) - size.height / 2, size.width,
                                 size.height)
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:self.enabled ? 1 : .35
        respectFlipped:YES
                 hints:nil];
}

@end

/* Each slider is paired with an editable numeric field, rather than relying on
 * a pointer-only interaction. Both routes send the same bounded value. */
@interface VLCInspectorNumberRow : VLCInspectorDocument <NSTextFieldDelegate>
@property VLCRedesignAlignedLabel *label;
@property VLCRedesignAlignedLabel *minimumLabel;
@property VLCRedesignAlignedLabel *maximumLabel;
@property NSTextField *field;
@property NSSlider *slider;
@property (copy) NSString *unit;
@property BOOL automaticZero;
@property NSNumberFormatter *formatter;
@property (copy) void (^changed)(double);
- (instancetype)initWithTitle:(NSString *)title minimum:(double)minimum maximum:(double)maximum unit:(NSString *)unit;
- (void)updateValue:(double)value enabled:(BOOL)enabled;
@end

static VLCRedesignAlignedLabel *VLCInspectorLabel(NSString *text, CGFloat size)
{
    VLCRedesignAlignedLabel *label = [VLCRedesignAlignedLabel labelWithString:text];
    label.font = [VLCRedesignAppearance fontOfSize:size weight:NSFontWeightRegular];
    label.textColor = [VLCRedesignAppearance colorWithRGB:0x969696];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.translatesAutoresizingMaskIntoConstraints = YES;
    return label;
}

@implementation VLCInspectorNumberRow

- (instancetype)initWithTitle:(NSString *)title minimum:(double)minimum maximum:(double)maximum unit:(NSString *)unit
{
    self = [super initWithFrame:NSMakeRect(0, 0, 400, 90)];
    if (!self)
        return nil;
    _unit = [unit copy];
    _formatter = [[NSNumberFormatter alloc] init];
    _formatter.numberStyle = NSNumberFormatterDecimalStyle;
    _formatter.usesGroupingSeparator = NO;
    _formatter.maximumFractionDigits = 3;
    _label = VLCInspectorLabel(title, 13);
    [self addSubview:_label];
    _field = [[NSTextField alloc] init];
    _field.cell = [[VLCRedesignAlignedTextFieldCell alloc] initTextCell:@""];
    _field.font = [VLCRedesignAppearance fontOfSize:12 weight:NSFontWeightRegular];
    _field.textColor = [VLCRedesignAppearance colorWithRGB:0xBBBBBB];
    _field.backgroundColor = NSColor.blackColor;
    _field.bordered = NO;
    _field.wantsLayer = YES;
    _field.layer.cornerRadius = 4;
    _field.layer.masksToBounds = YES;
    _field.alignment = NSTextAlignmentCenter;
    _field.delegate = self;
    _field.editable = YES;
    _field.selectable = YES;
    _field.drawsBackground = YES;
    _field.accessibilityLabel = title;
    _field.toolTip = [NSString stringWithFormat:_NS("Enter a value from %g to %g %@"), minimum, maximum, unit];
    [self addSubview:_field];
    _slider = [[NSSlider alloc] init];
    _slider.cell = [[VLCInspectorSliderCell alloc] init];
    _slider.minValue = minimum;
    _slider.maxValue = maximum;
    _slider.continuous = YES;
    _slider.target = self;
    _slider.action = @selector(sliderChanged:);
    _slider.accessibilityLabel = title;
    [self addSubview:_slider];
    _minimumLabel = VLCInspectorLabel([NSString stringWithFormat:@"%g %@", minimum, unit], 10);
    _maximumLabel = VLCInspectorLabel([NSString stringWithFormat:@"%g %@", maximum, unit], 10);
    _maximumLabel.alignment = NSTextAlignmentRight;
    [self addSubview:_minimumLabel];
    [self addSubview:_maximumLabel];
    return self;
}

- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds);
    _label.frame = NSMakeRect(20, 0, MAX(0, width - 140), 30);
    _field.frame = NSMakeRect(MAX(20, width - 108), 3, 88, 24);
    _slider.frame = NSMakeRect(20, 35, MAX(0, width - 40), 22);
    _minimumLabel.frame = NSMakeRect(20, 60, width / 2 - 20, 18);
    _maximumLabel.frame = NSMakeRect(width / 2, 60, width / 2 - 20, 18);
}

- (void)updateValue:(double)value enabled:(BOOL)enabled
{
    _field.enabled = _slider.enabled = enabled;
    if (_field.currentEditor || _slider.cell.highlighted)
        return;
    _slider.doubleValue = value;
    _field.stringValue = [self formattedValue:value];
    _slider.needsDisplay = YES;
}

- (NSString *)formattedValue:(double)value
{
    if (_automaticZero && value == 0)
        return _NS("Auto");
    return [[_formatter stringFromNumber:@(value)] stringByAppendingFormat:@" %@", _unit];
}

- (void)sliderChanged:(NSSlider *)sender
{
    _field.stringValue = [self formattedValue:sender.doubleValue];
    if (_changed)
        _changed(sender.doubleValue);
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSString *input = _unit.length ? [_field.stringValue stringByReplacingOccurrencesOfString:_unit withString:@""]
                                   : _field.stringValue;
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    NSNumber *number =
        [formatter numberFromString:[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
    if (number && isfinite(number.doubleValue)) {
        double value = MAX(_slider.minValue, MIN(_slider.maxValue, number.doubleValue));
        _slider.doubleValue = value;
        if (_changed)
            _changed(value);
    }
    _field.stringValue = [self formattedValue:_slider.doubleValue];
}

@end

@interface VLCRedesignInspector ()
@property NSArray<VLCRedesignPanelButton *> *tabs;
@property NSView *header;
@property NSScrollView *scroll;
@property VLCInspectorDocument *document;
@property NSMutableArray<NSView *> *content;
@property NSMutableDictionary<NSString *, VLCInspectorNumberRow *> *numberRows;
@property NSMutableDictionary<NSString *, NSPopUpButton *> *popups;
@property NSMutableDictionary<NSString *, NSButton *> *toggles;
@property NSMutableDictionary<NSString *, VLCRedesignColorRow *> *colorRows;
@property VLCRedesignSizeModeRow *sizeMode;
@property NSMutableDictionary<NSString *, NSString *> *audioParameters;
@property NSMutableDictionary<NSString *, NSArray<NSView *> *> *audioGroups;
@property NSMutableSet<NSString *> *expandedAudioGroups;
@property NSTimer *refreshTimer;
@end

@implementation VLCRedesignInspector

- (BOOL)isFlipped
{
    return YES;
}

- (VLCPlayerController *)player
{
    return VLCMain.sharedInstance.playQueueController.playerController;
}

- (instancetype)init
{
    self = [super initWithFrame:NSZeroRect];
    if (!self)
        return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = [[VLCRedesignAppearance colorWithRGB:0x0E0E0E] colorWithAlphaComponent:.95].CGColor;
    self.layer.cornerRadius = 10;
    self.layer.masksToBounds = YES;
    self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    _header = [[VLCInspectorDocument alloc] init];
    [self addSubview:_header];
    __weak typeof(self) weakSelf = self;
    NSMutableArray *tabs = [NSMutableArray array];
    NSArray *titles = @[ _NS("Playback"), _NS("Video"), _NS("Audio"), _NS("Subtitles") ];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        VLCRedesignPanelButton *button = [[VLCRedesignPanelButton alloc] init];
        button.tab = YES;
        button.title = button.accessibilityLabel = titles[i];
        button.activate = ^{
            weakSelf.selectedTab = i;
        };
        [_header addSubview:button];
        [tabs addObject:button];
    }
    _tabs = tabs;
    _expandedAudioGroups = [NSMutableSet set];
    _document = [[VLCInspectorDocument alloc] init];
    _scroll = [[NSScrollView alloc] init];
    _scroll.drawsBackground = NO;
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.documentView = _document;
    [self addSubview:_scroll];
    for (NSString *name in @[
             VLCPlayerCurrentMediaItemChanged, VLCPlayerCapabilitiesChanged, VLCPlayerAudioDelayChanged,
             VLCPlayerSubtitlesDelayChanged, VLCPlayerSubtitlesFPSChanged, VLCPlayerRateChanged,
             VLCInspectorSleepTimerChanged
         ]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged:) name:name object:nil];
    }
    [self buildContent];
    return self;
}

- (void)dealloc
{
    [_refreshTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [_refreshTimer invalidate];
    _refreshTimer = nil;
    if (self.window) {
        __weak typeof(self) weakSelf = self;
        _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:.5
                                                        repeats:YES
                                                          block:^(NSTimer *__unused timer) {
                                                              [weakSelf refresh];
                                                          }];
        [self refresh];
    }
}

- (void)setSelectedTab:(NSInteger)selectedTab
{
    if (selectedTab < 0 || selectedTab >= (NSInteger)_tabs.count || _selectedTab == selectedTab)
        return;
    _selectedTab = selectedTab;
    [self buildContent];
}

- (void)playerChanged:(NSNotification *)notification
{
    /* Controller notifications can be synchronous with a slider edit. Defer
     * repainting until the action has finished applying all related values. */
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf refresh];
    });
}

- (void)addHeading:(NSString *)title
{
    VLCRedesignAlignedLabel *label = VLCInspectorLabel(title, 15);
    label.frame = NSMakeRect(20, 0, 360, 38);
    [_content addObject:label];
}

- (VLCInspectorNumberRow *)addNumber:(NSString *)key
                               title:(NSString *)title
                             minimum:(double)minimum
                             maximum:(double)maximum
                                unit:(NSString *)unit
{
    VLCInspectorNumberRow *row = [[VLCInspectorNumberRow alloc] initWithTitle:title
                                                                      minimum:minimum
                                                                      maximum:maximum
                                                                         unit:unit];
    __weak typeof(self) weakSelf = self;
    row.changed = ^(double value) {
        [weakSelf applyNumber:value forKey:key];
    };
    _numberRows[key] = row;
    [_content addObject:row];
    return row;
}

- (NSPopUpButton *)addPopup:(NSString *)key
                      title:(NSString *)title
                     labels:(NSArray<NSString *> *)labels
                     values:(NSArray *)values
{
    VLCInspectorDocument *row = [[VLCInspectorDocument alloc] initWithFrame:NSMakeRect(0, 0, 400, 48)];
    VLCRedesignAlignedLabel *label = VLCInspectorLabel(title, 13);
    label.frame = NSMakeRect(20, 0, 162, 48);
    label.autoresizingMask = NSViewWidthSizable;
    [row addSubview:label];
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(192, 10, 188, 28) pullsDown:NO];
    popup.cell = [[VLCInspectorPopupCell alloc] initTextCell:@"" pullsDown:NO];
    popup.autoresizingMask = NSViewMinXMargin;
    popup.font = [VLCRedesignAppearance fontOfSize:12 weight:NSFontWeightRegular];
    popup.accessibilityLabel = title;
    popup.identifier = key;
    popup.target = self;
    popup.action = @selector(popupChanged:);
    for (NSUInteger i = 0; i < labels.count; i++) {
        [popup addItemWithTitle:labels[i]];
        popup.lastItem.representedObject = values[i];
    }
    [row addSubview:popup];
    _popups[key] = popup;
    [_content addObject:row];
    return popup;
}

- (NSButton *)addToggle:(NSString *)key title:(NSString *)title
{
    NSButton *toggle = [[VLCInspectorToggle alloc] initWithFrame:NSMakeRect(0, 0, 400, 44)];
    [toggle setButtonType:NSButtonTypeSwitch];
    toggle.font = [VLCRedesignAppearance fontOfSize:13 weight:NSFontWeightRegular];
    toggle.title = title;
    toggle.accessibilityLabel = title;
    toggle.identifier = key;
    toggle.target = self;
    toggle.action = @selector(toggleChanged:);
    _toggles[key] = toggle;
    [_content addObject:toggle];
    return toggle;
}

- (void)addAction:(NSString *)title selector:(SEL)selector
{
    VLCRedesignPanelButton *button = [[VLCRedesignPanelButton alloc] initWithFrame:NSMakeRect(0, 0, 400, 38)];
    button.footer = YES;
    button.title = button.accessibilityLabel = title;
    button.target = self;
    button.action = selector;
    [_content addObject:button];
}

- (void)addColor:(NSString *)key title:(NSString *)title
{
    VLCRedesignColorRow *row = [[VLCRedesignColorRow alloc] initWithTitle:title];
    __weak typeof(self) weakSelf = self;
    row.changed = ^(uint32_t RGB) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf)
            return;
        config_PutInt(key.UTF8String, RGB);
        [strongSelf.player refreshPausedSubtitleAppearance];
    };
    _colorRows[key] = row;
    [_content addObject:row];
}

- (void)buildContent
{
    [self.window makeFirstResponder:nil];
    for (NSView *view in _document.subviews.copy)
        [view removeFromSuperview];
    _content = [NSMutableArray array];
    _numberRows = [NSMutableDictionary dictionary];
    _popups = [NSMutableDictionary dictionary];
    _toggles = [NSMutableDictionary dictionary];
    _colorRows = [NSMutableDictionary dictionary];
    _sizeMode = nil;
    _audioParameters = [NSMutableDictionary dictionary];
    _audioGroups = [NSMutableDictionary dictionary];
    NSArray *roles = @[ @"playback", @"video", @"audio", @"subtitles" ];
    for (NSUInteger i = 0; i < _tabs.count; i++) {
        BOOL selected = (NSInteger)i == _selectedTab;
        _tabs[i].state = selected ? NSControlStateValueOn : NSControlStateValueOff;
        NSString *prefix = i == 0 ? @"VLC-redesign-inspector" : @"VLC-redesign-tracks";
        NSString *name = [NSString stringWithFormat:@"%@-%@-%@", prefix, roles[i], selected ? @"on" : @"off"];
        _tabs[i].image = VLCRedesignPanelImage(name);
        _tabs[i].underlineImage = selected ? VLCRedesignPanelImage(@"VLC-redesign-tracks-tab-line-video") : nil;
        _tabs[i].needsDisplay = YES;
    }
    if (_selectedTab == 0)
        [self buildPlayback];
    else if (_selectedTab == 1)
        [self buildVideo];
    else if (_selectedTab == 2)
        [self buildAudio];
    else
        [self buildSubtitles];
    [self addAction:_NS("Open Advanced Settings") selector:@selector(openAdvanced:)];
    for (NSView *view in _content)
        [_document addSubview:view];
    [_scroll.contentView scrollToPoint:NSZeroPoint];
    self.needsLayout = YES;
    [self refresh];
}

- (void)buildPlayback
{
    NSButton *reverse = [self addToggle:@"reverse" title:_NS("Reverse")];
    reverse.toolTip = _NS("Available when the current input supports reverse playback.");
    [self
        addPopup:@"sleep"
           title:_NS("Sleep Timer")
          labels:@[
              _NS("Off"), _NS("15 minutes"), _NS("30 minutes"), _NS("60 minutes"), _NS("90 minutes"), _NS("120 minutes")
          ]
          values:@[ @0, @15, @30, @60, @90, @120 ]];
    [self addNumber:@"speed" title:_NS("Speed") minimum:.25 maximum:2 unit:@"×"];
    [self addAction:_NS("Reset Playback Speed") selector:@selector(resetSpeed:)];
    [self addAction:_NS("Show Metadata") selector:@selector(showMetadata:)];
}

- (void)buildVideo
{
    NSArray *ratios = @[ _NS("Default"), @"16:9", @"4:3", @"16:10", @"1:1", @"2.35:1", @"2.39:1" ];
    NSArray *values = @[ @"", @"16:9", @"4:3", @"16:10", @"1:1", @"2.35:1", @"2.39:1" ];
    [self addPopup:@"aspect-ratio" title:_NS("Aspect Ratio") labels:ratios values:values];
    [self addPopup:@"crop" title:_NS("Crop") labels:ratios values:values];
    [self addPopup:@"zoom"
             title:_NS("Zoom")
            labels:@[ @"1:4", @"1:2", @"1:1 Original", @"2:1" ]
            values:@[ @.25, @.5, @1, @2 ]];
    [self addPopup:@"transform"
             title:_NS("Rotate / Flip")
            labels:@[ _NS("None"), _NS("90°"), _NS("180°"), _NS("270°"), _NS("Horizontal Flip"), _NS("Vertical Flip") ]
            values:@[ @"", @"90", @"180", @"270", @"hflip", @"vflip" ]];
    [self addHeading:_NS("Picture")];
    [self addToggle:@"adjust" title:_NS("Enable Picture Adjustments")];
    [self addNumber:@"brightness" title:_NS("Brightness") minimum:0 maximum:2 unit:@""];
    [self addNumber:@"contrast" title:_NS("Contrast") minimum:0 maximum:2 unit:@""];
    [self addNumber:@"saturation" title:_NS("Saturation") minimum:0 maximum:3 unit:@""];
    [self addNumber:@"hue" title:_NS("Hue") minimum:-180 maximum:180 unit:@"°"];
    [self addNumber:@"gamma" title:_NS("Gamma") minimum:.01 maximum:10 unit:@""];
    [self addAction:_NS("Reset Picture") selector:@selector(resetPicture:)];
    [self addAction:_NS("Expand Video Filters") selector:@selector(expandVideo:)];
}

- (void)buildAudio
{
    [self addHeading:_NS("Defaults")];
    [self addLanguagePopup:@"audio-language"];
    [self addHeading:_NS("Synchronization")];
    [self addNumber:@"audio-delay" title:_NS("Audio Track Delay") minimum:-10 maximum:10 unit:@"s"];
    [self addHeading:_NS("Filters")];
    NSMutableArray *labels = [NSMutableArray arrayWithObject:_NS("None")];
    NSMutableArray *values = [NSMutableArray arrayWithObject:@""];
    for (NSUInteger i = 0; i < NB_PRESETS; i++) {
        [labels addObject:_NS(preset_list_text[i])];
        [values addObject:@(i)];
    }
    [self addPopup:@"equalizer" title:_NS("Equalizer") labels:labels values:values];
    [self addToggle:@"compressor" title:_NS("Compressor")];
    [self addAudioParameters:@"compressor" keys:@[
        @"compressor-rms-peak", @"compressor-attack", @"compressor-release", @"compressor-threshold",
        @"compressor-ratio", @"compressor-knee", @"compressor-makeup-gain"
    ]];
    [self addToggle:@"spatializer" title:_NS("Spatializer")];
    [self addAudioParameters:@"spatializer" keys:@[
        @"spatializer-roomsize", @"spatializer-width", @"spatializer-wet", @"spatializer-dry", @"spatializer-damp"
    ]];
    [self addToggle:@"stereo_widen" title:_NS("Stereo Widener")];
    [self addAudioParameters:@"stereo_widen" keys:@[
        @"stereowiden-delay", @"stereowiden-feedback", @"stereowiden-crossfeed", @"stereowiden-dry-mix"
    ]];
    [self addAction:_NS("Expand Audio Filters") selector:@selector(expandAudio:)];
}

- (void)addAudioParameters:(NSString *)filter keys:(NSArray<NSString *> *)keys
{
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    for (NSString *key in keys) {
        module_config_t *option = config_FindConfig(key.UTF8String);
        if (!option || config_GetType(key.UTF8String) != VLC_VAR_FLOAT || option->min.f >= option->max.f)
            continue;
        NSString *unit = @"";
        if ([key hasSuffix:@"attack"] || [key hasSuffix:@"release"] || [key isEqualToString:@"stereowiden-delay"])
            unit = @"ms";
        else if ([key hasSuffix:@"threshold"] || [key hasSuffix:@"knee"] || [key hasSuffix:@"makeup-gain"])
            unit = @"dB";
        else if ([key hasSuffix:@"ratio"])
            unit = @"×";
        VLCInspectorNumberRow *row = [self addNumber:key title:_NS(option->psz_text)
                                            minimum:option->min.f maximum:option->max.f unit:unit];
        row.field.toolTip = row.slider.toolTip = option->psz_longtext ? _NS(option->psz_longtext) : nil;
        _audioParameters[key] = filter;
        [rows addObject:row];
        [_content removeLastObject];
    }
    if (!rows.count)
        return;
    VLCRedesignPanelButton *disclosure = [[VLCRedesignPanelButton alloc] init];
    disclosure.frame = NSMakeRect(0, 0, 400, 44);
    disclosure.footer = YES;
    disclosure.title = [_expandedAudioGroups containsObject:filter] ? _NS("Collapse Settings") : _NS("Expand Settings");
    disclosure.accessibilityLabel = [NSString stringWithFormat:_NS("%@ settings"), _toggles[filter].title];
    __weak typeof(self) weakSelf = self;
    __weak VLCRedesignPanelButton *weakDisclosure = disclosure;
    disclosure.activate = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf)
            return;
        [strongSelf.window makeFirstResponder:nil];
        BOOL expanded = ![strongSelf.expandedAudioGroups containsObject:filter];
        if (expanded)
            [strongSelf.expandedAudioGroups addObject:filter];
        else
            [strongSelf.expandedAudioGroups removeObject:filter];
        weakDisclosure.title = expanded ? _NS("Collapse Settings") : _NS("Expand Settings");
        for (NSView *row in strongSelf.audioGroups[filter])
            row.hidden = !expanded;
        strongSelf.needsLayout = YES;
    };
    [_content addObject:disclosure];
    VLCRedesignPanelButton *reset = [[VLCRedesignPanelButton alloc] init];
    reset.frame = NSMakeRect(0, 0, 400, 44);
    reset.title = _NS("Reset Filter");
    reset.accessibilityLabel = [NSString stringWithFormat:_NS("Reset %@"), _toggles[filter].title];
    reset.activate = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf)
            return;
        [strongSelf.window makeFirstResponder:nil];
        for (NSString *key in keys) {
            module_config_t *option = config_FindConfig(key.UTF8String);
            if (strongSelf.audioParameters[key] && option)
                [strongSelf applyNumber:option->orig.f forKey:key];
        }
        [strongSelf refresh];
    };
    [rows addObject:reset];
    for (NSView *row in rows)
        row.hidden = ![_expandedAudioGroups containsObject:filter];
    _audioGroups[filter] = rows;
    [_content addObjectsFromArray:rows];
}

- (void)addLanguagePopup:(NSString *)key
{
    NSPopUpButton *popup = [self addPopup:key
                                    title:_NS("Preferred Language")
                                   labels:@[
                                       _NS("Automatic"), _NS("English"), _NS("Hindi"), _NS("Korean"), _NS("Japanese"),
                                       _NS("French"), _NS("German"), _NS("Spanish")
                                   ]
                                   values:@[ @"", @"en", @"hi", @"ko", @"ja", @"fr", @"de", @"es" ]];
    popup.toolTip = _NS("Applies to future media. Use the track selector to change the current track.");
}

- (void)buildSubtitles
{
    [self addHeading:_NS("Defaults")];
    [self addLanguagePopup:@"sub-language"];
    [self addHeading:_NS("Synchronization")];
    [self addNumber:@"subtitle-delay" title:_NS("Subtitle Track Delay") minimum:-10 maximum:10 unit:@"s"];
    VLCInspectorNumberRow *speed = [self addNumber:@"subtitle-fps"
                                             title:_NS("Subtitle Speed")
                                           minimum:0
                                           maximum:60
                                              unit:@"fps"];
    speed.automaticZero = YES;
    speed.field.toolTip = speed.slider.toolTip = _NS("Frame rate for external subtitles. Auto (0) uses source timing.");
    [self addNumber:@"subsdelay-factor" title:_NS("Subtitle Duration Factor") minimum:0 maximum:20 unit:@""];
    [self addHeading:_NS("Appearance")];
    [self addToggle:@"embedded-sub-format" title:_NS("Embedded Subtitle Formatting")];
    NSArray<NSString *> *families = [NSFontManager.sharedFontManager.availableFontFamilies
        sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    [self addPopup:@"freetype-font" title:_NS("Subtitle Font")
             labels:[@[_NS("Automatic")] arrayByAddingObjectsFromArray:families]
             values:[@[@""] arrayByAddingObjectsFromArray:families]];
    [self addColor:@"freetype-color" title:_NS("Text Color")];
    [self addColor:@"freetype-outline-color" title:_NS("Outline Color")];
    [self addNumber:@"sub-margin" title:_NS("Vertical Position") minimum:0 maximum:500 unit:@"px"];
    _sizeMode = [[VLCRedesignSizeModeRow alloc] init];
    __weak typeof(self) weakSelf = self;
    _sizeMode.changed = ^(BOOL pixelMode) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf)
            return;
        [strongSelf.window makeFirstResponder:nil];
        NSInteger pixels = [NSUserDefaults.standardUserDefaults integerForKey:@"VLCRedesignSubtitlePixelSize"];
        if (pixels < 1 || pixels > 512)
            pixels = 24;
        config_PutInt("freetype-font-size", pixelMode ? pixels : 0);
        [strongSelf.player refreshPausedSubtitleAppearance];
        [strongSelf refresh];
    };
    [_content addObject:_sizeMode];
    [self addNumber:@"subtitle-scale" title:_NS("Relative Size") minimum:10 maximum:500 unit:@"%"];
    VLCInspectorNumberRow *pixels = [self addNumber:@"freetype-font-size" title:_NS("Pixel Size")
                                            minimum:1 maximum:512 unit:@"px"];
    pixels.field.toolTip = pixels.slider.toolTip = _NS("Font size in the subtitle canvas. Video scaling also scales subtitles.");
    [self addNumber:@"freetype-outline-thickness" title:_NS("Outline Thickness") minimum:0 maximum:50 unit:@""];
    [self addNumber:@"freetype-background-opacity" title:_NS("Background Opacity") minimum:0 maximum:100 unit:@"%"];
    [self addColor:@"freetype-background-color" title:_NS("Background Color")];
    [self addAction:_NS("Reset Subtitle Timing") selector:@selector(resetSubtitleTiming:)];
}

- (void)selectValue:(id)value popup:(NSPopUpButton *)popup
{
    if (!popup || popup.cell.highlighted)
        return;
    for (NSMenuItem *item in popup.itemArray) {
        if ([item.representedObject isEqual:value]) {
            [popup selectItem:item];
            return;
        }
    }
    /* Preserve values chosen in VLC's other controls rather than showing a
     * misleading default when the current value is not one of our presets. */
    NSMenuItem *custom = [popup itemWithTitle:_NS("Custom")];
    if (!custom) {
        [popup addItemWithTitle:_NS("Custom")];
        custom = popup.lastItem;
        custom.enabled = NO;
    }
    custom.representedObject = value;
    [popup selectItem:custom];
}

- (BOOL)filterEnabled:(NSString *)name object:(vlc_object_t *)object variable:(const char *)variable
{
    char *value = var_InheritString(object, variable);
    NSString *chain = value ? [NSString stringWithUTF8String:value] : @"";
    free(value);
    for (NSString *component in [chain componentsSeparatedByString:@":"])
        if ([[component componentsSeparatedByString:@"{"].firstObject isEqualToString:name])
            return YES;
    return NO;
}

- (void)refresh
{
    if (!_content)
        return;
    VLCPlayerController *player = self.player;
    BOOL media = player.currentMedia != nil;
    [_numberRows[@"speed"] updateValue:fabs(player.playbackRate) enabled:media && player.rateChangable];
    [_numberRows[@"audio-delay"] updateValue:secf_from_vlc_tick(player.audioDelay) enabled:media];
    [_numberRows[@"subtitle-delay"] updateValue:secf_from_vlc_tick(player.subtitlesDelay) enabled:media];
    [_numberRows[@"subtitle-fps"] updateValue:player.subtitlesFPS enabled:media];
    [_numberRows[@"subtitle-scale"] updateValue:player.subtitleTextScalingFactor enabled:media];
    if (_sizeMode) {
        NSInteger pixels = config_GetInt("freetype-font-size");
        BOOL pixelMode = pixels > 0;
        _sizeMode.pixelMode = pixelMode;
        if (_numberRows[@"subtitle-scale"].hidden != pixelMode ||
            _numberRows[@"freetype-font-size"].hidden == pixelMode) {
            _numberRows[@"subtitle-scale"].hidden = pixelMode;
            _numberRows[@"freetype-font-size"].hidden = !pixelMode;
            self.needsLayout = YES;
        }
        [_numberRows[@"freetype-font-size"] updateValue:pixels enabled:media];
        _toggles[@"embedded-sub-format"].enabled = media;
        _toggles[@"embedded-sub-format"].state = !config_GetInt("freetype-override-styles");
        char *font = config_GetPsz("freetype-font");
        [self selectValue:font ? [NSString stringWithUTF8String:font] : @"" popup:_popups[@"freetype-font"]];
        free(font);
    }
    _toggles[@"reverse"].enabled = media && player.rewindable;
    _toggles[@"reverse"].state = player.playbackRate < 0 ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSString *key in @[ @"audio-language", @"sub-language" ]) {
        if (_popups[key])
            [self selectValue:[player preferredLanguageForCategory:[key isEqualToString:@"audio-language"] ? AUDIO_ES
                                                                                                           : SPU_ES]
                        popup:_popups[key]];
    }
    NSDate *deadline = VLCPlaybackSleepTimer.sharedTimer.deadline;
    NSPopUpButton *sleep = _popups[@"sleep"];
    if (deadline) {
        NSString *title = [NSString
            stringWithFormat:_NS("%ld minutes remaining"), (long)MAX(1, ceil(deadline.timeIntervalSinceNow / 60))];
        NSMenuItem *countdown = [sleep.menu itemWithTag:-1];
        if (!countdown && sleep) {
            [sleep addItemWithTitle:title];
            countdown = sleep.lastItem;
            countdown.tag = -1;
            countdown.enabled = NO;
        }
        countdown.title = title;
        [sleep selectItem:countdown];
    } else {
        [self selectValue:@0 popup:sleep];
    }
    vout_thread_t *vout = player.mainVideoOutputThread;
    for (NSString *key in
         @[ @"brightness", @"contrast", @"saturation", @"hue", @"gamma", @"subsdelay-factor", @"sub-margin" ]) {
        VLCInspectorNumberRow *row = _numberRows[key];
        if (!row)
            continue;
        double value = vout ? ([key isEqualToString:@"sub-margin"] ? var_GetInteger(vout, key.UTF8String)
                                                                   : var_InheritFloat(vout, key.UTF8String))
                            : 0;
        if (vout && [key isEqualToString:@"subsdelay-factor"] &&
            ![self filterEnabled:@"subsdelay" object:VLC_OBJECT(vout) variable:"sub-filter"])
            value = 0;
        [row updateValue:value enabled:vout != NULL];
    }
    for (NSString *key in @[ @"aspect-ratio", @"crop", @"transform", @"zoom" ]) {
        NSPopUpButton *popup = _popups[key];
        popup.enabled = vout != NULL;
        if (!vout || !popup)
            continue;
        if ([key isEqualToString:@"zoom"]) {
            [self selectValue:@(var_GetFloat(vout, "zoom")) popup:popup];
        } else {
            const char *variable = [key isEqualToString:@"transform"] ? "transform-type" : key.UTF8String;
            char *value = var_InheritString(vout, variable);
            NSString *current = value ? [NSString stringWithUTF8String:value] : @"";
            free(value);
            if ([key isEqualToString:@"transform"] && ![self filterEnabled:@"transform"
                                                                    object:VLC_OBJECT(vout)
                                                                  variable:"video-filter"])
                current = @"";
            [self selectValue:current popup:popup];
        }
    }
    _toggles[@"adjust"].enabled = vout != NULL;
    if (vout) {
        _toggles[@"adjust"].state = [self filterEnabled:@"adjust" object:VLC_OBJECT(vout) variable:"video-filter"];
        vout_Release(vout);
    }
    [_numberRows[@"freetype-outline-thickness"] updateValue:config_GetInt("freetype-outline-thickness") enabled:media];
    [_numberRows[@"freetype-background-opacity"] updateValue:config_GetInt("freetype-background-opacity") * 100. / 255
                                                     enabled:media];
    for (NSString *key in _colorRows) {
        _colorRows[key].RGB = (uint32_t)config_GetInt(key.UTF8String);
        _colorRows[key].enabled = media;
    }
    audio_output_t *aout = player.mainAudioOutput;
    for (NSString *key in @[ @"compressor", @"spatializer", @"stereo_widen" ]) {
        _toggles[key].enabled = aout != NULL;
        _toggles[key].state = aout && [self filterEnabled:key object:VLC_OBJECT(aout) variable:"audio-filter"];
        ((NSControl *)_audioGroups[key].lastObject).enabled = aout != NULL;
    }
    for (NSString *key in _audioParameters) {
        NSString *filter = _audioParameters[key];
        [_numberRows[key] updateValue:aout ? var_InheritFloat(aout, key.UTF8String) : 0
                             enabled:aout && _toggles[filter].state == NSControlStateValueOn];
    }
    _popups[@"equalizer"].enabled = aout != NULL;
    if (aout) {
        char *preset = var_InheritString(aout, "equalizer-preset");
        NSString *name = preset ? [NSString stringWithUTF8String:preset] : @"";
        free(preset);
        id value = @"";
        if ([self filterEnabled:@"equalizer" object:VLC_OBJECT(aout) variable:"audio-filter"]) {
            value = name.length ? name : @"custom";
            for (NSUInteger i = 0; i < NB_PRESETS; i++)
                if ([name isEqualToString:[NSString stringWithUTF8String:preset_list[i]]])
                    value = @(i);
        }
        [self selectValue:value popup:_popups[@"equalizer"]];
        aout_Release(aout);
    }
}

- (void)applyNumber:(double)value forKey:(NSString *)key
{
    VLCPlayerController *player = self.player;
    if ([key isEqualToString:@"speed"]) {
        if (player.rateChangable)
            player.playbackRate = value * (player.playbackRate < 0 ? -1 : 1);
    } else if ([key isEqualToString:@"audio-delay"]) {
        player.audioDelay = vlc_tick_from_sec(value);
    } else if ([key isEqualToString:@"subtitle-delay"]) {
        player.subtitlesDelay = vlc_tick_from_sec(value);
    } else if ([key isEqualToString:@"subtitle-fps"]) {
        player.subtitlesFPS = value;
    } else if ([key isEqualToString:@"subtitle-scale"]) {
        player.subtitleTextScalingFactor = (unsigned int)lround(value);
    } else if (_audioParameters[key]) {
        audio_output_t *aout = player.mainAudioOutput;
        if (aout) {
            if (!var_Type(aout, key.UTF8String))
                var_Create(aout, key.UTF8String, VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
            var_SetFloat(aout, key.UTF8String, value);
            aout_Release(aout);
        }
    } else if ([key hasPrefix:@"freetype-"]) {
        config_PutInt(key.UTF8String,
                      lround([key isEqualToString:@"freetype-background-opacity"] ? value * 255 / 100 : value));
        if ([key isEqualToString:@"freetype-font-size"])
            [NSUserDefaults.standardUserDefaults setInteger:lround(value) forKey:@"VLCRedesignSubtitlePixelSize"];
        [player refreshPausedSubtitleAppearance];
    } else if ([key isEqualToString:@"sub-margin"]) {
        vout_thread_t *vout = player.mainVideoOutputThread;
        if (vout) {
            var_SetInteger(vout, "sub-margin", lround(value));
            vout_Release(vout);
        }
        [player refreshPausedSubtitleAppearance];
    } else {
        BOOL duration = [key isEqualToString:@"subsdelay-factor"];
        vlc_value_t vlcValue = {.f_float = value};
        [player setVideoFilterProperty:key forFilter:duration ? @"subsdelay" : @"adjust" withValue:vlcValue];
        [player enableVideoFilterWithName:duration ? @"subsdelay" : @"adjust" state:duration ? value > 0 : YES];
    }
}

- (void)popupChanged:(NSPopUpButton *)sender
{
    [self.window makeFirstResponder:nil];
    NSString *key = sender.identifier;
    id value = sender.selectedItem.representedObject;
    VLCPlayerController *player = self.player;
    if ([key isEqualToString:@"sleep"]) {
        NSInteger minutes = [value integerValue];
        VLCPlaybackSleepTimer.sharedTimer.deadline =
            minutes > 0 ? [NSDate dateWithTimeIntervalSinceNow:minutes * 60] : nil;
    } else if ([key isEqualToString:@"audio-language"] || [key isEqualToString:@"sub-language"]) {
        [player setPreferredLanguage:value forCategory:[key isEqualToString:@"audio-language"] ? AUDIO_ES : SPU_ES];
    } else if ([key isEqualToString:@"freetype-font"]) {
        config_PutPsz("freetype-font", [value UTF8String]);
        [player refreshPausedSubtitleAppearance];
    } else if ([key isEqualToString:@"equalizer"]) {
        BOOL enabled = [value isKindOfClass:NSNumber.class];
        [player enableAudioFilterWithName:@"equalizer" state:enabled];
        audio_output_t *aout = player.mainAudioOutput;
        if (enabled && aout) {
            NSUInteger index = [value unsignedIntegerValue];
            if (index < NB_PRESETS) {
                NSMutableArray *bands = [NSMutableArray arrayWithCapacity:EQZ_BANDS_MAX];
                for (NSUInteger i = 0; i < EQZ_BANDS_MAX; i++)
                    [bands addObject:[NSString stringWithFormat:@"%.7g", eqz_preset_10b[index].f_amp[i]]];
                var_SetString(aout, "equalizer-preset", preset_list[index]);
                var_SetString(aout, "equalizer-bands", [bands componentsJoinedByString:@" "].UTF8String);
                var_SetFloat(aout, "equalizer-preamp", eqz_preset_10b[index].f_preamp);
            }
        }
        if (aout)
            aout_Release(aout);
    } else if ([key isEqualToString:@"transform"]) {
        if ([value length]) {
            vlc_value_t vlcValue = {.psz_string = (char *)[value UTF8String]};
            [player setVideoFilterProperty:@"transform-type" forFilter:@"transform" withValue:vlcValue];
        }
        [player enableVideoFilterWithName:@"transform" state:[value length] > 0];
    } else {
        vout_thread_t *vout = player.mainVideoOutputThread;
        if (vout) {
            if ([value isKindOfClass:NSNumber.class])
                var_SetFloat(vout, key.UTF8String, [value floatValue]);
            else
                var_SetString(vout, key.UTF8String, [value UTF8String]);
            vout_Release(vout);
        }
    }
    [self refresh];
}

- (void)toggleChanged:(NSButton *)sender
{
    [self.window makeFirstResponder:nil];
    NSString *key = sender.identifier;
    BOOL enabled = sender.state == NSControlStateValueOn;
    if ([key isEqualToString:@"reverse"]) {
        if (self.player.rewindable)
            self.player.playbackRate = fabs(self.player.playbackRate) * (enabled ? -1 : 1);
    } else if ([key isEqualToString:@"adjust"]) {
        [self.player enableVideoFilterWithName:key state:enabled];
    } else if ([key isEqualToString:@"embedded-sub-format"]) {
        config_PutInt("freetype-override-styles", !enabled);
        [self.player refreshPausedSubtitleAppearance];
    } else {
        [self.player enableAudioFilterWithName:key state:enabled];
    }
    [self refresh];
}

- (void)resetSpeed:(id)sender
{
    [self.window makeFirstResponder:nil];
    if (self.player.rateChangable)
        self.player.playbackRate = 1;
}

- (void)resetPicture:(id)sender
{
    [self.window makeFirstResponder:nil];
    for (NSString *key in @[ @"brightness", @"contrast", @"saturation", @"gamma", @"hue" ]) {
        vlc_value_t value = {.f_float = [key isEqualToString:@"hue"] ? 0 : 1};
        [self.player setVideoFilterProperty:key forFilter:@"adjust" withValue:value];
    }
    [self refresh];
}

- (void)resetSubtitleTiming:(id)sender
{
    [self.window makeFirstResponder:nil];
    self.player.subtitlesDelay = 0;
    self.player.subtitlesFPS = 0;
    [self applyNumber:0 forKey:@"subsdelay-factor"];
    [self refresh];
}

- (void)showMetadata:(id)sender
{
    [VLCMain.sharedInstance.mainMenu showInformationPanel:sender];
}

- (void)expandVideo:(id)sender
{
    [VLCMain.sharedInstance.mainMenu showVideoEffects:sender];
}

- (void)expandAudio:(id)sender
{
    [VLCMain.sharedInstance.mainMenu showAudioEffects:sender];
}

- (void)openAdvanced:(id)sender
{
    [VLCMain.sharedInstance.mainMenu showPreferences:sender];
}

- (void)layout
{
    [super layout];
    CGFloat width = NSWidth(self.bounds);
    _header.frame = NSMakeRect(0, 0, width, 50);
    for (NSUInteger i = 0; i < _tabs.count; i++)
        _tabs[i].frame = NSMakeRect(i * width / 4, 0, width / 4, 50);
    _scroll.frame = NSMakeRect(0, 50, width, MAX(0, NSHeight(self.bounds) - 50));
    CGFloat y = 12;
    for (NSView *view in _content) {
        if (view.hidden)
            continue;
        CGFloat height = NSHeight(view.frame);
        if (view == _content.lastObject)
            y = MAX(y, NSHeight(_scroll.contentView.bounds) - height - 12);
        view.frame = NSMakeRect(0, y, width, height);
        if ([view isKindOfClass:VLCRedesignAlignedLabel.class])
            view.frame = NSMakeRect(20, y, MAX(0, width - 40), height);
        else if ([view isKindOfClass:NSButton.class] && ![view isKindOfClass:VLCRedesignPanelButton.class])
            view.frame = NSMakeRect(20, y, MAX(0, width - 40), height);
        y += height;
    }
    _document.frame = NSMakeRect(0, 0, width, MAX(y + 12, NSHeight(_scroll.contentView.bounds)));
}

@end
