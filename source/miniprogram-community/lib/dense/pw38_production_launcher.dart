import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../me/scan_record_store.dart';
import '../pw38/execution_identity_scope.dart';
import '../pw38/cache_completion.dart'
    show pw38CacheCompletionMarkerName, publishPw38CacheCompletion;
import '../pw38/production_result_contract.dart';
import '../pw38/generated_artifact_retirement.dart';
import 'pw38_generated_consumer_leases.dart';
import 'pw38_capture_retirement.dart';
import 'pw38_final_record_artifact.dart' show hasPw38FinalRecordProof;
import '../official_capture/dense_stage.dart';
import '../official_util/device_log.dart';
import '../official_util/capture_storage_admission.dart';
import '../pw38/whole_disk_admission.dart';
import '../point_cloud_lod/dense_lod_cache.dart' show densePlyPoints;
import '../ui/scan_record.dart';
import 'dense_stage_progress.dart';
import 'dense_work_state.dart';
import 'native_dense_stage_launcher.dart';
import 'pw_dense_ffi.dart' show PwDenseFrame;
import 'pw38_preview_artifact.dart';
import 'pw38_background_execution.dart';

/// Durable run namespace, disjoint from legacy scratch cleanup roots.
const kPw38FullRunsDirName = 'pw38_full_runs_v1';

/// Same selected order as the recovered original38 shared pipeline. These are
/// checked against actual engine receipts, never synthesized from progress.
const pw38ProductionStageOrder = <String>[
  'mvs768',
  'mvs1536',
  'cer',
  'fusionPly',
  'tsdf',
  'trim',
  'meshopt',
  'lagrange',
  'texture',
  'avVisibility',
  'avSfmToAbc',
  'avNormal',
  'glb',
];

typedef Pw38ProductionProgress = void Function(
  String phase,
  int done,
  int total,
);

/// The integration adapter must execute the complete shared engine on its
/// worker/async execution path and await actual native completion. This launcher
/// provides capture IO and persistence only; there is no legacy dense fallback.
abstract interface class Pw38FullPipelineRunner {
  bool get isAvailable;
  Future<Pw38PipelineResult> run({
    required DenseStageRequest request,
    required DenseStageInputs inputs,
    required String workDir,
    required Pw38ProductionProgress onProgress,
  });
}

/// Shared actual-N runners defer version-specific count checks to the measured
/// package/preparer; historical runners retain their exact97 gather contract.
abstract interface class Pw38ActualFramePipelineRunner
    implements Pw38FullPipelineRunner {}

/// Optional capability of the actual implementation AND its measured package.
/// Historical/mock runners keep their cold fallback without opting in.
abstract interface class Pw38RetirementDiskPipelineRunner
    implements Pw38ActualFramePipelineRunner {
  Future<bool> get hasVerifiedFeatureRetirement;
}

const _retirementConsumerPath =
    'Frameworks/libpw38ContinuousMvsMatchedWholeCut27V24.dylib';
const _retirementConsumerSha =
    '0ac58ae11d61d91fd551140e0623e46549d9e4a5f6c31652ed917272404fd8ae';
const _retirementPythonLeaves = [
  'production_whole_driver.py',
  'production_disk_guard.py',
  'prefix_disk_retirement.py',
];
const _retirementPythonPrefix =
    'Frameworks/PW38PythonExtensions/pw38_production_whole/';

bool pw38RetirementClosureMatches(
  Map<String, dynamic> profile, {
  required Map<String, String> actualSourceHashes,
  required String actualConsumerSha256,
}) {
  final pins = profile['source_pins'], python = profile['python_bindings'];
  final bindings = profile['bindings'];
  if (pins is! Map || python is! Map || bindings is! Map) return false;
  final consumer = bindings['consumer'];
  if (consumer is! Map ||
      consumer['path'] != _retirementConsumerPath ||
      consumer['sha256'] != _retirementConsumerSha ||
      actualConsumerSha256 != _retirementConsumerSha)
    return false;
  for (final leaf in _retirementPythonLeaves) {
    final rel = '$_retirementPythonPrefix$leaf';
    final hash = actualSourceHashes[rel];
    if (hash == null || pins[rel] != hash || python[rel] != hash) return false;
  }
  return true;
}

Future<bool> verifyPw38RetirementBudgetPackage(
  Pw38ExecutionIdentityScope scope,
) async {
  await scope.revalidate();
  Directory? root = scope.bundleRoot == null
      ? null
      : Directory(scope.bundleRoot!);
  if (root == null) {
    var candidate = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) {
      if (await File('${candidate.path}/pw38_production/PACKAGE.json')
          .exists()) {
        root = candidate;
        break;
      }
      if (candidate.parent.path == candidate.path) break;
      candidate = candidate.parent;
    }
  }
  if (root == null) return false;
  final base = await root.resolveSymbolicLinks();
  Future<List<int>?> regular(String rel) async {
    final f = File('$base/$rel');
    if (await FileSystemEntity.type(f.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await f.resolveSymbolicLinks() != f.path)
      return null;
    return f.readAsBytes();
  }

  final packageBytes = await regular('pw38_production/PACKAGE.json');
  final profileBytes = await regular('pw38_production/WHOLE_PROFILE.json');
  if (packageBytes == null || profileBytes == null) return false;
  final package = jsonDecode(utf8.decode(packageBytes));
  if (package is! Map ||
      package['whole_profile_sha256'] !=
          sha256.convert(profileBytes).toString())
    return false;
  final profile = jsonDecode(utf8.decode(profileBytes));
  if (profile is! Map<String, dynamic>) return false;
  final hashes = <String, String>{};
  for (final leaf in _retirementPythonLeaves) {
    final rel = '$_retirementPythonPrefix$leaf';
    final bytes = await regular(rel);
    if (bytes == null) return false;
    hashes[rel] = sha256.convert(bytes).toString();
  }
  final native = await regular(_retirementConsumerPath);
  return native != null &&
      pw38RetirementClosureMatches(
        profile,
        actualSourceHashes: hashes,
        actualConsumerSha256: sha256.convert(native).toString(),
      );
}

