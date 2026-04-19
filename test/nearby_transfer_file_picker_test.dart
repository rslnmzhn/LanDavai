import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_file_picker.dart';
import 'package:path/path.dart' as p;

void main() {
  test('android whole-folder selection enumerates nested files', () async {
    final root = await Directory.systemTemp.createTemp(
      'landa_nearby_picker_android_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final tripDirectory = Directory('${root.path}/Trip');
    final docsDirectory = Directory('${tripDirectory.path}/docs');
    await docsDirectory.create(recursive: true);

    final photo = File('${tripDirectory.path}/photo.png');
    final notes = File('${docsDirectory.path}/notes.txt');
    await photo.writeAsBytes(const <int>[1, 2, 3, 4]);
    await notes.writeAsString('hello nearby');

    final picker = NearbyTransferFilePicker(
      supportsDirectoryPickingOverride: true,
      pickDirectoryPathInvoker: () async => tripDirectory.path,
    );

    final selection = await picker.pickDirectory();

    expect(selection, isNotNull);
    expect(selection!.label, 'Trip');
    expect(
      selection.entries.map((entry) => entry.relativePath).toSet(),
      <String>{
        p.join('Trip', 'photo.png'),
        p.join('Trip', 'docs', 'notes.txt'),
      },
    );
  });
}
