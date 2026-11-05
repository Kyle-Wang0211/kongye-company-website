import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../me/cloud_library.dart';
import '../me/scan_record_store.dart';
import '../official_util/device_log.dart';
import '../official_capture/capture_archive_service.dart';
import '../official_capture/photo_archive_runtime.dart';
import '../pw38/capture_artifact_retirement.dart';
import '../pw38/pending_capture_retirement.dart';
import '../ui/shared/product_preview_cover.dart';
import 'pw38_final_record_artifact.dart';
import 'pw38_generated_consumer_leases.dart';

/// Publishes no new model and executes no reconstruction. Only a durable final
/// record can authorize retiring its old capture. A persisted original manifest
/// remains until both deletion and the account-record commit have completed.
final class Pw38CaptureRetirement {
  Pw38CaptureRetirement({
    required this.store,
    required this.drainPipelineReaders,
    this.suspendArchivesForTesting,
    this.drainCaptureArchiveForTesting,
    this.drainCloudReadsForTesting,
    this.onFinalCoverWaitForTesting,
  });

  final ScanRecordStore store;
  final Future<void> Function() drainPipelineReaders;
  final Future<Future<void> Function()> Function()? suspendArchivesForTesting;
  final Future<void> Function(String)? drainCaptureArchiveForTesting;
  final Future<void> Function(String)? drainCloudReadsForTesting;
  final void Function()? onFinalCoverWaitForTesting;
  static final _running = <String, Future<CaptureRetirementResult>>{};

  static final _publishing = <String>{};
  static final _coverContinuations =
      <String, Future<CaptureRetirementResult?>>{};

  /// Existing completion observers can await deferred cleanup without checking
  /// the capture before its legitimate final-frame callback has finished.
  Future<CaptureRetirementResult?> waitForCompletion(String recordId) async {
    final root = await store.accountDocumentsDirectory();
    final key = '${await root.resolveSymbolicLinks()}/$recordId';
    final running = _running[key];
    final result = running == null ? null : await running;
    if (result?.completed == true) return result;
    final deferred = _coverContinuations[key];
    return deferred == null ? result : await deferred;
  }

  /// A final GLB can publish before its existing shared renderer's first frame.
  /// Keep the capture writable until that exact renderer has attached its PNG.
  void _resumeAfterFinalCover(
    String id,
    String capturePath,
    String identity,
    String key,
  ) {
    if (_coverContinuations.containsKey(key)) return;
    late final Future<CaptureRetirementResult?> continuation;
    continuation = Pw38GeneratedConsumerLeases.instance
        .waitForFinalCover(capturePath, identity)
        .then<CaptureRetirementResult?>((_) async {
          final previous = _running[key];
          if (previous != null) await previous;
          if (!store.isActive) return null;
          final current = store.byId(id);
          if (current == null ||
              current.captureDir != capturePath ||
              current.artifactPath == null ||
              '${Uri.parse(current.artifactPath!).scheme == 'file' ? Uri.parse(current.artifactPath!).toFilePath() : current.artifactPath}:${current.finalGlbSha256}' !=
                  identity)
            return null;
          return await retire(recordId: id, captureDir: capturePath);
        })
        .catchError((Object error, StackTrace stack) {
          DeviceLog.log(
            'Full38',
            'final cover ready; cleanup retained record=$id: $error',
          );
          return null;
        })
        .whenComplete(() {
          if (identical(_coverContinuations[key], continuation)) {
            _coverContinuations.remove(key);
          }
        });
    _coverContinuations[key] = continuation;
  }

  /// Covers the complete live producer/publication interval, including the gap
  /// before the original deletion manifest exists. Re-entry cannot race it.
  static Future<void Function()> holdPublication(
    ScanRecordStore store,
    String recordId,
  ) async {
    final root = await store.accountDocumentsDirectory();
    final key = '${await root.resolveSymbolicLinks()}/$recordId';
    if (!_publishing.add(key)) throw StateError('Publication already active');
    var released = false;
    return () {
      if (!released) {
        released = true;
        _publishing.remove(key);
      }
    };
  }

