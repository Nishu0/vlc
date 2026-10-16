# Build and verification record

## Baseline

- Source revision: `4953f0be3ea61dd5fc62f2c333e540d2b166ccbc`.
- Version: `4.0.0-dev`.
- Branch: `codex/vlc-redesign`.
- Host inspected: Apple Silicon `arm64`; Xcode 26.5, build 17F42.
- Initial free space reported by `df`: approximately 35 GiB.
- Application-code changes at build start: none.
- Build directory: `build-macos-baseline/` (ignored by the existing repository rules).
- Build log: `build-macos-baseline/baseline-build.log`.

Initial invocation, run inside the build directory:

```sh
VLC_PATH=/opt/homebrew/bin:/Users/nisargthakkar/.cargo/bin \
  bash ../extras/package/macosx/build.sh -a aarch64 -j 6 \
  > baseline-build.log 2>&1
```

The official script bootstrapped missing development tools in `extras/tools/`; that is generated build output, not a redesign. This first attempt used the current host Darwin 25 triplet, found no prebuilt archive, and fell back to source dependencies. The rav1e vendor dependency then encountered Cargo's enclosing-workspace detection. That attempt was stopped; the application source and Cargo workspace were not modified to work around it.

VideoLAN's own macOS CI uses `VLC_FORCE_KERNELVERSION=19`. The matching dependency revision from `extras/ci/get-contrib-sha.sh macos-arm64` is `bb14e3f6d499eaab89c45a6b245142f5ccadd264`. Its published archive was available (HTTP 200, 215429815 bytes) and downloaded/extracted successfully. The invocation became:

```sh
VLC_FORCE_KERNELVERSION=19 \
VLC_PREBUILT_CONTRIBS_URL=https://artifacts.videolan.org/vlc/macos-arm64/vlc-contrib-aarch64-apple-darwin19-bb14e3f6d499eaab89c45a6b245142f5ccadd264.tar.zst \
VLC_PATH=/opt/homebrew/bin:/Users/nisargthakkar/.cargo/bin \
  bash ../extras/package/macosx/build.sh -a aarch64 -j 6 \
  > baseline-build-ci.log 2>&1
```

Configuration then found that the installed Xcode lacked `metallib`. Installed Apple's optional component with `xcodebuild -downloadComponent MetalToolchain` rather than disabling native UI shaders. Component log: `build-macos-baseline/metal-toolchain.log`.

The unchanged application build and packaging have completed. `xcrun --find metal` still selected Xcode's stub after installing the component; using `xcrun --toolchain Metal --find metal`/`metallib` fixed tool selection. Resuming make also required exporting `SDKROOT`. Finally, the prebuilt ncurses link metadata contained the CI machine's old SDK 26.2 path; a local `NCURSES_LIBS` make override linked the same library against the installed SDK. No application source was changed for these environment fixes.

The working local continuation is `bash build-macos-baseline/resume-build.sh`. It runs make and packaging with those overrides. Logs: `baseline-make-final.log`, `baseline-package-final.log`. This local helper is generated build output. Its effective commands, run inside the configured build directory, are:

```sh
export PATH="$PWD/../extras/tools/build/bin:/opt/homebrew/bin:$PATH"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
vlc_metal_path="$(xcrun --toolchain Metal --find metal)"
vlc_metallib_path="$(xcrun --toolchain Metal --find metallib)"
vlc_ncurses_flags="-L$PWD/contrib/aarch64-apple-darwin19/lib -lncursesw"
make -j6 METAL="$vlc_metal_path" METALLIB="$vlc_metallib_path" NCURSES_LIBS="$vlc_ncurses_flags"
make VLC.app METAL="$vlc_metal_path" METALLIB="$vlc_metallib_path" NCURSES_LIBS="$vlc_ncurses_flags"
```

To reproduce the **unchanged** baseline, check out the pinned revision in a separate checkout before configuring. Running these commands against the current redesign branch builds its changes instead. The preserved baseline artifacts remain unchanged.

Verified artifacts: `build-macos-baseline/artifacts/macos-baseline/VLC.app` and `build-macos-baseline/artifacts/VLC-baseline-arm64.dmg`. The main executable is arm64, SHA-256 `9e44baa8851bba204d4eddc7d72899e4bd334ad9944331e44ffd87f0b5fb36e6`. The bundle includes 390 plugins and passes deep strict ad-hoc signature verification. A machine-readable check record is saved as `build-macos-baseline/baseline-verification.json`.

Deterministic local fixtures have been generated in `build-macos-baseline/fixtures/`: a 12-second 320×180 Y4M video, a 12-second stereo PCM WAV, and an SRT with three four-second cues. These are generated test inputs, not shipped design assets.

## macOS baseline acceptance

- [x] Unchanged source compiles with the native macOS interface.
- [x] `VLC.app` packages successfully with required libraries/plugins.
- [x] Packaged app launches from its bundle.
- [x] Local video and audio actually play.
- [x] External subtitles load and timing can change.
- [x] Pause/seek/volume work.
- [x] Resizing and fullscreen preserve video output.
- [x] Exact source revision, command, logs and limitations recorded.

## Windows

Not started. The source map confirms separate Qt/QML interface work is required, so macOS is prioritized as requested. The documented build route is `doc/BUILD-win32.md` and `extras/package/win32/build.sh` with MinGW-w64 GCC or LLVM; the repository does not support treating MSVC as the normal build toolchain. An executable built or downloaded without Windows runtime verification is not a verified Windows deliverable.

## Observed baseline behavior

The packaged Cocoa app launched. Generated H.264 MP4 decoded using VideoToolbox and the external SRT rendered visibly. Pause/resume worked. A configured three-second backward keyboard seek changed paused position from 0.7133333 to 0.4633334 in the 12-second video. Native volume changed from 25% to 20% using Command–Down. Standard window zoom resized the window, and native fullscreen entered/exited successfully. The synchronization panel changed subtitle delay from 0.000 s to 0.500 s and was reset afterward. A separate PCM WAV played through the auhal output at gain zero. VLC itself converted the generated Y4M fixture to a 12-second H.264 MP4.

The native file-open automation did not reliably complete inside macOS's Go to Folder sheet; the video was subsequently opened through executable arguments. File-dialog automation is not counted as passed. Some network-discovery attempts emitted multicast-interface errors on this host, so network/casting is not counted as verified. Older macOS, Intel and Windows have not been tested. The baseline is locally ad-hoc signed, not a Developer ID signed/notarized release.

Baseline gate passed before any redesign application-code edits. The baseline app and DMG are preserved separately from the incrementally rebuilt app.

## First redesign slice

Native onboarding and appearance changes compile and package through the same configured build tree. The latest logs are `redesign-text-audit-make-final.log` and `redesign-text-audit-package-final.log`. See [onboarding verification and scope](onboarding-status.md). The working `build-macos-baseline/VLC.app` now contains these changes; it is distinct from the preserved unchanged baseline under `artifacts/macos-baseline/`.
