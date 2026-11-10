import 'dart:convert';
import 'dart:io';
import 'cached_downstream_request.dart';
import 'reconstruction_artifact_gate.dart';
import 'request.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';

const priorPhoneOutputStatus = 'PRIOR_PHONE_NATIVE_OUTPUT_REVALIDATED';
const initialPhoneParentSha256 = 'd42467b2a0dd95ad91207e070fe0c0549541b0226e81a366b450167456eb3339';

String _identityJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_identityJson(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_identityJson).join(',')}]';
  return jsonEncode(value);
}

/// Paths can move between process IO roots; every numerical/image byte identity remains fixed.
List<Map<String, Object?>> cachedFrameIdentity(List<Map<String, dynamic>> rows) => [
  for (final row in rows) {
    for (final key in ['pack_index', 'original_index', 'frame_id_f64_bits', 'width', 'height',
      'depth_scale', 'source_npz_sha256', 'source_npz_bytes']) key: row[key],
    for (final key in ['d16', 'camera_f64', 'metadata', 'original_camera', 'source_jpeg',
      'normal_image', 'texture_image', 'texture_camera']) key: {
        for (final field in ['role', 'bytes', 'sha256']) field: object(row[key])[field],
      },
  },
];

final class CachedPhoneSegment {
  CachedPhoneSegment._(this.first, this.last, this.parentRoot, this.parentResult, this.parentInputManifest);
  final Pw38Stage first, last;
  final String parentRoot;
  final Pw38Artifact parentResult;
  final Pw38Artifact? parentInputManifest;
  List<Pw38Stage> get activeStages => pw38StageOrder.sublist(first.index, last.index + 1);

  static CachedPhoneSegment parse(Map<String, dynamic> j, String inputRoot, String outputRoot,
      List<String> cleanupRoots) {
    final first = Pw38Stage.values.byName(string(j, 'first_stage'));
    final last = Pw38Stage.values.byName(string(j, 'last_stage'));
    if (!((first == Pw38Stage.texture && last == Pw38Stage.texture) ||
        (first == Pw38Stage.avVisibility && last == Pw38Stage.glb))) {
      throw StateError('Only the frozen texture or avVisibility..glb phone process segment is permitted');
    }
    final root = string(j, 'parent_run_root');
    if (!root.startsWith('/') || root.contains('\\') || root.contains('\x00') ||
        root.split('/').skip(1).any((p) => p.isEmpty || p == '.' || p == '..')) {
      throw StateError('Canonical absolute parent phone run root required');
    }
    bool overlap(String other) => root == other || root.startsWith('$other/') || other.startsWith('$root/');
    if ([inputRoot, outputRoot, ...cleanupRoots].any(overlap)) {
      throw StateError('Parent phone root cannot overlap input, fresh output or cleanup roots');
    }
    final result = artifact(j['parent_result']);
    if (result.path != 'RESULT.json' || result.role != 'parent_phone_result') {
      throw StateError('Only the frozen original parent RESULT.json is accepted');
    }
    return CachedPhoneSegment._(first, last, root, result,
      j['parent_input_manifest'] == null ? null : artifact(j['parent_input_manifest']));
  }

  String _slot(Pw38Stage stage) => switch (stage) {
    Pw38Stage.tsdf => 'tsdf', Pw38Stage.trim => 'meshio', Pw38Stage.meshopt => 'meshopt_ply',
    Pw38Stage.lagrange => 'geometry', Pw38Stage.texture => 'texture',
    Pw38Stage.avVisibility || Pw38Stage.avSfmToAbc || Pw38Stage.avNormal => 'normal',
    Pw38Stage.glb => 'glb', _ => throw StateError('No upstream stages in phone lineage'),
  };

