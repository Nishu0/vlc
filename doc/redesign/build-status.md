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

## Native player preview, October 17

The source at `a835ba0a9e60f31317c812387a2ec37367a836e0` completes another player milestone: responsive native chrome, direct track/device selectors, Queue / Bookmarks / Chapters, compact browser, and clipped seek redraws during live resizing. See [player scope and acceptance](player-status.md) for the remaining work. This is a partial redesign.

The full build and packaging ran through `resume-build.sh redesign-player-browser-final`. Both the packaged app and staged copy pass `codesign --verify --deep --strict`; they contain 390 plugins. The Apple Silicon executable SHA-256 is `975532e8dc4192bfc22f94f84f02fb356cc7596645f9aa1969b6167ec135d4f4`, and the native macOS plugin SHA-256 is `a0aa51dec49afa8883ae9df5e71bf85958f9c712c208f073f9779a3f39875245`. This is local ad-hoc signing, without Developer ID signing or notarization.

Local deliverables are `build-macos-baseline/artifacts/macos-player-preview-a835ba0a9e/VLC.app` and `build-macos-baseline/artifacts/VLC-player-preview-arm64.dmg`. The disk image passes `hdiutil verify` with CRC32 `FC04BFFE`. The staged folder contains a machine-readable verification record and scope README. Earlier previews and the unchanged baseline app remain in their separate folders. User media, test media and library databases are not bundled.

The staged app was launched by its own executable path, outside the working `VLC.app` build copy, with the supplied local MKV. Actual video and English subtitles rendered, and the selector exposed all 19 embedded subtitle tracks. Live resize checks at 802 and 604 points retained the duration; a pointer click sought to 1:30 after resizing. Full-library expansion opened the same fixture folder with playback still at 1:30. Cross-panel pointer-drop completion, network-source contents, fullscreen edge-hover and PiP return remain acceptance work. The four-tab inspector, seek thumbnails, complete library redesign and Windows port are still pending.

## Code-quality preview refresh, October 17

Source `e4bc2a9d9261fcc7f03251dabb2cffa0969a56ab` includes the Cocoa code-quality review recorded in
[player status](player-status.md). The full arm64 build/package ran through
`resume-build.sh redesign-quality`. The staged app is
`build-macos-baseline/artifacts/macos-player-preview-e4bc2a9d92/VLC.app`; the
updated disk image remains `build-macos-baseline/artifacts/VLC-player-preview-arm64.dmg`.
Both app copies pass deep strict ad-hoc signature verification, with 390 plugins.
The disk image passes `hdiutil verify`, CRC32 `8AE1DF2E`.

Executable SHA-256: `31a678cf79c81366f96519a7d901a193fa5ad56462ede3d1d8f88c7e37de4804`.
Native macOS plugin SHA-256: `2eebfd761cb64e2b26796a5210c66ec190b22f52224ede8ef230c0315dc04225`.
The parser's 12 regression cases also pass against the staged module. The
staged app opens the generated chapter video, loads its six-item fixture
folder in the compact browser, and changes from Play to Pause on playback.
Signing remains local/ad-hoc and is not notarized. Earlier staged apps and the
unchanged baseline are preserved. The scope and remaining redesign work have
not changed.

## Video-led inspector review build, October 17

Source `04eb47e1605657d8ca985b2205746e5dcd6d7e59` adds the first four-tab
inspector and the resume notification identified during the timestamped
[video review](video-review.md). It includes the preceding rotation/display
negotiation fixes. The implemented controls and remaining workflows are listed
in [player status](player-status.md); this remains a partial redesign.

The full arm64 build and packaging completed through
`resume-build.sh redesign-video-review`. Logs are
`build-macos-baseline/redesign-video-review-make-final.log` and
`build-macos-baseline/redesign-video-review-package-final.log`. The staged app is
`build-macos-baseline/artifacts/macos-player-preview-04eb47e160/VLC.app`.
Both the build copy and staged app pass deep strict ad-hoc signature verification
and contain 390 plugins. Signing is local, without Developer ID signing or
notarization.

The separate review image is
`build-macos-baseline/artifacts/VLC-video-review-preview-arm64.dmg`.
It passes `hdiutil verify`, CRC32 `A5E4CF35`. The previous player-preview disk
image and unchanged baseline are preserved. Executable SHA-256 is
`1aeeb0b5e36427c6147877a82f2d60faca870eb4d16471942fa580ae30f8ece7`;
macOS plugin SHA-256 is
`853afcbc34ad68ac7c01c20badc9ec9ca40d8caf520b70fd01eb4b80298a2e74`.
The staged folder contains its source revision, scope README and machine-readable
verification record. No user media, test media or library databases are bundled.

Thirteen inspector checks, eight resume-widget checks and twelve file-drop
checks pass against the staged module. The 42 native text renders and four
video-output scenarios also pass. Development-app testing confirmed real
rotation/restoration, speed/reset, audio delay, EQ/compressor activation,
subtitle delay/reset and future subtitle-language selection.

The packaged app has not received running-app acceptance: the computer-use tool
reported a locked Mac. Resume Continue/Dismiss, Escape, timeout and resize checks
remain pending. A paused-long-seek/caption-size interaction observed in the
development app also remains unresolved. Component checks and successful
packaging do not establish those playback paths. Windows remains unbuilt.

## Icon orientation refresh, October 17

Source `2c3391aedf38d7927999cc65b4d24a078de9cc0c` centralizes the missing
horizontal export reflections, including selected browser icons. The native
development app was visually checked with generated media; see the icon review
in [player status](player-status.md). The full build/package completed through
`resume-build.sh redesign-icon-orientation`. The staged app is
`build-macos-baseline/artifacts/macos-player-preview-2c3391aedf/VLC.app`; its
macOS module has the same Mach-O UUID as the visually checked development app.

The refreshed `build-macos-baseline/artifacts/VLC-video-review-preview-arm64.dmg`
passes `hdiutil verify`, CRC32 `1059AE79`. Both app copies pass deep strict
ad-hoc signature verification and contain 390 plugins. Executable SHA-256 is
`6fac731b5d1df809865156321593832809f96bcec429472e4cc6ba7308b3f193`;
macOS module SHA-256 is
`948e20028d60dbb66d894edf0c96af1d371e1e460985ed77f060fb055a470b90`.
The staged folder includes the source revision and verification metadata.
The broader resume/caption-size acceptance limits above remain open. This
refresh is still arm64 only, locally signed and not notarized.
