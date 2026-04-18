import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/clipboard/presentation/clipboard_preview_dialog.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_list.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_preview.dart';

import 'test_support/localized_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping text content opens full text preview dialog', (
    tester,
  ) async {
    final fullText =
        'A long text payload that should be previewed in full when tapped.';
    final localEntries = <ClipboardHistoryEntry>[
      ClipboardHistoryEntry(
        id: 'text-preview-entry',
        type: ClipboardEntryType.text,
        contentHash: 'text:preview',
        textValue: fullText,
        createdAt: DateTime(2026, 4, 1, 13, 45),
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
                  onPreviewLocalEntry: (entry) {
                    return showClipboardTextPreviewDialog(
                      context: context,
                      title: 'Clipboard text',
                      text: entry.textValue!,
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

    expect(find.text('Clipboard text'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SelectableText),
      ),
      findsOneWidget,
    );
  });
}
