import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/transfer/data/transfer_header_codec.dart';
import 'package:landa/features/transfer/domain/transfer_request.dart';

void main() {
  group('TransferHeaderCodec', () {
    test('round trips uncompressed transfer header', () {
      const codec = TransferHeaderCodec();
      const header = TransferHeader(
        requestId: 'request-1',
        files: <TransferFileManifestItem>[
          TransferFileManifestItem(
            fileName: 'folder/file.txt',
            sizeBytes: 42,
            sha256: 'abc123',
          ),
        ],
      );

      final encoded = codec.encode(header);
      final decoded = codec.decode(encoded.bytes);

      expect(encoded.compressed, isFalse);
      expect(decoded.requestId, header.requestId);
      expect(decoded.files.single.fileName, 'folder/file.txt');
      expect(decoded.files.single.sizeBytes, 42);
      expect(decoded.files.single.sha256, 'abc123');
    });

    test('compresses large manifest when gzip is smaller', () {
      const codec = TransferHeaderCodec(compressionThresholdBytes: 32);
      final header = TransferHeader(
        requestId: 'large-request',
        files: List<TransferFileManifestItem>.generate(
          400,
          (index) => TransferFileManifestItem(
            fileName: 'workspace/repeated/path/file_$index.txt',
            sizeBytes: index,
            sha256: '',
          ),
          growable: false,
        ),
      );

      final encoded = codec.encode(header);
      final decoded = codec.decode(encoded.bytes);

      expect(encoded.compressed, isTrue);
      expect(encoded.bytes.length, lessThan(encoded.rawBytesLength));
      expect(decoded.requestId, header.requestId);
      expect(decoded.files, hasLength(header.files.length));
      expect(decoded.files.last.fileName, header.files.last.fileName);
    });

    test('throws typed format exception for invalid header payload', () {
      const codec = TransferHeaderCodec();

      expect(
        () => codec.decode(Uint8List.fromList('[]'.codeUnits)),
        throwsA(isA<TransferHeaderFormatException>()),
      );
    });
  });
}
