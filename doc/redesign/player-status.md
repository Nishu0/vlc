# Native Mac player redesign

The main player is being implemented around VLC's existing native video output and player/queue controllers. The chrome, direct track/device selectors, Queue / Bookmarks / Chapters panel, compact browser, and the first four-tab inspector slice are implemented. A video-led resume notification is also implemented with native component checks; its running-app acceptance is pending an unlocked desktop. Hover thumbnails and the deeper inspector workflows remain parts of the main-player request.

## Shell and transport

The standard player uses the high-fidelity contexts and renders for dark `247:445` and light `2425:13624`, plus pause component `848:1713`. Thirty-seven original SVG resources are bundled unchanged; [the asset manifest](player-assets.json) maps each to its source and role. Reference sample video and filenames are not shipped as application content.

The top bar is 40 points high, and the normal bottom bar is 54 points high. Previous/play/next remain on the left. The seek bar takes available width between live elapsed/duration displays and the volume/tool groups. Video retains VLC's actual output, aspect ratio, input handling, and drag/drop. The windowed video has the reference inset and rounded corners; fullscreen retains the full video surface.

At widths below 920 points, seeking occupies a separate row. Below 560 points, a third row keeps volume and track controls usable when another sidebar occupies much of the window. Long title/folder labels truncate within their slots. Every new control uses the text alignment contract.

Actions call the real VLC controllers: play/pause, previous/next queue item, fast drag seeking and precise release/keyboard seeking, volume (0–200%), mute, duration/remaining toggle, jump-to-time dialog, audio/subtitle selectors, and queue visibility. Adjusting volume while muted unmutes at the requested level. The cone uses the exported SVG background/gradient, clipped by the current volume. Double-clicking it restores 100%.

The top controls provide the existing File actions, compact browser access, containing-folder navigation in the full library, minimize, zoom, fullscreen, and close. Playback tools retain access to video/audio/subtitle/playback commands, PiP, bookmarks, synchronization, media information, and preferences. The gear now opens the in-player inspector. Expanded filter editing, information and global preferences still use their existing native dialogs where their redesigned replacements are unfinished.

The legacy classic-layout preference retains the original interface. The standard player keeps the original controller/XIB integration behind the new chrome so VLC's output ownership, PiP transfer, audio fallback, and existing advanced actions continue to function.

## Direct track and device selectors

The native floating panel follows contexts `496:2495` (audio), `498:2674` (video), and `491:2216` (subtitles). Fourteen additional original SVGs supply the 20-point tab icons, 24-point selection/refresh/add/edit icons, selected underlines, and divider. Its normal size is 400 × 524 points, inset 20 points above the transport. Short windows compress the section headings and retain independently scrolling lists; the outer body scrolls if even the minimum arrangement cannot fit.

Video, Audio, and Subtitles tabs enumerate the active input's real tracks. None unselects the category, and each track selects exclusively through `VLCPlayerController`. Radio accessibility values expose selection. The controller's track metadata now holds/releases its stream ID so retained rows cannot outlive that ID when inputs change. Track list/selection/media/state notifications refresh the rows and preserve keyboard focus.

Audio outputs use the exact IDs returned by `aout_DevicesList`, including nonnumeric IDs; refresh re-enumerates available outputs. Embedded and external subtitles are separated by matching VLC's associated-source identifiers to its input-associated URL list. The plus button opens VLC's existing subtitle picker. The pencil opens the selected local text subtitle in TextEdit; it is disabled for an unsupported or unselected external file. This does not implement the video's later bulk subtitle assignment or timeline editor. Show Preferences opens the inspector on the matching Video, Audio or Subtitles tab. Escape and clicks outside the panel dismiss it; fullscreen keeps controls available while the panel is open.

## Queue, bookmarks, and chapters

