import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/clipboard/presentation/clipboard_preview_dialog.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_list.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_preview.dart';

import 'test_support/localized_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping image content opens image preview dialog', (
    tester,
  ) async {
    final localEntries = <ClipboardHistoryEntry>[
      ClipboardHistoryEntry(
        id: 'image-preview-entry',
        type: ClipboardEntryType.image,
        contentHash: 'image:preview',
        imagePath: 'ignored.png',
        createdAt: DateTime(2026, 4, 1, 14, 0),
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
                  isLocalScope: true,
                  localEntries: buildLocalClipboardListPreviews(localEntries),
                  remoteEntries: const <RemoteClipboardListEntryPreview>[],
                  isRemoteLoading: false,
                  emptyMessage: 'unused',
                  onPreviewLocalEntry: (_) {
                    return showClipboardImagePreviewDialog(
                      context: context,
                      title: 'Clipboard image',
                      imageProvider: const AssetImage(
                        'assets/tray/landa_tray.png',
                      ),
                    );
                  },
                  onPreviewRemoteEntry: (_) async {},
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

    expect(find.text('Clipboard image'), findsOneWidget);
  });
}
