# Nearby Transfer And QR Flow

This file covers the separate nearby-transfer feature seam. It is intentionally distinct from shared-access downloads.

## Ownership

- `NearbyTransferSessionStore`
  Owns nearby-transfer session truth, active mode, peer, handshake state, transfer progress, and session-local candidate state.
- Nearby transport adapters own transport details.
- `DiscoveryController` does not own nearby-transfer runtime truth.

## Main transport surfaces

- `lib/features/nearby_transfer/application/nearby_transfer_session_store.dart`
- `lib/features/nearby_transfer/data/lan_nearby_transport_adapter.dart`
- `lib/features/nearby_transfer/data/wifi_direct_transport_adapter.dart`
- `lib/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart`

## Current receive/send UX

- Nearby transfer uses its own entry surfaces and session flow.
- Pairing/verification uses digits instead of emoji.
- QR send surface keeps the QR centered; decorative pulse animation does not move the QR.
- QR scanner uses a square scanner viewport with matching overlay.
- Detection feedback is visible on successful scan.
- Receive flow shows a file list first; download happens only for explicitly selected files.
- Supported files can be previewed before download.

## Separation from shared-access browser

- Nearby transfer is not routed through `TransferSessionCoordinator` shared-access download semantics.
- The remote shared-access browser is a different surface and a different flow.

## Main presentation files

- `lib/features/nearby_transfer/presentation/nearby_transfer_qr_view.dart`
- `lib/features/nearby_transfer/presentation/nearby_transfer_scanner_view.dart`
- `lib/features/nearby_transfer/presentation/nearby_transfer_receive_view.dart`
- `lib/features/nearby_transfer/presentation/nearby_transfer_send_view.dart`

## Current regression coverage

- `test/nearby_transfer_qr_view_test.dart`
- `test/nearby_transfer_scanner_view_test.dart`
- `test/nearby_transfer_receive_view_test.dart`
- `test/nearby_transfer_send_view_test.dart`
- `test/nearby_transfer_entry_sheet_test.dart`
