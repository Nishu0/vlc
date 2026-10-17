/*****************************************************************************
 * resume-prompt.m: native resume prompt layout and action regressions
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#include <dlfcn.h>

@protocol VLCResumePromptTest <NSObject>
- (instancetype)initWithPosition:(NSInteger)seconds choice:(void (^)(BOOL))choice;
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
        Class promptClass = NSClassFromString(@"VLCRedesignResumePrompt");
        if (!promptClass)
            return 1;
        __block NSUInteger calls = 0;
        __block BOOL continuePlayback = NO;
        NSView *prompt = (NSView *)[(id<VLCResumePromptTest>)[promptClass alloc]
            initWithPosition:600 choice:^(BOOL choice) {
                calls++;
                continuePlayback = choice;
            }];
        NSTextField *message = [prompt valueForKey:@"message"];
        NSButton *resume = [prompt valueForKey:@"continueButton"];
        NSButton *dismiss = [prompt valueForKey:@"dismissButton"];
        BOOL passed = Check([message.stringValue containsString:@"00:10:00"], "Resume time is expressed in seconds");
        for (NSNumber *width in @[@550, @400, @300]) {
            prompt.frame = NSMakeRect(0, 0, width.doubleValue, 52);
            [prompt layoutSubtreeIfNeeded];
            BOOL contained = NSContainsRect(prompt.bounds, resume.frame) &&
                             NSContainsRect(prompt.bounds, dismiss.frame);
            BOOL separate = NSMaxX(message.frame) <= NSMinX(resume.frame) &&
                            NSMaxX(resume.frame) <= NSMinX(dismiss.frame);
            passed &= Check(contained && separate, "Responsive prompt controls do not overlap");
        }
        [resume performClick:nil];
        passed &= Check(calls == 1 && continuePlayback, "Continue invokes the resume action");
        [dismiss performClick:nil];
        passed &= Check(calls == 1, "A prompt completes only once");
        NSView *second = (NSView *)[(id<VLCResumePromptTest>)[promptClass alloc]
            initWithPosition:-1 choice:^(BOOL choice) {
                calls++;
                continuePlayback = choice;
            }];
        [second layoutSubtreeIfNeeded];
        message = [second valueForKey:@"message"];
        passed &= Check([message.stringValue containsString:@"00:00:00"], "Negative time is bounded");
        dismiss = [second valueForKey:@"dismissButton"];
        [dismiss performClick:nil];
        passed &= Check(calls == 2 && !continuePlayback, "Dismiss keeps playback at the beginning");
        return passed ? 0 : 1;
    }
}