Future<int> pw38ActiveDiskBudgetForRunner(
  Pw38FullPipelineRunner runner,
  int frames, {
  int Function(int)? overrideBudget,
}) async {
  if (overrideBudget != null) return overrideBudget(frames);
  final qualified =
      runner is Pw38RetirementDiskPipelineRunner &&
      await runner.hasVerifiedFeatureRetirement;
  return wholePrefixDiskBudget(
    frames,
    manifestBytes: 0, // Original inputs already occupy actual filesystem space.
    featureRetirementEnabled: qualified,
  )['required_free_bytes']!;
}

/// Optional display transport; legacy/test runners keep their existing API.
abstract interface class Pw38VisualPipelineRunner
    implements Pw38FullPipelineRunner {
  Future<Pw38PipelineResult> runWithVisuals({
    required DenseStageRequest request,
    required DenseStageInputs inputs,
    required String workDir,
    required Pw38ProductionProgress onProgress,
    void Function(Pw38PreviewArtifact artifact)? onPreview,
  });
}

/// Whole-owner observational events carry their native source clock pair.
/// Existing runners and the native three-argument callback ABI stay unchanged.
abstract interface class Pw38TimedVisualPipelineRunner
    implements Pw38VisualPipelineRunner {
  Future<Pw38PipelineResult> runWithTimedVisuals({
    required DenseStageRequest request,
    required DenseStageInputs inputs,
    required String workDir,
    required Pw38ProductionProgress onProgress,
    required void Function(String, int, int, DenseProgressSourceTime)
    onTimedProgress,
    void Function(Pw38PreviewArtifact artifact)? onPreview,
  });
}

/// Actual engine result plus absolute paths resolved by its artifact gate.
/// [receipt] is the complete runOfficialReconstruction result, including observed
/// SHA-256/size rows and terminal_glb_format_validation from its existing parser.
final class Pw38PipelineResult {
  Pw38PipelineResult.fromReceipt(
    this.receipt, {
    required String workRoot,
    this.identityScope = Pw38ExecutionIdentityScope.production,
  }) : outputs = Pw38ProductionOutputContract.fromReceipt(
         receipt,
         workRoot: workRoot,
         identityScope: identityScope,
       );
  final Pw38ExecutionIdentityScope identityScope;
  final Map<String, Object?> receipt;
  final Pw38ProductionOutputContract outputs;
  String get glbPath => outputs.glb.path;
  Pw38DenseOutput get denseOutput => outputs.dense;
}

/// Production capture -> original97 full38 -> actual record's local GLB.
/// Scratch, retained depths and restored JPEGs remain intact on every terminal
/// path. Recovery is a new, bound attempt from the dense-stage origin; no native
/// checkpoint resume or automatic cleanup is claimed.
final class Pw38ProductionLauncher implements DenseStageRecoveryLauncher {
  Pw38ProductionLauncher({
    required this.runner,
    NativeDenseStageLauncher? inputGatherer,
    ScanRecordStore? store,
    this.identityScope = Pw38ExecutionIdentityScope.production,
    this.recoveryPersistenceCheckpoint,
    Pw38BackgroundCoordinator? background,
    Future<int> Function()? readStorageBytes,
    int Function(int frames)? storageBudget,
  }) : _storageBudget = storageBudget,
       _readStorageBytes = readStorageBytes ?? readAvailableStorage,
       _gatherer = inputGatherer ?? NativeDenseStageLauncher(),
       _store = store ?? ScanRecordStore.instance,
       _background = background ?? Pw38BackgroundCoordinator.instance;

  final Future<int> Function() _readStorageBytes;
  final int Function(int frames)? _storageBudget;
  final Pw38FullPipelineRunner runner;
  final Pw38ExecutionIdentityScope identityScope;
  final NativeDenseStageLauncher _gatherer;
  final ScanRecordStore _store;
  final Pw38BackgroundCoordinator _background;

  /// Fault-injection seam for persistence tests; production leaves this null.
  /// Called only before/after durable IO, never from any numerical operation.
  final void Function(String checkpoint)? recoveryPersistenceCheckpoint;
  static bool _running = false;
  static bool _requiresProcessRestart = false;
  Future<void>? _completion;

  /// Completes after persistence and terminal progress (including failures).
  Future<void>? get completion => _completion;

  @override
  bool get isAvailable => runner.isAvailable;

  @override
  Future<DenseStageResult> start(DenseStageRequest request) async {
    final result = await _start(request, recovering: false);
    if (result.status != DenseStageStatus.started) {
      await _background.abandonBeforeStart(request.captureDir);
    }
    return result;
  }

  @override
  Future<DenseStageResult> recover(DenseStageRequest request) async {
    final plan = await inspectRecovery(request);
    if (!plan.canRecover) {
      await _background.abandonBeforeStart(request.captureDir);
      return DenseStageResult(DenseStageStatus.failed, message: plan.message);
    }
    final result = await _start(request, recovering: true);
    if (result.status != DenseStageStatus.started) {
      await _background.abandonBeforeStart(request.captureDir);
    }
    return result;
  }

