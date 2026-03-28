# Deletion Wave Map

Derived from `docs/refactor_master_plan.md` and `docs/refactor_workpacks/00_index.md`.

| Artifact or residue | Deleted or minimized by | Earliest wave | Deletion condition | Proof required |
| --- | --- | --- | --- | --- |
| `FriendRepository.loadOrCreateLocalPeerId()` as business owner of `local_peer_id` | `01` | Wave A | production local-peer reads and writes go through a dedicated local-identity boundary only | `GATE-01`, `GATE-08` |
| `DiscoveryPageEntry._DiscoveryBoundary` and page-local graph assembly | `02` | Wave B | discovery boundary creation lives outside the widget shell | `GATE-03`, `GATE-08` |
| `SharedCacheCatalogBridge` | `04` | Wave A | files and discovery read/write maintenance flows route through an explicit shared-cache maintenance contract | `GATE-02`, `GATE-03`, `GATE-07`, `GATE-08` |
| `DiscoveryPage -> FileExplorerPage.launch(...)` recache/remove/progress callback bundle | `04` | Wave A | files entry no longer consumes foreign callbacks or controller progress listenables for shared-cache maintenance | `GATE-02`, `GATE-03`, `GATE-08` |
| files `part / part of` cluster under `file_explorer_page.dart` | `05` | Wave B | files presentation is composed from normal files with explicit imports only | `GATE-03`, `GATE-07`, `GATE-08` |
| controller-side thumbnail IO through `SharedFolderCacheRepository` | `06` | Wave B | controller no longer reads/writes remote-share thumbnail artifacts directly | `GATE-04`, `GATE-08` |
| manual `RemoteShareBrowser` notification nudges from controller glue | `06` | Wave B | remote-share media projection updates are applied by the owning boundary, not controller patches | `GATE-04`, `GATE-08` |
| `SharedFolderCacheRepository` as broad do-everything repository | `07` | Wave C | its responsibilities are split into narrower collaborators or it is reduced to a thin adapter only | `GATE-02`, `GATE-04`, `GATE-08` |
| mixed transfer/watch-link routing between discovery shells and `VideoLinkShareService` | `08` | Wave A | transfer coordinator stays transfer-only and video-link flow has an explicit separate entry boundary | `GATE-05`, `GATE-08` |
| monolithic `DiscoveryPage` section and modal bodies | `03` | Wave C | screen is decomposed into focused sections without reintroducing callback lattices | `GATE-03`, `GATE-08` |
| monolithic `lan_packet_codec.dart` family surface | `09` | Wave C | protocol codec responsibilities are split by family while wire semantics stay frozen | `GATE-06`, `GATE-08` |
| missing architecture guardrails for bridges, callback backchannels, and `part` regressions | `10` | Wave D | dedicated guard suite fails on prohibited patterns and protected entry flows have explicit smoke coverage | `GATE-07`, `GATE-08` |
