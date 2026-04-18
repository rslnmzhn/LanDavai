import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_list.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_preview.dart';

import 'test_support/localized_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ClipboardSheet local image rows expose explicit copy action', (
    tester,
  ) async {
    final localEntries = <ClipboardHistoryEntry>[
      ClipboardHistoryEntry(
        id: 'image-entry',
        type: ClipboardEntryType.image,
        contentHash: 'image:preview',
        imagePath: 'ignored.png',
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
              onCopyLocalEntry: (_) async {},
              onCopyRemoteText: (_) async {},
              onDeleteLocalEntry: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.text('Image from clipboard'), findsNothing);
    expect(find.text('2026-04-01 12:30'), findsOneWidget);
    expect(find.byType(ClipboardHistoryPreviewRow), findsOneWidget);
  });
}
