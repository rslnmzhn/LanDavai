import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_list.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_preview.dart';

import 'test_support/localized_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ClipboardSheet lazily builds large local history and still reveals older entries on scroll',
    (tester) async {
      final localEntries = List<ClipboardHistoryEntry>.generate(60, (index) {
        return ClipboardHistoryEntry(
          id: 'entry-$index',
          type: ClipboardEntryType.text,
          contentHash: 'text:$index',
          textValue: 'Local entry $index',
          createdAt: DateTime.fromMillisecondsSinceEpoch(index + 1),
        );
      }).reversed.toList(growable: false);

      await tester.pumpWidget(
        buildLocalizedTestApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: ClipboardSheetList(
                isLocalScope: true,
                localEntries: buildLocalClipboardListPreviews(localEntries),
                remoteEntries: const <RemoteClipboardListEntryPreview>[],
                isRemoteLoading: false,
                emptyMessage: 'unused',
                onPreviewLocalEntry: (_) async {},
                onPreviewRemoteEntry: (_) async {},
                onCopyLocalEntry: (_) async {},
                onCopyRemoteText: (_) async {},
                onDeleteLocalEntry: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Local entry 59'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('clipboard-local-entry-entry-0'),
          skipOffstage: false,
        ),
        findsNothing,
      );

      await tester.dragUntilVisible(
        find.text('Local entry 0'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Local entry 0'), findsOneWidget);
    },
  );
}
