# Refactor Workpacks Index

## 1. Purpose

This index tracks workpack status against the current post-refactor baseline.

Read order:

1. `docs/refactor_master_plan.md`
2. this index
3. the target workpack you are executing
4. `18_deletion_wave_map.md` and `19_test_gates_matrix.md`

## 2. Workpack Registry

| Workpack ID | Title | Status | Primary zone | Depends on | Required test gates | Main residue reduced |
| --- | --- | --- | --- | --- | --- | --- |
| `00` | Index | baseline | execution map | none | none | sequencing drift |
| `01` | Local peer identity owner extraction | completed | local identity ownership | none | `GATE-01`, `GATE-08` | friend/local-identity double responsibility |
| `02` | Discovery boundary factory extraction | completed | discovery composition | `01`, `04`, `06`, `08` | `GATE-03`, `GATE-08` | widget-local graph assembly |
| `03` | Discovery page surface split | completed | discovery UI shell | `02`, `04`, `08` | `GATE-03`, `GATE-08` | page-level coordinator sprawl |
| `04` | Shared-cache maintenance contract cutover | completed | maintenance backchannel | none | `GATE-02`, `GATE-03`, `GATE-07`, `GATE-08` | bridge and callback backchannel |
| `05` | Files part-graph removal | completed | files presentation | `04` | `GATE-02`, `GATE-03`, `GATE-07`, `GATE-08` | hidden files-module coupling |
| `06` | Remote-share media projection cleanup | completed | controller thumbnail IO bypass | `04` | `GATE-02`, `GATE-04`, `GATE-08` | controller-side media IO |
| `07` | Shared-folder-cache repository split | completed | infra repository | `04`, `06` | `GATE-02`, `GATE-04`, `GATE-08` | god-repository surface |
| `08` | Transfer and video-link separation | completed | mixed transfer/watch-link shell | none | `GATE-05`, `GATE-08` | transfer/video-link overlap |
| `09` | Protocol codec family decomposition | completed | protocol codec split | `08` | `GATE-06`, `GATE-08` | protocol god-module |
| `10` | Architecture guard and regression hardening | open | guardrails + weak UI flows | `01`, `03`, `04`, `05`, `06`, `07`, `08`, `09` | `GATE-07`, `GATE-08` | drift without proof |
| `18` | Deletion wave map | baseline | deletion coordination | all workpacks | all relevant proofs | legacy residue |
| `19` | Test gates matrix | baseline | gate coordination | none | none | unsafe sequencing |

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

## 4. Suggested Pull Request Waves (Historical)

- Wave A: `01`, `04`, `08`
- Wave B: `06`, `02`, `05`
- Wave C: `07`, `03`, `09`
- Wave D: `10`

Waves A–C are complete. Wave D remains open until workpack 10’s remaining UI
coverage gaps are closed.
