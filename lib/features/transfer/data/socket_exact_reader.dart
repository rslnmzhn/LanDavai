import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class SocketExactReader {
  SocketExactReader(Socket socket) {
    _subscription = socket.listen(
      (chunk) {
        if (chunk.isEmpty) {
          return;
        }
        _chunks.addLast(Uint8List.fromList(chunk));
        _availableBytes += chunk.length;
        _signalWaiter();
      },
      onError: (Object error) {
        _error = error;
        _signalWaiter();
      },
      onDone: () {
        _isDone = true;
        _signalWaiter();
      },
      cancelOnError: true,
    );
  }

  final Queue<Uint8List> _chunks = Queue<Uint8List>();
  late final StreamSubscription<List<int>> _subscription;
  Completer<void>? _waiter;
  Object? _error;
  var _isDone = false;
  var _availableBytes = 0;
  var _headOffset = 0;

  Future<Uint8List> readExact(int byteCount) async {
    if (byteCount < 0) {
      throw ArgumentError.value(byteCount, 'byteCount', 'Must be >= 0');
    }
    if (byteCount == 0) {
      return Uint8List(0);
    }

    while (_availableBytes < byteCount) {
      if (_error != null) {
        throw StateError('Socket read failed: $_error');
      }
      if (_isDone) {
        throw StateError(
          'Socket closed before reading $byteCount bytes '
          '(available=$_availableBytes).',
        );
      }
      _waiter ??= Completer<void>();
      await _waiter!.future;
    }

    final out = Uint8List(byteCount);
    var written = 0;
    while (written < byteCount) {
      final head = _chunks.first;
      final remainingInHead = head.length - _headOffset;
      final toCopy = min(byteCount - written, remainingInHead);
      out.setRange(written, written + toCopy, head, _headOffset);
      written += toCopy;
      _headOffset += toCopy;
      _availableBytes -= toCopy;

      if (_headOffset >= head.length) {
        _chunks.removeFirst();
        _headOffset = 0;
      }
    }
    return out;
  }

  void _signalWaiter() {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
    _waiter = null;
  }

  Future<void> close() => _subscription.cancel();
}
