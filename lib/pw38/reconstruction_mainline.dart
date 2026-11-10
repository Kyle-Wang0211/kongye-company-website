import 'memory_policy.dart';
import 'generated_artifact_retirement.dart';
import 'generated_normal_input_retirement.dart';

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../dense/pw38_preview_artifact.dart';
import '../official_util/worker_storage_query.dart';
import 'execution_identity_scope.dart';
import 'dense_binding_contract.dart';
import 'native_downstream.dart';
import 'original_retention_io.dart';
import 'production_original_fixture_binding.dart';
import 'production_whole_runtime.dart';
import 'request.dart';
import 'result_failure_persistence.dart';
import 'reconstruction_artifact_gate.dart';
import 'reconstruction_request.dart';
import 'terminal_glb.dart';
import 'whole_dense_binding.dart';
import 'whole_disk_admission.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';

/// Unknown codec/topology output keeps the old reserve-only admission exactly.
/// It is explicit headroom policy, not a claimed all-output or remaining-write
/// upper bound; do not add another reserve or invent a new unknown-stage STOP.
Map<String, Object?> requirePw38SuffixLegacyAllowance(
  String path, {
  required String stage,
  int Function(String)? storageQuery,
}) {
  final available = (storageQuery ?? readAvailableStorageInWorker)(path);
  requireWholeDiskBytes(available, wholeDiskReserveBytes, stage: stage);
  return {
    'schema': 'PW38_SUFFIX_LEGACY_ALLOWANCE_V1',
    'remaining_stage': stage,
    'available_free_bytes': available,
    'required_free_bytes': wholeDiskReserveBytes,
    'legacy_headroom_allowance_bytes': wholeDiskReserveBytes,
    'filesystem_reserve_included': true,
    'remaining_write_upper_bytes': null,
    'allowance_scope': 'LEGACY_HEADROOM_NOT_OUTPUT_UPPER_BOUND',
  };
}

/// Loads only the immutable profile selected by the package-bound launcher.
/// The launcher owns source-closure binding; this gate rechecks its actual bytes.
Future<Map<String, dynamic>> loadWholeProfileForMainline(
  Map<String, String> bootstrap,
) async {
  final path = bootstrap['whole_profile_path'];
  final expected = bootstrap['whole_profile_sha256'];
  final bundle = bootstrap['bundle_path'];
  if (path == null ||
      bundle == null ||
      expected == null ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(expected) ||
      !path.startsWith('$bundle/')) {
    throw StateError('Package-bound whole profile path/hash required');
  }
  final file = File(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.resolveSymbolicLinks() != path ||
      await file.length() > 1024 * 1024) {
    throw StateError('Package-bound whole profile bytes changed');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > 1024 * 1024 ||
      sha256.convert(bytes).toString() != expected) {
    throw StateError('Package-bound whole profile bytes changed');
  }
  return object(jsonDecode(utf8.decode(bytes)));
}

const _wholeRunKeys = {
  'low_gray',
  'original_fixture_receipt',
  'm0_trace_path',
  'm0_run_id',
};

