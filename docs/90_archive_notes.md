# Docs Archive Notes

This file records which old docs were archived and why.

## Archived location

- `docs/archive/refactor_baseline_legacy/`

## Archived files

- `completed.md`
- `refactor_master_plan.md`
- `refactor_workpacks/00_index.md`
- `refactor_workpacks/01_local_peer_identity_owner_extraction.md`
- `refactor_workpacks/02_discovery_boundary_factory_extraction.md`
- `refactor_workpacks/03_discovery_page_surface_split.md`
- `refactor_workpacks/04_shared_cache_maintenance_contract_cutover.md`
- `refactor_workpacks/05_files_part_graph_removal.md`
- `refactor_workpacks/06_remote_share_media_projection_cleanup.md`
- `refactor_workpacks/07_shared_folder_cache_repository_split.md`
- `refactor_workpacks/08_transfer_video_link_separation.md`
- `refactor_workpacks/09_protocol_codec_family_decomposition.md`
- `refactor_workpacks/10_architecture_guard_and_regression_hardening.md`
- `refactor_workpacks/18_deletion_wave_map.md`
- `refactor_workpacks/19_test_gates_matrix.md`

## Why these files were archived

- They document a completed refactor program, not the current day-to-day system map.
- They are historical and milestone-oriented, while current maintenance needs a code-aligned reference organized by active seams and flows.
- Their content overlapped heavily with [AGENTS.md](/e:/Projects/Landa/AGENTS.md) and with each other.
- Keeping them in the active `docs/` root made navigation noisy and made it harder to find current system documentation quickly.

## What replaced them as active reference

- [00_index.md](/e:/Projects/Landa/docs/00_index.md)
- [01_architecture_owner_map.md](/e:/Projects/Landa/docs/01_architecture_owner_map.md)
- [02_discovery_navigation_surfaces.md](/e:/Projects/Landa/docs/02_discovery_navigation_surfaces.md)
- [03_shared_access_downloads.md](/e:/Projects/Landa/docs/03_shared_access_downloads.md)
- [04_nearby_transfer_qr_flow.md](/e:/Projects/Landa/docs/04_nearby_transfer_qr_flow.md)
- [05_build_release_packaging.md](/e:/Projects/Landa/docs/05_build_release_packaging.md)
- [06_regression_and_test_gates.md](/e:/Projects/Landa/docs/06_regression_and_test_gates.md)

## Deletion policy used in this audit

No old docs were hard-deleted blindly. Historical material was preserved under `docs/archive/` because it can still be useful for archaeology, but it is no longer part of the active read path.
