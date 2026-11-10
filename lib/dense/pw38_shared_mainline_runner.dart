import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../official_capture/dense_stage.dart';
import '../pw38/execution_identity_scope.dart';
import '../pw38/generated_artifact_retirement.dart';
import '../pw38/request.dart' show hashFile;
import '../pw38/whole_dense_live_observer.dart';
import '../pw38/reconstruction_mainline.dart';
import '../pw38/production_original_fixture_binding.dart';
import 'native_dense_stage_launcher.dart';
import 'pw38_production_launcher.dart';
import 'dense_stage_progress.dart';
import 'pw38_preview_artifact.dart';
import 'pw38_generated_consumer_leases.dart';

/// Preparation returns a measured immutable request and the actual package
/// paths. It must use the production material/session producers, rather than
/// import a historical fixture's successful output or material identity.
typedef Pw38PrepareProductionCapture = Future<Map<String, String>> Function({
  required DenseStageRequest request,
  required DenseStageInputs inputs,
  required String workDir,
});

/// Executes the real shared pipeline on an isolate. Native bindings and native
/// allocations are created inside that worker; only JSON/path IO crosses it.
final class Pw38SharedMainlineRunner
    implements Pw38RetirementDiskPipelineRunner, Pw38TimedVisualPipelineRunner {
  const Pw38SharedMainlineRunner({
    required this.prepareCapture,
    required this.isAvailable,
    this.identityScope = Pw38ExecutionIdentityScope.production,
  });
  final Pw38ExecutionIdentityScope identityScope;
  final Pw38PrepareProductionCapture prepareCapture;
  @override
  final bool isAvailable;

  @override
  Future<bool> get hasVerifiedFeatureRetirement =>
      verifyPw38RetirementBudgetPackage(identityScope);

  @override
  Future<Pw38PipelineResult> run({
    required DenseStageRequest request,
    required DenseStageInputs inputs,
    required String workDir,
    required Pw38ProductionProgress onProgress,
  }) => runWithVisuals(
    request: request,
    inputs: inputs,
    workDir: workDir,
    onProgress: onProgress,
  );

  @override
  Future<Pw38PipelineResult> runWithVisuals({
    required DenseStageRequest request,
    required DenseStageInputs inputs,
    required String workDir,
    required Pw38ProductionProgress onProgress,
    void Function(Pw38PreviewArtifact artifact)? onPreview,
  }) => _runWithTimedVisuals(
    request: request,
    inputs: inputs,
    workDir: workDir,
    onProgress: onProgress,
    onPreview: onPreview,
  );

  @override
  Future<Pw38PipelineResult> runWithTimedVisuals({
    required DenseStageRequest request,
    required DenseStageInputs inputs,
    required String workDir,
    required Pw38ProductionProgress onProgress,
    required void Function(String, int, int, DenseProgressSourceTime)
    onTimedProgress,
    void Function(Pw38PreviewArtifact artifact)? onPreview,
  }) => _runWithTimedVisuals(
    request: request,
    inputs: inputs,
    workDir: workDir,
    onProgress: onProgress,
    onTimedProgress: onTimedProgress,
    onPreview: onPreview,
  );

  Future<Pw38PipelineResult> _runWithTimedVisuals({
    required DenseStageRequest request,
    required DenseStageInputs inputs,
    required String workDir,
    required Pw38ProductionProgress onProgress,
    void Function(String, int, int, DenseProgressSourceTime)? onTimedProgress,
    void Function(Pw38PreviewArtifact artifact)? onPreview,
  }) async {
    if (!isAvailable) throw StateError('Original38 package is unavailable');
    await identityScope.revalidate();
    identityScope.requireCapture(request.captureDir);
    final canonicalWork = await Directory(workDir).resolveSymbolicLinks();
    final messages = ReceivePort();
    final completed = Completer<Map<String, Object?>>();
    final previews = Pw38PreviewReceiver(
      workRoot: canonicalWork,
      onPreview: onPreview,
    );
    final denseProgress = Pw38DenseProgressReceiver(
      workRoot: canonicalWork,
      onProgress: onProgress,
      onTimedProgress: onTimedProgress,
    );
    final subscription = messages.listen((dynamic message) {
      if (message is Map && message['kind'] == 'preview') {
        previews.add(message);
      } else if (message is Map && message['kind'] == 'retire_preview') {
        // Nonblocking: current viewer may need the next preview before releasing
        // this one. Drain validation/offer first so ACK cannot overtake enqueue.
        final path = message['path'];
        final ack = message['ack'];
        final token = message['token'];
        if (path is String &&
            path.startsWith('$canonicalWork/') &&
            ack is SendPort &&
            token is int) {
          unawaited(
            () async {
              await previews.drain;
              await Pw38GeneratedConsumerLeases.instance.retireWhenIdle(path);
              ack.send({'token': token, 'path': path});
            }().catchError((Object e) {
              previews.errors.add('Retirement retained: $e');
            }),
          );
        }
      } else if (message is Map && message['kind'] == 'dense_progress') {
        denseProgress.add(message);
      } else if (message is Map && message['kind'] == 'stage') {
        onProgress(message['stage'] as String, message['completed'] as int, 13);
      } else if (message is Map && message['kind'] == 'result') {
        denseProgress.close();
        if (!completed.isCompleted) {
          completed.complete(
            Map<String, Object?>.from(message['value'] as Map),
          );
        }
      } else if (message is List) {
        denseProgress.close();
        if (!completed.isCompleted) {
          completed.completeError(StateError('Full38 worker failed: $message'));
        }
      } else if (message == null && !completed.isCompleted) {
        denseProgress.close();
        completed.completeError(
          StateError('Full38 worker exited without result'),
        );
      }
    });
    try {
      await Isolate.spawn(
        _pw38ProductionWorker,
        <String, Object?>{
          'prepare': prepareCapture,
          'request': request,
          'inputs': inputs,
          'work_root': canonicalWork,
          'identity_scope': identityScope.toJson(),
          'port': messages.sendPort,
          'visuals': onPreview != null,
        },
        onError: messages.sendPort,
        onExit: messages.sendPort,
        errorsAreFatal: true,
      );
      final result = await completed.future;
      previews.close();
      await previews.drain;
      if (result['full38_complete'] != true) {
        throw StateError('Original38 stopped: ${result['stopped_reason']}');
      }
      await identityScope.revalidate();
      return Pw38PipelineResult.fromReceipt(
        result,
        workRoot: canonicalWork,
        identityScope: identityScope,
      );
    } finally {
      denseProgress.close();
      previews.abort();
      await previews.drain;
      await subscription.cancel();
      messages.close();
    }
  }
}

