import 'dart:convert';
import 'dart:io';

import '../../official_capture/dense_stage.dart';

/// A new capture must finish both persistence operations before its one launch.
/// Reopening resumes only an explicitly persisted Finish intent.
final class Automatic38Flow {
  static const intentFileName = 'pw38_automatic_intent_v1.json';
  String? _captureDir;
  bool _sparsePersisted = false;
  bool _draftPersisted = false;
  bool _attempted = false;
  bool _starting = false;
  bool _rejected = false;

  bool get canRetry => _rejected && !_starting;
  bool get armed => _captureDir != null;
  bool get pending =>
      _starting || (_captureDir != null && !_attempted && _sparsePersisted);

  /// A tiny orchestration record, not a numerical checkpoint. Call only after
  /// the account-owned capture path has been checked by the existing route.
  void persistIntent(String captureDir) {
    if (_captureDir != captureDir) {
      throw StateError('Automatic38 intent does not belong to this capture');
    }
    final directory = Directory(captureDir);
    if (FileSystemEntity.typeSync(captureDir, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Automatic38 intent requires a real capture directory');
    }
    final target = '$captureDir/$intentFileName';
    final temporary = '$target.pending';
    for (final path in [target, temporary]) {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw StateError('Automatic38 intent path is not a regular file');
      }
    }
    File(temporary).writeAsStringSync(
      jsonEncode({
        'schema': 'pw38_automatic_intent/1',
        'capture_name': directory.uri.pathSegments
            .where((v) => v.isNotEmpty)
            .last,
        'pipeline': 'original38',
      }),
      flush: true,
    );
    File(temporary).renameSync(target);
  }

  /// No marker means historical material. Inputs must separately be verified
  /// by the owning page; the marker alone never grants permission to launch.
  bool restoreIntent(String captureDir, {required bool inputsPersisted}) {
    if (!inputsPersisted) return false;
    final directory = Directory(captureDir);
    if (FileSystemEntity.typeSync(captureDir, followLinks: false) !=
        FileSystemEntityType.directory) {
      return false;
    }
    final path = '$captureDir/$intentFileName';
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    final file = File(path);
    if (file.lengthSync() > 4096) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return false;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 3 ||
        decoded['schema'] != 'pw38_automatic_intent/1' ||
        decoded['pipeline'] != 'original38' ||
        decoded['capture_name'] !=
            directory.uri.pathSegments.where((v) => v.isNotEmpty).last) {
      return false;
    }
    arm(captureDir);
    sparsePersisted(captureDir);
    draftPersisted(captureDir);
    return true;
  }

  void arm(String captureDir) {
    if (_captureDir == captureDir) return;
    _captureDir = captureDir;
    _sparsePersisted = false;
    _draftPersisted = false;
    _attempted = false;
    _rejected = false;
  }

  void sparsePersisted(String captureDir) {
    if (_captureDir == captureDir) _sparsePersisted = true;
  }

  void draftPersisted(String captureDir) {
    if (_captureDir == captureDir) _draftPersisted = true;
  }

  Future<DenseStageResult?> startIfReady({
    required String captureDir,
    required bool readOnly,
    required bool denseEntered,
    required int pointCount,
    required DenseStageLauncher launcher,
    Future<void> Function()? beforeStart,
    bool userInitiated = false,
  }) async {
    if (readOnly ||
        denseEntered ||
        _captureDir != captureDir ||
        !_sparsePersisted ||
        !_draftPersisted ||
        _starting ||
        (_attempted && !(userInitiated && canRetry)) ||
        pointCount <= 0) {
      return null;
    }
    // Set before the first await: repeated snapshots cannot launch in parallel.
    _attempted = true;
    if (!launcher.isAvailable) {
      _rejected = true;
      return const DenseStageResult(
        DenseStageStatus.failed,
        message: '完整38处理引擎暂不可用，素材已保留；可稍后继续处理',
      );
    }
    _starting = true;
    _rejected = false;
    try {
      await beforeStart?.call();
      final result = await launcher.start(
        DenseStageRequest(
          captureDir: captureDir,
          sparsePlyPath: '$captureDir/official_sfm_sparse.ply',
          pointCount: pointCount,
          selection: null,
        ),
      );
      _rejected = result.status != DenseStageStatus.started;
      if (!_rejected) {
        // The production launcher publishes its durable dense marker before
        // accepting. Keep this intent on every rejection or IO failure.
        final intent = '$captureDir/$intentFileName';
        try {
          if (FileSystemEntity.typeSync(intent, followLinks: false) ==
              FileSystemEntityType.file) {
            File(intent).deleteSync();
          }
        } on FileSystemException {
          // The real dense marker still prevents a duplicate launch.
        }
      }
      return result;
    } catch (_) {
      _rejected = true;
      rethrow;
    } finally {
      _starting = false;
    }
  }

  /// Only the explicit recovery button can retry a rejected pre-authorization
  /// launch. A durable dense marker always takes precedence over this path.
  Future<DenseStageResult?> retryRejectedStart({
    required String captureDir,
    required bool readOnly,
    required bool denseEntered,
    required int pointCount,
    required DenseStageLauncher launcher,
    Future<void> Function()? beforeStart,
  }) async {
    if (!canRetry) {
      return null;
    }
    return startIfReady(
      captureDir: captureDir,
      readOnly: readOnly,
      denseEntered: denseEntered,
      pointCount: pointCount,
      launcher: launcher,
      beforeStart: beforeStart,
      userInitiated: true,
    );
  }
}
