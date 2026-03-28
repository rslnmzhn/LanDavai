# Refactor Workpacks Index

## 1. Purpose

This index replaces the completed tactical backlog.
It enumerates only the remaining refactor work that still makes architectural sense after the owner extractions already landed.

Read order:

1. `docs/refactor_master_plan.md`
2. this index
3. the target workpack you are executing
4. `18_deletion_wave_map.md` and `19_test_gates_matrix.md`

## 2. Workpack Registry

| Workpack ID | Title | Primary zone | Depends on | Required test gates | Main residue reduced |
| --- | --- | --- | --- | --- | --- |
| `00` | Index | execution map | none | none | orphaned sequencing |
| `01` | Local peer identity owner extraction | `local_peer_id` still hidden in `FriendRepository` | none | `GATE-01`, `GATE-08` | friend/local-identity double responsibility |
| `02` | Discovery boundary factory extraction | `DiscoveryPageEntry` composition-root sprawl | `01`, `04`, `06`, `08` | `GATE-03`, `GATE-08` | page-entry assembly shell |
| `03` | Discovery page surface split | giant `DiscoveryPage` UI shell | `02`, `04`, `08` | `GATE-03`, `GATE-08` | page-level coordinator sprawl |
| `04` | Shared-cache maintenance contract cutover | `SharedCacheCatalogBridge` plus files/shared-cache callback residue | none | `GATE-02`, `GATE-03`, `GATE-07`, `GATE-08` | bridge and callback backchannel |
| `05` | Files part-graph removal | `part / part of` files presentation cluster | `04` | `GATE-02`, `GATE-03`, `GATE-07`, `GATE-08` | hidden files-module coupling |
| `06` | Remote-share media projection cleanup | controller/repository thumbnail and preview residue | `04` | `GATE-02`, `GATE-04`, `GATE-08` | controller-side thumbnail IO bypass |
| `07` | Shared-folder-cache repository split | broad infra repository responsibilities | `04`, `06` | `GATE-02`, `GATE-04`, `GATE-08` | god-repository surface |
| `08` | Transfer and video-link separation | mixed transfer/watch-link shell concerns | none | `GATE-05`, `GATE-08` | transfer/video-link overlap |
| `09` | Protocol codec family decomposition | `lan_packet_codec.dart` size and scenario sprawl | `08` | `GATE-06`, `GATE-08` | protocol god-module |
| `10` | Architecture guard and regression hardening | missing post-refactor guardrails | `01`, `03`, `04`, `05`, `06`, `07`, `08`, `09` | `GATE-07`, `GATE-08` | drift without proof |
| `18` | Deletion wave map | deletion coordination | all active workpacks | all relevant proofs | orphaned legacy residue |
| `19` | Test gates matrix | gate coordination | none | none | unsafe sequencing |

## 3. Dependency Graph

- `01 -> 02`
- `04 -> 02`
- `06 -> 02`
- `08 -> 02`
- `02 -> 03`
- `04 -> 03`
- `08 -> 03`
- `04 -> 05`
- `04 -> 06`
- `04 + 06 -> 07`
- `08 -> 09`
- `01 + 03 + 04 + 05 + 06 + 07 + 08 + 09 -> 10`
- all executable workpacks feed `18`

## 4. Parallelism Rules

Can run in parallel:

- `01` and `04`
- `04` and `08`
- `05` and `06` after `04`

Should not run in parallel:

- `02` with `04` or `06`, because the boundary factory should be extracted after the callback and media seams are clearer
- `03` before `02`, because page decomposition should not keep rebuilding the old entry graph
- `07` before `06`, because repository splitting should follow the clarified remote-share media contract
- `10` before the other workpacks it is supposed to lock in

## 5. Suggested Pull Request Waves

- Wave A
  - `01`, `04`, `08`
- Wave B
  - `06`, `02`, `05`
- Wave C
  - `07`, `03`, `09`
- Wave D
  - `10`

The intent is:

- Wave A removes the most obvious cross-boundary residue
- Wave B shrinks shells and the remaining files presentation coupling
- Wave C tackles large infra and protocol modules
- Wave D converts the new architecture into enforceable guardrails
