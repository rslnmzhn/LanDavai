# Anti-Regression Checklist

Practical pre-merge checklist for the current Landa post-refactor baseline.

## 1. Ownership Drift

- No canonical truth moved back into `DiscoveryController`, `DiscoveryPage`,
  widgets, repositories, or helper facades.
- Owner boundaries remain explicit:
  - `LocalPeerIdentityStore`
  - `SharedCacheCatalog`
  - `SharedCacheIndexStore`
  - `SharedCacheMaintenanceBoundary`
  - `RemoteShareBrowser`
  - `RemoteShareMediaProjectionBoundary`
  - `FilesFeatureStateOwner`
  - `PreviewCacheOwner`
  - `TransferSessionCoordinator`
  - `VideoLinkSessionBoundary`
  - `DownloadHistoryBoundary`
  - `ClipboardHistoryStore`
  - `RemoteClipboardProjectionStore`
- Thin infra ports stay thin:
  - `SharedCacheRecordStore`
  - `SharedCacheThumbnailStore`

## 2. Dual-Truth / Dual-Route

- No duplicated canonical sources for the same seam.
- No compatibility mirrors promoted back into real production paths.
- No parallel read/write routes for the same feature flow.

## 3. Forbidden Patterns (Guarded)

- No `SharedCacheCatalogBridge`.
- No discovery/files callback backchannel.
- No `part / part of` under `lib/`.
- No controller ownership of:
  - local peer identity
  - video-link sessions
  - thumbnail IO
- No re-broadening of:
  - `SharedFolderCacheRepository`
  - `LanPacketCodec`
  - `lan_packet_codec_common.dart`
- No local peer identity logic inside `FriendRepository`.

## 4. Protocol + Infra Integrity

- `LanPacketCodec` remains a thin facade.
- `lan_packet_codec_common.dart` contains common-only helpers/constants.
- Family codecs remain in dedicated files under
  `lib/features/discovery/data/`.
- `SharedFolderCacheRepository` remains a thin record store only.

## 5. UI Regression Proof

- Weak entry flows remain covered by behavior-level widget tests:
  - discovery → files launch
  - files/viewer entry
  - remote-share preview/viewer launch
  - history populated/open-folder action
- Any touched user-visible flow keeps behavior-level proof (not just
  constructor/import survivability).

## 6. Verification Targets

Run targeted tests when touching these zones:

- Architecture guardrails:
  - `test/architecture_guard_test.dart`
- Discovery entry/menus:
  - `test/smoke_test.dart`
- Shared-cache recache/remove UI entry:
  - `test/blocked_entry_flow_regression_test.dart`
- Files entry/viewer flows:
  - `test/files_entry_flow_regression_test.dart`
- Remote-share preview/viewer flows:
  - `test/remote_share_viewer_flow_regression_test.dart`
- History populated/open-folder flows:
  - `test/history_entry_flow_regression_test.dart`

Always run:

- `flutter analyze`
- `flutter test`

## 7. Pre-Merge Review Questions

- Did any change add a second owner or duplicate truth?
- Did any flow regain a legacy route or compatibility bypass?
- Did any controller/page/widget absorb owner responsibilities?
- Did any facade grow into a god-module?
- Are all touched UI flows still proven by behavior-level tests?
