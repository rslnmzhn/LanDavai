# How to Extend Landa Safely

Practical guidance for adding new functionality without breaking the current
post‑refactor baseline.

## 1. Where New Code Should Live

Use the existing structure:

```text
lib/
  app/                   app‑level composition and routing
  core/                  shared primitives/utilities
  features/<feature>/
    application/         owners, boundaries, read models
    data/                persistence, protocols, IO adapters
    domain/              domain models/types
    presentation/        widgets, screens, UI surfaces
test/
  *_owner_test.dart
  *_boundary_test.dart
  *_store_test.dart
  *_flow_regression_test.dart
  smoke_test.dart
  architecture_guard_test.dart
```

Place new tests near the seam they protect:

- flow/entry coverage → `*_flow_regression_test.dart` or `smoke_test.dart`
- ownership/boundary logic → `*_owner_test.dart` / `*_boundary_test.dart`
- storage logic → `*_store_test.dart`

## 2. Adding a New Feature or Seam

Decide upfront:

- Owner: the single source of truth for a seam.
- Boundary: commands/projections that touch external systems or other features.
- Read model: consumer‑facing projection over owner state.
- Thin infra port: minimal interface to IO/persistence.

Avoid:

- placing truth inside `DiscoveryController`, `DiscoveryPage`, or widgets
- creating new god‑repositories or god‑modules
- reintroducing compatibility mirrors as real production paths

## 3. What Each Role Means (Practical)

- **Owner truth**: mutates canonical state, owns policy.
- **Read model / projection**: read‑only, derived from owners.
- **Boundary**: orchestrates side effects or external IO, not a truth holder.
- **Thin infra port**: minimal IO surface for persistence/artifacts.
- **Compatibility shell**: thin facade only; must not regain behavior ownership.

If you cannot articulate a single owner, stop and re‑split the seam.

## 4. Avoid Known Regressions

Never reintroduce:

- callback backchannels
- `SharedCacheCatalogBridge`‑style workarounds
- `part / part of` under `lib/`
- dual truth or dual route for the same seam
- hidden god‑modules under a new filename

Keep these thin:

- `LanPacketCodec` (facade only)
- `lan_packet_codec_common.dart` (common helpers only)
- `SharedFolderCacheRepository` (record store only)

## 5. Protocol / Storage / Cache Changes

- Protocol family logic stays in dedicated codec files.
- `LanPacketCodec` delegates, does not implement families.
- `lan_packet_codec_common.dart` must not absorb family logic or DTOs.
- `SharedFolderCacheRepository` must remain a thin `SharedCacheRecordStore`.
- Thumbnail artifacts stay in `SharedCacheThumbnailStore` flows.

If a change needs a new owner or port, introduce it explicitly and keep it thin.

## 6. UI Flow Safety

When adding user‑visible flows:

- provide behavior‑level proof (widget/smoke tests)
- do not rely on constructor/import survivability
- keep assertions stable and surface‑level

Weak flows must remain covered:

- discovery → files launch
- files/viewer entry
- remote‑share preview/viewer launch
- history populated/open‑folder action

## 7. Verification Before Merge

Always run:

- `flutter analyze`
- `flutter test`

Targeted tests when touching these zones:

- guardrails → `test/architecture_guard_test.dart`
- discovery entry → `test/smoke_test.dart`
- shared‑cache recache/remove UI entry →
  `test/blocked_entry_flow_regression_test.dart`
- files entry/viewer →
  `test/files_entry_flow_regression_test.dart`
- remote‑share preview/viewer →
  `test/remote_share_viewer_flow_regression_test.dart`
- history populated/open‑folder →
  `test/history_entry_flow_regression_test.dart`

## 8. Quick “Do / Don’t”

Do:

- pick a single owner for new truth
- keep boundaries thin and explicit
- add behavior‑level regression proof for new UI flows

Don’t:

- re‑centralize truth in controllers/pages/widgets
- add compatibility bypasses
- grow thin facades into new god‑modules
