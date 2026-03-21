# Deletion Wave Map

Derived from `docs/refactor_master_plan.md` and the tactical workpacks in `docs/refactor_workpacks/`.

| Artifact | Deleted by workpack | Earliest allowed phase | Deletion condition | Proof required | Still blocked by |
| --- | --- | --- | --- | --- | --- |
| `FriendRepository` conceptual ownership of `_localPeerIdKey` | `02` | Phase 1 | local identity writes route only through `LocalPeerIdentityStore` | `GATE-01`, `GATE-03` | implementation still calling `loadOrCreateLocalPeerId` as business owner |
| `DiscoveryPage` dependency assembly | `03` | Phase 2 | page receives injected boundaries only | `GATE-06` | none after `03` |
| `DiscoveryController._devicesByIp` as primary identity truth | `20` | Phase 3 | `DeviceRegistry` owns identity writes and identity reads | `GATE-03`, `GATE-07` | `04`, `06`, `20` |
| `DiscoveryController._aliasByMac` as primary identity owner | `20` | Phase 3 | identity reads no longer depend on controller alias mirror | `GATE-03`, `GATE-07` | `04`, `06`, `20` |
| `DiscoveryController._trustedDeviceMacs` as primary trust truth | `20` | Phase 3 | trust writes route only through `TrustedLanPeerStore` | `GATE-03` | `05`, `06`, `20` |
| `DiscoveryController._friends` as peer-owner cluster | `20` | Phase 3 | persistent internet endpoint reads and writes route through `InternetPeerEndpointStore` and discovery read model | `GATE-01`, `GATE-07` | `03a`, `06`, `20` |
| `DiscoveryController._loadSettings` | `20` | Phase 3 | settings load path routes through `SettingsStore` only | `GATE-01`, `GATE-06` | `03b`, `20` |
| `DiscoveryController._saveSettings` | `20` | Phase 3 | settings write path routes through `SettingsStore` only | `GATE-01`, `GATE-06` | `03b`, `20` |
| `PeerVocabularyAdapter` | `20` | Phase 3 | local identity, internet endpoint, and discovery read-side cutovers no longer need merged peer wording bridge | `GATE-07` | `02`, `03a`, `06`, `20` |
| `DeviceIdentityBridge` | `20` | Phase 3 | registry-driven identity reads and writes are the only production path | `GATE-03`, `GATE-07` | `04`, `20` |
| `ProtocolDispatchFacade` | `21` | Phase 4 | no packet flow depends on facade | `GATE-02`, `GATE-04` | `07`, `08`, `09`, `21` |
| residual transport lifecycle inside `LanDiscoveryService` | `21` | Phase 4 | transport adapter owns socket lifecycle | `GATE-02` | `07`, `21` |
| residual codec helpers inside `LanDiscoveryService` | `21` | Phase 4 | packet codec set owns encode and decode authority | `GATE-02` | `08`, `21` |
| `DiscoveryController._ownerSharedCaches` | `12` | Phase 5 | all cache reads route through `SharedCacheCatalog` only | `GATE-05`, `GATE-06`, `GATE-07` | `10`, `11`, `22`, `12` |
| `DiscoveryController._ownerIndexEntriesByCacheId` | `12` | Phase 5 | no index read path uses controller mirror | `GATE-05`, `GATE-06`, `GATE-07` | `11`, `22`, `12` |
| `SharedCacheCatalogBridge` | `12` | Phase 5 | metadata and index reads no longer need parity bridge | `GATE-05`, `GATE-06`, `GATE-07` | `10`, `11`, `22`, `12` |
| `DiscoveryController._clipboardHistory` | `13` | Phase 6 | local clipboard UI and writes use `ClipboardHistoryStore` only | `GATE-01`, `GATE-06`, `GATE-07` | `13` |
| remote clipboard half of `ClipboardSheet -> DiscoveryController` dependency | `13a` | Phase 6 | sheet reads remote clipboard entries from explicit projection boundary only | `GATE-02`, `GATE-06`, `GATE-07` | `09`, `13a` |
| `DiscoveryController._remoteShareOptions` | `14` | Phase 6 | session browse state lives in `RemoteShareBrowser` only | `GATE-02`, `GATE-05`, `GATE-06`, `GATE-07` | `09`, `12`, `22`, `14` |
| files feature `part`-owned state cluster | `15` | Phase 6 | files widgets read explicit owner, not `part`-owned truth | `GATE-06`, `GATE-07` | `14`, `15` |
| `_MediaPreviewCache` as owner | `16` | Phase 6 | preview lifecycle is managed by explicit owner only | `GATE-06`, `GATE-07` | `15`, `16` |
| `TransferSessionBridge` | `17` | Phase 6 | coordinator is sole transfer-session writer | `GATE-02`, `GATE-04`, `GATE-07` | `17` |
| `DiscoveryController._downloadHistory` | `13b` | Phase 6 | download history reads and writes no longer route through discovery controller | `GATE-06`, `GATE-07` | `17`, `13b` |
| full `ClipboardSheet -> DiscoveryController` dependency surface | `23` | Phase 6 | both local-history and remote-projection controller dependencies are gone and no wrapper survives | `GATE-06`, `GATE-07` | `13`, `13a`, `23` |
| obsolete cross-feature callbacks from discovery UI | `23` | Phase 6 | features interact through explicit contracts, not callbacks | `GATE-06`, `GATE-07` | `13`, `13a`, `13b`, `14`, `15`, `16`, `17`, `23` |
| `LegacyDiscoveryFacade` | `23` | Phase 6 | no screen consumes broad legacy discovery surface | `GATE-06`, `GATE-07` | `06`, `13a`, `13b`, `14`, `23` |
| `FileExplorerFacade` | `23` | Phase 6 | files UI no longer needs facade to hide old state or preview ownership | `GATE-06`, `GATE-07` | `15`, `16`, `23` |
