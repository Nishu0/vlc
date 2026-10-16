# Text alignment contract

The user requested consistent alignment for every redesigned button, input, label, and other text surface. Apply these rules to each new screen as it is implemented; this is not a claim that unimplemented screens have been audited.

## Shared native implementation

- `VLCRedesignTextLayout` centers the visible glyph bounds, including wrapped lines, inside a supplied rectangle. It respects horizontal alignment and paragraph styling, and handles flipped/native drawing coordinates.
- `VLCRedesignAlignedLabel` retains native label/accessibility behavior and uses that renderer for text contained in controls and rows. Its alignment insets are zero because it draws in its actual bounds instead of the native cell's padded rectangle. Shortcut keycaps, their separators, shortcut row captions, unassigned hints, and preview timestamps share it.
- Onboarding action buttons and theme-choice captions use the same rendering function. Keep button text centered in the actual button bounds, rather than applying per-title pixel offsets.
- Shortcut keycaps reserve the measured width of the full key combination and remain single-line. Let adjacent descriptive captions wrap before compressing modifier/arrow symbols onto another line.
- Editable folder text keeps native selection, caret, and horizontal scrolling. Its cell shares a drawing/editing rectangle and accounts for native field-editor padding. Do not replace editable text with a static drawing.
- Flowing headings, body paragraphs, field captions, and validation messages retain their layout anchors and paragraph alignment from the design. Centering a control label does not imply centering every paragraph horizontally.

## Verification for each screen

Check the actual rendered app, not only constraint values. Compare visible text with its container or neighboring row. Verify horizontal padding, vertical centering where specified, baseline consistency, and the edges of wrapped text blocks.

Include normal/selected/editing input states, empty placeholders, long paths, uppercase/lowercase/descenders, and shortcut symbols where relevant. Check the minimum supported window size, the reference size, a large window, and light/dark appearances. Confirm that wrapping, clipping, selection, keyboard interaction, and native accessibility remain usable.

When an implementation adds a new kind of control, verify its native text/editor geometry before reusing it throughout a screen. Reuse saved Figma references for comparisons; a local render check does not require another Figma read.

## Current coverage

The first audit covers the three implemented onboarding steps. A native render probe exercises the actual shared renderer and native label controls with 42 cases: action titles, shortcut glyphs, theme names, wrapped captions, small timestamps, left/right alignment, empty text, both coordinate orientations, and labels positioned by Auto Layout. All passed with at most half a rendered pixel of measured alignment deviation on this host. The probe and logs remain ignored build output under `build-macos-baseline/`.

The running app was also checked with empty and long folder input, validation errors, light and dark themes, and compact and large windows. At the shortcut screen's 960×680 minimum, descriptive captions wrap while modifier/arrow combinations remain on one line. The appearance page was checked at its fitting compact width and at 1512×949. Its captions, timestamps, and action titles remain centered within their containers.

The original VLC player, library, settings, and peripheral dialogs have not been converted to this text system. Verify those surfaces when their redesign is implemented.
