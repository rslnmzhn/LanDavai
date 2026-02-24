# AGENTS.md

## Purpose
This file defines a single implementation and design contract for all agents working on this repository.
Goal: keep one consistent app identity across chats, sessions, and agents.

## Product
- App type: peer-to-peer LAN file transfer (no central transfer server).
- Targets: Windows, Linux, Android, iOS.
- Core promise: fast local transfer, simple pairing, predictable UX.

## Stack Contract
- Framework: Flutter (stable channel).
- Language: Dart.
- State management: Riverpod (prefer `Notifier`/`AsyncNotifier`).
- Navigation: `go_router`.
- Lints: `flutter_lints` + strict analyzer warnings.
- Architecture style: feature-first + clean boundaries.

## Source Layout Contract
Use this structure unless there is a strong reason not to:

```text
lib/
  app/
    app.dart
    router.dart
    theme/
      app_theme.dart
      app_colors.dart
      app_spacing.dart
      app_radius.dart
      app_typography.dart
  core/
    errors/
    utils/
    widgets/
  features/
    discovery/
    transfer/
    history/
    settings/
```

Rules:
- No UI code in data layer.
- No direct networking calls from widgets.
- Shared design tokens must live only in `lib/app/theme/*`.

## Visual Identity Contract (Do Not Drift)
Agents must keep the same style direction.

### Design direction
- Tone: clean, technical, confident.
- Density: medium, not cramped.
- Corner style: rounded, not fully pill everywhere.
- Motion: subtle and purposeful.

### Color tokens (single source of truth)
- `brandPrimary`: `#0B6E4F`
- `brandAccent`: `#F4A259`
- `bgBase`: `#F7F9FB`
- `surface`: `#FFFFFF`
- `textPrimary`: `#111827`
- `textSecondary`: `#4B5563`
- `success`: `#15803D`
- `warning`: `#B45309`
- `error`: `#B91C1C`

Do not introduce one-off hex colors in widgets.

### Typography
- Primary font: Manrope.
- Monospace/supporting numeric font: JetBrains Mono.
- Use semantic styles from theme only; no ad-hoc `TextStyle` unless unavoidable.

### Spacing and shape
- Spacing scale: `4, 8, 12, 16, 20, 24, 32`.
- Radius scale: `8, 12, 16, 24`.
- Default card radius: `16`.
- Default button height: `44` mobile, `40` desktop.

### Components
- Buttons: max 2 emphasis levels on one screen (`primary`, `secondary`).
- Cards: soft elevation, no heavy shadows.
- Lists: clear row separators or card grouping, not mixed randomly.
- Progress UI: always show percent + speed + ETA when data exists.

## UX Contract
- Every transfer-related flow must expose state clearly:
  - `idle`, `discovering`, `pairing`, `transferring`, `paused`, `completed`, `failed`.
- Critical actions (accept/decline overwrite/cancel transfer) require explicit confirmation.
- Errors must be actionable and human readable.
- Empty states must include next action.

## Networking Contract
- Discovery first: mDNS on LAN.
- Fallback: manual IP connect.
- Transport: reliable stream (TCP/QUIC abstraction allowed).
- Transfers must support resume with chunk-based progress tracking.
- Pairing must use explicit trust confirmation (code or QR).

## Code Quality Contract
- Keep files focused; split widgets >200 lines.
- Prefer pure functions for mapping/parsing logic.
- Add tests for business logic and protocol framing.
- Do not add dependencies without clear need.
- Preserve backward compatibility of public models when possible.

## Agent Response Contract
When implementing changes, agents should:
1. State assumptions briefly.
2. Implement code, not only propose.
3. Report exact files changed.
4. Include verification steps run (analyze/test/manual).
5. List remaining risks or TODOs.

## Prompt Template For Consistent Results
Use this template when asking any agent:

```text
Task:
Context:
Constraints:
Target platforms:
Definition of done:
Out of scope:
```

Optional style lock line:
`Follow AGENTS.md visual identity and do not introduce new design tokens.`

## Definition of Done (Default)
- Builds on touched platforms.
- No new analyzer warnings in touched files.
- Theme/token contract respected.
- UX states handled for loading/success/error.
- Changes summarized with file list and validation notes.