The floating 400-point panel follows contexts `491:1781`, `6320:13763`, and `6321:14024`. Its maximum height is 946 points, reduced to fit the player above the transport. It uses the original tab, sort, repeat, shuffle, add/remove, and grip SVGs. Original active audio/subtitle/settings/queue icons replace their inactive counterparts when selected. That panel milestone brought the manifest to 67 original player resources. Panel buttons share the same aligned text renderer and native keyboard/accessibility behavior.

Queue rows use `VLCPlayQueueModel` items, titles, and durations. The current input is highlighted, and sort/order changes keep its identity. Add appends real files or directories without interrupting playback. Sorting, repeat off/current/all, shuffle, row activation, removal, and previous/next availability call the existing queue controller. Native drag/drop reuses `VLCPlayQueueDataSource`, including library/file payload handling; local drags advertise move and the panel does not drag the window. Move-earlier/later context actions provide an alternative to dragging. Return activates the selected row; Delete removes it. A new items-updated notification keeps the floating view synchronized with reorder, reset, and metadata updates. Moves with a missing item ID return an error rather than indexing outside the playlist.

Bookmarks use VLC's shared media-library storage. Adding an unindexed input first registers it as external media. Creation, rename, seek, removal, and reopening use the stored media ID and millisecond time; callbacks update open panels through a weak observer whose registration is removed on teardown. The shared backend now correctly returns success after `addBookmark` succeeds. Chapter rows come from the selected real player title and activate `selectedChapterIndex`; media without chapters displays an empty state.

Native checks created a bookmark at 2:00, renamed it, sought back to it after moving playback, reopened it after restarting VLC, and removed it. A generated three-chapter MKV jumped to 2:00 via Return. The queue plus button appended a 12-second fixture without changing the current input; its total changed from 6:00 to 6:12. Duration sorting placed that fixture first, row activation played it, and removing it restored the 6:00 total and transport availability. A pointer drag moved the second item below the last row, with the live queue order changing. Repeat and shuffle changed the real controller state and were restored. Native plain table styling corrected clipped duration text. Queue rows, bookmark names/times, and chapter numbers/times were visually reviewed. The full-size queue was also visually reviewed. External file/library drops still need a completed pointer-driven acceptance check; the compact-browser section records the current automation limitation. A full-width review exposed selected icon buttons disappearing because the radio-button drawing branch consumed their on state; that branch now requires a selection image. A native pixel-render probe failed before the fix (134 icon pixels off, zero on) and passed afterward, while radio selection still rendered correctly.

## Compact browser

The left browser follows `848:1995` (file list), `848:1997` (Videos), `858:5001` (Music), `858:5294` (Network), and `858:3290` (view options). The rail is 50 points wide; the browser reaches the reference 427-point width, shrinking on narrower windows to preserve usable video space. Windowed video resizes beside it, while fullscreen keeps the video surface full-size with the browser overlaid. The queue remains open while browsing so files can be dragged across. The top folder icon and aligned folder-name button open that folder in VLC's full library. Expand and Home return to the existing full library, preserving the native playback/output ownership path.

Folder contents load off the main thread and discard stale results. History has Back/Forward and a bounded parent menu ending at `/`; an active directory watcher updates changed folders. Search filters names live. Name, modified-date, and watched sorting use available file/library metadata. List rows, generated media thumbnails, a responsive grid, and the two-choice view popup share the native text alignment renderer. Quick Look supplies real local thumbnails with a workspace-icon fallback and a bounded cache. No reference sample media is bundled.

Videos uses monitored folders. Music uses actual Songs, Albums, Artists, and Genres; playlists and recents come from the library model. Play and Add to queue call VLC's existing controllers. Add Folder, Create/Rename Playlist, importing media into a playlist, file/library drops, and the native network-source/stream-opening paths use existing storage and dialogs. Folder and music-group navigation keep selection consistent as asynchronous results arrive. Network-source contents and full-library views retain their existing native UI pending those later redesign stages.