  /// Resume an original manifest, or finish the pre-manifest publication gap.
  /// Only the new persisted account-bound GLB proof authorizes the latter;
  /// legacy captures and a still-running producer are never scanned/deleted.
  Future<CaptureRetirementResult?> resumePending(String recordId) async {
    final record = store.byId(recordId);
    if (record == null || !hasPw38FinalRecordProof(record)) return null;
    final proof = await verifyPw38FinalRecordArtifact(store, record);
    final root = Directory(
      await (await store.accountDocumentsDirectory()).resolveSymbolicLinks(),
    );
    if (_publishing.contains('${root.path}/$recordId')) return null;
    final pending = PendingCaptureRetirementStore(
      accountRoot: root,
      accountNamespace: proof.accountNamespace,
      recordId: recordId,
    );
    final token = await pending.load(
      requirePublicationAndConsumersDrained: () async {
        final current = store.byId(recordId);
        if (!store.isActive ||
            current == null ||
            !pw38FinalRecordProofMatches(current, proof)) {
          throw StateError('Pending final model identity changed');
        }
      },
    );
    if (token == null) {
      final capture = record.captureDir;
      if (capture == null ||
          record.localRawDeletedAt != null ||
          !await Directory(capture).exists())
        return null;
      // A previously attached model may have lost power or a reader drain may
      // have failed before prepare(). No training is needed to retire it.
      return retire(recordId: recordId, captureDir: capture);
    }
    return retire(
      recordId: recordId,
      captureDir: pending.captureRootFor(token).path,
    );
  }