Future<void> _pw38ProductionWorker(Map<String, Object?> message) async {
  final port = message['port'] as SendPort;
  final prepare = message['prepare'] as Pw38PrepareProductionCapture;
  final work = message['work_root'] as String;
  WholeDenseLiveObserver.eventPort = port;
  WholeDenseLiveObserver.workRoot = work;
  WholeDenseLiveObserver.visuals = message['visuals'] == true;
  WholeDenseLiveObserver.onDepthReadersDrained = (receipt) async {
    final mvsRoot = receipt['mvs_root'];
    final paths = receipt['depth_paths'];
    if (receipt['schema'] != 'PW38_DEPTH_READERS_DRAINED_V1' ||
        receipt['readers_drained'] != true ||
        mvsRoot is! String ||
        !mvsRoot.startsWith('$work/') ||
        paths is! List ||
        paths.length != 2 ||
        await Directory(mvsRoot).resolveSymbolicLinks() != mvsRoot ||
        paths[0] != '$mvsRoot/low/depth.f32' ||
        paths[1] != '$mvsRoot/high/depth.f32') {
      throw StateError(
        'Actual depth readers/ownership acknowledgement missing',
      );
    }
    final workDirectory = Directory(work);
    final retirement = GeneratedArtifactRetirement(
      root: Directory(mvsRoot),
      evidenceFile: File(
        '${workDirectory.parent.parent.path}/pw38_completion_evidence/${workDirectory.uri.pathSegments.where((p) => p.isNotEmpty).last}/depth_retirement.json',
      ),
    );
    for (final pass in ['low', 'high']) {
      final file = File('$mvsRoot/$pass/depth.f32');
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.resolveSymbolicLinks() != file.path)
        throw StateError('Noncanonical generated depth bank');
      retirement.register(
        '$pass/depth.f32',
        bytes: await file.length(),
        sha256: await hashFile(file),
        lastReaderStage: 3,
      );
    }
    await retirement.stageValidated(3);
  };
  final identityScope = Pw38ExecutionIdentityScope.fromJson(
    Map<String, dynamic>.from(message['identity_scope'] as Map),
  );
  await identityScope.revalidate();
  identityScope.requireCapture(
    (message['request'] as DenseStageRequest).captureDir,
  );
  port.send({'kind': 'stage', 'stage': 'input_preparation', 'completed': 0});
  // The preparer must bind its native libraries here, in this worker. Its
  // closure/config must contain sendable IO values, never pre-opened FFI handles.
  final preparedBootstrap = await prepare(
    request: message['request'] as DenseStageRequest,
    inputs: message['inputs'] as DenseStageInputs,
    workDir: work,
  );
  final proof = preparedBootstrap is OriginalFixtureBoundBootstrap
      ? preparedBootstrap.proof
      : null;
  final bootstrap = Map<String, String>.from(preparedBootstrap);
  identityScope.requireBootstrap(bootstrap);
  final requestPath = bootstrap['request_path'];
  if (requestPath == null ||
      !requestPath.startsWith('$work/') ||
      await File(requestPath).resolveSymbolicLinks() != requestPath) {
    throw StateError('Effective production request must belong to this run');
  }
  final previewRetirements = Pw38PreviewRetirementBridge(port);
  final result = await runReconstructionMainline(
    bootstrap,
    productionFixtureProof: proof,
    identityScope: identityScope,
    onPreviewRetirementReady: previewRetirements.request,
    onStage: (stage, completed) =>
        port.send({'kind': 'stage', 'stage': stage, 'completed': completed}),
    onDenseProgress: (phase, done, total) => port.send({
      'kind': 'dense_progress',
      'work_root': work,
      'phase': phase,
      'done': done,
      'total': total,
    }),
    onPreview: message['visuals'] == true
        ? (artifact) => port.send({
            'kind': 'preview',
            'work_root': work,
            'value': artifact.toJson(),
          })
        : null,
  );
  previewRetirements.close();
  Isolate.exit(port, {'kind': 'result', 'value': result});
}