There are now 96 original SVG player resources. A targeted Figma check found that the inactive Music instance's screenshot and exported code/SVG disagree (the export depicts a gear); the browser uses the original cached Music asset from the full library instead. It is not a claim that every icon variant or the full-library screens are finished.

The video icon review found missing horizontal reflections in the title-bar
folder/sidebar, speaker, browser expand/music and selected video/music assets.
The shared image loader now restores the enclosing export transforms, including
the video-track, refresh and queue-arrow assets. It retains the original SVGs
and intrinsic sizes. Browser controls no longer apply separate reflections,
which previously missed selected states. The rebuilt development app was
visually checked with generated media: folders have their tabs on the left,
the sidebar marker stays on the left, speaker waves face right, Expand points
up/right, and video/music icons retain their orientation when selected.
This check does not establish full-library icon parity; those views still use
the existing native interface.

Checks so far: live search narrowed six filesystem entries to the requested file; grid navigation opened two nested folders; Back/Forward restored each location; a generated second episode appeared automatically through the directory watcher. Grid/list switching and the parent menu now pass after fixing collection registration order, retaining the weak caption outlet through subview ownership, and bounding parent traversal. A probe loads the actual built browser grid item and renders three native collection items. The shared renderer still passes 42 native cases; file/URL/plain-text/empty pasteboard parsing passes independently. The file context action appended a generated 12-second clip, changing the queue from 6:00 to 6:12 while the current 3-minute input remained unchanged. Music opened its real (empty test-library) Songs list, and a playlist created in the native browser dialog appeared in persistent storage. Pointer drags begin native tracking in both browser and queue, but the current automation leaves tracking unfinished until Escape; cross-panel insertion remains unverified. A separate QA playlist was created and populated through the native file picker; its imported clip appeared without changing playback or the queue. Browser layouts were visually reviewed after resizing to 802 and 604 points wide. Full-library expansion opened the same fixture folder, retaining playback at 1:30. Network-source content navigation still needs its own acceptance check. The paired browser/queue remains open until its tool or Escape closes the queue; other floating selectors retain outside-click dismissal.

## Video-led inspector and resume notification

The [timestamped video review](video-review.md) records the visual and interaction
references. The gear now opens a persistent right-hand inspector with Playback,
Video, Audio and Subtitles tabs, matching the workflow demonstrated at
07:08–09:18. It remains open while the video plays and during numeric edits;
Escape or the gear closes it. Its body scrolls in short windows, and the shared
native renderer aligns the tab labels, fields, switches and buttons.

Implemented bindings:

- Playback speed from 0.25× to 2×, reset, capability-aware reverse, a cancellable
  sleep timer, and the existing metadata route. The timer belongs to playback,
  survives closing the inspector, and stops playback when its wall-clock
  deadline expires; wake checks handle an overdue deadline.
- Aspect ratio, crop, zoom, quarter-turn rotation and flips, plus live brightness,
  contrast, saturation, hue and gamma. Reset restores picture values. Expanded
  video filters still open the existing native effects editor.
- Audio delay, preferred language for future media, the 18 built-in EQ presets,
  compressor, spatializer and stereo widener. Expanded parameters still use
  the existing audio effects editor.
- Subtitle delay, external subtitle FPS including Auto, duration factor,
  relative text size, vertical position, outline thickness, background opacity,
  color choices and a preferred language for future media. Current track
  selection remains in the direct track selector.

Numeric fields and sliders share bounded values. Invalid/non-finite text does
not apply. Reset and tab actions finish editing first so an old field editor
cannot overwrite a reset. Thirteen native regression checks cover these fields
and timer expiry/cancellation/replacement/ownership.

