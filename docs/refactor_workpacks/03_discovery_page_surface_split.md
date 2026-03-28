# Workpack 03: Discovery Page Surface Split

## Purpose

Разрезать `DiscoveryPage` как god-page на отдельные presentation surfaces.
Это UI decomposition workpack, not a new owner split.

## Current evidence

- `lib/features/discovery/presentation/discovery_page.dart` is the largest Dart file in `lib/`
- one page still bundles:
  - main discovery content
  - add-share and device-action menus
  - history sheet
  - clipboard sheet entry
  - receive panel entry
  - video-link flow entry
  - action bar and progress widgets

## Target state

- `DiscoveryPage` becomes a thin screen shell
- major UI surfaces move into dedicated presentation files
- page-level feature launch code shrinks materially
- extracted owners remain external and authoritative

## In scope

- `lib/features/discovery/presentation/discovery_page.dart`
- new supporting presentation files under `lib/features/discovery/presentation/`
- related discovery smoke/widget tests

## Out of scope

- shared-cache bridge removal
- local peer identity extraction
- transfer/video-link domain redesign
- protocol or repository refactors

## Pull Request Cycle

1. Inventory the major UI surfaces and launcher methods inside `DiscoveryPage`.
2. Extract focused widgets/sheets/launcher helpers with explicit inputs.
3. Leave page-local ephemeral UI state only where it is truly screen-local.
4. Remove obsolete inline modal/entry lattice from the main page file.
5. Run `flutter analyze`, discovery entry smokes, and full `flutter test`.

## Required test gates

- `GATE-02`
- `GATE-08`

## Completion proof

- `DiscoveryPage` shrinks materially
- major surfaces live in dedicated presentation files
- no feature truth moves back into page-local state
- feature-entry smoke coverage stays green
