// dense_work_state.dart — where a work stands with respect to the dense stage, read from its directory
// (so it survives an app restart). Build 174, user 2026-09-24:
//   「永远不会重新训练稠密。如果有那就是 bug」
//   「补拍只适用于稀疏阶段呀!当用户点击下一步的时候就回不去了呀!就是用户点击下一步的时候，数据采集
//    阶段就正式结束了」
//
//   notStarted        no sign of a dense run: capture/sparse entries (补拍, 重建, 选区编辑, 下一步) as before
//   startedIncomplete a dense run began (下一步 was tapped) but no complete official_dense.ply: the only thing
//                     left to do is to finish the dense stage (「完成稠密」, same selection as the first run);
//                     no 补拍 / 重建 / sparse editing — that is not a re-training, it never completed
//   done              complete official_dense.ply (header count fills the file): never trained again
//
// Evidence that a run began, any one suffices: the marker written when the launcher starts a run
// (dense_started.json, from build 174), the dense_work/ scratch the job leaves behind when it is killed
// (older builds), or an official_dense.ply of any length (only the dense job writes that file).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../official_capture/selection_box.dart';
import '../official_util/device_log.dart';
import '../point_cloud_lod/dense_lod_cache.dart' show densePlyComplete;
import '../pw38/cache_completion.dart';
import '../pw38/execution_identity_scope.dart';
import 'dense_stage_progress.dart';

const String kDensePlyFileName = 'official_dense.ply';
const String kDenseWorkDirName = 'dense_work';

/// Written by the dense launcher the moment a run really starts (inputs gathered, job about to begin).
const String kDenseStartedMarkerName = 'dense_started.json';

enum DenseWorkState { notStarted, startedIncomplete, done }

final _cacheProofs = <String, Pw38CacheCompletionProof>{};
final _cacheChecks = <String, Future<DenseWorkState>>{};
final _failedCacheChecks = <String, String>{};
final _deferredCacheStates =
    <
      String,
      ({
        String captureDir,
        DenseWorkState state,
        Pw38ExecutionIdentityScope scope,
      })
    >{};
bool _cacheHandoffScheduled = false;

String _captureKey(String path) => Directory(path).resolveSymbolicLinksSync();
String _cacheKey(String root, Pw38ExecutionIdentityScope scope) =>
    '$root|${jsonEncode(scope.toJson())}';
String _fileSignature(String path) {
  try {
    final stat = File(path).statSync();
    return '${stat.type}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:'
        '${stat.changed.microsecondsSinceEpoch}';
  } catch (_) {
    return 'UNREADABLE';
  }
}

String _failureDependencies(String root) =>
    '${_fileSignature('$root/$pw38CacheCompletionMarkerName')}|'
    '${_fileSignature('${Directory(root).parent.parent.path}/scan_records.json')}';

void _scheduleCacheHandoff() {
  if (_cacheHandoffScheduled ||
      denseStageProgress.value?.state == DenseStageState.running)
    return;
  _cacheHandoffScheduled = true;
  scheduleMicrotask(() {
    _cacheHandoffScheduled = false;
    if (denseStageProgress.value?.state == DenseStageState.running) return;
    if (_deferredCacheStates.isEmpty) return;
    final entry = _deferredCacheStates.entries.first;
    _deferredCacheStates.remove(entry.key);
    if (_deferredCacheStates.isEmpty) {
      denseStageProgress.removeListener(_scheduleCacheHandoff);
    }
    _notifyCacheState(
      entry.value.captureDir,
      entry.value.state,
      identityScope: entry.value.scope,
    );
    if (_deferredCacheStates.isNotEmpty) _scheduleCacheHandoff();
  });
}

