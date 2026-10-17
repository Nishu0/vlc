/*****************************************************************************
 * VLCResumeDialogController.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2015 VLC authors and VideoLAN
 *
 * Authors: Felix Paul Kühne <fkuehne -at- videolan -dot- org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/


#import "VLCResumeDialogController.h"

#import "main/VLCMain.h"
#import "extensions/NSString+Helpers.h"
#import "windows/video/VLCVideoOutputProvider.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryWindow.h"
#import "windows/video/VLCMainVideoViewController.h"
#import "windows/video/VLCVideoWindowCommon.h"

#import <vlc_configuration.h>

@interface VLCResumeDialogController()
{
    int _currentResumeTimeout;
    CompletionBlock _completionBlock;
    NSTimer *_countdownTimer;
    VLCInputItem *_inputItem;
    NSInteger _lastPosition;
    __weak VLCMainVideoViewController *_resumeVideoController;
}
- (void)finishWithResult:(enum ResumeResult)result;
@end

@implementation VLCResumeDialogController

- (instancetype)init
{
    self = [super initWithWindowNibName:@"ResumeDialog"];
    if (self) {
        [NSNotificationCenter.defaultCenter addObserver:self
                                                 selector:@selector(updateCocoaWindowLevel:)
                                                     name:VLCWindowShouldUpdateLevel
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [_countdownTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)windowDidLoad
{
    [_titleLabel setStringValue:_NS("Continue playback")];
    [_resumeButton setTitle:_NS("Continue playback")];

    [_alwaysResumeCheckbox setTitle:_NS("Always continue media playback")];

    [self updateTextLabels];
}

- (void)showWindowWithItem:(VLCInputItem *)inputItem withLastPosition:(NSInteger)pos completionBlock:(CompletionBlock)block
{
    [self cancel];
    _inputItem = inputItem;
    _lastPosition = pos;
    _currentResumeTimeout = 10;
    _completionBlock = [block copy];

    VLCVideoWindowCommon *owner = [NSApp.mainWindow isKindOfClass:VLCVideoWindowCommon.class]
        ? (VLCVideoWindowCommon *)NSApp.mainWindow : VLCMain.sharedInstance.libraryWindow;
    VLCMainVideoViewController *videoController = owner.videoViewController;
    __weak typeof(self) weakSelf = self;
    BOOL embedded = [videoController showResumeAtPosition:pos choice:^(BOOL continuePlayback) {
        [weakSelf finishWithResult:continuePlayback ? RESUME_NOW : RESUME_RESTART];
    }];
    if (embedded) {
        _resumeVideoController = videoController;
    } else {
        [self updateTextLabels];
        NSWindow *window = self.window;
        window.level = VLCMain.sharedInstance.voutProvider.currentStatusWindowLevel;
        [window center];
        [window makeKeyAndOrderFront:nil];
    }
    _countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *__unused timer) {
        [weakSelf updateAlertWindow:timer];
    }];
}

- (void)updateTextLabels
{
    NSString *restartButtonLabel = _NS("Restart playback");
    restartButtonLabel = [restartButtonLabel stringByAppendingFormat:@" (%d)", _currentResumeTimeout];
    [_restartButton setTitle:restartButtonLabel];

    if (!_inputItem) {
        return;
    }

    NSString *labelString = [NSString stringWithFormat:_NS("Playback of \"%@\" will continue at %@"), _inputItem.title, [NSString stringWithTime:_lastPosition]];
    [_descriptionLabel setStringValue:labelString];
    [_alwaysResumeCheckbox setState:NSControlStateValueOff];
}

- (void)updateAlertWindow:(NSTimer *)timer
{
    --_currentResumeTimeout;
    if (_currentResumeTimeout <= 0) {
        [self finishWithResult:RESUME_RESTART];
        return;
    }

    NSString *buttonLabel = _NS("Restart playback");
    buttonLabel = [buttonLabel stringByAppendingFormat:@" (%d)", _currentResumeTimeout];

    [_restartButton setTitle:buttonLabel];
}

- (void)finishWithResult:(enum ResumeResult)result
{
    CompletionBlock completion = _completionBlock;
    [self cancel];
    if (completion)
        completion(result);
}

- (IBAction)buttonClicked:(id)sender
{
    [self finishWithResult:sender == _resumeButton ? RESUME_NOW : RESUME_RESTART];
}

- (IBAction)resumeSettingChanged:(id)sender
{
    int newState = [sender state] == NSControlStateValueOn ? 1 : 0;
    msg_Dbg(getIntf(), "Changing resume setting to %i", newState);
    config_PutInt("macosx-continue-playback", newState);
}

- (void)updateCocoaWindowLevel:(NSNotification *)aNotification
{
    NSInteger i_level = [aNotification.userInfo[VLCWindowLevelKey] integerValue];
    if (self.isWindowLoaded && [self.window isVisible] && [self.window level] != i_level)
        [self.window setLevel: i_level];
}

- (void)cancel
{
    [_countdownTimer invalidate];
    _countdownTimer = nil;
    _completionBlock = nil;
    _inputItem = nil;
    [_resumeVideoController cancelResumePrompt];
    _resumeVideoController = nil;
    if (self.isWindowLoaded)
        [self.window close];
}

@end
