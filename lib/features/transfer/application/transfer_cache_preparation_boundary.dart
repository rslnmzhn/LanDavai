import 'package:flutter/foundation.dart';

import 'transfer_cache_preparation_models.dart';

class TransferCachePreparationBoundary extends ChangeNotifier {
  TransferCachePreparationBoundary();

  SharedDownloadPreparationState? _downloadPreparationState;
  SharedUploadPreparationState? _uploadPreparationState;

  SharedDownloadPreparationState? get sharedDownloadPreparationState =>
      _downloadPreparationState;

  bool get isPreparingSharedDownload => _downloadPreparationState != null;

  SharedUploadPreparationState? get sharedUploadPreparationState =>
      _uploadPreparationState;

  bool get isPreparingSharedUpload => _uploadPreparationState != null;

  void setDownloadPreparation({
    required String requestId,
    required String ownerName,
    required SharedDownloadPreparationStage stage,
  }) {
    _downloadPreparationState = SharedDownloadPreparationState(
      requestId: requestId,
      ownerName: ownerName,
      stage: stage,
    );
    notifyListeners();
  }

  void clearDownloadPreparation({String? requestId}) {
    final current = _downloadPreparationState;
    if (current == null ||
        (requestId != null && current.requestId != requestId)) {
      return;
    }
    _downloadPreparationState = null;
    notifyListeners();
  }

  void setUploadPreparation({
    required String requestId,
    required String requesterName,
    required SharedUploadPreparationStage stage,
  }) {
    _uploadPreparationState = SharedUploadPreparationState(
      requestId: requestId,
      requesterName: requesterName,
      stage: stage,
    );
    notifyListeners();
  }

  void clearUploadPreparation({String? requestId}) {
    final current = _uploadPreparationState;
    if (current == null ||
        (requestId != null && current.requestId != requestId)) {
      return;
    }
    _uploadPreparationState = null;
    notifyListeners();
  }
}
