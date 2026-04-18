import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_list.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_preview.dart';

import 'test_support/localized_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ClipboardSheetList renders summarized text preview but copy still uses full payload',
    (tester) async {
      final fullText =
          'First line of a very long clipboard payload.\n'
          '${List<String>.filled(40, 'segment').join(' ')}';
      String? copiedText;

      final localEntries = <ClipboardHistoryEntry>[
        ClipboardHistoryEntry(
          id: 'long-text-entry',
          type: ClipboardEntryType.text,
          contentHash: 'text:long',
          textValue: fullText,
          createdAt: DateTime(2026, 4, 1, 12, 30),
        ),
      ];

      await tester.pumpWidget(
        buildLocalizedTestApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: SizedBox(
              height: 320,
              child: ClipboardSheetList(
                isLocalScope: true,
                localEntries: buildLocalClipboardListPreviews(localEntries),
                remoteEntries: const <RemoteClipboardListEntryPreview>[],
                isRemoteLoading: false,
                emptyMessage: 'unused',
                onPreviewLocalEntry: (_) async {},
                onPreviewRemoteEntry: (_) async {},
                onCopyLocalEntry: (entry) async {
                  copiedText = entry.textValue;
                },
                onCopyRemoteText: (_) async {},
                onDeleteLocalEntry: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(fullText), findsNothing);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.copy_rounded));
      await tester.pumpAndSettle();

      expect(copiedText, fullText);
    },
  );
}
