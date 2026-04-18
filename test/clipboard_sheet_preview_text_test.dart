import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/presentation/clipboard_sheet_preview.dart';

void main() {
  test('clipboard preview builder collapses and truncates long text safely', () {
    final fullText =
        'Line one\n\nLine two\t\tLine three ${List<String>.filled(80, 'tail').join(' ')}';

    final preview = buildClipboardPreviewText(fullText);

    expect(preview.length, lessThan(fullText.length));
    expect(preview.contains('\n'), isFalse);
    expect(preview.endsWith('…'), isTrue);
  });
}