  Future<CaptureRetirementResult> retire({
    required String recordId,
    required String captureDir,
  }) async {
    final root = await store.accountDocumentsDirectory();
    final key = '${await root.resolveSymbolicLinks()}/$recordId';
    final existing = _running[key];
    if (existing != null) return existing;
    final operation = _retire(recordId, captureDir);
    _running[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_running[key], operation)) _running.remove(key);
    }
  }

  Future<CaptureRetirementResult> _retire(String id, String capturePath) async {
    final record = store.byId(id);
    if (record == null) throw StateError('Completed record disappeared');
    final proof = await verifyPw38FinalRecordArtifact(store, record);
    await store.requireOwnedPath(capturePath);
    final input = Directory(capturePath);
    final capture = Directory(
      '${await input.parent.resolveSymbolicLinks()}/'
      '${input.uri.pathSegments.where((s) => s.isNotEmpty).last}',
    );
    final root = Directory(
      await (await store.accountDocumentsDirectory()).resolveSymbolicLinks(),
    );
    final pending = PendingCaptureRetirementStore(
      accountRoot: root,
      accountNamespace: proof.accountNamespace,
      recordId: id,
    );
    if (capture.path != '${root.path}/captures_official/$id') {
      throw StateError('Capture is outside the completed record namespace');
    }
    if (record.captureDir == null &&
        record.localRawDeletedAt != null &&
        !await capture.exists() &&
        !await File('${root.path}/.pw_capture_retirement/$id.json').exists()) {
      return const CaptureRetirementResult(
        completed: true,
        deletedPaths: [],
        alreadyAbsentPaths: [],
        pendingPaths: [],
        failures: {},
        deletedBytes: 0,
      );
    }
    void requireCurrent() {
      final current = store.byId(id);
      if (!store.isActive ||
          current == null ||
          !pw38FinalRecordProofMatches(current, proof)) {
        throw StateError('Final record changed during capture retirement');
      }
    }

    // Never retire a final model's only canonical-camera cover. The shared
    // reader rejects sparse/old-run covers and checks the selected GLB file.
    var latest = store.byId(id)!;
    final destination = File('${root.path}/scans_official/$id.png');
    await store.requireOwnedPath(destination.path);
    final existingCoverIsDurable =
        latest.thumbnailPath == destination.path &&
        latest.finalCoverGlbSha256 == proof.sha256Hex &&
        latest.finalCoverSha256 != null &&
        await destination.exists() &&
        (await sha256.bind(destination.openRead()).first).toString() ==
            latest.finalCoverSha256;
    if (!existingCoverIsDurable) {
      var cover = productPreviewCoverFor(latest);
      if (cover == null) {
        try {
          final ready = Pw38GeneratedConsumerLeases.instance.waitForFinalCover(
            capture.path,
            '${proof.publishedGlb}:${proof.sha256Hex}',
          );
          onFinalCoverWaitForTesting?.call();
          await ready.timeout(const Duration(seconds: 30));
          requireCurrent();
          latest = store.byId(id)!;
          cover = productPreviewCoverFor(latest);
        } on TimeoutException {
          // Generation is complete; a hidden or not-yet-ready renderer may
          // still deliver its first frame later through the same callback.
        }
      }
      if (cover == null || !cover.path.startsWith('${capture.path}/')) {
        final key = '${root.path}/$id';
        _resumeAfterFinalCover(
          id,
          capture.path,
          '${proof.publishedGlb}:${proof.sha256Hex}',
          key,
        );
        return const CaptureRetirementResult(
          completed: false,
          deletedPaths: [],
          alreadyAbsentPaths: [],
          pendingPaths: ['final_cover'],
          failures: {},
          deletedBytes: 0,
        );
      }
      final selectedCover = cover;
      final hash = (await sha256.bind(selectedCover.openRead()).first)
          .toString();
      final stage = File('${destination.path}.pending');
      await store.requireOwnedPath(stage.path);
      // Copy byte-for-byte; no decode, recompression, rendering or new view.
      final sink = stage.openWrite();
      try {
        await sink.addStream(selectedCover.openRead());
        await sink.flush();
      } finally {
        await sink.close();
      }
      // Use a flushed file copy before publishing its stable account path.
      final staged = stage.openSync(mode: FileMode.append);
      try {
        staged.flushSync();
      } finally {
        staged.closeSync();
      }
      requireCurrent();
      if ((await sha256.bind(stage.openRead()).first).toString() != hash) {
        throw StateError('Final cover copy changed; capture retained');
      }
      await stage.rename(destination.path);
      if (!await store.attachPreviewThumbnail(
        expected: latest,
        thumbnailPath: destination.path,
        isCurrent: () {
          requireCurrent();
          return productPreviewCoverFor(latest)?.path == selectedCover.path;
        },
        finalCoverSha256: hash,
        finalCoverGlbSha256: proof.sha256Hex,
      )) {
        throw StateError('Final cover record changed; capture retained');
      }
    }

    Future<void> Function()? releaseArchives;
    try {
      if (suspendArchivesForTesting != null) {
        releaseArchives = await suspendArchivesForTesting!();
      } else {
        final archive = photoArchiveCoordinatorFor(store);
        final lease = archive.beginProcessingActivity();
        releaseArchives = lease.close;
        await archive.waitForIdle();
      }
      // Recovery also drains any known old preview streams in this process.
      await Pw38GeneratedConsumerLeases.instance
          .closeCaptureOffersAndWaitForIdle(capture.path);
      await drainPipelineReaders();
      if (await capture.exists()) {
        await (drainCaptureArchiveForTesting ??
            CaptureArchiveService.instance.waitForCaptureIdle)(capture.path);
      }
      requireCurrent();
      final cloudDrain = drainCloudReadsForTesting;
      if (cloudDrain != null) {
        await cloudDrain(id);
      } else {
        await CloudLibrary.forStore(store)?.retireCaptureSourcesFor(id);
      }
      requireCurrent();
      requireCurrent();
      // The old card-photo copy belongs to this work too. Only discard it
      // after the final cover record commit has succeeded.
      final oldPhotoCover = await store.thumbnailFileFor(
        id,
        pipelineKind: record.pipelineKind,
      );
      await store.requireOwnedPath(oldPhotoCover.path);
      if (await oldPhotoCover.exists()) await oldPhotoCover.delete();
      requireCurrent();
      final token = await pending.prepare(
        captureRoot: capture,
        publishedGlb: File(proof.publishedGlb),
        expectedGlbSha256: proof.sha256Hex,
        expectedGlbBytes: proof.bytes,
        requirePublicationAndConsumersDrained: () async => requireCurrent(),
      );
      final result = await pending.resume(
        requirePublicationAndConsumersDrained: () async => requireCurrent(),
      );
      if (result == null || !result.completed) {
        throw StateError('Capture cleanup pending: ${result?.failures}');
      }
      requireCurrent();
      await store.retireCaptureMetadataAfterGlbValidation(
        id: id,
        captureDir: capture.path,
        artifactPath: store.byId(id)!.artifactPath!,
        expectedSha256: proof.sha256Hex,
        expectedBytes: proof.bytes,
        pendingToken: token,
      );
      await pending.finish(
        requireStoreCommittedAndConsumersDrained: () async {
          requireCurrent();
          if (store.byId(id)!.captureDir != null) {
            throw StateError('Capture metadata has not committed retirement');
          }
        },
      );
      return result;
    } finally {
      await releaseArchives?.call();
    }
  }
}
