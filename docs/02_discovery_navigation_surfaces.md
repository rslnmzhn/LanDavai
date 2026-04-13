# Discovery And Navigation Surfaces

This file documents the current user-facing discovery shell and the main route/surface entrypoints.

## Main shell

- `lib/features/discovery/presentation/discovery_page.dart`
  Thin discovery shell. It renders the main device list, opens the side menu, and pushes dedicated screens such as the download browser.
- `lib/features/discovery/presentation/discovery_device_list_section.dart`
  Main device surface plus shared transfer progress/preparation card.
- `lib/features/discovery/presentation/discovery_side_menu_surface.dart`
  Side-menu content and menu actions.
- `lib/features/discovery/presentation/discovery_destination_pages.dart`
  Dedicated menu destination screens.

## Current menu model

- The menu opens as a drawer on narrow layouts.
- Menu actions open dedicated screens/routes.
- `DiscoveryPage` remains a thin shell and does not own feature truth.

## Discovery-related entry surfaces

- Files entry: dedicated Files surface from discovery menu.
- History entry: dedicated History surface from discovery menu.
- Settings entry: dedicated Settings surface with tabbed presentation.
- Receive/download entry: dedicated remote download browser route.
- Nearby send/receive entry: nearby-transfer sheet/surfaces separate from shared-access downloads.

## Remote download browser

- `lib/features/discovery/presentation/remote_download_browser_page.dart`
  Network file browser for shared-access downloads.
- Uses `RemoteShareBrowser` for remote catalog/projection truth.
- Uses route-scoped `FilesFeatureStateOwner` instances for search/sort/view/path state.
- Uses `TransferSessionCoordinator` for preview and explicit download requests.

## Settings surface

- `lib/features/settings/presentation/app_settings_sheet.dart`
- `lib/features/settings/presentation/app_settings_tab_sections.dart`

Settings are split into tabs and switch by tap and swipe. The screen is presentation-focused and does not own settings truth.

## Discovery weak-flow coverage

The main shell and destination entry flows are covered by:

- `test/smoke_test.dart`
- `test/files_entry_flow_regression_test.dart`
- `test/history_entry_flow_regression_test.dart`
- `test/blocked_entry_flow_regression_test.dart`
