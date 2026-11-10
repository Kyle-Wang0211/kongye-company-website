import 'dart:async';

import 'package:path_provider/path_provider.dart';

import 'worker_storage_query.dart';

const int minimumCaptureStorageBytes = 5000000000;
const String captureStorageInsufficientMessage = '存储空间不足，请先清理至至少5 GB';
const String captureStorageUnavailableMessage = '无法读取可用存储空间，请稍后重试';

/// Query the actual Documents filesystem through the verified libc disk API.
/// The existing path_provider locates the app sandbox; no new plugin is needed.
/// [path] optionally selects an existing capture/output directory on that disk.
Future<int> readAvailableStorage({String? path}) async {
  final directory = path ?? (await getApplicationDocumentsDirectory()).path;
  return readAvailableStorageInWorker(directory);
}

class CaptureStorageDecision {
  const CaptureStorageDecision._({
    required this.allowed,
    this.availableBytes,
    this.message,
    this.obsolete = false,
  });

  final bool allowed;
  final int? availableBytes;
  final String? message;

  /// A newer request, cancelled navigation, or disposal superseded this check.
  /// Callers should silently discard it rather than display a stale error.
  final bool obsolete;
}

/// Own one instance per capture-entry State; dispose it with that State.
/// Call [check] immediately before *each* new/resumed capture start, and pass
/// the page's current/mounted predicate. Do not cache an allowed decision.
class CaptureStorageAdmission {
  CaptureStorageAdmission({Future<int> Function()? readBytes})
    : _readBytes = readBytes ?? readAvailableStorage;

  final Future<int> Function() _readBytes;
  int _request = 0;
  bool _disposed = false;

  void cancelPending() => _request++;

  void dispose() {
    _disposed = true;
    cancelPending();
  }

  Future<CaptureStorageDecision> check({bool Function()? isCurrent}) async {
    final request = ++_request;
    bool current() =>
        !_disposed && request == _request && (isCurrent?.call() ?? true);
    if (!current()) {
      return const CaptureStorageDecision._(allowed: false, obsolete: true);
    }
    try {
      final bytes = await _readBytes().timeout(const Duration(seconds: 3));
      if (!current()) {
        return const CaptureStorageDecision._(allowed: false, obsolete: true);
      }
      if (bytes < 0) {
        throw const FormatException('Negative available disk bytes');
      }
      return CaptureStorageDecision._(
        allowed: bytes >= minimumCaptureStorageBytes,
        availableBytes: bytes,
        message: bytes < minimumCaptureStorageBytes
            ? captureStorageInsufficientMessage
            : null,
      );
    } catch (_) {
      if (!current()) {
        return const CaptureStorageDecision._(allowed: false, obsolete: true);
      }
      return const CaptureStorageDecision._(
        allowed: false,
        message: captureStorageUnavailableMessage,
      );
    }
  }
}