  Future<DenseStageResult> _start(
    DenseStageRequest request, {
    required bool recovering,
  }) async {
    if (_requiresProcessRestart) {
      return const DenseStageResult(
        DenseStageStatus.failed,
        message: wholeRestartRequiredMessage,
      );
    }
    try {
      await _requireOrigin(request);
      await identityScope.revalidate();
      _recordFor(request);
      identityScope.requireCapture(request.captureDir);
    } catch (error) {
      return DenseStageResult(
        DenseStageStatus.failed,
        message: DenseStageProgress.shorten(error),
      );
    }
    if (request.selection != null) {
      return const DenseStageResult(
        DenseStageStatus.failed,
        message: '完整38流程尚不支持选区，请使用整朵点云',
      );
    }
    if (!isAvailable) {
      return const DenseStageResult(
        DenseStageStatus.unavailable,
        message: '完整38处理引擎不可用',
      );
    }
    if (_running ||
        denseStageProgress.value?.state == DenseStageState.running) {
      return const DenseStageResult(
        DenseStageStatus.failed,
        message: '处理已在进行中，请等它完成',
      );
    }
    final denied = denseDenyReason(request.captureDir);
    if (denied != null) {
      return const DenseStageResult(
        DenseStageStatus.failed,
        message: '稠密点云已经生成过，不会重新训练',
      );
    }
    try {
      await verifyDenseWorkStateOf(
        request.captureDir,
        identityScope: identityScope,
      );
      await _requireOrigin(request);
    } catch (error) {
      return DenseStageResult(
        DenseStageStatus.failed,
        message: DenseStageProgress.shorten(error),
      );
    }
    if (!recovering &&
        denseWorkStateOf(request.captureDir, identityScope: identityScope) !=
            DenseWorkState.notStarted) {
      return const DenseStageResult(
        DenseStageStatus.failed,
        message: '已有未完成处理任务，需续跑原任务，不能重新开始完整38',
      );
    }
    // Do not silently replace a partial file from a different run/engine.
    if (FileSystemEntity.typeSync(
          '${request.captureDir}/$kDensePlyFileName',
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      return const DenseStageResult(
        DenseStageStatus.failed,
        message: '已有未完成稠密产物，需核对原任务后续跑',
      );
    }
    if (_running ||
        denseStageProgress.value?.state == DenseStageState.running) {
      return const DenseStageResult(
        DenseStageStatus.failed,
        message: '处理已在进行中，请等它完成',
      );
    }
    _running = true;
    DateTime? preparingStarted;
    Pw38BackgroundLease? backgroundLease;
    void Function()? removeRevocationListener;
    try {
      // Claim before further asynchronous preparation, so a busy duplicate
      // start/page exit cannot release this attempt's reservation.
      backgroundLease = await _background.claim(request.captureDir);
      final record = await _requireOrigin(request);
      if (record.artifactPath != null) {
        throw StateError('作品已有成品，不会覆盖');
      }
      final target = await _store.glbFileFor(
        record.id,
        pipelineKind: record.pipelineKind,
      );
      await _requireAbsent(target);
      await _requireOrigin(request, paths: [target.path]);
      final priorRuns = Directory(
        '${request.captureDir}/$kPw38FullRunsDirName',
      );
      if (!recovering &&
          await priorRuns.exists() &&
          await priorRuns.list(followLinks: false).isEmpty == false) {
        throw StateError('已有完整38任务记录，需续跑原任务，不能重新开始');
      }
      // Authorization is a tiny atomic marker publication BEFORE slow input
      // gathering/hashing. The existing dense state reads this marker, so an app
      // death during preparation never reopens capture or selection editing.
      final recoveryOrigin = recovering ? await _recoveryOrigin(request) : null;
      if (!recovering) await _authorize(request, record);
      await _requireOrigin(request, expectedId: record.id);
      final started = DateTime.now();
      preparingStarted = started;
      denseStageProgress.value = DenseStageProgress(
        captureDir: request.captureDir,
        state: DenseStageState.running,
        phase: 'preparing',
        startedAt: started,
      );
      removeRevocationListener = _store.addRevocationListener(() {
        final current = denseStageProgress.value;
        if (current?.captureDir == request.captureDir &&
            current?.startedAt == started) {
          denseStageProgress.value = null;
        }
      });
      recoveryPersistenceCheckpoint?.call('authorization_published');
      await _requireOrigin(request);
      final inputs = await _gatherer.gatherInputs(
        request,
        forceJpeg: true,
        sortByFrameId: true,
        expectedFrameCount: runner is Pw38ActualFramePipelineRunner ? null : 97,
      );
      await _requireOrigin(request);
      if (inputs.frames.any((f) => f.hasNv12 || f.jpegPath.isEmpty)) {
        throw StateError('完整38需要有序JPEG输入');
      }
      if (runner is Pw38ActualFramePipelineRunner) {
        requireWholeDiskBytes(
          await _readStorageBytes(),
          await pw38ActiveDiskBudgetForRunner(
            runner,
            inputs.frames.length,
            overrideBudget: _storageBudget,
          ),
        );
        await _requireOrigin(request);
      }
      final inputIdentity = await _inputIdentity(request, inputs);
      if (recoveryOrigin?['inputs'] != null &&
          jsonEncode(recoveryOrigin!['inputs']) != jsonEncode(inputIdentity)) {
        throw StateError('本地输入与原任务不一致，保留原任务，不能继续处理');
      }
      // Full38 retained inputs/outputs must stay outside the legacy dense_work
      // and reconstruction_work cleanup roots. Resolver JPEG cache is retained
      // until the runner copies and verifies it in this durable run's input root.
      final work = await Directory(
        '${request.captureDir}/$kPw38FullRunsDirName',
      ).create(recursive: true);
      await _requireOrigin(request, paths: [work.path]);
      // A staging directory is never passed to a native runner. Only after
      // its complete origin has been atomically written is the whole directory
      // atomically published into the committed full38_* namespace. ENOSPC or
      // app death leaves a recognizable, never-executed partial for diagnostics.
      final preparing = await work.createTemp('.preparing_full38_');
      await _requireOrigin(request, paths: [preparing.path]);
      final staging = Directory(await preparing.resolveSymbolicLinks());
      final authorization = await _readRegularJson(
        File('${request.captureDir}/$kDenseStartedMarkerName'),
      );
      final authorizationHash = await _hashRegular(
        File('${request.captureDir}/$kDenseStartedMarkerName'),
      );
      final origin = File('${staging.path}/RECOVERY_ORIGIN.json');
      recoveryPersistenceCheckpoint?.call('before_origin_write');
      await _writeAtomicJson(
        origin,
        {
          'schema': 'PW38_LOCAL_RECOVERY_ORIGIN_V1',
          'record_id': record.id,
          'account_namespace': record.accountNamespace,
          'capture_dir': await Directory(request.captureDir)
              .resolveSymbolicLinks(),
          'scope': identityScope.toJson(),
          'point_count': request.pointCount,
          'selection': request.selection?.toJson(),
          'authorization_sha256': authorizationHash,
          'inputs': inputIdentity,
          'action': recovering ? 'restart_dense_origin' : 'start_dense',
          if (recoveryOrigin?['_run_path'] != null)
            'previous_run': recoveryOrigin!['_run_path'],
        },
        afterPendingWrite: () {
          recoveryPersistenceCheckpoint?.call('origin_pending_written');
        },
      );
      // Re-read both the write and original approval before publishing a run.
      if (authorization['pw38_authorization'] == null ||
          await _hashRegular(
                File('${request.captureDir}/$kDenseStartedMarkerName'),
              ) !=
              authorizationHash) {
        throw StateError('原任务授权已改变，保留准备数据');
      }
      recoveryPersistenceCheckpoint?.call('origin_written');
      await _requireOrigin(request, paths: [preparing.path]);
      final suffix = staging.path
          .split('/')
          .last
          .substring('.preparing_'.length);
      final runPath = '${staging.parent.path}/$suffix';
      if (await FileSystemEntity.type(runPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('拒绝覆盖已有完整38任务');
      }
      final run = await staging.rename(runPath);
      recoveryPersistenceCheckpoint?.call('attempt_published');
      await _requireOrigin(request, paths: [run.path]);
      denseStageProgress.value = denseStageProgress.value?.copyWith(
        phase: 'session',
      );
      _completion = _run(
        request,
        inputs,
        run,
        record.id,
        started,
        backgroundLease,
      ).whenComplete(removeRevocationListener);
      unawaited(_completion!);
      return const DenseStageResult(
        DenseStageStatus.started,
        message: '完整38处理已开始',
      );
    } catch (e, st) {
      if (backgroundLease != null)
        await _background.finish(backgroundLease, success: false);
      _running = false;
      removeRevocationListener?.call();
      if (preparingStarted != null && _store.isActive) {
        denseStageProgress.value = DenseStageProgress(
          captureDir: request.captureDir,
          state: DenseStageState.failed,
          phase: 'preparation_failed',
          message: DenseStageProgress.shorten(e),
          startedAt: preparingStarted,
          finishedAt: DateTime.now(),
        );
      }
      DeviceLog.log('Full38', 'input preparation failed: $e\n$st');
      return DenseStageResult(
        DenseStageStatus.failed,
        message: DenseStageProgress.shorten(e),
      );
    }
  }

  Future<void> _run(
    DenseStageRequest request,
    DenseStageInputs inputs,
    Directory work,
    String recordId,
    DateTime started,
    Pw38BackgroundLease backgroundLease,
  ) async {
    final dir = request.captureDir;
    var backgroundSuccess = false;
    void Function()? releasePublication;
    try {
      releasePublication = await Pw38CaptureRetirement.holdPublication(
        _store,
        recordId,
      );
      await _requireOrigin(request, expectedId: recordId);
      void publishProgress(
        String phase,
        int done,
        int total, [
        DenseProgressSourceTime? source,
      ]) {
        _background.update(backgroundLease, phase, done, total);
        final current = denseStageProgress.value;
        if (_store.isActive &&
            current?.captureDir == dir &&
            current?.state == DenseStageState.running) {
          denseStageProgress.value = current!.copyWith(
            phase: phase,
            done: done,
            total: total,
            sourceTime: source,
          );
        }
      }

      final result = await _runWithVisuals(
        request: request,
        inputs: inputs,
        workDir: work.path,
        onProgress: (phase, done, total) => publishProgress(phase, done, total),
        onTimedProgress: (phase, done, total, source) =>
            publishProgress(phase, done, total, source),
      );
      await _requireOrigin(request, expectedId: recordId);
      // Reparse against the publisher's actual run root; the worker cannot
      // redirect publication by returning a different path/type object.
      final outputs = Pw38ProductionOutputContract.fromReceipt(
        result.receipt,
        workRoot: work.path,
        identityScope: identityScope,
      );
      final glb = File(outputs.glb.path);
      final glbRow = outputs.glb.row;
      await _verifyObserved(glb, glbRow, work);
      File? dense;
      Map<String, Object?>? denseRow;
      var points = 0;
      switch (outputs.dense) {
        case Pw38DensePlyOutput(:final artifact):
          dense = File(artifact.path);
          denseRow = artifact.row;
          await _verifyObserved(dense, denseRow, work);
          final count = densePlyPoints(dense.path);
          if (count == null || count <= 0) {
            throw StateError('完整38稠密PLY不完整');
          }
          points = count;
        case Pw38OriginalRetainedOutput(:final files):
          // Last-reader retirement substitutes only a hash-bound prior measured
          // validation record, never a predicted output or an absent-file pass.
          Map<String, dynamic>? retiredEvidence;
          final retirementReceipt = result.receipt['generated_retirement'];
          if (retirementReceipt is Map) {
            final evidencePath = retirementReceipt['evidence_path'];
            final evidenceHash = retirementReceipt['evidence_sha256'];
            final evidencePrefix = '$dir/pw38_completion_evidence/';
            if (evidencePath is! String ||
                !evidencePath.startsWith(evidencePrefix) ||
                evidenceHash is! String ||
                await _hashRegular(File(evidencePath)) != evidenceHash)
              throw StateError('Retired output evidence identity mismatch');
            retiredEvidence = await _readRegularJson(File(evidencePath));
            if (retiredEvidence['schema'] != 'PW38_GENERATED_RETIREMENT_V1' ||
                retiredEvidence['root'] != outputs.glb.root ||
                retiredEvidence['status'] != 'STAGE_RETIRED' ||
                (retiredEvidence['failures'] as List).isNotEmpty)
              throw StateError('Retirement did not pass');
          }
          for (final artifact in files) {
            if (retiredEvidence != null &&
                (retiredEvidence['deleted'] as List).contains(
                  artifact.relativePath,
                )) {
              final prior =
                  (retiredEvidence['artifacts'] as Map)[artifact.relativePath];
              if (prior is! Map ||
                  prior['bytes'] != artifact.bytes ||
                  prior['sha256'] != artifact.sha256 ||
                  prior['last_reader_stage'] != 9 ||
                  await FileSystemEntity.type(
                        artifact.path,
                        followLinks: false,
                      ) !=
                      FileSystemEntityType.notFound)
                throw StateError('Prior retained output validation mismatch');
            } else {
              await _verifyObserved(File(artifact.path), artifact.row, work);
            }
          }
      }
      final record = await _requireOrigin(request, expectedId: recordId);
      if (record.artifactPath != null) throw StateError('作品成品已改变，停止覆盖');
      final target = await _store.glbFileFor(
        record.id,
        pipelineKind: record.pipelineKind,
      );
      final denseTarget = dense == null
          ? null
          : File('$dir/$kDensePlyFileName');
      await _requireAbsent(target);
      if (denseTarget != null) await _requireAbsent(denseTarget);
      // Stage verified copies beside each final destination. Failed copies stay
      // for diagnostics; existing files are never deleted or overwritten.
      Future<void> requirePublication() => _requireOrigin(
        request,
        expectedId: recordId,
        paths: [target.path, if (denseTarget != null) denseTarget.path],
      );
      final stagedGlb = await _stageCopy(
        glb,
        target,
        glbRow,
        requireWritable: requirePublication,
      );
      final stagedDense = dense == null
          ? null
          : await _stageCopy(
              dense,
              denseTarget!,
              denseRow!,
              requireWritable: requirePublication,
            );
      await requirePublication();
      await _requireAbsent(target);
      if (denseTarget != null) await _requireAbsent(denseTarget);
      await requirePublication();
      final current = _recordFor(request, expectedId: recordId);
      if (current.artifactPath != null) throw StateError('作品成品已改变，停止覆盖');
      await stagedGlb.rename(target.path);
      await requirePublication();
      if (stagedDense != null) {
        await stagedDense.rename(denseTarget!.path);
        await requirePublication();
      }
      await _verifyBytes(target, glbRow);
      if (denseTarget != null) await _verifyBytes(denseTarget, denseRow!);
      // Re-read immediately before updating so edits made during the long job
      // (name, thumbnail, cloud metadata, viewed state, etc.) are preserved.
      await requirePublication();
      final latest = _recordFor(request, expectedId: recordId);
      if (latest.artifactPath != null) throw StateError('作品成品已改变，停止挂接');
      await _store.attachVerifiedLocalArtifact(
        id: latest.id,
        captureDir: latest.captureDir!,
        artifactPath: Uri.file(target.path).toString(),
        finalGlbSha256: glbRow['sha256'] as String,
        finalGlbBytes: glbRow['bytes'] as int,
      );
      await requirePublication();
      final persisted = _store.byId(recordId);
      if (persisted?.artifactPath != Uri.file(target.path).toString()) {
        throw StateError('作品被删除或成品挂接失败');
      }
      await requirePublication();
      final completedProgress = DenseStageProgress(
        captureDir: dir,
        state: DenseStageState.done,
        phase: 'done',
        done: 13,
        total: 13,
        outPly: denseTarget?.path,
        points: points,
        startedAt: started,
        finishedAt: DateTime.now(),
        preview: Pw38PreviewArtifact(
          path: target.path,
          stage: 'glb',
          role: 'glb',
          bytes: glbRow['bytes'] as int,
          sha256: glbRow['sha256'] as String,
        ),
      );
      // A paired account proof allows one exact capture retirement below.
      // Legacy records retain their existing work-level completion route.
      final singleCaptureRetirement = _store.account != null &&
          persisted != null && hasPw38FinalRecordProof(persisted);
      if (!singleCaptureRetirement && result.receipt['generated_retirement'] is Map) {
        await publishPw38CacheCompletion(
          captureDir: dir,
          workRoot: work.path,
          recordId: recordId,
          publishedGlbPath: target.path,
          receipt: result.receipt,
          identityScope: identityScope,
          preserveReceiptOnly: true,
        );
        denseStageProgress.value = completedProgress.copyWith(
          state: DenseStageState.running,
          phase: 'finalizing',
        );
        // Progress now selects the safely published GLB. Any in-flight preview
        // read/cover still holds its actual consumer lease until completion.
        Pw38GeneratedConsumerLeases.instance.closeOffers(work.path);
        await Pw38GeneratedConsumerLeases.instance
            .waitForIdle(work.path)
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw StateError(
                'Generated cleanup retained active consumers: ${Pw38GeneratedConsumerLeases.instance.activeConsumers(work.path)}',
              ),
            );
        await requirePublication();
        final retirement = GeneratedArtifactRetirement(
          root: Directory(await work.resolveSymbolicLinks()),
          evidenceFile: File(
            '$dir/pw38_completion_evidence/${work.uri.pathSegments.where((p) => p.isNotEmpty).last}/final_retirement.json',
          ),
        );
        final relative = glb.path.substring(work.path.length + 1);
        retirement.register(
          relative,
          bytes: outputs.glb.bytes,
          sha256: outputs.glb.sha256,
          lastReaderStage: 99,
        );
        await retirement.finalizeGlbOnly(
          glbRelative: relative,
          publishedPath: target.path,
          validatePublished: () async {
            await requirePublication();
            await _verifyBytes(target, glbRow);
            final attached = _store.byId(recordId);
            if (attached?.artifactPath != Uri.file(target.path).toString())
              throw StateError('Published record detached before retirement');
          },
        );
      }
      if (!singleCaptureRetirement && outputs.dense is Pw38OriginalRetainedOutput) {
        await writePw38CacheCompletedMarker(
          captureDir: dir,
          workRoot: work.path,
          recordId: recordId,
          publishedGlbPath: target.path,
          receipt: result.receipt,
          identityScope: identityScope,
        );
      }
      if (_store.account != null) {
        // The published GLB is now independent of capture/RESULT. Select it
        // before sealing old previews, then drain actual IO before deleting.
        denseStageProgress.value = completedProgress.copyWith(
          state: DenseStageState.running,
          phase: 'finalizing',
        );
        try {
          final cleanup = await Pw38CaptureRetirement(
            store: _store,
            drainPipelineReaders: () async {
              Pw38GeneratedConsumerLeases.instance.closeOffers(work.path);
              await Pw38GeneratedConsumerLeases.instance.waitForIdle(work.path);
            },
          ).retire(recordId: recordId, captureDir: dir);
          DeviceLog.log(
            'Full38',
            cleanup.completed
                ? 'capture retired; final GLB retained record=$recordId'
                : 'final GLB retained; cleanup awaiting ${cleanup.pendingPaths} record=$recordId',
          );
        } catch (cleanupError, cleanupStack) {
          // The generated model remains valid. Its original pending manifest
          // survives for restart; cleanup failure must not rerun reconstruction.
          DeviceLog.log(
            'Full38',
            'published GLB cleanup pending record=$recordId: $cleanupError\n$cleanupStack',
          );
        }
      }
      denseStageProgress.value = completedProgress;
      DeviceLog.log('Full38', 'actual13-stage GLB linked record=$recordId');
      _background.update(backgroundLease, 'done', 13, 13);
      backgroundSuccess = true;
    } catch (e, st) {
      if (wholeFailureNeedsProcessRestart(e)) _requiresProcessRestart = true;
      DeviceLog.log('Full38', 'failed; retained scratch=${work.path}: $e\n$st');
      if (!_store.isActive) return;
      final last = denseStageProgress.value;
      denseStageProgress.value = DenseStageProgress(
        captureDir: dir,
        state: DenseStageState.failed,
        phase: 'failed',
        message: _requiresProcessRestart
            ? wholeRestartRequiredMessage
            : DenseStageProgress.shorten(e),
        startedAt: started,
        finishedAt: DateTime.now(),
        preview: last?.captureDir == dir ? last?.preview : null,
        live: last?.captureDir == dir ? last?.live : null,
      );
    } finally {
      try {
        await _background.finish(backgroundLease, success: backgroundSuccess);
      } finally {
        releasePublication?.call();
        _running = false;
      }
    }
  }

  Future<Pw38PipelineResult> _runWithVisuals({
    required DenseStageRequest request,
    required DenseStageInputs inputs,
    required String workDir,
    required Pw38ProductionProgress onProgress,
    required void Function(String, int, int, DenseProgressSourceTime)
    onTimedProgress,
  }) {
    final visual = runner;
    if (visual is! Pw38VisualPipelineRunner) {
      return runner.run(
        request: request,
        inputs: inputs,
        workDir: workDir,
        onProgress: onProgress,
      );
    }
    void publishPreview(Pw38PreviewArtifact artifact) {
      final current = denseStageProgress.value;
      if (_store.isActive &&
          current?.captureDir == request.captureDir &&
          current?.state == DenseStageState.running) {
        denseStageProgress.value = current!.copyWith(preview: artifact);
      }
    }

    if (visual is Pw38TimedVisualPipelineRunner) {
      return visual.runWithTimedVisuals(
        request: request,
        inputs: inputs,
        workDir: workDir,
        onProgress: onProgress,
        onTimedProgress: onTimedProgress,
        onPreview: publishPreview,
      );
    }
    return visual.runWithVisuals(
      request: request,
      inputs: inputs,
      workDir: workDir,
      onProgress: onProgress,
      onPreview: publishPreview,
    );
  }

  Future<void> _authorize(DenseStageRequest request, ScanRecord record) async {
    await _requireOrigin(request, expectedId: record.id);
    final root = await Directory(request.captureDir).resolveSymbolicLinks();
    final sparse = File(request.sparsePlyPath);
    if (await sparse.parent.resolveSymbolicLinks() != root ||
        sparse.uri.pathSegments.last != 'official_sfm_sparse.ply') {
      throw StateError('原稀疏输入不属于当前作品');
    }
    // Same durable capture-lock schema as the existing start marker. The
    // namespaced binding adds ownership for preparation interrupted before a
    // worker/input manifest exists; it does not assert input bytes or success.
    await _writeAtomicJson(
      File('$root/$kDenseStartedMarkerName'),
      {
        'schema': 'pw_dense_started/1',
        if (identityScope.isIndependentTest) ...{
          'bundle_id': identityScope.bundleId,
          'build': identityScope.build,
          'identity_scope': identityScope.toJson(),
        },
        'started_at': DateTime.now().toIso8601String(),
        'sparse_points': request.pointCount,
        'selection': request.selection?.toJson(),
        'pw38_authorization': {
          'schema': 'PW38_LOCAL_AUTHORIZATION_V1',
          'record_id': record.id,
          'account_namespace': record.accountNamespace,
          'capture_dir': root,
          'scope': identityScope.toJson(),
          'sparse_relative_path': 'official_sfm_sparse.ply',
          'point_count': request.pointCount,
          'selection': request.selection?.toJson(),
          'approved_action': 'enter_dense_permanently',
        },
      },
      afterPendingWrite: () {
        recoveryPersistenceCheckpoint?.call('authorization_pending_written');
      },
    );
  }

  @override
  Future<DenseStageRecoveryPlan> inspectRecovery(
    DenseStageRequest request,
  ) async {
    try {
      final record = await _requireOrigin(request);
      if (_requiresProcessRestart) {
        return const DenseStageRecoveryPlan(
          DenseStageRecoveryStatus.unavailable,
          message: wholeRestartRequiredMessage,
        );
      }
      await identityScope.revalidate();
      identityScope.requireCapture(request.captureDir);
      if (_running ||
          denseStageProgress.value?.state == DenseStageState.running) {
        return const DenseStageRecoveryPlan(
          DenseStageRecoveryStatus.busy,
          message: '处理正在进行中',
        );
      }
      final target = await _store.glbFileFor(
        record.id,
        pipelineKind: record.pipelineKind,
      );
      if (record.artifactPath != null ||
          await FileSystemEntity.type(target.path, followLinks: false) !=
              FileSystemEntityType.notFound ||
          denseDenyReason(request.captureDir) != null ||
          File('${request.captureDir}/$pw38CacheCompletionMarkerName')
              .existsSync()) {
        return const DenseStageRecoveryPlan(
          DenseStageRecoveryStatus.completed,
          message: '已有成品或完成记录，不会覆盖或重新处理',
        );
      }
      if (!isAvailable) {
        return const DenseStageRecoveryPlan(
          DenseStageRecoveryStatus.unavailable,
          message: '完整38处理引擎不可用',
        );
      }
      final origin = await _recoveryOrigin(request);
      return DenseStageRecoveryPlan(
        DenseStageRecoveryStatus.available,
        action: DenseStageRecoveryAction.restartDense,
        priorRunPath: origin['_run_path'] as String,
        message: origin['inputs'] == null
            ? '授权已保存；启动时核对本地输入，从稠密阶段起点重新处理，不是断点续跑'
            : '已核对本地输入；从稠密阶段起点重新处理，不是断点续跑',
      );
    } catch (error) {
      return DenseStageRecoveryPlan(
        DenseStageRecoveryStatus.invalid,
        message: DenseStageProgress.shorten(error),
      );
    }
  }

  Future<Map<String, dynamic>> _recoveryOrigin(
    DenseStageRequest request,
  ) async {
    final record = await _requireOrigin(request);
    final markerFile = File('${request.captureDir}/$kDenseStartedMarkerName');
    final marker = await _readRegularJson(markerFile);
    if (marker['schema'] != 'pw_dense_started/1' ||
        marker['sparse_points'] != request.pointCount ||
        jsonEncode(marker['selection']) !=
            jsonEncode(request.selection?.toJson())) {
      throw StateError('原任务选区或输入身份不一致，不能重新选择');
    }
    if (request.selection != null) {
      throw StateError('完整38选区衔接尚未就绪，保留原任务');
    }
    final root = await Directory(request.captureDir).resolveSymbolicLinks();
    final authorization = marker['pw38_authorization'];
    if (authorization is! Map ||
        authorization['schema'] != 'PW38_LOCAL_AUTHORIZATION_V1' ||
        authorization['record_id'] != record.id ||
        authorization['account_namespace'] != record.accountNamespace ||
        authorization['capture_dir'] != root ||
        jsonEncode(authorization['scope']) !=
            jsonEncode(identityScope.toJson()) ||
        authorization['sparse_relative_path'] != 'official_sfm_sparse.ply' ||
        authorization['point_count'] != request.pointCount ||
        jsonEncode(authorization['selection']) !=
            jsonEncode(marker['selection']) ||
        authorization['approved_action'] != 'enter_dense_permanently') {
      throw StateError('旧任务缺少可核验的恢复授权绑定，保留原任务');
    }
    final authorizationHash = await _hashRegular(markerFile);
    if (!await File(request.sparsePlyPath).exists()) {
      throw StateError('本地输入缺失：official_sfm_sparse.ply');
    }
    if (await File(request.sparsePlyPath).resolveSymbolicLinks() !=
        '$root/official_sfm_sparse.ply') {
      throw StateError('原稀疏输入不属于当前作品');
    }
    final metadata = File('$root/official_sfm_sparse_meta.json');
    if (!await metadata.exists()) {
      throw StateError('本地输入缺失：official_sfm_sparse_meta.json');
    }
    // Regular-file checks only: before the first gather there is no byte
    // manifest to compare. Actual gathering validates source formats/identities.
    await _hashRegular(metadata);
    final runs = Directory('$root/$kPw38FullRunsDirName');
    final candidates = <Map<String, dynamic>>[];
    final entries = await runs.exists()
        ? await runs.list(followLinks: false).toList()
        : <FileSystemEntity>[];
    for (final entry in entries) {
      if (entry is Directory &&
          entry.path.split('/').last.startsWith('.preparing_full38_')) {
        await _requireNeverExecutedPreparation(entry);
        continue;
      }
      if (entry is! Directory ||
          !entry.path.split('/').last.startsWith('full38_') ||
          await entry.resolveSymbolicLinks() != entry.path) {
        throw StateError('原任务目录身份异常，保留现有文件');
      }
      final completed = File('${entry.path}/outputs/RESULT.json');
      if (await completed.exists()) {
        final result = await _readRegularJson(completed);
        if (result['full38_complete'] == true || result['exit_code'] == 0) {
          throw StateError('原任务已有成功回执，需核对成品挂接，不能重新处理');
        }
      }
      final file = File('${entry.path}/RECOVERY_ORIGIN.json');
      if (!await file.exists()) {
        throw StateError('旧任务缺少可核验的恢复输入绑定，保留原任务');
      }
      final origin = await _readRegularJson(file);
      if (origin['schema'] != 'PW38_LOCAL_RECOVERY_ORIGIN_V1' ||
          origin['authorization_sha256'] != authorizationHash ||
          origin['record_id'] != record.id ||
          origin['account_namespace'] != record.accountNamespace ||
          origin['capture_dir'] != root ||
          jsonEncode(origin['scope']) != jsonEncode(identityScope.toJson()) ||
          origin['point_count'] != request.pointCount ||
          jsonEncode(origin['selection']) != jsonEncode(marker['selection']) ||
          origin['inputs'] is! Map) {
        throw StateError('原任务与当前作品或账号不一致');
      }
      // Every prior attempt must have the same immutable input binding.
      if (candidates.isNotEmpty &&
          jsonEncode(candidates.first['inputs']) !=
              jsonEncode(origin['inputs'])) {
        throw StateError('历史任务输入不一致，保留全部任务');
      }
      origin['_run_path'] = entry.path;
      candidates.add(origin);
    }
    if (candidates.isEmpty) {
      // Our own durable approval proves the dense entry even when the app died
      // before input hashing or run publication. Never invent a worker receipt.
      return {'inputs': null, '_run_path': markerFile.path};
    }
    final origin = candidates.last;
    final inputs = origin['inputs'] as Map;
    for (final key in ['sparse', 'metadata']) {
      final row = inputs[key];
      if (row is! Map) throw StateError('原任务缺少本地输入身份');
      final expectedName = key == 'sparse'
          ? 'official_sfm_sparse.ply'
          : 'official_sfm_sparse_meta.json';
      if (row['name'] != expectedName) {
        throw StateError('原任务输入路径身份不一致');
      }
      final file = File('$root/$expectedName');
      if (!await file.exists()) throw StateError('本地输入缺失：${row['name']}');
      if (await _hashRegular(file) != row['sha256']) {
        throw StateError('本地输入损坏或已改变：${row['name']}');
      }
    }
    final photos = inputs['photos'];
    if (photos is! List || photos.isEmpty) {
      throw StateError('原任务缺少可核验的本地照片清单');
    }
    for (final raw in photos) {
      if (raw is! Map ||
          raw['path'] is! String ||
          raw['sha256'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(raw['sha256'] as String)) {
        throw StateError('原任务照片身份记录不完整');
      }
      final photo = File(raw['path'] as String);
      if (!await photo.exists()) {
        throw StateError('本地输入缺失：原任务照片');
      }
      if (await _hashRegular(photo) != raw['sha256']) {
        throw StateError('本地输入损坏或已改变：原任务照片');
      }
    }
    return origin;
  }

  Future<void> _requireNeverExecutedPreparation(Directory directory) async {
    if (await directory.resolveSymbolicLinks() != directory.path) {
      throw StateError('准备目录身份异常，保留现有文件');
    }
    await for (final entry in directory.list(followLinks: false)) {
      final name = entry.path.split('/').last;
      if (entry is! File ||
          (name != 'RECOVERY_ORIGIN.json' &&
              !name.startsWith('.pw38_write_'))) {
        throw StateError('准备目录含未知执行文件，不能认定为未开始任务');
      }
      if (await FileSystemEntity.type(entry.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('准备目录含异常文件，保留原任务');
      }
    }
  }

  Future<Map<String, Object?>> _inputIdentity(
    DenseStageRequest request,
    DenseStageInputs inputs,
  ) async {
    final sparse = File(request.sparsePlyPath);
    final metadata = File(
      '${request.captureDir}/official_sfm_sparse_meta.json',
    );
    // Test gatherers and legacy callers may not have these files. A normal
    // first start retains its existing behavior, but recovery stays unavailable.
    final sources = <String, Object?>{};
    for (final entry in {'sparse': sparse, 'metadata': metadata}.entries) {
      sources[entry.key] = await entry.value.exists()
          ? {
              'name': entry.value.uri.pathSegments.last,
              'sha256': await _hashRegular(entry.value),
            }
          : null;
    }
    final photos = <Map<String, Object?>>[];
    for (final frame in inputs.frames) {
      final photo = File(frame.jpegPath);
      photos.add({
        'path': await photo.exists()
            ? await photo.resolveSymbolicLinks()
            : photo.absolute.path,
        'sha256': await photo.exists() ? await _hashRegular(photo) : null,
      });
    }
    sources['photos'] = photos;
    sources['gathered_sha256'] = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'frames': [
                for (var i = 0; i < inputs.frames.length; i++)
                  {
                    ..._frameIdentity(inputs.frames[i]),
                    'jpeg_sha256': photos[i]['sha256'],
                  },
              ],
              'xyz_sha256': _xyzIdentity(inputs.pointsXyz),
            }),
          ),
        )
        .toString();
    return sources;
  }

  Future<ScanRecord> _requireOrigin(
    DenseStageRequest request, {
    String? expectedId,
    Iterable<String> paths = const [],
  }) async {
    await _store.ensureLoaded();
    await _store.requireOwnedPath(request.captureDir);
    for (final path in paths) {
      await _store.requireOwnedPath(path);
    }
    return _recordFor(request, expectedId: expectedId);
  }

  ScanRecord _recordFor(DenseStageRequest request, {String? expectedId}) {
    if (!_store.isActive) {
      throw StateError('Account workspace is locked or revoked');
    }
    final id = expectedId ?? request.recordId;
    final records = id == null
        ? _store.records
              .where(
                (r) =>
                    r.captureDir != null &&
                    _samePath(r.captureDir!, request.captureDir),
              )
              .toList()
        : [if (_store.byId(id) case final r?) r];
    if (records.length != 1 ||
        records.single.captureDir == null ||
        !_samePath(records.single.captureDir!, request.captureDir)) {
      throw StateError('拍摄目录必须对应唯一的已有作品记录');
    }
    final record = records.single;
    if (_store.account case final account?) {
      if (record.accountNamespace != account.namespace) {
        throw StateError('Capture belongs to a different account workspace');
      }
    }
    return record;
  }
}

