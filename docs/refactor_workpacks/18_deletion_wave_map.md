# Deletion Wave Map

Derived from `docs/refactor_master_plan.md` and the tactical workpacks in `docs/refactor_workpacks/`.

| Artifact | Deleted by workpack | Earliest allowed phase | Deletion condition | Proof required | Still blocked by |
| --- | --- | --- | --- | --- | --- |
| `FriendRepository` conceptual ownership of `_localPeerIdKey` | `02` | Phase 1 | local identity writes route only through `LocalPeerIdentityStore` | repository contract + identity mapping proof | implementation branch still calling `loadOrCreateLocalPeerId` for ownership |
| `DiscoveryPage` dependency assembly | `03` | Phase 2 | page receives injected boundaries only | UI smoke proof | none after `03` |
| `DiscoveryController._devicesByIp` as primary identity truth | `20` | Phase 3 | `DeviceRegistry` owns identity writes and reads | identity mapping proof | `04`, `06` |
| `DiscoveryController._aliasByMac` as primary identity owner | `20` | Phase 3 | identity reads no longer depend on controller alias mirror | migration regression proof | `04`, `06` |
| `DiscoveryController._trustedDeviceMacs` as primary trust truth | `20` | Phase 3 | trust writes route only through `TrustedLanPeerStore` | trust regression + UI smoke proof | `05`, `06` |
| `ProtocolDispatchFacade` | `21` | Phase 4 | no packet flow depends on facade | protocol compatibility + session continuity proof | `07`, `08`, `09` |
| residual transport lifecycle inside `LanDiscoveryService` | `21` | Phase 4 | transport adapter owns socket lifecycle | protocol compatibility proof | `07` |
| residual codec helpers inside `LanDiscoveryService` | `21` | Phase 4 | packet codec set owns encode/decode authority | codec parity proof | `08` |
| `DiscoveryController._ownerSharedCaches` | `12` | Phase 5 | all cache reads route through `SharedCacheCatalog` | shared cache consistency + migration regression proof | `10`, `11`, `22` |
| `DiscoveryController._ownerIndexEntriesByCacheId` | `12` | Phase 5 | no index read path uses controller mirror | shared cache consistency + UI smoke proof | `11`, `22` |
| `SharedCacheCatalogBridge` | `12` | Phase 5 | metadata/index reads and writes no longer need parity bridge | shared cache read/write cutover proof | `10`, `11`, `22` |
| `DiscoveryController._clipboardHistory` | `13` | Phase 6 | clipboard UI and writes use `ClipboardHistoryStore` only | repository contract + UI smoke proof | `06`, `12` |
| `_remoteShareOptions` | `14` | Phase 6 | session browse state lives in `RemoteShareBrowser` | shared cache consistency + UI smoke proof | `09`, `12`, `22` |
| files feature `part`-owned state cluster | `15` | Phase 6 | files widgets read explicit owner, not part-owned truth | UI smoke + migration regression proof | `14` |
| `_MediaPreviewCache` as owner | `16` | Phase 6 | preview lifecycle lives in explicit owner | preview path regression proof via UI smoke | `15` |
| `TransferSessionBridge` | `17` | Phase 6 | coordinator is sole session writer | session continuity proof | `09`, `06` |
| obsolete cross-feature callbacks from discovery UI | `23` | Phase 6 | features interact through explicit contracts, not callbacks | UI smoke + migration regression proof | `13`, `14`, `15`, `16`, `17` |
| `LegacyDiscoveryFacade` | `23` | Phase 6 | no screen consumes broad legacy discovery surface | UI smoke proof | `06`, `14`, `23` |
| `FileExplorerFacade` | `23` | Phase 6 | files UI no longer needs facade to hide old state/cache ownership | UI smoke proof | `15`, `16` |
