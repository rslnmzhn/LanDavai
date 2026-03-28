# Workpack 02: Discovery Boundary Factory Extraction

## Purpose

Убрать большой discovery composition root из widget lifecycle.
Это не новый ownership split.
Это extraction of assembly and lifecycle wiring out of `DiscoveryPageEntry`.

## Current evidence

- `lib/app/discovery_page_entry.dart` still:
  - calls `AppDatabase.instance`
  - constructs repositories, services, owners, and controller
  - keeps a private `_DiscoveryBoundary`
  - mixes widget lifecycle with composition lifecycle
- the file remains a large app-shell assembly surface instead of a thin entry widget

## Target state

- explicit discovery boundary factory or app-level composition object builds the graph
- `DiscoveryPageEntry` becomes a thin host for an already-built boundary
- widget state no longer owns ad-hoc service/repository assembly

## In scope

- `lib/app/discovery_page_entry.dart`
- new composition/boundary factory file(s) under `lib/app/` or another narrow app-layer location
- tests or smokes that cover discovery entry bootstrapping

## Out of scope

- discovery page UI split
- new owner extraction
- shared-cache callback cleanup
- protocol redesign

## Pull Request Cycle

1. Inventory the exact object graph currently built in `DiscoveryPageEntry`.
2. Introduce the explicit boundary factory/composition surface.
3. Move assembly and ownership rules there without changing feature truth.
4. Shrink `DiscoveryPageEntry` to a thin lifecycle host.
5. Run `flutter analyze`, discovery smoke tests, and full `flutter test`.

## Required test gates

- `GATE-02`

## Completion proof

- `DiscoveryPageEntry` no longer assembles the full discovery graph inline
- `_DiscoveryBoundary` is deleted or reduced to a thin value object outside widget state
- entry flow still boots correctly under smoke tests
- analyzer and tests stay green
