import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/transfer/application/shared_download_request_mapper.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';

void main() {
  test('maps untrusted download request to queued incoming request', () {
    final mapper = SharedDownloadRequestMapper(isTrustedSender: (_) => false);
    final event = _event();

    final mapping = mapper.map(event: event, cache: _cache());

    expect(mapping.normalizedRequesterMac, 'aa:bb:cc:dd:ee:ff');
    expect(mapping.isPreviewRequest, isFalse);
    expect(mapping.isTrustedFriendRequester, isFalse);
    expect(
      mapping.notice.infoMessage,
      'Download request from Laptop for "Photos".',
    );
    expect(mapping.notice.clearError, isTrue);
    expect(mapping.incomingRequest, isNotNull);
    expect(mapping.incomingRequest!.requestId, 'request-1');
    expect(mapping.incomingRequest!.sharedCacheId, 'cache-1');
    expect(mapping.incomingRequest!.sharedLabel, 'Photos');
    expect(mapping.incomingRequest!.selectedRelativePaths, <String>['a.jpg']);
  });

  test('maps trusted friend request to auto-approve notice', () {
    final mapper = SharedDownloadRequestMapper(
      isTrustedSender: (mac) => mac == 'aa:bb:cc:dd:ee:ff',
    );

    final mapping = mapper.map(event: _event(), cache: _cache());

    expect(mapping.isTrustedFriendRequester, isTrue);
    expect(
      mapping.notice.infoMessage,
      'Trusted friend Laptop requested "Photos". Auto-approving.',
    );
    expect(mapping.incomingRequest, isNotNull);
  });

  test('maps preview request without creating incoming queue request', () {
    final mapper = SharedDownloadRequestMapper(isTrustedSender: (_) => true);

    final mapping = mapper.map(
      event: _event(previewMode: true),
      cache: _cache(),
    );

    expect(mapping.isPreviewRequest, isTrue);
    expect(mapping.isTrustedFriendRequester, isFalse);
    expect(mapping.notice.infoMessage, 'Preview request from Laptop.');
    expect(mapping.incomingRequest, isNull);
  });

  test('builds stable diagnostic details for request stages', () {
    final mapper = SharedDownloadRequestMapper(isTrustedSender: (_) => false);

    final details = mapper.diagnostics(
      event: _event(),
      normalizedRequesterMac: 'aa:bb:cc:dd:ee:ff',
      cacheId: 'cache-normalized',
    );

    expect(details.received['requesterIp'], '192.168.1.20');
    expect(details.received['requesterMacAddress'], 'aa:bb:cc:dd:ee:ff');
    expect(details.received['cacheId'], 'cache-normalized');
    expect(details.received['previewMode'], isFalse);
    expect(details.received['transferPort'], 4545);
    expect(details.autoApprovedForFriend.containsKey('previewMode'), isFalse);
    expect(details.autoApprovedForFriend['requestsWholeShare'], isFalse);
  });
}

DownloadRequestEvent _event({bool previewMode = false}) {
  return DownloadRequestEvent(
    requestId: 'request-1',
    requesterIp: '192.168.1.20',
    requesterName: 'Laptop',
    requesterMacAddress: 'AA-BB-CC-DD-EE-FF',
    cacheId: 'cache-1',
    selectedRelativePaths: <String>['a.jpg'],
    selectedFolderPrefixes: const <String>[],
    transferPort: 4545,
    previewMode: previewMode,
    observedAt: DateTime(2026),
  );
}

SharedFolderCacheRecord _cache() {
  return SharedFolderCacheRecord(
    cacheId: 'cache-1',
    role: SharedFolderCacheRole.owner,
    ownerMacAddress: '11:22:33:44:55:66',
    rootPath: '/photos',
    displayName: 'Photos',
    indexFilePath: '/cache/index.json',
    itemCount: 1,
    totalBytes: 1,
    updatedAtMs: 1,
  );
}