Running-app checks confirmed 1.5× speed and reset, audio delay and actual EQ /
compressor module activation, subtitle delay and reset, all 19 MKV subtitle
rows, and the direct-selector footer opening the matching inspector tab.
Choosing Hindi as the future subtitle preference selected the actual Hindi
stream after switching away and reopening the MKV. Automatic language selection
was restored afterward. The size control reported the requested 150%; a paused
long seek then exhausted the input while requesting further decoded frames, so
visible-caption size acceptance remains unresolved rather than counted passed.

Rotation testing exposed two backend gaps: display negotiation attempted a
converter for orientation changes even when the display could accept them, and
the metadata-only transform lost its hardware context. Those paths now retain
the context, negotiate with the display, and restore the original format when
removing the filter. The Apple display uses its negotiated orientation. Four
video-output scenarios pass, including the original chroma case, accepting and
rejecting displays, restoration, and the real transform's context retention.
The new orientation and context regressions failed before their fixes. The
supplied hardware-decoded MKV visibly rotated to portrait and returned to
landscape with the filters intact.

The resume notification follows 14:08: a small centered message immediately
above the transport, with Continue Watching and Dismiss, rather than a separate
window. The classic player retains its old dialog. Resume times now convert
VLC ticks to seconds correctly, duration eligibility uses matching units, and
command-line resume policy is honored. Completion or cancellation clears the
old timer/callback before another media item can reuse it. Eight component
checks cover time formatting, three widths, actions and one-shot completion.
Running-app resume, Escape, timeout and resize acceptance are pending because
the computer-use tool reported a locked Mac during this part of testing.

The full inspector is not complete. Cue timeline, waveform, scoped presets,
font-family/exact-pixel controls, richer color editing, complete inline filter
parameters and hardware/output choices remain explicitly pending. No working
feature is inferred merely from a placeholder in a Figma or video frame.

## Verification record

The native arm64 player was built and run with generated local media. Play/Pause changed state; seeking moved the real input to 1:30; volume changed to 35%; mute/unmute and adjusting volume while muted worked. Next/Previous switched between two queue items. The elapsed-time button opened the native time dialog and submitted a 1:15 jump. Duration toggled to remaining time. Audio and subtitle menus populated from the active input, including actual audio output devices, and the playback tools menu retained its parameter controls and advanced commands.

Light/dark and full-width layouts were visually reviewed. The narrow layout separates seeking from transport/tools. The very narrow queue-open layout exposed a slider repaint problem; its drawing is now clipped to its actual bounds and no longer uses the legacy knob renderer. A subsequent narrow native render retained the duration text without the stale track image. The custom drawing bypasses the system slider drawing pass. Live resizing later reproduced sibling overpainting despite the draw-rectangle clip; the slider now owns a layer with masksToBounds, so native tracking redraws are clipped as well. Native views at 802 and 604 points retained the duration, and a pointer click sought to 1:30 after resizing. A probe also loaded the actual built slider class, enlarged and shrank it, and verified its separate clipped layer and rendered neighboring duration. The shared text renderer's 42 native render cases passed after adding single-line truncation support.

A user-provided MKV with 19 embedded subtitle tracks was tested locally. Switching English variants changed the core selected stream; Hindi rendered visibly after seeking into the episode. None unselected all subtitles. The audio device changed to built-in speakers and back to the system output, with the radio state following the core. Importing a generated SRT through the plus control added a separate external row, and selecting it rendered its text over the movie. The user's media stays outside the repository. The full-size panel was visually reviewed, and the pencil opened the generated SRT in TextEdit without modifying it.

Fullscreen entry and Escape exit were observed. A later fullscreen capture attempt failed in ScreenCaptureKit with error -3811; the inspection tool remained bound to the hidden owner window. Edge-hover interaction and PiP return remain acceptance checks: PiP opened the macOS panel, but that panel's content and controls could not be confirmed through the current inspection tool. Do not count opening a panel as successful video/return verification.

An older populated test-library directory triggered an AppKit constraint-update loop during startup. The unchanged baseline reproduced the same exception; a fresh isolated test-library directory started successfully. Preserve the failing test data for a separate library-layout investigation. No broad AppKit workaround was retained in this change.

