# Native macOS regression checks

`file-drop.m` loads the file-drop parser from a built VLC app and checks modern
file/stream URLs, absolute and relative text paths, empty data, legacy filename
arrays, mixed values, and malformed legacy property lists. It uses a unique
pasteboard and temporary file, without opening media or changing VLC's queue.
Malformed legacy values use a test double because AppKit rejects them when
publishing a real pasteboard.

Run from the repository root after building the macOS app. Set `vlc_test_app` to
its absolute path, then compile and run:

```sh
vlc_test_app="$PWD/build-macos-baseline/VLC-dev.app"
clang -fobjc-arc -Wall -Wextra -framework Cocoa \
    -Wl,-rpath,"$vlc_test_app/Contents/Frameworks" \
    test/modules/gui/macosx/file-drop.m -o /tmp/vlc-file-drop-test
/tmp/vlc-file-drop-test "$vlc_test_app/Contents/Frameworks/plugins/libmacosx_plugin.dylib"
```

The executable and app must have matching architectures. This standalone check
is not currently integrated into the cross-platform test runner.

`pip-container.m` checks the actual PiP container class without starting playback.
After moving its video view back to a native player host, a late PiP appearance
callback must not add constraints to that host or change its geometry. Compile
it like `file-drop.m`, with its own executable name. Running-app checks cover the
system PiP presentation, controls and return animation separately.

`inspector.m` checks numeric text entry, range validation, keyboard-editable and
centered fields, disabled controls, timer expiration/cancellation/replacement,
wake checks and timer ownership. It loads the actual inspector classes but uses
an injected expiration handler, so it does not start or stop VLC playback.
Compile it with the same command, replacing `file-drop.m` with `inspector.m` and
choosing a distinct executable name.

`resume-prompt.m` checks timestamp display, non-overlapping controls at three
widths, Continue/Dismiss dispatch and one-shot completion. It does not resume
actual media; that is covered by running-app acceptance of the controller path.
Compile it in the same way, using its source and a distinct executable name.

`window-commands.m` checks that window commands run serially on held video
outputs while leaving the main queue available for synchronous output setup.
This models the fullscreen-restoration lock cycle without opening playback.
It links the core and loads the GUI module from the same build tree to avoid
loading two copies of the Objective-C classes:

```sh
clang -fobjc-arc -std=gnu11 -Wall -Wextra -DHAVE_CONFIG_H \
    -Ibuild-macos-baseline -Iinclude -I. -framework Cocoa \
    test/modules/gui/macosx/window-commands.m \
    -Lbuild-macos-baseline/src/.libs -Lbuild-macos-baseline/lib/.libs -lvlc -lvlccore \
    -Wl,-rpath,"$PWD/build-macos-baseline/src/.libs" \
    -Wl,-rpath,"$PWD/build-macos-baseline/lib/.libs" \
    -Wl,-rpath,"$PWD/build-macos-baseline/VLC-dev.app/Contents/Frameworks" \
    -o /tmp/vlc-window-commands-test
VLC_PLUGIN_PATH="$PWD/build-macos-baseline/modules" /tmp/vlc-window-commands-test \
    "$PWD/build-macos-baseline/modules/.libs/libmacosx_plugin.dylib"
```

`fullscreen-controls.m` loads the actual chrome visibility method with native
window geometry, a fake player state and an injected pointer source. It checks
both edges, leaving the window, windowed mode and four open-panel cases. Compile
like `resume-prompt.m`. It does not claim physical pointer acceptance.

`seek-preview.m` links the production preview, appearance and aligned-label
objects. It supplies a real thumbnail preparser without starting the GUI or a
playing input. Use a video longer than 80 seconds with visibly changing frames.
Checks cover distinct requested frames, timestamp text, cache reuse, stale
completion, cancellation, temporary-file cleanup and owner teardown.

```sh
vlc_test_objects="$PWD/build-macos-baseline/modules/gui/macosx/redesign/.libs"
clang -fobjc-arc -std=gnu11 -Wall -Wextra -DHAVE_CONFIG_H \
    -Ibuild-macos-baseline -Iinclude -I. -Imodules/gui/macosx \
    -framework Cocoa -framework CoreText test/modules/gui/macosx/seek-preview.m \
    "$vlc_test_objects/libmacosx_plugin_la-VLCRedesignSeekPreview.o" \
    "$vlc_test_objects/libmacosx_plugin_la-VLCRedesignAppearance.o" \
    "$vlc_test_objects/libmacosx_plugin_la-VLCRedesignTextLayout.o" \
    -Lbuild-macos-baseline/src/.libs -Lbuild-macos-baseline/lib/.libs -lvlc -lvlccore \
    -Wl,-rpath,"$PWD/build-macos-baseline/src/.libs" \
    -Wl,-rpath,"$PWD/build-macos-baseline/lib/.libs" \
    -o /tmp/vlc-seek-preview-test
VLC_PLUGIN_PATH="$PWD/build-macos-baseline/modules" /tmp/vlc-seek-preview-test \
    /absolute/path/to/test-video.mkv
```
