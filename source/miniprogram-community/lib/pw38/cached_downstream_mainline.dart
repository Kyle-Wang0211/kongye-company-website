import 'dart:convert';
import 'dart:io';
import 'cached_downstream_request.dart';
import 'cached_phone_segment.dart';
import 'native_downstream.dart';
import 'request.dart';
import 'reconstruction_artifact_gate.dart';
import 'terminal_glb.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';

/// Cached input IO plus the existing nine native consumers. No upstream stage
/// driver or upstream receipt is executed, synthesized, or imported here.
Future<Map<String, Object?>> runCachedDownstream(Map<String, String> bootstrap) async {
  CachedDownstreamRequest? request;
  Directory? owned;
  String? runningStage;
  Map<String, Object?>? terminalValidation;
  final stages = <Map<String, Object?>>[];
  final nativeCalls = <Map<String, Object?>>[];
  final bindings = <Map<String, Object?>>[];
  final copied = <Map<String, Object?>>[];
  final priorStages = <Map<String, Object?>>[];
  final lineageOrigins = <Map<String, Object?>>[];
  final priorArtifacts = <Map<String, Object?>>[];
  String? copyReceiptHash;
  bool copyComplete = false;
  Future<Map<String, Object?>> finish(int code, String? reason) async {
    final expectedStages = request?.activeStages ?? pw38StageOrder.skip(4).toList();
    final segmentComplete = code == 0 && reason == null && stages.length == expectedStages.length &&
        List.generate(stages.length, (i) => stages[i]['stage'] == expectedStages[i].name).every((v) => v) &&
        stages.every((s) => s['entry_return_code'] == 0 && s['output_identity_status'] == 'OBSERVED_THIS_RUN') &&
        nativeCalls.isNotEmpty && nativeCalls.every((c) => c['return_code'] == 0) && copyComplete;
    final lineage = [...priorStages, ...stages];
    final complete = segmentComplete && lineage.length == 9 &&
        List.generate(lineage.length, (i) => lineage[i]['stage'] == pw38StageOrder[i + 4].name).every((v) => v) &&
        lineage.every((s) => s['entry_return_code'] == 0 &&
          ['OBSERVED_THIS_RUN', priorPhoneOutputStatus].contains(s['output_identity_status'])) &&
        stages.every((s) => s['entry_return_code'] == 0 && s['output_identity_status'] == 'OBSERVED_THIS_RUN') &&
        terminalValidation?['status'] == 'PASS_TERMINAL_GLB_STRUCTURE';
    final value = <String, Object?>{
      'schema': 'PW38_CACHED_DOWNSTREAM_RESULT_V1', 'route_id': cachedDownstreamRoute,
      'classification': 'cached_filtered_depth_diagnostic_not_original38_or_production',
      'run_id': request?.runId, 'bundle_id': bootstrap['bundle_id'], 'build': bootstrap['build'],
      'request_sha256': bootstrap['request_sha256'], 'ordered_input_manifest_sha256': request?.json['ordered_input_manifest_sha256'],
      'filter_result': request?.json['filter_result'], 'filter_output_manifest': request?.json['filter_output_manifest'],
      'full38_complete': false, 'mvs_executed': false,
      'upstream_stage_receipts': 'NONE_IMPORTED_OR_SYNTHESIZED', 'downstream_complete': complete,
      'exit_code': code, 'stopped_reason': reason, 'running_stage': runningStage,
      'native_binding': bindings, 'actual_native_calls': nativeCalls, 'stages': stages,
      if (request?.phoneSegment != null) ...{
        'segment_complete': segmentComplete,
        'phone_process_segment': request!.json['phone_process_segment'],
        'current_phone_stages': stages,
        'prior_phone_stage_lineage': priorStages,
        'prior_stage_lineage': priorStages,
        'phone_lineage_origins': lineageOrigins,
        'parent_revalidated_artifacts': priorArtifacts,
        'ordered_frame_identity': request.orderedFrameIdentity,
        'native_library_identity': request.native,
        'segment_output_policy': 'CURRENT_ACTUAL_NATIVE_ONLY_PRIOR_OUTPUTS_REVALIDATED_SEPARATELY',
      },
      'cached_input_copy': {'classification': 'INPUT_IO_ONLY_NOT_NATIVE_STAGE_OUTPUT',
        'copied_files': copied.where((row) => row['status'] == 'copied_and_verified').length,
        'attempted_files': copied.length, 'complete': copyComplete, 'copy_receipt_sha256': copyReceiptHash},
      'output_identity_policy': request?.phoneSegment == null ? 'measured_after_actual_native_success' :
        'current_native_outputs_measured_after_success_prior_native_outputs_revalidated',
      'format_evidence_policy': 'actual_native_consumer_return_codes_and_terminal_glb_structure',
      'terminal_glb_format_validation': terminalValidation ?? 'NOT_CHECKED',
      'normal_input_format': 'jpeg', 'normal_metadata_gate': 'ACTUAL_NATIVE_CONSUMER_RETURNS_REQUIRED',
      'geometry_quality_or_production_acceptance': 'NOT_CLAIMED',
    };
    if (owned != null) await File('${owned.path}/RESULT.json').writeAsString(jsonEncode(value), flush: true);
    return value;
  }
  Future<void> journal(String stage) async {
    runningStage = stage;
    await finish(38, 'RUNNING: native process exit may leave this last persisted checkpoint');
  }
  try {
    if (bootstrap['bundle_id'] != 'com.kyle.pocketworldOnnxBench.k35476742' || bootstrap['build'] != '3810') {
      throw StateError('Dedicated Dense38 test app identity required; production app is outside this route');
    }
    final r = await CachedDownstreamRequest.load(File(bootstrap['request_path']!), bootstrap['request_sha256']!);
    request = r;
    final gate = ReconstructionArtifactGate(Directory(r.ioRoots.durableInputRoot),
      Directory(r.ioRoots.downstreamOutputRoot), r.outputs);
    await gate.requireFresh();
    // All immutable inputs and the actual header-format order/meta are checked
    // before creating the fresh App-owned run directory.
    await r.verifyMaterial(gate);
    await gate.runRoot.create(recursive: false); owned = gate.runRoot;
    await journal('cached_input_copy');
    final copyReceipt = File('${owned.path}/CACHE_COPY.json');
    Future<void> persistCopy(String status, [String? error]) async {
      await copyReceipt.writeAsString(jsonEncode({'schema': 'PW38_CACHED_INPUT_COPY_V1',
        'classification': 'INPUT_IO_ONLY_NOT_NATIVE_STAGE_OUTPUT', 'status': status,
        'request_sha256': bootstrap['request_sha256'], 'expected_files': r.copies.length,
        'copied_files': copied.where((row) => row['status'] == 'copied_and_verified').length,
        'copy_api': 'dart:io File.copy', 'numeric_return_code': 'NOT_EXPOSED_BY_DART_FILE_COPY',
        'files': copied, 'error': error}), flush: true);
    }
    try {
      await persistCopy('copying');
      for (final item in r.copies) {
        await gate.verifyInput(item.source);
        final source = await gate.regularFile(gate.inputRoot, item.source.path);
        final destination = File('${owned.path}/${checkedRelativePath(item.destination)}');
        await destination.parent.create(recursive: true);
        if (await FileSystemEntity.type(destination.path, followLinks: false) != FileSystemEntityType.notFound) {
          throw StateError('Fresh cached copy destination required: ${item.destination}');
        }
        final row = <String, Object?>{'source_path': item.source.path, 'destination_path': item.destination,
          'source_role': item.source.role, 'status': 'copy_started'};
        copied.add(row);
        row['copy_return_path'] = (await source.copy(destination.path)).path;
        row['source_bytes_after_copy'] = await source.length();
        row['source_sha256_after_copy'] = await hashFile(source);
        final verified = await gate.regularFile(gate.runRoot, item.destination);
        row['destination_bytes'] = await verified.length();
        row['destination_sha256'] = await hashFile(verified);
        await gate.verifyInput(item.source);
        if (row['source_bytes_after_copy'] != item.source.bytes || row['destination_bytes'] != item.source.bytes ||
            row['source_sha256_after_copy'] != item.source.sha256 || row['destination_sha256'] != item.source.sha256) {
          throw StateError('Copied retained input bytes changed: ${item.destination}');
        }
        row['status'] = 'copied_and_verified';
        await persistCopy('copying');
      }
      await persistCopy('complete');
      copyReceiptHash = await hashFile(copyReceipt); copyComplete = true;
    } catch (e) {
      if (copied.isNotEmpty && copied.last['status'] == 'copy_started') {
        copied.last['status'] = 'failed'; copied.last['error'] = e.toString();
        copied.last['os_error_code'] = e is FileSystemException ? e.osError?.errorCode : null;
      }
      await persistCopy('failed', e.toString());
      rethrow;
    }
    // Copies intentionally do not enter gate.measured: that map is reserved for
    // real native outputs. The native retained-path accessor reads this run root.
    final native = DownstreamNative(r, bootstrap['bundle_path']!, calls: nativeCalls);
    if (r.phoneSegment != null) {
      await journal('prior_phone_native_output_revalidation');
      priorStages.addAll(await r.phoneSegment!.copyValidatedPrior(r, gate, bootstrap['bundle_path']!,
        lineageOrigins, priorArtifacts));
    }
    await journal('native_binding');
    await native.bind(stages: r.activeStages);
    bindings.add({'available': native.drivers.keys.map((s) => s.name).toList(),
      'missing': native.missing.map((s, e) => MapEntry(s.name, e))});
    for (final s in r.activeStages) {
      if (native.drivers[s] is! NativeDriver) throw StateError('${s.name}: ${native.missing[s] ?? "Native cached downstream binding unavailable"}');
    }
    for (final s in r.activeStages) {
      final p = object(r.paths[s.name]);
      for (final key in const ['input_ply', 'high_ply', 'sfm_json', 'sfm_abc', 'low_obj', 'obj']) {
        final value = p[key];
        if (value is String && !(s == Pw38Stage.avVisibility && key == 'sfm_json') &&
            !(s == Pw38Stage.avSfmToAbc && key == 'sfm_abc')) await gate.verifyProduced(value);
      }
      if (s == Pw38Stage.tsdf || s == Pw38Stage.avVisibility) {
        for (var i = 0; i < 97; i++) { await r.verifyCopiedFrame(i, gate); }
      }
      if (s == Pw38Stage.glb) {
        for (final a in gate.measured.values.where((a) => ['obj', 'mtl', 'color_png', 'normal_png'].contains(a.role)).toList()) {
          await gate.verifyProduced(a.path);
        }
      }
      await gate.prepare(s); await journal(s.name);
      final driver = native.drivers[s]! as NativeDriver;
      final watch = Stopwatch()..start();
      final rc = await driver.call();
      final row = <String, Object?>{'stage': s.name, 'entry_return_code': rc,
        'native_entries_bound': driver.verifiedCAbiSymbols, 'native_binary_sha256': driver.binarySha256,
        'elapsed_microseconds': watch.elapsedMicroseconds, 'output_identity_status': 'OBSERVATION_PENDING'};
      stages.add(row);
      if (rc != 0) return await finish(rc, '${s.name} native consumer returned $rc');
      row['outputs'] = await gate.observe(s); row['output_identity_status'] = 'OBSERVED_THIS_RUN';
    }
    if (r.activeStages.last == Pw38Stage.glb) {
      await journal('terminal_glb_format_validation');
      final glb = r.outputPaths(Pw38Stage.glb, 'glb');
      if (glb.length != 1) throw StateError('One terminal GLB required');
      await gate.verifyProduced(glb.single);
      terminalValidation = await validateTerminalGlb(File('${owned.path}/${checkedRelativePath(glb.single)}'));
      await gate.verifyProduced(glb.single);
      stages.last['terminal_glb_format_validation'] = terminalValidation;
    }
    runningStage = null;
    return await finish(0, null);
  } catch (e) { return await finish(38, '$e'); }
}