/// Serial IO validation keeps producer observations ordered across the isolate
/// boundary. A display failure is retained without failing reconstruction.
final class Pw38PreviewReceiver {
  Pw38PreviewReceiver({required this.workRoot, this.onPreview});
  final String workRoot;
  final void Function(Pw38PreviewArtifact artifact)? onPreview;
  final errors = <String>[];
  Future<void> _pending = Future<void>.value();
  bool _active = true;
  bool _discardPending = false;
  int _queued = 0, _lastStage = -1;
  String? _lastIdentity;
  Future<void> get drain => _pending;
  void close() => _active = false;
  void abort() {
    _active = false;
    _discardPending = true;
  }

  bool add(Object? message) {
    if (!_active ||
        message is! Map ||
        message['kind'] != 'preview' ||
        message['work_root'] != workRoot) {
      return false;
    }
    if (_queued >= 8) return false;
    final value = message['value'];
    _queued++;
    _pending = _pending.then((_) async {
      try {
        if (_discardPending) return;
        final artifact = await Pw38PreviewArtifact.verify(
          value,
          workRoot: workRoot,
        );
        const stages = [
          'sparse',
          'depth',
          'dense',
          'tsdf',
          'trim',
          'meshopt',
          'lagrange',
          'glb',
        ];
        final stage = stages.indexOf(artifact.stage);
        if (!_discardPending &&
            stage >= _lastStage &&
            artifact.identity != _lastIdentity) {
          _lastStage = stage;
          _lastIdentity = artifact.identity;
          if (onPreview != null) {
            Pw38GeneratedConsumerLeases.instance.offer(
              artifact.path,
              workRoot: workRoot,
            );
            onPreview!(artifact);
          }
        }
      } catch (error) {
        if (errors.length < 5) errors.add('$error');
      } finally {
        _queued--;
      }
    });
    return true;
  }
}

