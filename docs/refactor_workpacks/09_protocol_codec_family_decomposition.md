# Workpack 09: Protocol Codec Family Decomposition

## Purpose

Split protocol codec responsibilities by family while keeping wire semantics
unchanged.

## Status

Completed.

## Target State (Baseline)

- family codecs live in dedicated files under `lib/features/discovery/data/`
- DTO truth in `lan_packet_codec_models.dart`
- shared helpers/constants in `lan_packet_codec_common.dart`
- `LanPacketCodec` is a thin compatibility facade

## Dependencies

- `08_transfer_video_link_separation.md`

## Required Test Gates

- `GATE-06`
- `GATE-08`

## Completion Proof (Current Baseline)

Protocol files present:

- `lan_presence_packet_codec.dart`
- `lan_transfer_packet_codec.dart`
- `lan_friend_packet_codec.dart`
- `lan_share_packet_codec.dart`
- `lan_clipboard_packet_codec.dart`
- `lan_packet_codec_models.dart`
- `lan_packet_codec_common.dart`
- `lan_packet_codec.dart` (facade)

Guard tests prevent re-expansion:

- `test/architecture_guard_test.dart`