/// Byte/path transport checks only. This helper never creates execution authority.
Future<void> validateWholeRunBindingPaths(
  Map<String, dynamic> rows, {
  required String runRoot,
  required String proofOutputRoot,
  required String proofReceiptPath,
  required int frames,
}) async {
  if (rows.length != 4 ||
      !rows.keys.toSet().containsAll(_wholeRunKeys) ||
      frames < 10 ||
      frames > 97 ||
      await Directory(runRoot).resolveSymbolicLinks() != runRoot ||
      proofOutputRoot != '$runRoot/original_fixture' ||
      proofReceiptPath != '$runRoot/ORIGINAL_FIXTURE_RECEIPT.json' ||
      rows['m0_trace_path'] != '$runRoot/whole_app_m0.jsonl' ||
      rows['m0_run_id'] is! String ||
      !RegExp('^$pid-[0-9]+\u0024').hasMatch(rows['m0_run_id'] as String)) {
    throw StateError(
      'Whole per-run bindings differ from actual proof/run roots',
    );
  }
  final trace = File(rows['m0_trace_path'] as String);
  if (await FileSystemEntity.type(trace.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await trace.resolveSymbolicLinks() != trace.path) {
    throw StateError('Actual current whole observer trace required');
  }
  for (final key in ['low_gray', 'original_fixture_receipt']) {
    final row = object(rows[key]);
    final expected = key == 'low_gray'
        ? '$proofOutputRoot/images.f16'
        : proofReceiptPath;
    final path = row['path'];
    final file = File(expected);
    if (row.length != 3 ||
        path != expected ||
        row['bytes'] is! int ||
        (row['bytes'] as int) <= 0 ||
        (key == 'low_gray' && row['bytes'] != frames * 768 * 576 * 2) ||
        row['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['sha256'] as String) ||
        await FileSystemEntity.type(expected, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.resolveSymbolicLinks() != expected ||
        await file.length() != row['bytes'] ||
        await hashFile(file) != row['sha256']) {
      throw StateError('Whole per-run $key changed or outside actual proof');
    }
  }
}

/// Only the checked in-worker capability authorizes merging run-specific paths.
Future<Map<String, dynamic>> bindWholeProfileForRun(
  Map<String, dynamic> profile,
  Map<String, String> bootstrap, {
  OriginalFixtureExecutionProof? proof,
  required File request,
  required String requestSha256,
  required int frames,
}) async {
  if (proof == null) {
    throw StateError('Actual whole production execution proof required');
  }
  await proof.requireBoundRequest(request, requestSha256);
  final raw = bootstrap['whole_run_bindings'];
  if (raw == null || raw.length > 16384) {
    throw StateError('Bounded actual whole run bindings required');
  }
  final rows = object(jsonDecode(raw));
  final runRoot = Directory(proof.outputRoot).parent.path;
  await validateWholeRunBindingPaths(
    rows,
    runRoot: runRoot,
    proofOutputRoot: proof.outputRoot,
    proofReceiptPath: proof.receiptPath,
    frames: frames,
  );
  final parsedRequest = object(jsonDecode(await request.readAsString()));
  if (object(parsedRequest['io_roots'])['durable_input_root'] !=
          '$runRoot/inputs' ||
      !request.path.startsWith('$runRoot/preparation/') ||
      await hashFile(request) != requestSha256) {
    throw StateError(
      'Whole run bindings escaped actual proof-bound request run',
    );
  }
  return {...profile, ...rows};
}

/// Reads the entire stopped observation, including material work and all suffixes.
/// These are discrete physical observations, not an unsampled peak guarantee.
Future<Map<String, dynamic>> validateWholeAppMemoryTrace(
  Map<String, dynamic> metadata, {
  bool requireSuccess = true,
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) async {
  final capBytes = wholeMemoryCapBytes(identityScope);
  final path = metadata['m0_trace_path'];
  final run = metadata['m0_run_id'];
  if (path is! String ||
      metadata['m0_cap_B'] != capBytes ||
      run is! String ||
      metadata['m0_pid'] is! int ||
      metadata['m0_pid'] != pid ||
      !RegExp('^$pid-[0-9]+\u0024').hasMatch(run) ||
      metadata['m0_start_return_code'] != 0 ||
      metadata['m0_stop_return_code'] is! int) {
    throw StateError('Whole-App M0 actual ownership/stop receipt missing');
  }
  final file = File(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.resolveSymbolicLinks() != path) {
    throw StateError('Whole-App actual M0 trace absent');
  }
  final input = await file.open();
  try {
    final size = await input.length();
    if (size == 0) throw StateError('Whole-App M0 empty trace');
    await input.setPosition(size - 1);
    if ((await input.read(1)).single != 10) {
      throw StateError('Whole-App M0 incomplete final row');
    }
  } finally {
    await input.close();
  }
  final failures = <String>[];
  if (metadata['m0_stop_return_code'] != 0 ||
      metadata['m0_finish_boundary_return_code'] != 0) {
    failures.add('Actual stop/boundary return code failed');
  }
  var count = 0, peak = 0, lastTime = 0;
  var started = false,
      finished = false,
      initialized = false,
      finishBoundary = false;
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (line.isEmpty || line.length > 16384 || finished) {
      throw StateError('Whole-App M0 malformed/after-stop row');
    }
    final row = object(jsonDecode(line));
    final stamp = row['mono_ns'], physical = row['phys_footprint_B'];
    count++;
    if (row['schema'] != 'pw38.m0.memory/1' ||
        row['pid'] != pid ||
        row['run_id'] != run ||
        row['seq'] is! int ||
        row['seq'] != count ||
        stamp is! int ||
        stamp <= 0 ||
        stamp < lastTime ||
        row['cap_B'] != capBytes ||
        physical is! int ||
        physical <= 0) {
      throw StateError(
        'Whole-App M0 identity/order/physical cap failed: seq=$count physical=$physical stage=${row['stage']}',
      );
    }
    if (row['receipt_rc'] != 0 ||
        row['cap_exceeded_latched'] != false ||
        row['cap_exceeded_now'] != false ||
        physical > capBytes) {
      if (failures.length < 16) {
        failures.add(
          'seq=$count physical=$physical stage=${row['stage']} receipt_rc=${row['receipt_rc']}',
        );
      }
    }
    lastTime = stamp;
    if (physical > peak) peak = physical;
    if (count == 1) started = row['event'] == 'start';
    if (count > 1 && row['event'] == 'start') {
      throw StateError('Whole-App M0 repeated start');
    }
    if (row['event'] == 'boundary' &&
        row['stage'] == '/whole_runtime_initialized') {
      initialized = true;
    }
    if (row['event'] == 'boundary' &&
        row['stage'] == '/whole_pipeline_finished') {
      finishBoundary = true;
    }
    if (row['event'] == 'stop') finished = true;
  }
  if (!started || !initialized || !finishBoundary || !finished || count < 4) {
    throw StateError(
      'Whole-App M0 complete start/initialize/finish/stop trace required',
    );
  }
  if (requireSuccess && failures.isNotEmpty) {
    throw StateError(
      'Whole-App M0 failed: physical_peak_bytes=$peak; $failures',
    );
  }
  return {
    'status': failures.isEmpty
        ? 'PASS_ACTUAL_WHOLE_APP_OBSERVATIONS'
        : 'FAIL_ACTUAL_WHOLE_APP_OBSERVATIONS',
    'failures': failures,
    'physical_peak_bytes': peak,
    'samples': count,
    'm0_run_id': run,
    'm0_trace_path': path,
    'm0_trace_bytes': await file.length(),
    'm0_trace_sha256': await hashFile(file),
    'scope': 'ACTUAL_OBSERVER_START_THROUGH_TERMINAL_STOP',
  };
}

/// Dedicated test-app entry. Its package check does not belong to the shared
/// algorithm engine used by the production launcher.
Future<Map<String, Object?>> runOfficialReconstruction(
  Map<String, String> bootstrap, {
  Pw38DenseMainline? denseCore,
}) => _runReconstruction(bootstrap, dedicatedEntry: true, denseCore: denseCore);

/// Actual shared engine: load the immutable request, execute the existing dense
/// core and all nine downstream consumers, then validate the generated GLB.
/// Calling this function does not establish production-device acceptance.
Future<Map<String, Object?>> runReconstructionMainline(
  Map<String, String> bootstrap, {
  Pw38DenseMainline? denseCore,
  OriginalFixtureExecutionProof? productionFixtureProof,
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
  void Function(String stage, int completed)? onStage,
  void Function(String phase, int done, int total)? onDenseProgress,
  void Function(Pw38PreviewArtifact artifact)? onPreview,
  void Function(String path, Future<void> Function() release)?
  onPreviewRetirementReady,
}) => _runReconstruction(
  bootstrap,
  dedicatedEntry: false,
  denseCore: denseCore,
  productionFixtureProof: productionFixtureProof,
  identityScope: identityScope,
  onStage: onStage,
  onDenseProgress: onDenseProgress,
  onPreview: onPreview,
  onPreviewRetirementReady: onPreviewRetirementReady,
);

Future<Map<String, Object?>> _runReconstruction(
  Map<String, String> bootstrap, {
  required bool dedicatedEntry,
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
  Pw38DenseMainline? denseCore,
  OriginalFixtureExecutionProof? productionFixtureProof,
  void Function(String stage, int completed)? onStage,
  void Function(String phase, int done, int total)? onDenseProgress,
  void Function(Pw38PreviewArtifact artifact)? onPreview,
  void Function(String path, Future<void> Function() release)?
  onPreviewRetirementReady,
}) async {
  ReconstructionRequest? request;
  Directory? owned;
  Map<String, Object?>? denseResult;
  GeneratedArtifactRetirement? retirement;
  final stages = <Map<String, Object?>>[];
  final bindings = <Map<String, Object?>>[];
  String? runningStage;
  Map<String, Object?>? terminalValidation;
  final nativeCalls = <Map<String, Object?>>[];
  final previewObserver = Pw38PreviewObserver(onPreview);
  Map<String, dynamic>? wholeProfile, wholeObserverMetadata, wholeMemory;
  var observerStopAttempted = false;
  Future<Map<String, Object?>> finish(
    int code,
    String? reason, {
    bool terminal = true,
  }) async {
    if (terminal && wholeObserverMetadata != null && !observerStopAttempted) {
      observerStopAttempted = true;
      try {
        if (wholeProfile == null) {
          throw StateError(
            'Verified whole profile unavailable for observer stop',
          );
        }
        wholeObserverMetadata = await stopWholeProductionObserver(
          metadata: wholeObserverMetadata!,
          profile: wholeProfile,
          bundleRoot: bootstrap['bundle_path']!,
          identityScope: identityScope,
        );
      } catch (error) {
        if (error is WholeProductionRuntimeFailure && error.metadata != null) {
          wholeObserverMetadata = error.metadata;
        }
        code = 38;
        reason =
            '${reason ?? 'Whole pipeline terminal observation failed'}; $error';
      }
      if (wholeObserverMetadata?['m0_stop_return_code'] is int) {
        try {
          wholeMemory = await validateWholeAppMemoryTrace(
            wholeObserverMetadata!,
            requireSuccess: false,
            identityScope: identityScope,
          );
          if (wholeMemory!['status'] != 'PASS_ACTUAL_WHOLE_APP_OBSERVATIONS') {
            throw StateError(
              'Whole-App observation failed: ${wholeMemory!['failures']}',
            );
          }
        } catch (error) {
          code = 38;
          reason =
              '${reason ?? 'Whole pipeline terminal observation failed'}; $error';
        }
      }
      nativeCalls.add({
        'native_entry': 'pw38_m0_observer_stop',
        'return_code': wholeObserverMetadata?['m0_stop_return_code'],
      });
    }

    if (terminal && retirement != null) {
      try {
        await retirement.seal();
      } catch (e) {
        code = 38;
        reason = '${reason ?? 'Generated retirement failed'}; $e';
      }
    }
    final artifactRetirement = retirement;
    final value = <String, Object?>{
      'schema': 'PW38_OFFICIAL_RECONSTRUCTION_RESULT_V1',
      'route_id': reconstructionRoute,
      'run_id': request?.runId,
      'bundle_id': bootstrap['bundle_id'],
      'build': bootstrap['build'],
      if (!dedicatedEntry) 'identity_scope': identityScope.toJson(),
      'execution_entry': dedicatedEntry
          ? 'dedicated_test_app'
          : 'shared_mainline',
      'production_device_acceptance': 'NOT_ESTABLISHED_BY_THIS_RESULT',
      'request_sha256': bootstrap['request_sha256'],
      'input_identity_status': request?.json['input_identity_status'],
      'input_origin': request?.json['input_origin'],
      'recipe': {
        ...pw38SelectedRecipe,
        'ordered_frames': request?.frames.length ?? 97,
        if (request?.json['dense_producer_profile'] == wholeDenseProfile)
          'fusion_geo_pixel_threshold': 1.0,
      },
      'noise_identity': request?.json['noise_identity'],
      'dense_producer_profile': request?.json['dense_producer_profile'],
      'ordered_frames': request?.frames.length,
      'template_request_sha256': bootstrap['template_request_sha256'],
      'input_binding_path': bootstrap['input_binding_path'],
      'input_binding_sha256': bootstrap['input_binding_sha256'],
      'full38_complete':
          code == 0 &&
          reason == null &&
          stages.length == 13 &&
          terminalValidation?['status'] == 'PASS_TERMINAL_GLB_STRUCTURE',
      'exit_code': code,
      'stopped_reason': reason,
      'running_stage': runningStage,
      'native_binding': bindings,
      'actual_native_calls': nativeCalls,
      'dense_native_result': denseResult,
      if (wholeObserverMetadata != null)
        'whole_observer_metadata': wholeObserverMetadata,
      if (wholeMemory != null) 'whole_app_memory': wholeMemory,
      'stages': stages,
      'output_identity_policy': 'measured_after_actual_success',
      'format_evidence_policy': 'actual_native_consumer_return_codes',
      'terminal_glb_format_validation': terminalValidation ?? 'NOT_CHECKED',
      'display_observation_errors': previewObserver.errors,
      if (artifactRetirement != null)
        'generated_retirement': {
          'schema': 'PW38_GENERATED_RETIREMENT_V1',
          'evidence_path': artifactRetirement.evidenceFile.path,
          'evidence_sha256': await artifactRetirement.evidenceFile.exists()
              ? await hashFile(artifactRetirement.evidenceFile)
              : null,
          'deleted': artifactRetirement.deleted.toList(),
          'failures': artifactRetirement.failures.toList(),
        },
    };
    if (owned != null) {
      return savePw38ResultSafely(
        File('${owned.path}/RESULT.json'),
        value,
        terminal: terminal,
      );
    }
    return value;
  }

  Future<void> journal(String stage) async {
    runningStage = stage;
    await finish(
      38,
      'RUNNING: native process exit may leave this last persisted checkpoint',
      terminal: false,
    );
    onStage?.call(stage, stages.length);
  }

  try {
    if (bootstrap.containsKey('whole_observer_metadata')) {
      wholeObserverMetadata = object(
        jsonDecode(bootstrap['whole_observer_metadata']!),
      );
      wholeProfile = await loadWholeProfileForMainline(bootstrap);
    }
    if (!dedicatedEntry) {
      await identityScope.revalidate();
      identityScope.requireBootstrap(bootstrap);
    }
    if (dedicatedEntry &&
        (bootstrap['bundle_id'] != 'com.kyle.pocketworldOnnxBench.k35476742' ||
            bootstrap['build'] != '3810')) {
      throw StateError('Dedicated full38 candidate identity mismatch');
    }
    for (final key in [
      'bundle_id',
      'build',
      'bundle_path',
      'request_path',
      'request_sha256',
    ]) {
      if (bootstrap[key] == null || bootstrap[key]!.isEmpty) {
        throw StateError('Explicit execution identity missing: $key');
      }
    }
    final r = await ReconstructionRequest.load(
      File(bootstrap['request_path']!),
      bootstrap['request_sha256']!,
    );
    request = r;
    if (!dedicatedEntry) {
      requireProductionDenseProvenance(r.json, proof: productionFixtureProof);
      if (usesOriginalRetained97(r.json)) {
        await productionFixtureProof!.requireBoundRequest(
          File(bootstrap['request_path']!),
          bootstrap['request_sha256']!,
        );
      }
    }
    final gate = ReconstructionArtifactGate(
      Directory(r.ioRoots.durableInputRoot),
      Directory(r.ioRoots.downstreamOutputRoot),
      r.outputs,
    );
    final native = DownstreamNative(
      r,
      bootstrap['bundle_path']!,
      calls: nativeCalls,
      allowDiagnosticTexture: dedicatedEntry,
    );
    await gate.requireFresh();
    await r.verifyMaterial(gate);
    await gate.runRoot.create(recursive: false);
    owned = gate.runRoot;
    retirement = GeneratedArtifactRetirement(
      root: gate.runRoot,
      evidenceFile: File(
        '${gate.runRoot.parent.parent.parent.path}/pw38_completion_evidence/${gate.runRoot.parent.uri.pathSegments.where((p) => p.isNotEmpty).last}/retirement.json',
      ),
    );
    final previewLeases = <String, GeneratedArtifactLease>{};
    final previewLastReaders = <String, int>{};
    final previewReleaseRequested = <String>{};
    // Acknowledged native readers, including delayed avNormal(trim) and
    // avVisibility(lagrange). Producer order is not last-consumer order.
    int lastReader(Pw38Stage producer, String role) {
      if (producer == Pw38Stage.cer) return 3;
      if (producer == Pw38Stage.fusionPly && r.originalCacheOnly) return 9;
      if (producer == Pw38Stage.tsdf) return 5;
      if (producer == Pw38Stage.trim) return 11;
      if (producer == Pw38Stage.meshopt) return 7;
      if (producer == Pw38Stage.lagrange) return 9;
      if (producer == Pw38Stage.avVisibility)
        return role == 'sfm_json' ? 10 : 9;
      if (producer == Pw38Stage.avSfmToAbc) return 11;
      // Texture material is checked again before GLB and survives until publication.
      return 99;
    }

    void registerObserved(Pw38Stage producer) {
      for (final a in gate.measured.values) {
        if (!r.outputs[producer]!.any(
          (spec) => spec.fileSet
              ? a.path.startsWith('${spec.path}/') && a.role == spec.role
              : a.path == spec.path,
        ))
          continue;
        retirement!.register(
          a.path,
          bytes: a.bytes,
          sha256: a.sha256,
          lastReaderStage: lastReader(producer, a.role),
        );
        if (onPreview != null &&
            a.role == 'mesh_ply' &&
            const {
              Pw38Stage.tsdf,
              Pw38Stage.trim,
              Pw38Stage.meshopt,
              Pw38Stage.lagrange,
            }.contains(producer)) {
          previewLeases[a.path] = retirement.acquireLease(
            a.path,
            'async_viewer',
          );
          previewLastReaders[a.path] = lastReader(producer, a.role);
        }
      }
    }

    await journal('dense_native_binding');
    final whole = r.json['dense_producer_profile'] == wholeDenseProfile;
    Map<String, dynamic>? wholeRunProfile;
    if (whole) {
      wholeProfile ??= await loadWholeProfileForMainline(bootstrap);
      wholeRunProfile = await bindWholeProfileForRun(
        wholeProfile,
        bootstrap,
        proof: productionFixtureProof,
        request: File(bootstrap['request_path']!),
        requestSha256: bootstrap['request_sha256']!,
        frames: r.frames.length,
      );
      if (wholeObserverMetadata == null ||
          wholeObserverMetadata!['m0_trace_path'] !=
              wholeRunProfile['m0_trace_path'] ||
          wholeObserverMetadata!['m0_run_id'] != wholeRunProfile['m0_run_id'] ||
          wholeObserverMetadata!['m0_pid'] != pid ||
          wholeObserverMetadata!['m0_start_return_code'] != 0 ||
          wholeObserverMetadata!['return_code'] != 0 ||
          wholeObserverMetadata!['m0_initialize_boundary_return_code'] != 0 ||
          wholeObserverMetadata!['m0_stop_return_code'] != null) {
        throw StateError(
          'Whole observer metadata differs from actual proof/run binding',
        );
      }
    }
    final dense =
        denseCore ??
        (whole
            ? await openWholeDenseMainline(
                r,
                bootstrap['bundle_path']!,
                wholeProfile: wholeRunProfile!,
                identityScope: identityScope,
              )
            : await openRootBoundDense(r, bootstrap['bundle_path']!));
    bindings.add({
      'dense_header_sha256': dense.headerSha256,
      'dense_binary_sha256': dense.binarySha256,
      'dense_defined_symbols': dense.actualDefinedSymbols,
    });
    // Native init retains every selected parameter, including photo_first=false.
    // Native owns creation of work/retention roots; only create their parents.
    final fusion = object(r.paths['fusionPly']);
    for (final key in [
      'work_dir',
      if (!r.originalCacheOnly) 'out_ply',
      'fused_depth_dir',
    ]) {
      await File(
        '${owned.path}/${checkedRelativePath(string(fusion, key))}',
      ).parent.create(recursive: true);
    }
    if (r.originalCacheOnly) {
      await journal('original_python_runtime_binding');
      await native.initializePythonRuntime();
    }
    await journal(whole ? wholeDenseNativeEntry : 'pw_full38_dense_run');
    // Existing native counters are observational only; they do not append to
    // the13-stage completion journal or imply any point-cloud delivery.
    final denseReceipt = await dense.run(r, onProgress: onDenseProgress);
    denseResult = denseReceipt.nativeResult;
    if (whole) {
      validateWholeDenseReceipt(
        Map<String, dynamic>.from(denseResult),
        count: r.frames.length,
        outputRoot: r.ioRoots.downstreamOutputRoot,
        fusionPaths: fusion,
        identityScope: identityScope,
      );
    }
    final nativeEntry =
        denseResult['native_entry'] ??
        (whole
            ? throw StateError('Whole native entry receipt absent')
            : 'pw_full38_dense_run');
    if (denseReceipt.returnCode != 0 ||
        denseResult['status'] != 0 ||
        denseResult['frames'] != r.frames.length ||
        denseResult['fused_frames'] != r.frames.length) {
      return await finish(
        denseReceipt.returnCode == 0 ? 38 : denseReceipt.returnCode,
        'Actual native dense job did not complete97 fused references',
      );
    }
    if (r.originalCacheOnly) {
      final root = r.ioRoots.downstreamOutputRoot;
      if (denseResult['out_ply'] != '' ||
          denseResult['dense_producer_profile'] !=
              r.json['dense_producer_profile'] ||
          denseResult['fused_depth_dir'] !=
              '$root/${string(fusion, 'fused_depth_dir')}' ||
          denseResult['order_json'] !=
              '$root/${string(fusion, 'fused_depth_dir')}/order.json' ||
          denseResult['work_dir'] != '$root/${string(fusion, 'work_dir')}') {
        throw StateError(
          'Actual original cache-only result paths/profile mismatch',
        );
      }
    }
    for (final s in pw38StageOrder.take(4)) {
      final row = <String, Object?>{
        'stage': s.name,
        'entry_return_code': denseReceipt.returnCode,
        'native_entry': nativeEntry,
        'grouped_call': true,
        'native_phase_milliseconds': denseReceipt.phaseMilliseconds[s],
        'output_identity_status': s.index < 2
            ? 'NOT_RETAINED_BY_EXISTING_NATIVE_CALL'
            : 'OBSERVATION_PENDING',
      };
      stages.add(row);
      if (s.index >= 2) {
        row['outputs'] = await gate.observe(s);
        row['output_identity_status'] = 'OBSERVED_THIS_RUN';
        registerObserved(s);
      }
    }
    await r.bindActualRetention(gate);
    if (r.originalCacheOnly && denseResult['points'] != r.originalKeptTotal) {
      throw StateError('Original kept_total differs from actual native result');
    }
    await retirement.stageValidated(3);
    if (r.json['input_identity_status'] == 'ACCEPTED_REGENERATED_INPUTS') {
      // Production preparation copied the capture JPEGs into this run's inputs
      // before generating the independent normal PNGs. Dense/source validation
      // has now returned; suffix readers use texture/normal material instead.
      // Keep any JPEG also bound under another role (including JPEG normals).
      final protected = r.material
          .where((a) => a.role != 'source_jpeg')
          .map((a) => a.path)
          .toSet();
      final sourceRetirement = GeneratedArtifactRetirement(
        root: gate.inputRoot,
        evidenceFile: File(
          '${retirement.evidenceFile.parent.path}/source-jpeg-copy-retirement.json',
        ),
      );
      for (final a in r.material.where(
        (a) => a.role == 'source_jpeg' && !protected.contains(a.path),
      )) {
        sourceRetirement.register(
          a.path,
          bytes: a.bytes,
          sha256: a.sha256,
          lastReaderStage: 3,
        );
      }
      await sourceRetirement.stageValidated(3);
      await sourceRetirement.seal();
    }
    // Original stage order loads downstream consumers after dense output gates.
    await journal('downstream_native_binding');
    await native.bind();
    bindings.add({
      'available': native.drivers.keys.map((s) => s.name).toList(),
      'missing': native.missing.map((s, e) => MapEntry(s.name, e)),
    });
    for (final s in pw38StageOrder.skip(4)) {
      if (native.drivers[s] is! NativeDriver)
        throw StateError(
          '${s.name}: ${native.missing[s] ?? "Reconstruction native binding unavailable"}',
        );
    }
    for (final s in pw38StageOrder.skip(4)) {
      // Consumers receive only paths measured after their producer completed.
      final p = object(r.paths[s.name]);
      for (final key in const [
        'input_ply',
        'high_ply',
        'sfm_json',
        'sfm_abc',
        'low_obj',
        'obj',
      ]) {
        final value = p[key];
        if (value is String &&
            !(s == Pw38Stage.avVisibility && key == 'sfm_json') &&
            !(s == Pw38Stage.avSfmToAbc && key == 'sfm_abc'))
          await gate.verifyProduced(value);
      }
      if (s == Pw38Stage.tsdf || s == Pw38Stage.avVisibility) {
        for (var i = 0; i < r.frames.length; i++) {
          await gate.verifyProduced(r.retainedOutputPath(i, 'd16'));
          await gate.verifyProduced(r.retainedOutputPath(i, 'camera_f64'));
        }
      }
      if (s == Pw38Stage.glb) {
        for (final a
            in gate.measured.values
                .where(
                  (a) => [
                    'obj',
                    'mtl',
                    'color_png',
                    'normal_png',
                  ].contains(a.role),
                )
                .toList()) {
          await gate.verifyProduced(a.path);
        }
      }
      final suffixDisk = whole
          ? requirePw38SuffixLegacyAllowance(owned.path, stage: s.name)
          : null;
      await gate.prepare(s);
      await journal(s.name);
      final driver = native.drivers[s]! as NativeDriver;
      final watch = Stopwatch()..start();
      final rc = await driver.call();
      final row = <String, Object?>{
        'stage': s.name,
        'entry_return_code': rc,
        'native_entries_bound': driver.verifiedCAbiSymbols,
        'native_binary_sha256': driver.binarySha256,
        'elapsed_microseconds': watch.elapsedMicroseconds,
        'output_identity_status': 'OBSERVATION_PENDING',
        if (suffixDisk != null) 'disk_admission': suffixDisk,
      };
      stages.add(row);
      if (rc != 0)
        return await finish(rc, '${s.name} native consumer returned $rc');
      row['outputs'] = await gate.observe(s);
      row['output_identity_status'] = 'OBSERVED_THIS_RUN';
      registerObserved(s);
      if (s == Pw38Stage.texture &&
          r.json['input_identity_status'] == 'ACCEPTED_REGENERATED_INPUTS') {
        // Per-run scene JPG/CAM copies are read only by the awaited texture
        // consumer. avVisibility/avNormal use the separate original_images
        // and original_camera material; GLB uses the observed texture outputs.
        // Never retire a path that is also bound under another material role.
        final textureRoles = {'texture_image', 'texture_camera'};
        final protected = r.material
            .where((a) => !textureRoles.contains(a.role))
            .map((a) => a.path)
            .toSet();
        final sceneRetirement = GeneratedArtifactRetirement(
          root: gate.inputRoot,
          evidenceFile: File(
            '${retirement.evidenceFile.parent.path}/texture-input-retirement.json',
          ),
        );
        for (final a in r.material.where(
          (a) => textureRoles.contains(a.role) && !protected.contains(a.path),
        )) {
          sceneRetirement.register(
            a.path,
            bytes: a.bytes,
            sha256: a.sha256,
            lastReaderStage: s.index,
          );
        }
        await sceneRetirement.stageValidated(s.index);
        await sceneRetirement.seal();
      }
      if (s == Pw38Stage.avNormal &&
          r.json['input_identity_status'] == 'ACCEPTED_REGENERATED_INPUTS' &&
          (r.json['normal_input_format'] ?? 'png') == 'png') {
        await retireGeneratedNormalInputPngs(
          inputRoot: gate.inputRoot,
          evidenceFile: File('${retirement.evidenceFile.parent.path}/normal-input-retirement.json'),
          normalImages: r.orderedMaterial.map((frame) => artifact(frame['normal_image'])),
          allMaterial: r.material,
        );
      }
      if (s == Pw38Stage.meshopt) {
        // Native simplify bridge also writes two measured raw input arrays;
        // neither is read after that awaited native call returns.
        for (final key in ['positions_f32', 'indices_u32']) {
          final relative = checkedRelativePath(string(p, key));
          final file = await gate.regularFile(gate.runRoot, relative);
          retirement.register(
            relative,
            bytes: await file.length(),
            sha256: await hashFile(file),
            lastReaderStage: s.index,
          );
        }
      }
      // Display only completed, measured geometry. No new numerical operation,
      // producer call or predicted identity is introduced by this observation.
      if (onPreview != null &&
          const {
            Pw38Stage.tsdf,
            Pw38Stage.trim,
            Pw38Stage.meshopt,
            Pw38Stage.lagrange,
          }.contains(s)) {
        for (final a in gate.measured.values.where(
          (a) =>
              a.role == 'mesh_ply' &&
              r.outputPaths(s, 'mesh_ply').contains(a.path),
        )) {
          previewObserver.emit(
            Pw38PreviewArtifact(
              path: '${owned.path}/${a.path}',
              stage: s.name,
              role: 'ply',
              bytes: a.bytes,
              sha256: a.sha256,
            ),
          );
        }
      }
      await retirement.stageValidated(s.index);
      for (final entry in previewLastReaders.entries) {
        if (entry.value <= s.index && previewReleaseRequested.add(entry.key)) {
          onPreviewRetirementReady?.call(
            '${owned.path}/${entry.key}',
            previewLeases[entry.key]!.release,
          );
        }
      }
    }
    await journal('terminal_glb_format_validation');
    final glbPaths = r.outputPaths(Pw38Stage.glb, 'glb');
    if (glbPaths.length != 1)
      throw StateError('Exactly one terminal GLB required');
    await gate.verifyProduced(glbPaths.single);
    terminalValidation = await validateTerminalGlb(
      File('${owned.path}/${checkedRelativePath(glbPaths.single)}'),
    );
    await gate.verifyProduced(glbPaths.single);
    terminalValidation['absolute_path'] =
        '${owned.path}/${checkedRelativePath(glbPaths.single)}';
    final glbObserved = gate.measured[glbPaths.single]!;
    previewObserver.emit(
      Pw38PreviewArtifact(
        path: terminalValidation['absolute_path']! as String,
        stage: 'glb',
        role: 'glb',
        bytes: glbObserved.bytes,
        sha256: glbObserved.sha256,
      ),
    );
    stages.last['terminal_glb_format_validation'] = terminalValidation;
    runningStage = null;
    return await finish(0, null);
  } catch (e) {
    return await finish(38, '$e');
  }
}
