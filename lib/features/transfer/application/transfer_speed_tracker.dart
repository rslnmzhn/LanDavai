class TransferSpeedTracker {
  double _uploadSpeedBytesPerSecond = 0;
  double _downloadSpeedBytesPerSecond = 0;
  DateTime? _uploadSpeedSampleAt;
  DateTime? _downloadSpeedSampleAt;
  int _uploadSpeedSampleBytes = 0;
  int _downloadSpeedSampleBytes = 0;

  double get uploadSpeedBytesPerSecond => _uploadSpeedBytesPerSecond;
  double get downloadSpeedBytesPerSecond => _downloadSpeedBytesPerSecond;

  void resetUpload({required int currentBytes}) {
    _uploadSpeedBytesPerSecond = 0;
    _uploadSpeedSampleBytes = currentBytes;
    _uploadSpeedSampleAt = DateTime.now();
  }

  void updateUpload({required int currentBytes}) {
    final now = DateTime.now();
    final sampleAt = _uploadSpeedSampleAt;
    if (sampleAt == null) {
      _uploadSpeedSampleAt = now;
      _uploadSpeedSampleBytes = currentBytes;
      return;
    }

    final elapsedMs = now.difference(sampleAt).inMilliseconds;
    final deltaBytes = currentBytes - _uploadSpeedSampleBytes;
    if (deltaBytes < 0) {
      _uploadSpeedSampleAt = now;
      _uploadSpeedSampleBytes = currentBytes;
      _uploadSpeedBytesPerSecond = 0;
      return;
    }
    if (elapsedMs < 250 || deltaBytes == 0) {
      return;
    }

    final instantSpeed = (deltaBytes * 1000) / elapsedMs;
    if (_uploadSpeedBytesPerSecond <= 0) {
      _uploadSpeedBytesPerSecond = instantSpeed;
    } else {
      _uploadSpeedBytesPerSecond =
          (_uploadSpeedBytesPerSecond * 0.7) + (instantSpeed * 0.3);
    }
    _uploadSpeedSampleAt = now;
    _uploadSpeedSampleBytes = currentBytes;
  }

  void clearUpload() {
    _uploadSpeedBytesPerSecond = 0;
    _uploadSpeedSampleBytes = 0;
    _uploadSpeedSampleAt = null;
  }

  void resetDownload({required int currentBytes}) {
    _downloadSpeedBytesPerSecond = 0;
    _downloadSpeedSampleBytes = currentBytes;
    _downloadSpeedSampleAt = DateTime.now();
  }

  void updateDownload({required int currentBytes}) {
    final now = DateTime.now();
    final sampleAt = _downloadSpeedSampleAt;
    if (sampleAt == null) {
      _downloadSpeedSampleAt = now;
      _downloadSpeedSampleBytes = currentBytes;
      return;
    }

    final elapsedMs = now.difference(sampleAt).inMilliseconds;
    final deltaBytes = currentBytes - _downloadSpeedSampleBytes;
    if (deltaBytes < 0) {
      _downloadSpeedSampleAt = now;
      _downloadSpeedSampleBytes = currentBytes;
      _downloadSpeedBytesPerSecond = 0;
      return;
    }
    if (elapsedMs < 250 || deltaBytes == 0) {
      return;
    }

    final instantSpeed = (deltaBytes * 1000) / elapsedMs;
    if (_downloadSpeedBytesPerSecond <= 0) {
      _downloadSpeedBytesPerSecond = instantSpeed;
    } else {
      _downloadSpeedBytesPerSecond =
          (_downloadSpeedBytesPerSecond * 0.7) + (instantSpeed * 0.3);
    }
    _downloadSpeedSampleAt = now;
    _downloadSpeedSampleBytes = currentBytes;
  }

  void clearDownload() {
    _downloadSpeedBytesPerSecond = 0;
    _downloadSpeedSampleBytes = 0;
    _downloadSpeedSampleAt = null;
  }
}
