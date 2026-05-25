import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/files/application/audio_artwork_reader.dart';

void main() {
  test('extracts APIC artwork from ID3v2.3 MP3 files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'landa_audio_artwork_reader_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}song.mp3');
    final imageBytes = _imageBytes();
    await file.writeAsBytes(_buildMp3WithArtwork(imageBytes));

    final result = await const AudioArtworkReader().loadRawAudioCoverBytes(
      file.path,
    );

    expect(result, orderedEquals(imageBytes));
  });

  test('extracts picture block artwork from FLAC files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'landa_audio_artwork_reader_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}song.flac');
    final imageBytes = _imageBytes();
    await file.writeAsBytes(_buildFlacWithPicture(imageBytes));

    final result = await const AudioArtworkReader().loadRawAudioCoverBytes(
      file.path,
    );

    expect(result, orderedEquals(imageBytes));
  });

  test('returns null for files without supported embedded artwork', () async {
    final directory = await Directory.systemTemp.createTemp(
      'landa_audio_artwork_reader_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}song.mp3');
    await file.writeAsBytes(ascii.encode('not an id3 file'));

    final result = await const AudioArtworkReader().loadRawAudioCoverBytes(
      file.path,
    );

    expect(result, isNull);
  });
}

Uint8List _imageBytes() {
  return Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4]);
}

List<int> _buildMp3WithArtwork(Uint8List imageBytes) {
  final mimeBytes = ascii.encode('image/png');
  final payload = BytesBuilder(copy: false)
    ..addByte(0)
    ..add(mimeBytes)
    ..addByte(0)
    ..addByte(3)
    ..addByte(0)
    ..add(imageBytes);
  final payloadBytes = payload.toBytes();
  final frameSize = payloadBytes.length;
  final frame = BytesBuilder(copy: false)
    ..add(ascii.encode('APIC'))
    ..add(_uint32(frameSize))
    ..add(<int>[0, 0])
    ..add(payloadBytes);
  final frameBytes = frame.toBytes();
  final header = BytesBuilder(copy: false)
    ..add(ascii.encode('ID3'))
    ..add(<int>[3, 0, 0])
    ..add(_syncSafe(frameBytes.length));
  return <int>[...header.toBytes(), ...frameBytes];
}

List<int> _buildFlacWithPicture(Uint8List imageBytes) {
  final mimeBytes = ascii.encode('image/png');
  final descriptionBytes = ascii.encode('cover');
  final pictureBlock = BytesBuilder(copy: false)
    ..add(_uint32(3))
    ..add(_uint32(mimeBytes.length))
    ..add(mimeBytes)
    ..add(_uint32(descriptionBytes.length))
    ..add(descriptionBytes)
    ..add(_uint32(1))
    ..add(_uint32(1))
    ..add(_uint32(24))
    ..add(_uint32(0))
    ..add(_uint32(imageBytes.length))
    ..add(imageBytes);
  final pictureBytes = pictureBlock.toBytes();
  return <int>[
    ...ascii.encode('fLaC'),
    0x80 | 6,
    ..._uint24(pictureBytes.length),
    ...pictureBytes,
  ];
}

List<int> _uint24(int value) {
  return <int>[(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
}

List<int> _uint32(int value) {
  return <int>[
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];
}

List<int> _syncSafe(int value) {
  return <int>[
    (value >> 21) & 0x7f,
    (value >> 14) & 0x7f,
    (value >> 7) & 0x7f,
    value & 0x7f,
  ];
}