bool _samePath(String a, String b) =>
    Uri.directory(Directory(a).absolute.path).normalizePath() ==
    Uri.directory(Directory(b).absolute.path).normalizePath();

Future<void> _requireAbsent(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('拒绝覆盖已有产物 ${file.path}');
  }
}

Future<void> _verifyObserved(File file, Map row, Directory work) async {
  final path = file.absolute.path;
  final relative = row['path'] as String;
  if (!path.startsWith('${work.absolute.path}/') ||
      !path.endsWith('/$relative') ||
      relative.startsWith('/') ||
      relative.split('/').any((p) => p.isEmpty || p == '.' || p == '..') ||
      relative.contains('\\') ||
      await file.resolveSymbolicLinks() != path) {
    throw StateError('实际产物不在本次运行目录或路径身份不一致');
  }
  await _verifyBytes(file, row);
}

Future<void> _verifyBytes(File file, Map row) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() != row['bytes'] ||
      (await sha256.bind(file.openRead()).first).toString() != row['sha256']) {
    throw StateError('实际产物字节身份核对失败 ${file.path}');
  }
}

Future<File> _stageCopy(
  File source,
  File target,
  Map row, {
  required Future<void> Function() requireWritable,
}) async {
  await requireWritable();
  await target.parent.create(recursive: true);
  await requireWritable();
  final staging = await target.parent.createTemp('.full38_publish_');
  await requireWritable();
  final file = await source.copy(
    '${staging.path}/${target.uri.pathSegments.last}',
  );
  await requireWritable();
  await _verifyBytes(file, row);
  await requireWritable();
  return file;
}

