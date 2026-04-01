# PR Review Checklist

Targeted checklist for Landa’s post‑refactor baseline. Use this to detect
architecture drift, ownership regressions, dual‑truth paths, and weak
verification.

## 1. Ownership and Truth

- Did any change move canonical truth back into `DiscoveryController`,
  `DiscoveryPage`, widgets, repositories, or helper facades?
- Did the PR introduce a second owner for an existing seam?
- Are owner/boundary responsibilities still explicit and single‑source?

## 2. Deleted‑Residue Regressions

- Any reintroduction of:
  - `SharedCacheCatalogBridge`
  - discovery/files callback bundle
  - `part / part of` under `lib/`
- Any controller ownership of:
  - local peer identity
  - video‑link sessions
  - thumbnail IO

## 3. Thin‑Boundary Integrity

- `SharedFolderCacheRepository` still a thin `SharedCacheRecordStore`?
- `LanPacketCodec` still a thin facade (no family logic)?
- `lan_packet_codec_common.dart` still common‑only?
- `SharedCacheRecordStore` and `SharedCacheThumbnailStore` still thin ports?

## 4. Dual‑Route / Dual‑Truth Risk

- Any compatibility shell promoted back into production truth?
- Any new fallback paths that create dual‑read / dual‑write?
- Any duplicated canonical state between owners?

## 5. UI Behavior Proof

- If a user‑visible flow changed, is there behavior‑level proof (widget/smoke)?
- Weak flows that must remain covered:
  - discovery → files launch
  - files/viewer entry
  - remote‑share preview/viewer launch
  - history populated/open‑folder action

## 6. Verification Quality

Required when touching related areas:

- Guardrails: `test/architecture_guard_test.dart`
- Discovery entry/menu: `test/smoke_test.dart`
- Shared‑cache recache/remove UI entry:
  `test/blocked_entry_flow_regression_test.dart`
- Files entry/viewer:
  `test/files_entry_flow_regression_test.dart`
- Remote‑share preview/viewer:
  `test/remote_share_viewer_flow_regression_test.dart`
- History populated/open‑folder:
  `test/history_entry_flow_regression_test.dart`
- Always: `flutter analyze`, `flutter test`

## 7. Review Outcome Prompts

Approve if:

- ownership boundaries remain single‑source
- no forbidden residue or dual‑route appears
- thin facades stayed thin
- behavior‑level proof exists for touched flows
- targeted tests + analyze + full test run are green

Request changes if:

- truth drifted into controllers/pages/widgets/repositories
- guardrails or thin‑facade boundaries broadened
- UI flow changed without behavior‑level proof

Block if:

- dual‑truth or dual‑route exists
- a forbidden residue reappears
- protocol or cache seams re‑centralize ownership
