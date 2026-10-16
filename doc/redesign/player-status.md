# Native Mac player redesign

The main player is being implemented around VLC's existing native video output and player/queue controllers. The chrome and direct track/device selectors are implemented. The four-tab settings inspector, compact browser, hover thumbnails, and queue presentation remain separate parts of the main-player request.

## Shell and transport

The standard player uses the high-fidelity contexts and renders for dark `247:445` and light `2425:13624`, plus pause component `848:1713`. Thirty-seven original SVG resources are bundled unchanged; [the asset manifest](player-assets.json) maps each to its source and role. Reference sample video and filenames are not shipped as application content.

The top bar is 40 points high, and the normal bottom bar is 54 points high. Previous/play/next remain on the left. The seek bar takes available width between live elapsed/duration displays and the volume/tool groups. Video retains VLC's actual output, aspect ratio, input handling, and drag/drop. The windowed video has the reference inset and rounded corners; fullscreen retains the full video surface.

At widths below 920 points, seeking occupies a separate row. Below 560 points, a third row keeps volume and track controls usable when another sidebar occupies much of the window. Long title/folder labels truncate within their slots. Every new control uses the text alignment contract.

Actions call the real VLC controllers: play/pause, previous/next queue item, fast drag seeking and precise release/keyboard seeking, volume (0–200%), mute, duration/remaining toggle, jump-to-time dialog, audio/subtitle selectors, and queue visibility. Adjusting volume while muted unmutes at the requested level. The cone uses the exported SVG background/gradient, clipped by the current volume. Double-clicking it restores 100%.

The top controls provide the existing File actions, library access, Finder reveal for local media, minimize, zoom, fullscreen, and close. Playback tools retain access to video/audio/subtitle/playback commands, PiP, bookmarks, synchronization, media information, and preferences. These menus currently expose existing native dialogs; their replacement by the designed inspector is still pending.

The legacy classic-layout preference retains the original interface. The standard player keeps the original controller/XIB integration behind the new chrome so VLC's output ownership, PiP transfer, audio fallback, and existing advanced actions continue to function.

## Direct track and device selectors

The native floating panel follows contexts `496:2495` (audio), `498:2674` (video), and `491:2216` (subtitles). Fourteen additional original SVGs supply the 20-point tab icons, 24-point selection/refresh/add/edit icons, selected underlines, and divider. Its normal size is 400 × 524 points, inset 20 points above the transport. Short windows compress the section headings and retain independently scrolling lists; the outer body scrolls if even the minimum arrangement cannot fit.

Video, Audio, and Subtitles tabs enumerate the active input's real tracks. None unselects the category, and each track selects exclusively through `VLCPlayerController`. Radio accessibility values expose selection. The controller's track metadata now holds/releases its stream ID so retained rows cannot outlive that ID when inputs change. Track list/selection/media/state notifications refresh the rows and preserve keyboard focus.

Audio outputs use the exact IDs returned by `aout_DevicesList`, including nonnumeric IDs; refresh re-enumerates available outputs. Embedded and external subtitles are separated by matching VLC's associated-source identifiers to its input-associated URL list. The plus button opens VLC's existing subtitle picker. The pencil opens the selected local text subtitle in TextEdit; it is disabled for an unsupported or unselected external file. This does not implement the video's later bulk subtitle assignment or timeline editor. Show Preferences opens the existing preferences window. Escape and clicks outside the panel dismiss it; fullscreen keeps controls available while the panel is open.

## Verification record

The native arm64 player was built and run with generated local media. Play/Pause changed state; seeking moved the real input to 1:30; volume changed to 35%; mute/unmute and adjusting volume while muted worked. Next/Previous switched between two queue items. The elapsed-time button opened the native time dialog and submitted a 1:15 jump. Duration toggled to remaining time. Audio and subtitle menus populated from the active input, including actual audio output devices, and the playback tools menu retained its parameter controls and advanced commands.

Light/dark and full-width layouts were visually reviewed. The narrow layout separates seeking from transport/tools. The very narrow queue-open layout exposed a slider repaint problem; its drawing is now clipped to its actual bounds and no longer uses the legacy knob renderer. A subsequent narrow native render retained the duration text without the stale track image. The final repaint correction bypasses the system slider drawing pass and draws the custom cell directly; subsequent native renders after selector and playback actions kept the duration visible. The shared text renderer's 42 native render cases passed after adding single-line truncation support.

A user-provided MKV with 19 embedded subtitle tracks was tested locally. Switching English variants changed the core selected stream; Hindi rendered visibly after seeking into the episode. None unselected all subtitles. The audio device changed to built-in speakers and back to the system output, with the radio state following the core. Importing a generated SRT through the plus control added a separate external row, and selecting it rendered its text over the movie. The user's media stays outside the repository. The pencil editor handoff and full-size panel still need an explicit acceptance check.

Fullscreen entry and Escape exit were observed. Edge-hover interaction and PiP return remain acceptance checks: PiP opened the macOS panel, but that panel's content and controls could not be confirmed through the current inspection tool. Do not count opening a panel as successful video/return verification.

An older populated test-library directory triggered an AppKit constraint-update loop during startup. The unchanged baseline reproduced the same exception; a fresh isolated test-library directory started successfully. Preserve the failing test data for a separate library-layout investigation. No broad AppKit workaround was retained in this change.

Build/runtime logs and generated media remain ignored under `build-macos-baseline/`. Development UI iterations use a separate ad-hoc-signed `VLC-dev.app`; final preview distribution requires the full package build and signature checks. Test playback is authorized by the user; owned preview processes are stopped before replacing their binaries. Library test data is isolated through `VLC_USERDATA_PATH`.

## Remaining main-player parts

- Designed compact file/library browser and queue presentation with real rows, navigation, and drag/drop.
- Four-tab settings inspector and its parameter bindings, including video and playback settings.
- Hover thumbnails generated for the hovered time, independent of the playing input.
- Remaining fullscreen edge-hover, keyboard focus, PiP return, and small-window checks.
- Full player acceptance against the video interaction map, including unsupported/live input states.

This is not the complete VLC redesign or a Windows build.
