import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/clipboard/presentation/clipboard_preview_dialog.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_list.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_preview.dart';

import 'test_support/localized_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping remote image content opens honest preview-only dialog', (
    tester,
  ) async {
    final remoteEntries = <RemoteClipboardEntry>[
      RemoteClipboardEntry(
        id: 'remote-image-preview-entry',
        type: ClipboardEntryType.image,
        imageBytes: Uint8List.fromList(const <int>[137, 80, 78, 71]),
        createdAt: DateTime(2026, 4, 1, 14, 15),
      ),
    ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: SizedBox(
                height: 320,
                child: ClipboardSheetList(
                  isLocalScope: false,
                  localEntries: const <LocalClipboardListEntryPreview>[],
                  remoteEntries: buildRemoteClipboardListPreviews(
                    remoteEntries,
                  ),
                  isRemoteLoading: false,
                  emptyMessage: 'unused',
                  onPreviewLocalEntry: (_) async {},
                  onPreviewRemoteEntry: (_) {
                    return showClipboardImagePreviewDialog(
                      context: context,
                      title: 'Remote clipboard image preview',
                      imageProvider: const AssetImage(
                        'assets/tray/landa_tray.png',
                      ),
                      note:
                          'Preview quality only. Original remote clipboard image is not available.',
                    );
                  },
                  onCopyLocalEntry: (_) async {},
                  onCopyRemoteText: (_) async {},
                  onDeleteLocalEntry: (_) async {},
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ClipboardHistoryPreviewRow));
    await tester.pumpAndSettle();

    expect(find.text('Remote clipboard image preview'), findsOneWidget);
    expect(
      find.text(
        'Preview quality only. Original remote clipboard image is not available.',
      ),
      findsOneWidget,
    );
  });
}
