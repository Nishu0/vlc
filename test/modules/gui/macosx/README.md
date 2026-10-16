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