void _notifyCacheState(
  String captureDir,
  DenseWorkState state, {
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) {
  final current = denseStageProgress.value;
  if (current?.state == DenseStageState.running) {
    if (_deferredCacheStates.isEmpty) {
      denseStageProgress.addListener(_scheduleCacheHandoff);
    }
    _deferredCacheStates[_cacheKey(captureDir, identityScope)] = (
      captureDir: captureDir,
      state: state,
      scope: identityScope,
    );
    return;
  }
  if (state == DenseWorkState.done) {
    try {
      if (_cacheProofs[_cacheKey(_captureKey(captureDir), identityScope)]
              ?.stillMatches() !=
          true) {
        state = DenseWorkState.startedIncomplete;
      }
    } catch (_) {
      state = DenseWorkState.startedIncomplete;
    }
  }
  denseStageProgress.value = DenseStageProgress(
    captureDir: captureDir,
    state: state == DenseWorkState.done
        ? DenseStageState.done
        : DenseStageState.failed,
    phase: state == DenseWorkState.done ? 'done' : 'cache_verification_failed',
    done: state == DenseWorkState.done ? 13 : 0,
    total: 13,
    // Retained pixels are not a dense cloud point count; outPly remains null.
    message: state == DenseWorkState.done ? null : '完整38缓存或成品核验未通过，保留原任务',
    finishedAt: DateTime.now(),
  );
}

/// Cold restart hashes cache, GLB, request and durable bindings off the UI
/// isolate. Explicit integrity rechecks never reuse an in-process proof.
Future<DenseWorkState> verifyDenseWorkStateOf(
  String captureDir, {
  bool recheck = false,
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) async {
  if (!File('$captureDir/$pw38CacheCompletionMarkerName').existsSync()) {
    return denseWorkStateOf(captureDir, identityScope: identityScope);
  }
  final root = _captureKey(captureDir);
  final key = _cacheKey(root, identityScope);
  final pending = _cacheChecks[key];
  if (pending != null) return pending;
  if (!recheck && _cacheProofs[key]?.stillMatches() == true) {
    _notifyCacheState(
      captureDir,
      DenseWorkState.done,
      identityScope: identityScope,
    );
    return DenseWorkState.done;
  }
  _cacheProofs.remove(key);
  // RecordStore may repair relocated paths while this worker is reading. Store
  // the dependencies observed before the attempt, so that repair cannot be
  // mistaken for the state which failed and permanently suppress the retry.
  final dependenciesAtStart = _failureDependencies(root);
  final scopeJson = identityScope.toJson();
  final check = () async {
    try {
      final proof = await Isolate.run(
        () => verifyPw38CacheCompletion(
          root,
          identityScope: Pw38ExecutionIdentityScope.fromJson(
            Map<String, dynamic>.from(scopeJson),
          ),
        ),
      );
      if (!proof.stillMatches())
        throw StateError('Completion changed after verification');
      _cacheProofs[key] = proof;
      _failedCacheChecks.remove(key);
      _notifyCacheState(
        captureDir,
        DenseWorkState.done,
        identityScope: identityScope,
      );
      return DenseWorkState.done;
    } catch (error) {
      _cacheProofs.remove(key);
      _failedCacheChecks[key] = dependenciesAtStart;
      DeviceLog.log('Full38', 'cache restart verification failed: $error');
      _notifyCacheState(
        captureDir,
        DenseWorkState.startedIncomplete,
        identityScope: identityScope,
      );
      return DenseWorkState.startedIncomplete;
    } finally {
      _cacheChecks.remove(key);
    }
  }();
  _cacheChecks[key] = check;
  return check;
}

/// The publisher calls this only after durable artifact attachment. A completion
/// marker cannot mark a run done until full byte verification finishes.
Future<void> writePw38CacheCompletedMarker({
  required String captureDir,
  required String workRoot,
  required String recordId,
  required String publishedGlbPath,
  required Map<String, Object?> receipt,
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) async {
  await identityScope.revalidate();
  identityScope.requireCapture(captureDir);
  final root = _captureKey(captureDir);
  final key = _cacheKey(root, identityScope);
  if (_cacheChecks.containsKey(key))
    throw StateError('Cache verification already active');
  final scopeJson = identityScope.toJson();
  final check = () async {
    await publishPw38CacheCompletion(
      captureDir: root,
      workRoot: workRoot,
      recordId: recordId,
      publishedGlbPath: publishedGlbPath,
      receipt: receipt,
      identityScope: identityScope,
    );
    final proof = await Isolate.run(
      () => verifyPw38CacheCompletion(
        root,
        identityScope: Pw38ExecutionIdentityScope.fromJson(
          Map<String, dynamic>.from(scopeJson),
        ),
      ),
    );
    if (!proof.stillMatches())
      throw StateError('Completion changed after publication');
    _cacheProofs[key] = proof;
    _failedCacheChecks.remove(key);
    return DenseWorkState.done;
  }();
  _cacheChecks[key] = check;
  try {
    await check;
  } finally {
    _cacheChecks.remove(key);
  }
}

DenseWorkState denseWorkStateOf(
  String captureDir, {
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) {
  final ply = '$captureDir/$kDensePlyFileName';
  if (!File('$captureDir/$pw38CacheCompletionMarkerName').existsSync() &&
      densePlyComplete(ply))
    return DenseWorkState.done;
  try {
    final root = _captureKey(captureDir);
    final key = _cacheKey(root, identityScope);
    identityScope.requireCapture(root);
    if (File('$root/$pw38CacheCompletionMarkerName').existsSync()) {
      if (_cacheProofs[key]?.stillMatches() == true) return DenseWorkState.done;
      _cacheProofs.remove(key);
      if (_failedCacheChecks[key] != _failureDependencies(root)) {
        // Defer notifications past the current widget build. Until bytes pass,
        // the marker closes capture but cannot claim completed output.
        unawaited(
          Future<void>(() async {
            await verifyDenseWorkStateOf(
              captureDir,
              identityScope: identityScope,
            );
          }),
        );
      }
      return DenseWorkState.startedIncomplete;
    }
    if (File('$captureDir/$kDenseStartedMarkerName').existsSync() ||
        Directory('$captureDir/$kDenseWorkDirName').existsSync() ||
        File(ply).existsSync()) {
      return DenseWorkState.startedIncomplete;
    }
  } catch (_) {
    if (File('$captureDir/$pw38CacheCompletionMarkerName').existsSync()) {
      return DenseWorkState.startedIncomplete;
    }
  }
  return DenseWorkState.notStarted;
}

/// Presentation/navigation uses a completed artifact only while an actual
/// byte-verified proof and its durable record attachment still match.
({String recordId, String glbPath})? verifiedPw38CacheArtifact(
  String captureDir, {
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) {
  try {
    final proof =
        _cacheProofs[_cacheKey(_captureKey(captureDir), identityScope)];
    if (proof != null && proof.stillMatches()) {
      return (recordId: proof.recordId, glbPath: proof.publishedGlb);
    }
    denseWorkStateOf(
      captureDir,
      identityScope: identityScope,
    ); // May schedule cold/repaired-binding validation.
  } catch (_) {}
  return null;
}

/// 下一步 was tapped for this work at some point (running, killed, failed or done): the capture stage
/// is over — no 补拍, no 重建, no sparse editing.
bool denseStageEntered(String captureDir) =>
    denseWorkStateOf(captureDir) != DenseWorkState.notStarted;

/// Why a capture/sparse entry (补拍, 继续/重新重建, 从照片重建) must not open for [captureDir], or null.
/// Routes and the gallery card call this before pushing anything.
String? recaptureBlockedReason(String captureDir) =>
    switch (denseWorkStateOf(captureDir)) {
      DenseWorkState.notStarted => null,
      DenseWorkState.startedIncomplete =>
        'dense stage entered (下一步 tapped, not finished): only 完成稠密 is allowed',
      DenseWorkState.done => 'dense stage done: the capture stage is closed',
    };

/// The long-press menu's 「开始训练 / 拍摄更多照片」 (both go back to capture or sparse): only for a work
/// that has no sparse cloud yet AND never entered the dense stage.
bool showRecaptureEntries({
  required bool canViewSparse,
  required bool denseEntered,
}) => !canViewSparse && !denseEntered;

/// The launcher's record of a run that starts. Never deleted: it is the proof, after a restart, that
/// the capture stage is over. [selection] = the box the run was asked for (null = the whole cloud), so
/// 「完成稠密」 later runs on the same selection.
void writeDenseStartedMarker(
  String captureDir, {
  required SelectionBox? selection,
  required int sparsePoints,
  bool requirePersistence = false,
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) {
  try {
    identityScope.requireCapture(captureDir);
    final f = File('$captureDir/$kDenseStartedMarkerName');
    final contents = jsonEncode(<String, Object?>{
      'schema': 'pw_dense_started/1',
      if (identityScope.isIndependentTest) ...{
        'bundle_id': identityScope.bundleId,
        'build': identityScope.build,
        'identity_scope': identityScope.toJson(),
      },
      'started_at': DateTime.now().toIso8601String(),
      'sparse_points': sparsePoints,
      'selection': selection?.toJson(),
    });
    f.writeAsStringSync(contents, flush: true);
    if (requirePersistence && f.readAsStringSync() != contents) {
      throw StateError('Dense start marker was not durably saved');
    }
  } catch (e) {
    // The job still runs; dense_work/ (made by the job) remains as evidence if it is killed.
    DeviceLog.log('DenseStage', 'could not write $kDenseStartedMarkerName: $e');
    if (requirePersistence) rethrow;
  }
}

/// The selection to finish an interrupted dense run with: the marker's (what the first run was asked
/// for); for a run started by a build without the marker, the box saved in the work directory.
Future<SelectionBox?> denseResumeSelection(String captureDir) async {
  try {
    final f = File('$captureDir/$kDenseStartedMarkerName');
    if (f.existsSync()) {
      final j = jsonDecode(f.readAsStringSync());
      if (j is Map) return SelectionBox.fromJson(j['selection']);
    }
  } catch (_) {}
  return SelectionBox.loadFrom(captureDir);
}