/// Parent-isolate gate for observational dense progress from exactly one run.
/// Native phase counters are distinct from the13-stage completion journal.
final class Pw38DenseProgressReceiver {
  Pw38DenseProgressReceiver({
    required this.workRoot,
    required this.onProgress,
    this.onTimedProgress,
  });
  final String workRoot;
  final Pw38ProductionProgress onProgress;
  final void Function(String, int, int, DenseProgressSourceTime)?
  onTimedProgress;
  bool _active = true;

  void close() => _active = false;

  /// Unknown, malformed, foreign-run or terminally stale observations are
  /// ignored. The per-run ReceivePort is separate from every other run, and
  /// this exact canonical work-root binding rejects accidental stale routing.
  bool add(Object? message) {
    if (!_active ||
        message is! Map ||
        message['kind'] != 'dense_progress' ||
        message['work_root'] != workRoot) {
      return false;
    }
    final phase = message['phase'];
    final done = message['done'];
    final total = message['total'];
    if (phase is! String ||
        phase.isEmpty ||
        phase.length > 511 ||
        phase.contains('\u0000') ||
        utf8.encode(phase).length > 511 ||
        done is! int ||
        total is! int ||
        total <= 0 ||
        total > 0x7fffffff ||
        done < 0 ||
        done > total) {
      return false;
    }
    final mono = message['source_mono_ns'], wall = message['source_wall_ns'];
    if (mono is int &&
        mono > 0 &&
        wall is int &&
        wall > 0 &&
        onTimedProgress != null) {
      onTimedProgress!(phase, done, total, DenseProgressSourceTime(mono, wall));
    } else {
      onProgress(phase, done, total);
    }
    return true;
  }
}

/// A release acknowledgement never blocks the numerical pipeline. Tokens bind
/// ACKs to this worker/path, and close discards late ACKs after worker completion.
final class Pw38PreviewRetirementBridge {
  Pw38PreviewRetirementBridge(this.parent) {
    _subscription = _acks.listen((dynamic value) {
      if (_closed || value is! Map) return;
      final token = value['token'], path = value['path'];
      final pending = _pending[token];
      if (pending == null || pending.$1 != path) return;
      _pending.remove(token);
      unawaited(
        pending.$2().catchError((Object e) {
          errors.add('$e');
        }),
      );
    });
  }
  final SendPort parent;
  final ReceivePort _acks = ReceivePort();
  late final StreamSubscription<dynamic> _subscription;
  final _pending = <int, (String, Future<void> Function())>{};
  final errors = <String>[];
  int _token = 0;
  bool _closed = false;
  void request(String path, Future<void> Function() release) {
    if (_closed) return;
    final token = ++_token;
    _pending[token] = (path, release);
    parent.send({
      'kind': 'retire_preview',
      'path': path,
      'token': token,
      'ack': _acks.sendPort,
    });
  }

  void close() {
    _closed = true;
    _pending.clear();
    unawaited(_subscription.cancel());
    _acks.close();
  }
}