Future<String> _hashRegular(File file) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError('本地输入不是普通文件 ${file.path}');
  }
  return (await sha256.bind(file.openRead()).first).toString();
}

Future<Map<String, dynamic>> _readRegularJson(File file) async {
  await _hashRegular(file);
  final value = jsonDecode(await file.readAsString());
  if (value is! Map<String, dynamic>) throw StateError('原任务记录格式损坏');
  return value;
}

// Small fixed chunks keep recovery bookkeeping independent of point-cloud size.
String _xyzIdentity(List<double> points) {
  final output = _DigestReceiver();
  final sink = sha256.startChunkedConversion(output);
  for (var start = 0; start < points.length; start += 1024) {
    final count = (points.length - start).clamp(0, 1024);
    final bytes = ByteData(count * 8);
    for (var i = 0; i < count; i++) {
      bytes.setFloat64(i * 8, points[start + i], Endian.little);
    }
    sink.add(bytes.buffer.asUint8List());
  }
  sink.close();
  return output.value!.toString();
}

final class _DigestReceiver implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

Map<String, Object?> _frameIdentity(PwDenseFrame frame) => {
  'id': frame.frameId,
  'fx': frame.fx,
  'fy': frame.fy,
  'cx': frame.cx,
  'cy': frame.cy,
  'w': frame.imageW,
  'h': frame.imageH,
  'q': frame.qWxyz,
  't': frame.t,
};

int _atomicWriteSequence = 0;

/// New-file publication only. Each failed write keeps its own unique partial,
/// so an incomplete JSON file can never occupy the committed destination.
Future<void> _writeAtomicJson(
  File destination,
  Map<String, Object?> value, {
  void Function()? afterPendingWrite,
}) async {
  await _requireAbsent(destination);
  final contents = jsonEncode(value);
  final pending = File(
    '${destination.parent.path}/.pw38_write_'
    '${DateTime.now().microsecondsSinceEpoch}_${_atomicWriteSequence++}_'
    '${destination.uri.pathSegments.last}',
  );
  await pending.create(exclusive: true);
  await pending.writeAsString(contents, flush: true);
  afterPendingWrite?.call();
  if (await pending.readAsString() != contents) {
    throw StateError('任务授权或输入记录未完整保存');
  }
  await _requireAbsent(destination);
  await pending.rename(destination.path);
}