Build/runtime logs and generated media remain ignored under `build-macos-baseline/`. Development UI iterations use a separate ad-hoc-signed `VLC-dev.app`; final preview distribution requires the full package build and signature checks. Test playback is authorized by the user; owned preview processes are stopped before replacing their binaries. Library test data is isolated through `VLC_USERDATA_PATH`.

## Code-quality review

The redesign now follows nearby Cocoa code with expanded setup methods, typed
navigation state and section/sort enums, explicit optional callbacks, and shared
image loading. Formatting was separated into its own commit; its non-comment
tokens and concatenated string values were checked against the preceding source.

Playlist/group database queries and directory-watch opens run on the browser's
serial worker queue. The main thread applies results only for the current visible
location. Hiding or detaching the browser invalidates pending work, cancels its
watch, and closes its popup. Reused thumbnail views check their represented entry
before accepting asynchronous artwork. The bounded shared SVG cache uses NSCache.

The native arm64 development build passes. Compiler type/nullability warnings in
the changed panels were resolved; retained legacy pasteboard support still uses
AppKit's deprecated filename type. Standalone parser checks cover 12 valid,
empty, mixed, relative-path, and malformed payload cases; their source and run
instructions are in `test/modules/gui/macosx/`. The 42 text renders, three-item
grid, selected icons/radio buttons, and clipped slider probes pass. Running-app
checks confirmed playlist media loading, Music/Songs navigation, Back history,
and browser hide/reopen. File-descriptor inspection confirmed that hiding the
browser releases its folder watch. A generated clip appeared automatically
after reopening the browser, confirming that watching resumes. This is local verification, not upstream
maintainer review.

## Remaining main-player parts

- Remaining external file/library drop acceptance checks.
- Remaining inspector workflows: cue timeline/waveform, scoped presets, exact font controls, richer color editing, full inline filter parameters and output capabilities.
- Running-app acceptance of the new resume prompt, plus the unresolved paused-long-seek/caption-size check.
- Hover thumbnails generated for the hovered time, independent of the playing input.
- Remaining fullscreen edge-hover, keyboard focus, PiP return, and small-window checks.
- Full player acceptance against the video interaction map, including unsupported/live input states.

The full native package at `a835ba0a9e` was staged outside the working build copy and launched with the supplied local MKV. Video and English subtitles rendered, and all 19 embedded subtitle rows populated. The app and disk image passed signature/checksum verification; paths and hashes are in [build status](build-status.md).

This is not the complete VLC redesign or a Windows build.

## Player acceptance follow-up, October 18

A separate QA bundle identity and media-library directory isolate playback
history, preferences and playlists from the normal app. Native testing confirmed
the resume notification's correct seconds, Continue action, Dismiss, Escape and
ten-second timeout. Continue sought to the saved position; the other choices
kept playback near the beginning. Placement was visually checked above the
transport in the narrower layout. Resize and media-change cancellation still
need their own acceptance checks.

Paused seeking reproduced an underlying decoder problem: subtitle decoders
requested more input through the next-frame path without consuming its video
countdown, so a seek could demux to EOF while the interface displayed the target
time. Only video decoders now request that extra buffering. A deterministic
regression failed before the correction, consuming cues to the end of a
180-second source after seeking to 60 seconds. It passes afterward with the
last buffered cue at 60.32 seconds; all 14 input-decoder scenarios pass.

The rebuilt core retains the supplied MKV through repeated paused long seeks
and shows the corresponding scenes. Further testing identified a separate
VideoToolbox allocation-pacing stall when resuming: the video decoder can wait
for pictures held by the paused output before it processes the unpause command.
That issue is still under investigation. Subtitle size was seen at 150%, but
live redraw of an already rendered paused cue also needs further work. This
follow-up does not declare the player acceptance gate complete.
