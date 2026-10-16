# Existing native surface coverage

All 49 macOS XIB files at the pinned baseline are accounted for below. Feature IDs refer to [the feature map](feature-map.md). A mapped source file is not a completed redesigned screen. Runtime-created views and the new Figma-only surfaces are additionally covered in the feature map.

Preserve every underlying action while replacing the visual surface. Where the reference does not include a dedicated advanced dialog, apply the established design components and record the added screen explicitly. Keep the existing classic/player paths available during implementation until their replacements pass playback and interaction checks.

| Existing UI resource | Feature groups | Disposition |
| --- | --- | --- |
| [About.xib](../../modules/gui/macosx/UI/About.xib) | T11 | Retain function; extend visual system to this peripheral surface |
| [AddonManager.xib](../../modules/gui/macosx/UI/AddonManager.xib) | T08 | Recompose/restyle; preserve controller actions and data bindings |
| [AudioEffects.xib](../../modules/gui/macosx/UI/AudioEffects.xib) | I01, I02 | Recompose/restyle; preserve controller actions and data bindings |
| [Bookmarks.xib](../../modules/gui/macosx/UI/Bookmarks.xib) | I10 | Recompose/restyle; preserve controller actions and data bindings |
| [ConvertAndSave.xib](../../modules/gui/macosx/UI/ConvertAndSave.xib) | T07 | Recompose/restyle; preserve controller actions and data bindings |
| [CoreDialogs.xib](../../modules/gui/macosx/UI/CoreDialogs.xib) | T11 | Retain function; extend visual system to this peripheral surface |
| [ErrorPanel.xib](../../modules/gui/macosx/UI/ErrorPanel.xib) | T11 | Retain function; extend visual system to this peripheral surface |
| [Help.xib](../../modules/gui/macosx/UI/Help.xib) | T11 | Retain function; extend visual system to this peripheral surface |
| [LogMessageWindow.xib](../../modules/gui/macosx/UI/LogMessageWindow.xib) | T11 | Retain function; extend visual system to this peripheral surface |
| [MainMenu.xib](../../modules/gui/macosx/UI/MainMenu.xib) | T01, T02, T06, T07, T09, T11 | Recompose/restyle; preserve controller actions and data bindings |
| [Open.xib](../../modules/gui/macosx/UI/Open.xib) | T06 | Recompose/restyle; preserve controller actions and data bindings |
| [PlaylistAccessoryView.xib](../../modules/gui/macosx/UI/PlaylistAccessoryView.xib) | L01, L08 | Recompose/restyle; preserve controller actions and data bindings |
| [PopupPanel.xib](../../modules/gui/macosx/UI/PopupPanel.xib) | I01, T11 | Recompose/restyle; preserve controller actions and data bindings |
| [Preferences.xib](../../modules/gui/macosx/UI/Preferences.xib) | T01, T03 | Recompose/restyle; preserve controller actions and data bindings |
| [ResumeDialog.xib](../../modules/gui/macosx/UI/ResumeDialog.xib) | L11 | Recompose/restyle; preserve controller actions and data bindings |
| [SimplePreferences.xib](../../modules/gui/macosx/UI/SimplePreferences.xib) | T01, T03 | Recompose/restyle; preserve controller actions and data bindings |
| [StreamOutput.xib](../../modules/gui/macosx/UI/StreamOutput.xib) | T07 | Recompose/restyle; preserve controller actions and data bindings |
| [SyncTracks.xib](../../modules/gui/macosx/UI/SyncTracks.xib) | S04, S07 | Recompose/restyle; preserve controller actions and data bindings |
| [TextfieldPanel.xib](../../modules/gui/macosx/UI/TextfieldPanel.xib) | T11 | Retain function; extend visual system to this peripheral surface |
| [TimeSelectionPanel.xib](../../modules/gui/macosx/UI/TimeSelectionPanel.xib) | P02 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCClassicMainVideoView.xib](../../modules/gui/macosx/UI/VLCClassicMainVideoView.xib) | P01, P02, P03, P05, P10 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCCustomCropARPanel.xib](../../modules/gui/macosx/UI/VLCCustomCropARPanel.xib) | I03 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCDetachedAudioWindow.xib](../../modules/gui/macosx/UI/VLCDetachedAudioWindow.xib) | P09 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCFullScreenPanel.xib](../../modules/gui/macosx/UI/VLCFullScreenPanel.xib) | P05 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCInformationWindow.xib](../../modules/gui/macosx/UI/VLCInformationWindow.xib) | I09 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryAlbumTableCellView.xib](../../modules/gui/macosx/UI/VLCLibraryAlbumTableCellView.xib) | L06 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryCarouselCollectionViewItem.xib](../../modules/gui/macosx/UI/VLCLibraryCarouselCollectionViewItem.xib) | L10 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryCollectionViewAudioGroupSupplementaryDetailView.xib](../../modules/gui/macosx/UI/VLCLibraryCollectionViewAudioGroupSupplementaryDetailView.xib) | L06 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryCollectionViewMediaItemListSupplementaryDetailView.xib](../../modules/gui/macosx/UI/VLCLibraryCollectionViewMediaItemListSupplementaryDetailView.xib) | L03 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryCollectionViewMediaItemSupplementaryDetailView.xib](../../modules/gui/macosx/UI/VLCLibraryCollectionViewMediaItemSupplementaryDetailView.xib) | L03 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryHeroView.xib](../../modules/gui/macosx/UI/VLCLibraryHeroView.xib) | L10 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryHomeViewActionsView.xib](../../modules/gui/macosx/UI/VLCLibraryHomeViewActionsView.xib) | L10 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibrarySongTableCellView.xib](../../modules/gui/macosx/UI/VLCLibrarySongTableCellView.xib) | L06 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryTableCellView.xib](../../modules/gui/macosx/UI/VLCLibraryTableCellView.xib) | L03 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryVideoTableCellView.xib](../../modules/gui/macosx/UI/VLCLibraryVideoTableCellView.xib) | L03 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryWindow.xib](../../modules/gui/macosx/UI/VLCLibraryWindow.xib) | L02, P10 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryWindowChaptersView.xib](../../modules/gui/macosx/UI/VLCLibraryWindowChaptersView.xib) | I10 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryWindowNavigationSidebarView.xib](../../modules/gui/macosx/UI/VLCLibraryWindowNavigationSidebarView.xib) | L05 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryWindowPlayQueueView.xib](../../modules/gui/macosx/UI/VLCLibraryWindowPlayQueueView.xib) | L01 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryWindowSidebarRootView.xib](../../modules/gui/macosx/UI/VLCLibraryWindowSidebarRootView.xib) | L01, I01, I10 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCLibraryWindowTitlesView.xib](../../modules/gui/macosx/UI/VLCLibraryWindowTitlesView.xib) | I10 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCMainVideoView.xib](../../modules/gui/macosx/UI/VLCMainVideoView.xib) | P01, P02, P03, P05, P10 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCMainVideoViewAudioMediaDecorativeView.xib](../../modules/gui/macosx/UI/VLCMainVideoViewAudioMediaDecorativeView.xib) | P09 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCMediaItemCollectionViewItem.xib](../../modules/gui/macosx/UI/VLCMediaItemCollectionViewItem.xib) | L02, L03 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCMediaSourceDeviceCollectionViewItem.xib](../../modules/gui/macosx/UI/VLCMediaSourceDeviceCollectionViewItem.xib) | L02, L07, T06 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCPlayQueueTableCellView.xib](../../modules/gui/macosx/UI/VLCPlayQueueTableCellView.xib) | L01 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCPlaybackEndView.xib](../../modules/gui/macosx/UI/VLCPlaybackEndView.xib) | L10, L11 | Recompose/restyle; preserve controller actions and data bindings |
| [VLCStatusBarIconMainMenu.xib](../../modules/gui/macosx/UI/VLCStatusBarIconMainMenu.xib) | P01, T11 | Retain function; extend visual system to this peripheral surface |
| [VideoEffects.xib](../../modules/gui/macosx/UI/VideoEffects.xib) | I01, I03 | Recompose/restyle; preserve controller actions and data bindings |

Also preserve input-dependent controls reachable through menus: disc title/menu navigation, programs, teletext, A–B loop, frame stepping, snapshots, renderer selection, audio channels/device selection, capture settings and custom aspect/crop controls. Their availability must follow actual input/output capabilities.
