import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_list.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_preview.dart';

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
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: ClipboardSheetList(
                localEntries: buildLocalClipboardListPreviews(localEntries),
                remoteDevices: const [],
                selectedRemoteIp: null,
                remoteEntries: const <RemoteClipboardListEntryPreview>[],
                isRemoteLoading: false,
                onRemoteDeviceChanged: (_) {},
                onLoadRemoteEntries: null,
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
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 320,
              child: ClipboardSheetList(
                localEntries: buildLocalClipboardListPreviews(localEntries),
                remoteDevices: const [],
                selectedRemoteIp: null,
                remoteEntries: const <RemoteClipboardListEntryPreview>[],
                isRemoteLoading: false,
                onRemoteDeviceChanged: (_) {},
                onLoadRemoteEntries: null,
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
      await tester.pump();

      final previewText = buildClipboardPreviewText(fullText);
      expect(find.text(previewText), findsOneWidget);
      expect(find.text(fullText), findsNothing);

      await tester.tap(find.byTooltip('Copy text'));
      await tester.pump();

      expect(copiedText, fullText);
    },
  );

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
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: ClipboardSheetList(
              localEntries: buildLocalClipboardListPreviews(localEntries),
              remoteDevices: const [],
              selectedRemoteIp: null,
              remoteEntries: const <RemoteClipboardListEntryPreview>[],
              isRemoteLoading: false,
              onRemoteDeviceChanged: (_) {},
              onLoadRemoteEntries: null,
              onCopyLocalEntry: (_) async {},
              onCopyRemoteText: (_) async {},
              onDeleteLocalEntry: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Copy image'), findsOneWidget);
  });

  test('clipboard preview builder collapses and truncates long text safely', () {
    final fullText =
        'Line one\n\nLine two\t\tLine three ${List<String>.filled(80, 'tail').join(' ')}';

    final preview = buildClipboardPreviewText(fullText);

    expect(preview.length, lessThan(fullText.length));
    expect(preview.contains('\n'), isFalse);
    expect(preview.endsWith('…'), isTrue);
  });
}