  List<String> _requiredCalls(Pw38Stage stage) => switch (stage) {
    Pw38Stage.tsdf => ['pw38_vdb_create', 'pw38_vdb_integrate_d16_original_numpy',
      'pw38_vdb_extract_raw', 'pw38_trimesh_process_export_raw'],
    Pw38Stage.trim => ['pw38_open3d_clean_ply'], Pw38Stage.meshopt => ['pw38_meshopt_simplify_ply'],
    Pw38Stage.lagrange => ['pw38_lagrange_fill_ply'], Pw38Stage.texture => ['pw_texture38_run'],
    Pw38Stage.avVisibility => ['pw38_av_prepare_sfm_json'],
    Pw38Stage.avSfmToAbc => ['pw38_av_convert_sfm_to_abc'],
    Pw38Stage.avNormal => ['pw38_av_bake_normal'], Pw38Stage.glb => ['pw38_glb_export_obj'],
    _ => throw StateError('No upstream calls in phone lineage'),
  };

  Future<List<Map<String, Object?>>> copyValidatedPrior(CachedDownstreamRequest request,
      ReconstructionArtifactGate gate, String bundleRoot, List<Map<String, Object?>> origins,
      List<Map<String, Object?>> copiedArtifacts) async {
    final parentGate = ReconstructionArtifactGate(Directory(parentRoot), gate.runRoot, request.outputs);
    final receipt = await parentGate.regularFile(parentGate.inputRoot, parentResult.path);
    if (await receipt.length() != parentResult.bytes || await hashFile(receipt) != parentResult.sha256) {
      throw StateError('Frozen parent phone RESULT identity changed');
    }
    final parent = object(jsonDecode(await receipt.readAsString()));
    if (parent['schema'] != 'PW38_CACHED_DOWNSTREAM_RESULT_V1' || parent['route_id'] != cachedDownstreamRoute ||
        parent['classification'] != request.json['classification'] || parent['full38_complete'] != false ||
        parent['mvs_executed'] != false || parent['bundle_id'] != 'com.kyle.pocketworldOnnxBench.k35476742' ||
        parent['upstream_stage_receipts'] != 'NONE_IMPORTED_OR_SYNTHESIZED') {
      throw StateError('Parent must be an actual dedicated cached-filter diagnostic phone result');
    }
    Object? oldIdentity = parent['ordered_frame_identity'];
    if (first == Pw38Stage.texture) {
      if (parentResult.sha256 != initialPhoneParentSha256 || parentInputManifest == null ||
          parent['run_id'] != 'cached_filtered_OFFICIAL97_phone_v9' ||
          parent['request_sha256'] != '8d41d13bd7c1df671f60e5738f8736908b531b65d661dece01626d6b7ec9478c' ||
          parent['ordered_input_manifest_sha256'] != '172d3d49a388645809683f3cec8e050fa314ef5de8ab5b068a54d7f8691d65b8') {
        throw StateError('First segment must continue the exact frozen V9 failed result and bind its input manifest');
      }
      final manifest = parentInputManifest!;
      if (manifest.sha256 != parent['ordered_input_manifest_sha256']) {
        throw StateError('Parent input manifest SHA must be bound by original parent RESULT');
      }
      if (manifest.role != 'parent_phone_input_manifest' || !request.material.any((a) =>
          a.path == manifest.path && a.role == manifest.role && a.bytes == manifest.bytes && a.sha256 == manifest.sha256)) {
        throw StateError('Original parent manifest must be explicitly bound in current material');
      }
      await gate.verifyInput(manifest);
      final document = object(jsonDecode(await (await gate.regularFile(gate.inputRoot, manifest.path)).readAsString()));
      if (document['schema'] != 'PW38_CACHED_INPUT_MANIFEST_V1') throw StateError('Invalid parent ordered manifest');
      oldIdentity = cachedFrameIdentity((document['ordered_frames'] as List).map(object).toList());
    } else if (parent['segment_complete'] != true || parent['exit_code'] != 0 ||
        object(parent['phone_process_segment'])['first_stage'] != 'texture' ||
        object(parent['phone_process_segment'])['last_stage'] != 'texture') {
      throw StateError('Final segment requires a complete actual texture-only phone result');
    }
    if (_identityJson(oldIdentity) != _identityJson(request.orderedFrameIdentity)) {
      throw StateError('Parent ordered97 frame/depth/K/E/JPEG/camera byte identity differs');
    }
    final inherited = parent['prior_phone_stage_lineage'] == null ? <Map<String, dynamic>>[] :
      (parent['prior_phone_stage_lineage'] as List).map(object).toList();
    final current = (parent['stages'] as List).map(object).toList();
    if (first == Pw38Stage.avVisibility && (inherited.length != 4 || current.length != 1 ||
        object(object(parent['phone_process_segment'])['parent_result'])['sha256'] != initialPhoneParentSha256)) {
      throw StateError('Texture parent must preserve exactly the original four-stage phone lineage');
    }
    final prefix = [...inherited, ...current];
    final required = pw38StageOrder.sublist(4, first.index);
    if (prefix.length != required.length) throw StateError('Exact contiguous prior-stage prefix required');
    final parentCalls = (parent['actual_native_calls'] as List).map(object).toList();
    if (parentCalls.isEmpty || parentCalls.any((c) => c['return_code'] != 0)) {
      throw StateError('Parent actual native calls must contain only real rc0 calls');
    }
    final oldOrigins = parent['phone_lineage_origins'] == null ? <Map<String, dynamic>>[] :
      (parent['phone_lineage_origins'] as List).map(object).toList();
    if (first == Pw38Stage.avVisibility && (oldOrigins.length != 1 ||
        oldOrigins.single['result_sha256'] != initialPhoneParentSha256 ||
        oldOrigins.single['run_id'] != 'cached_filtered_OFFICIAL97_phone_v9' ||
        oldOrigins.single['request_sha256'] != '8d41d13bd7c1df671f60e5738f8736908b531b65d661dece01626d6b7ec9478c')) {
      throw StateError('Inherited phone lineage must retain the frozen original V9 origin');
    }
    origins.addAll(oldOrigins.map((o) => Map<String, Object?>.from(o)));
    origins.add({'run_id': parent['run_id'], 'request_sha256': parent['request_sha256'],
      'result_sha256': parentResult.sha256, 'run_root': parentRoot,
      'actual_native_calls': parentCalls, 'native_library_identity': parent['native_library_identity'] ?? request.native});
    final result = <Map<String, Object?>>[];
    final seen = <String>{};
    for (var i = 0; i < prefix.length; i++) {
      final row = prefix[i], stage = required[i];
      final inheritedStage = i < inherited.length;
      if (row['stage'] != stage.name || row['entry_return_code'] != 0 ||
          row['native_entries_bound'] is! List || (row['native_entries_bound'] as List).isEmpty ||
          row['output_identity_status'] != (inheritedStage ? priorPhoneOutputStatus : 'OBSERVED_THIS_RUN')) {
        throw StateError('Noncontiguous or unsuccessful prior native stage: ${stage.name}');
      }
      final library = object(request.native[_slot(stage)]);
      if (row['native_binary_sha256'] != library['binary_sha256']) {
        throw StateError('Prior ${stage.name} native binary differs from current request slot');
      }
      final nativeFile = await gate.regularFile(Directory(bundleRoot), string(library, 'bundle_relative_path'));
      if (await hashFile(nativeFile) != library['binary_sha256']) {
        throw StateError('Actual current packaged ${stage.name} library bytes changed');
      }
      final origin = inheritedStage ? object(row['origin']) : origins.last;
      if (inheritedStage && (origin['result_sha256'] != initialPhoneParentSha256 ||
          origin['run_id'] != 'cached_filtered_OFFICIAL97_phone_v9' ||
          origin['request_sha256'] != '8d41d13bd7c1df671f60e5738f8736908b531b65d661dece01626d6b7ec9478c' ||
          origin['native_binary_sha256'] != row['native_binary_sha256'])) {
        throw StateError('Inherited ${stage.name} origin identity changed');
      }
      final calls = inheritedStage ? (origins.singleWhere((o) => o['result_sha256'] == origin['result_sha256'])
        ['actual_native_calls'] as List).map(object).toList() : parentCalls;
      if (calls.isEmpty || calls.any((c) => c['return_code'] != 0) ||
          !_requiredCalls(stage).every((entry) => calls.any((c) => c['native_entry'] == entry))) {
        throw StateError('Actual rc0 native-call evidence missing for ${stage.name}');
      }
      if (stage == Pw38Stage.tsdf) {
        final integrate = calls.where((c) => c['native_entry'] == 'pw38_vdb_integrate_d16_original_numpy').toList();
        if (integrate.length != 97 || List.generate(97, (i) => i).any((index) =>
            integrate.where((c) => c['frame_index'] == index).length != 1)) {
          throw StateError('Original phone TSDF requires exactly97 actual ordered integration calls');
        }
      }
      final outputs = (row['outputs'] as List).map(object).toList();
      final specs = request.outputs[stage]!;
      final counts = {for (final spec in specs) spec: 0};
      for (final output in outputs) {
        final path = checkedRelativePath(string(output, 'path'));
        final matches = specs.where((s) => output['role'] == s.role && (s.fileSet
          ? path.startsWith('${s.path}/${s.prefix}') && path.endsWith(s.suffix!) &&
            path.substring(s.path.length + 1).split('/').length == 1 : path == s.path)).toList();
        final bytes = output['bytes'];
        if (matches.length != 1 || !seen.add(path) || bytes is! int || bytes < 0 ||
            (bytes == 0 && output['role'] != 'visibility_byte_gate') ||
            (matches.single.shapeBytes != null && matches.single.shapeBytes != bytes) ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(string(output, 'sha256'))) {
          throw StateError('Invalid or undeclared prior stage artifact: $path');
        }
        counts[matches.single] = counts[matches.single]! + 1;
        if (inheritedStage) {
          final previously = (parent['parent_revalidated_artifacts'] as List).map(object).where((a) => a['path'] == path).toList();
          if (previously.length != 1 || previously.single['sha256'] != output['sha256'] ||
              previously.single['bytes'] != bytes || previously.single['status'] != priorPhoneOutputStatus) {
            throw StateError('Inherited parent artifact was not independently revalidated: $path');
          }
        }
        final source = await parentGate.regularFile(parentGate.inputRoot, path);
        if (await source.length() != bytes || await hashFile(source) != output['sha256']) {
          throw StateError('Prior phone native artifact bytes changed: $path');
        }
        final destination = File('${gate.runRoot.path}/$path');
        await destination.parent.create(recursive: true);
        if (await FileSystemEntity.type(destination.path, followLinks: false) != FileSystemEntityType.notFound) {
          throw StateError('Prior artifact destination must be fresh: $path');
        }
        await source.copy(destination.path);
        final copied = await gate.regularFile(gate.runRoot, path);
        if (await copied.length() != bytes || await hashFile(copied) != output['sha256'] ||
            await source.length() != bytes || await hashFile(source) != output['sha256']) {
          throw StateError('Prior artifact copy/source stream SHA mismatch: $path');
        }
        gate.measured[path] = ObservedReconstructionArtifact(path, string(output, 'role'), bytes, string(output, 'sha256'));
        copiedArtifacts.add({'path': path, 'role': output['role'], 'bytes': bytes, 'sha256': output['sha256'],
          'status': priorPhoneOutputStatus, 'source_parent_root': parentRoot, 'parent_result_sha256': parentResult.sha256,
          'classification': 'PRIOR_NATIVE_ARTIFACT_IO_ONLY_NOT_THIS_RUN_NATIVE_OUTPUT'});
      }
      if (counts.entries.any((e) => e.value == 0 || (!e.key.fileSet && e.value != 1))) {
        throw StateError('Complete prior stage output set required: ${stage.name}');
      }
      result.add({...row, 'output_identity_status': priorPhoneOutputStatus,
        'origin': inheritedStage ? origin : {
          'run_id': parent['run_id'], 'request_sha256': parent['request_sha256'],
          'result_sha256': parentResult.sha256, 'run_root': parentRoot,
          'native_binary_sha256': row['native_binary_sha256'],
        },
        'revalidated_from_parent_result_sha256': parentResult.sha256});
    }
    if (await hashFile(receipt) != parentResult.sha256) throw StateError('Parent RESULT changed during prior IO');
    return result;
  }
}
