/*****************************************************************************
 * inspector.m: native inspector numeric-entry and sleep-timer regressions
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <math.h>

/* Exercise the classes in the built module, without starting a VLC instance. */
@protocol VLCInspectorNumberTest <NSObject>
@property (readonly) NSTextField *field;
@property (readonly) NSSlider *slider;
@property (copy) void (^changed)(double);
- (instancetype)initWithTitle:(NSString *)title minimum:(double)minimum maximum:(double)maximum unit:(NSString *)unit;
- (void)updateValue:(double)value enabled:(BOOL)enabled;
- (void)controlTextDidEndEditing:(NSNotification *)notification;
@end

@protocol VLCSleepTimerTest <NSObject>
@property (copy) NSDate *deadline;
- (instancetype)initWithExpirationHandler:(void (^)(void))handler;
- (void)checkDeadline:(NSNotification *)notification;
@end

static BOOL Check(BOOL condition, const char *description)
{
    fprintf(stderr, "%s: %s\n", description, condition ? "PASS" : "FAIL");
    return condition;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "Usage: %s /path/to/libmacosx_plugin.dylib\n", argv[0]);
            return 1;
        }
        [NSApplication sharedApplication];
        if (!dlopen(argv[1], RTLD_NOW | RTLD_LOCAL)) {
            fprintf(stderr, "%s\n", dlerror());
            return 1;
        }
        Class rowClass = NSClassFromString(@"VLCInspectorNumberRow");
        Class timerClass = NSClassFromString(@"VLCPlaybackSleepTimer");
        if (!rowClass || !timerClass)
            return 1;
        id<VLCInspectorNumberTest> row = [(id<VLCInspectorNumberTest>)[rowClass alloc]
            initWithTitle:@"Speed" minimum:.25 maximum:2 unit:@"×"];
        __block double applied = -1;
        row.changed = ^(double value) { applied = value; };
        BOOL passed = Check(row.field.editable && row.field.selectable, "Numeric field is editable");
        passed &= Check(row.field.alignment == NSTextAlignmentCenter, "Numeric text is centered");
        [row updateValue:1 enabled:YES];
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        row.field.stringValue = [[formatter stringFromNumber:@1.25] stringByAppendingString:@" ×"];
        [row controlTextDidEndEditing:nil];
        passed &= Check(fabs(applied - 1.25) < .0001, "Typed value reaches binding");
        row.field.stringValue = @"100 ×";
        [row controlTextDidEndEditing:nil];
        passed &= Check(applied == 2 && row.slider.doubleValue == 2, "Typed maximum is bounded");
        row.field.stringValue = @"not a number";
        applied = -1;
        [row controlTextDidEndEditing:nil];
        passed &= Check(applied == -1 && row.slider.doubleValue == 2, "Invalid text does not apply");
        row.field.stringValue = @"-5 ×";
        [row controlTextDidEndEditing:nil];
        passed &= Check(applied == .25 && row.slider.doubleValue == .25, "Typed minimum is bounded");
        [row updateValue:1 enabled:NO];
        passed &= Check(!row.field.enabled && !row.slider.enabled, "Unavailable parameter disables both controls");

        __block NSUInteger expirations = 0;
        id<VLCSleepTimerTest> timer = [(id<VLCSleepTimerTest>)[timerClass alloc]
            initWithExpirationHandler:^{ expirations++; }];
        timer.deadline = [NSDate dateWithTimeIntervalSinceNow:.01];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        passed &= Check(expirations == 1 && timer.deadline == nil, "Timer expires and clears deadline");
        [timer checkDeadline:nil];
        passed &= Check(expirations == 1, "Timer expires only once");
        timer.deadline = [NSDate dateWithTimeIntervalSinceNow:.01];
        timer.deadline = nil;
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        passed &= Check(expirations == 1, "Cancelled timer does not expire");
        timer.deadline = [NSDate dateWithTimeIntervalSinceNow:.01];
        timer.deadline = [NSDate dateWithTimeIntervalSinceNow:3600];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        passed &= Check(expirations == 1, "Replacing deadline cancels previous timer");
        timer.deadline = [NSDate dateWithTimeIntervalSinceNow:-1];
        [timer checkDeadline:nil];
        passed &= Check(expirations == 2 && timer.deadline == nil, "Overdue deadline expires after wake check");
        __weak id<VLCSleepTimerTest> releasedTimer;
        @autoreleasepool {
            id<VLCSleepTimerTest> temporary = [(id<VLCSleepTimerTest>)[timerClass alloc]
                initWithExpirationHandler:^{ expirations++; }];
            temporary.deadline = [NSDate dateWithTimeIntervalSinceNow:3600];
            releasedTimer = temporary;
        }
        passed &= Check(releasedTimer == nil, "Timer does not retain its owner");
        return passed ? 0 : 1;
    }
}
