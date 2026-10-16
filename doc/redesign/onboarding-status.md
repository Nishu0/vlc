# Native Mac onboarding and appearance

This is the first implementation slice after the unchanged baseline gate. It is not the complete redesigned VLC application.

## Implemented

- Native, resizable welcome window based on Figma `1899:3055`, appearance `1902:3670` / `1902:4020`, and shortcut introduction `1902:6770`.
- Welcome text, original exported cone, editable optional folder field, native directory picker, existing-directory validation, Back/Next/Finish navigation.
- Finish submits the selected folder through `VLCLibraryController`, checks the return value, persists onboarding completion, and returns to VLC's library window.
- Persistent light/dark/system appearance and nine accent choices. System appearance follows the effective application appearance. Existing native accent consumers use the selected color.
- Bundled Inter Light, Regular, Medium, and SemiBold fonts with the original SIL Open Font License. Twenty-four original SVG exports retain their dimensions and artwork.
- Composed native player illustration in the theme page. This is an appearance preview; its decorative transport/window icons do not control playback.
- Shortcut hints read the active VLC configuration and native menu bindings. The file-browser shortcut shows “Not Set” until that redesigned workflow has a binding.
- Help → Welcome to VLC… reopens onboarding, including after completion.

Source: `modules/gui/macosx/redesign/`, integrated in `VLCMain.m`, `NSColor+VLCAdditions.m`, and `Makefile.am`. Asset provenance is in `modules/gui/macosx/Resources/redesign/README.txt`.

## Observed verification

The native interface was built and launched on this Apple Silicon Mac. Invalid folder input was blocked, an empty folder was accepted, the native Browse sheet selected the generated fixtures directory, and Back preserved the folder. Light/dark/system and accent controls changed the running appearance. The shortcut screen showed configured Mac bindings, including Command–Control–Left/Right for short seeks and Command–Option–P for the queue. Its labels wrapped without overlapping controls at the minimum 960×680 content size.

Finish imported the fixture directory into a separate test media-library database. A read-only database check found one 12-second audio item and one 12-second video item under the selected folder. The test used generated media only. The existing VLC library remains the destination after onboarding; its full Figma redesign is a later slice.

The large-window check exposed a clipped illustration header. The preview now retains its aspect ratio and reduces its width when necessary to remain below the window's top edge. Its width preference uses low priority so Cocoa does not enlarge the window beyond the display to satisfy it. The final native large-window render retained the entire header and transport bar. Light and dark renders, persistence after restart, and Escape dismissal were also checked. Final package and repaired-layout checks are recorded in `build-macos-baseline/redesign-onboarding-verification.json`.

## Local preview artifacts

- `build-macos-baseline/artifacts/macos-onboarding-preview/VLC.app`
- `build-macos-baseline/artifacts/VLC-onboarding-preview-arm64.dmg`

The app includes 390 VLC plugins and passes deep strict ad-hoc signature verification. Launch it and use **Help → Welcome to VLC…** if onboarding has already been completed. The included README describes the preview's limited scope.

The onboarding button labels now center their visible Core Text glyph bounds rather than the font's line box. This corrects the low baseline reported for Back/Next and applies consistently to Finish/Browse. The rebuilt native appearance screen was visually checked, and Back/Next navigation was exercised again.

The media-folder field now fills the input height and uses a native text cell with a shared drawing/editing rectangle. Glyph metrics and field-editor descender padding determine its vertical placement. The displayed `~/Movies` path was visually checked beside Browse in the packaged VLC app. A native component check using the same cell verified selection and typing a longer path. Input remains left-aligned, editable, and horizontally scrollable.

## Scope remaining

The actual playback controls, top bar, compact browser, library home, music, mini-player, inspectors, settings, customization, and advanced workflows still need implementation and acceptance against the full map. Most existing windows still use VLC's original native layout. Applying dark mode and an accent does not make those windows match Figma.

Windows has a separate Qt/QML interface and has not been changed or built. The current Mac builds target arm64 only and use local ad-hoc signatures, not Developer ID notarization.

The Figma connection initially exhausted its Starter-plan read allowance. On 2026-10-16, the user upgraded their main team; `whoami` subsequently confirmed a Professional Dev seat, and the previously blocked request succeeded. Follow the [cache and budget workflow](figma-reference-workflow.md) for continued work. Cached references can be reused for local implementation and visual checks.
