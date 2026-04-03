import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/application/clipboard_source_scope_store.dart';

void main() {
  test('keeps explicit local sentinel and resets removed remote selection', () {
    final store = ClipboardSourceScopeStore();

    expect(store.selectedSourceId, ClipboardSourceScopeStore.localSourceId);
    expect(store.isLocalSelected, isTrue);

    store.selectRemote('192.168.1.44');
    expect(
      store.selectedSourceId,
      ClipboardSourceScopeStore.remoteSourceId('192.168.1.44'),
    );
    expect(store.selectedRemoteIp, '192.168.1.44');

    store.syncAvailableRemoteIps(const <String>['192.168.1.55']);
    expect(store.selectedSourceId, ClipboardSourceScopeStore.localSourceId);
    expect(store.selectedRemoteIp, isNull);
  });
}
