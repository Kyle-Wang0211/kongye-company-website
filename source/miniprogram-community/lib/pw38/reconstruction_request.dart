import 'frame_transport.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'request.dart';
import 'original_retention_io.dart';
import 'reconstruction_artifact_gate.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';
import 'vendor/production_downstream_bridge_v3/lib/pw38_downstream.dart';

const reconstructionSchema = 'PW38_OFFICIAL_RECONSTRUCTION_REQUEST_V1';
const reconstructionRoute = 'PW38_OFFICIAL_RECONSTRUCTION_V1';

/// New measurements belong to this run; no historical upstream success is imported.
final class ReconstructionRequest implements Pw38RequestTransport {
  ReconstructionRequest._(this.json, this.ioRoots, this.frames, this.material,
      this.outputs, this.orderedMaterial);
  @override final Map<String, dynamic> json;
  @override final Pw38IoRoots ioRoots;
  @override final List<RequestFrame> frames;
  final List<Pw38Artifact> material;
  final List<Map<String, dynamic>> orderedMaterial;
  final Map<Pw38Stage, List<ReconstructionOutput>> outputs;
  final retained = <int, Map<String, String>>{};
  /// Shared retained tuple layout, not evidence of the old numerical producer.
  bool get originalCacheOnly => usesOriginalRetained97(json);
  int? originalKeptTotal;
  @override String get runId => string(json, 'run_id');
  @override Map<String, dynamic> get paths => object(json['stage_paths']);
  @override Map<String, dynamic> get native => object(json['native_libraries']);
  @override List<String> outputPaths(Pw38Stage stage, String role) =>
      outputs[stage]!.where((a) => a.role == role && !a.fileSet).map((a) => a.path).toList();
  @override String retainedOutputPath(int index, String key) {
    final path = retained[index]?[key];
    if (path == null) throw StateError('Actual dense retention not yet observed for frame $index');
    return path;
  }

  static Future<ReconstructionRequest> load(File file, String expectedHash) async {
    if (await hashFile(file) != expectedHash) throw StateError('Frozen reconstruction request changed');
    final j = object(jsonDecode(await file.readAsString()));
    final count = frameTransportCount(j);
    if (j['schema'] != reconstructionSchema || j['route_id'] != reconstructionRoute ||
        j['ordered_frames'] != count || j['algorithm_revision'] != 'c0f26ee018a2b3f9d0fa773a49711cf203da9277' ||
        ['retained_upstream', 'artifact_format_evidence', 'native_input_format_receipt', 'outputs'].any(j.containsKey)) {
      throw StateError('Explicit selected97 reconstruction transport required');
    }
    if (j.containsKey('dense_producer_profile') && !usesOriginalRetained97(j)) {
      throw StateError('Unsupported explicit dense producer profile');
    }
    MainlineRequest.validateInputIdentity(j);
    for (final key in ['ordered_input_manifest_sha256', 'model_manifest_sha256', 'environment_manifest_sha256']) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(string(j, key))) throw StateError('Frozen $key required');
    }
    final io = object(j['io_roots']);
    final roots = Pw38IoRoots(durableInputRoot: string(io, 'durable_input_root'),
        downstreamOutputRoot: string(io, 'downstream_output_root'), textureSceneRoot: string(io, 'texture_scene_root'));
    roots.validate((j['cleanup_roots'] as List).cast<String>());
    final material = (j['material_inputs'] as List).map(artifact).toList();
    final lookup = {for (final a in material) a.path: a};
    if (lookup.length != material.length) throw StateError('Duplicate material input path');
    final ordered = (j['ordered_material'] as List).map(object).toList();
    final dense = object(j['dense_inputs']);
    final denseRows = (dense['frames'] as List).map(object).toList();
    if (ordered.length != count || denseRows.length != count || dense['input_root'] != roots.durableInputRoot) {
      throw StateError('Exact97 material and dense order under durable input root required');
    }
    final frames = <RequestFrame>[];
    final scene = <String>{};
    double? previous;
    for (var i = 0; i < count; i++) {
      final f = ordered[i], d = denseRows[i];
      final id = (d['frame_id'] as num).toDouble();
      final data = ByteData(8)..setFloat64(0, id, Endian.big);
      final bits = data.getUint64(0, Endian.big).toRadixString(16).padLeft(16, '0');
      if (f['pack_index'] != i || f['original_index'] != i || bits != f['frame_id_f64_bits'] ||
          !id.isFinite || (previous != null && id <= previous)) throw StateError('Selected97 order changed');
      previous = id;
      for (final key in ['source_jpeg', 'texture_image', 'texture_camera', 'normal_image', 'original_camera']) {
        final a = artifact(f[key]), actual = lookup[artifact(f[key]).path];
        if (actual == null || actual.sha256 != a.sha256 || actual.bytes != a.bytes || actual.role != a.role) {
          throw StateError('Ordered $key absent from frozen material inputs');
        }
        if (key.startsWith('texture_')) {
          if (!('${roots.durableInputRoot}/${a.path}').startsWith('${roots.textureSceneRoot}/')) {
            throw StateError('Texture material outside scene root');
          }
          scene.add(a.path);
        }
      }
      if (string(d, 'jpeg_path') != artifact(f['source_jpeg']).path) {
        throw StateError('Dense JPEG must bind this ordered source photograph');
      }
      frames.add(RequestFrame(bits, 1536, 1152, artifact(f['original_camera']).path));
    }
    if (scene.length != count * 2) throw StateError('Complete97 distinct JPG/CAM scene required');
    final denseArtifacts = (dense['artifacts'] as List).map(artifact).toList();
    if (denseArtifacts.map((a) => a.path).toSet().length != denseArtifacts.length) throw StateError('Duplicate dense input');
    for (final a in denseArtifacts) {
      final actual = lookup[a.path];
      if (actual == null || actual.sha256 != a.sha256 || actual.bytes != a.bytes || actual.role != a.role) {
        throw StateError('Dense input not bound to frozen material: ${a.path}');
      }
    }
    for (final d in denseRows) {
      if (!denseArtifacts.any((a) => a.path == d['jpeg_path'])) throw StateError('Dense JPEG manifest incomplete');
    }
    if (usesOriginalRetained97(j)) {
      validateOriginalFusionJpegs(dense, lookup, profile: j['dense_producer_profile'] as String);
    }
    final noise = object(j['noise_identity']);
    final originalNoise = noise['kind'] == 'original_E0_seed0_sorted97';
    final cpuNoise = noise['kind'] == 'official_PyTorch_CPU_E0_seed0_sorted97' ||
        (variableFrameTransport(j) && noise['kind'] == 'official_PyTorch_CPU_E0_seed0_prefix');
    if ((variableFrameTransport(j) && noise['kind'] != 'official_PyTorch_CPU_E0_seed0_prefix') || (!originalNoise && !cpuNoise) ||
        noise['ordered_input_manifest_sha256'] != j['ordered_input_manifest_sha256'] ||
        noise['low_sha256'] != lookup[dense['low_noise_f32']]?.sha256 ||
        noise['high_sha256'] != lookup[dense['high_noise_f32']]?.sha256) {
      throw StateError('Declared E0 noise lineage and actual hashes required');
    }
    if (cpuNoise) {
      // These are the actual outputs of the user-approved CPU reconstruction,
      // not an assertion that the missing historical CUDA bytes were recovered.
      final producer = lookup[dense['noise_producer_json']];
      if (variableFrameTransport(j)) {
        validateNoisePrefixIdentity(noise, count);
        if (lookup[dense['low_noise_f32']]?.bytes != lowNoiseBytes(count) || lookup[dense['high_noise_f32']]?.bytes != highNoiseBytes(count)) throw StateError('Actual noise prefix shape mismatch');
      }
      if (noise['backend'] != 'cpu' || noise['seed_base'] != 0 ||
          noise['seed_rule'] != 'torch.manual_seed(0 + frame_index)' ||
          noise['historical_cuda_byte_parity'] != 'NOT_CLAIMED' ||
          (!variableFrameTransport(j) && (noise['low_sha256'] != officialLowNoiseBankSha256 || noise['high_sha256'] != officialHighNoiseBankSha256)) ||
          producer == null || producer.role != 'noise_producer_evidence' ||
          producer.sha256 != 'aa09d2db3c79d940d0f741fae4dcd0523bf02d8ff69145cf98d5ed47aff4703f') {
        throw StateError('Approved CPU reconstruction output and producer binding required');
      }
    }
    final specs = object(j['output_specs']);
    if (specs.length != 13) throw StateError('Explicit13 stage output declarations required');
    final outputs = <Pw38Stage, List<ReconstructionOutput>>{};
    for (final stage in pw38StageOrder) {
      outputs[stage] = (specs[stage.name] as List).map(ReconstructionOutput.fromJson).toList();
    }
    // The native grouped call removes low rows and does not retain raw high rows.
    // Do not invent independently observed output identities for those phases.
    if (outputs[Pw38Stage.mvs768]!.isNotEmpty || outputs[Pw38Stage.mvs1536]!.isNotEmpty) {
      throw StateError('Native low/high phases do not retain standalone outputs');
    }
    final fusion = object(object(j['stage_paths'])['fusionPly']);
    if (fusion.containsKey('retained_frames')) throw StateError('Future retention hashes forbidden');
    final dir = checkedRelativePath(string(fusion, 'fused_depth_dir'));
    outputs[Pw38Stage.fusionPly]!.add(ReconstructionOutput('$dir/order.json', 'order'));
    if (!usesOriginalRetained97(j)) {
      outputs[Pw38Stage.fusionPly]!.add(ReconstructionOutput('$dir/order.json.partial', 'order_publication_evidence'));
    }
    for (var i = 0; i < count; i++) {
      final stem = '$dir/${i.toString().padLeft(8, '0')}';
      outputs[Pw38Stage.fusionPly]!.addAll([
        ReconstructionOutput('$stem.d16', 'retained_d16', shapeBytes: 1536 * 1152 * 2),
        ReconstructionOutput('$stem.camera.f64le', 'retained_camera', shapeBytes: 200),
        ReconstructionOutput('$stem.json', 'retained_metadata'),
        if (usesOriginalRetained97(j)) ReconstructionOutput('$stem.col.u8', 'retained_color', shapeBytes: 5308416)]);
    }
    final work = checkedRelativePath(string(fusion, 'work_dir'));
    final cer = outputs[Pw38Stage.cer]!;
    if(cer.length != 4) throw StateError('Four retained merged CER arrays required');
    for(final role in ['depth', 'conf0', 'conf1', 'conf2']) {
      final rows = cer.where((a) => a.role == role).toList();
      if(rows.length != 1 || rows.single.fileSet || rows.single.path != '$work/$role.f32' ||
          rows.single.shapeBytes != count * 1536 * 1152 * 4) throw StateError('Native merged CER shape/path mismatch');
    }
    final declaredPaths = <String>{};
    for(final stage in pw38StageOrder) {
      for(final a in outputs[stage]!) {
        if(!declaredPaths.add(a.path) && !a.fileSet) throw StateError('Output alias across stages');
        if(a.path == 'RESULT.json') throw StateError('Output collides with run journal');
      }
    }
    final request = ReconstructionRequest._(j, roots, frames, material, outputs, ordered);
    request.validateBindings();
    return request;
  }

  void validateBindings() {
    String p(Pw38Stage s, String key) => checkedRelativePath(string(object(paths[s.name]), key));
    String one(Pw38Stage s, String role) {
      final values = outputPaths(s, role);
      if (values.length != 1) throw StateError('One $role declaration required for ${s.name}');
      return values.single;
    }
    for (final stage in pw38StageOrder.skip(2)) {
      final requiredRoles = originalCacheOnly && stage == Pw38Stage.fusionPly
          ? {'retained_d16', 'retained_camera', 'retained_metadata', 'retained_color', 'order'}
          : pw38RequiredOutputRoles[stage]!;
      if (!outputs[stage]!.map((a) => a.role).toSet().containsAll(requiredRoles)) {
        throw StateError('Complete ${stage.name} output roles required');
      }
    }
    if (originalCacheOnly) {
      if (object(paths['fusionPly'])['out_ply'] != '' ||
          outputs[Pw38Stage.fusionPly]!.any((a) => a.role == 'dense_ply' || a.role == 'order_publication_evidence')) {
        throw StateError('Original retained-only producer forbids dense PLY/partial artifacts');
      }
    } else if (one(Pw38Stage.fusionPly, 'dense_ply') != p(Pw38Stage.fusionPly, 'out_ply')) {
      throw StateError('Dense PLY output binding');
    }
    for (final s in [Pw38Stage.tsdf, Pw38Stage.trim, Pw38Stage.meshopt, Pw38Stage.lagrange]) {
      if (one(s, 'mesh_ply') != p(s, 'output_ply')) throw StateError('${s.name} PLY output binding');
    }
    for (final pair in [(Pw38Stage.trim, Pw38Stage.tsdf), (Pw38Stage.meshopt, Pw38Stage.trim),
        (Pw38Stage.lagrange, Pw38Stage.meshopt), (Pw38Stage.texture, Pw38Stage.lagrange)]) {
      if (p(pair.$1, 'input_ply') != one(pair.$2, 'mesh_ply')) throw StateError('Current mesh dependency binding');
    }
    final prefix = p(Pw38Stage.texture, 'output_prefix');
    final color = outputs[Pw38Stage.texture]!.where((a) => a.role == 'color_png').toList();
    final normal = outputs[Pw38Stage.avNormal]!.where((a) => a.role == 'normal_png').toList();
    final visibility = outputs[Pw38Stage.avVisibility]!.where((a) => a.role == 'visibility_byte_gate').toList();
    if(color.length != 1 || !color.single.fileSet || color.single.path != prefix.substring(0,prefix.lastIndexOf('/')) ||
        color.single.prefix != '${prefix.split('/').last}_' || color.single.suffix != '_map_Kd.png' ||
        normal.length != 1 || !normal.single.fileSet || normal.single.path != p(Pw38Stage.avNormal,'normal_directory') ||
        normal.single.suffix != '.png' || visibility.length != 7 || visibility.any((a) => a.fileSet) ||
        !visibility.map((a) => a.path).toSet().containsAll([for(final name in ['V.f64le','col.u8','vi.i64le','cj.i64le','ox.f64le','oy.f64le','cams.f64le'])
          '${p(Pw38Stage.avVisibility,'gate_directory')}/$name'])) throw StateError('Native dynamic output directory binding mismatch');

    if (one(Pw38Stage.texture, 'obj') != '$prefix.obj' || one(Pw38Stage.texture, 'mtl') != '$prefix.mtl' ||
        p(Pw38Stage.avVisibility, 'high_ply') != one(Pw38Stage.lagrange, 'mesh_ply') ||
        one(Pw38Stage.avVisibility, 'sfm_json') != p(Pw38Stage.avVisibility, 'sfm_json') ||
        p(Pw38Stage.avSfmToAbc, 'sfm_json') != one(Pw38Stage.avVisibility, 'sfm_json') ||
        one(Pw38Stage.avSfmToAbc, 'sfm_abc') != p(Pw38Stage.avSfmToAbc, 'sfm_abc') ||
        p(Pw38Stage.avNormal, 'sfm_abc') != one(Pw38Stage.avSfmToAbc, 'sfm_abc') ||
        p(Pw38Stage.avNormal, 'low_obj') != one(Pw38Stage.texture, 'obj') ||
        p(Pw38Stage.avNormal, 'high_ply') != one(Pw38Stage.trim, 'mesh_ply') ||
        p(Pw38Stage.glb, 'obj') != one(Pw38Stage.texture, 'obj') ||
        p(Pw38Stage.glb, 'normal_directory') != p(Pw38Stage.avNormal, 'normal_directory') ||
        one(Pw38Stage.glb, 'glb') != p(Pw38Stage.glb, 'output_glb')) throw StateError('Actual downstream IO chain mismatch');
    if (p(Pw38Stage.avVisibility, 'original_images') != p(Pw38Stage.avNormal, 'original_images')) {
      throw StateError('Original photograph roots differ');
    }
    final normalInputFormat = json.containsKey('normal_input_format')
        ? json['normal_input_format'] : 'png';
    if (normalInputFormat != 'png' && normalInputFormat != 'jpeg') {
      throw StateError('Explicit normal input format must be png or jpeg');
    }
    for (var i = 0; i < orderedMaterial.length; i++) {
      final image = artifact(orderedMaterial[i]['normal_image']);
      final suffix = normalInputFormat == 'png' ? 'png' : 'jpg';
      if (image.path != '${p(Pw38Stage.avNormal, 'original_images')}/$i.$suffix') {
        throw StateError('Original photograph outside actual normal input folder');
      }
      if (normalInputFormat == 'jpeg') {
        final source = artifact(orderedMaterial[i]['source_jpeg']);
        if (image.bytes != source.bytes || image.sha256 != source.sha256) {
          throw StateError('Normal JPEG must bind the same ordered source photograph bytes');
        }
      }
    }
  }

  Future<void> verifyMaterial(ReconstructionArtifactGate gate) async {
    final count = frames.length;
    for (final a in material) { await gate.verifyInput(a); }
    final expected = {for (final f in orderedMaterial) ...[
      artifact(f['texture_image']).path, artifact(f['texture_camera']).path]};
    final actual = <String>{};
    await for (final e in Directory(ioRoots.textureSceneRoot).list(recursive: true, followLinks: false)) {
      final type = await FileSystemEntity.type(e.path, followLinks: false);
      if (type == FileSystemEntityType.file) actual.add(e.path.substring(ioRoots.durableInputRoot.length + 1));
      else if (type != FileSystemEntityType.directory) throw StateError('Nonregular texture scene input');
    }
    if (actual.length != count * 2 || !actual.containsAll(expected)) throw StateError('Actual complete97 texture scene mismatch');
  }

  Future<void> bindActualRetention(ReconstructionArtifactGate gate) async {
    final count = frames.length;
    final dir = checkedRelativePath(string(object(paths['fusionPly']), 'fused_depth_dir'));
    if (originalCacheOnly) {
      originalKeptTotal = await readOriginalRetained97(directory: dir, profile: json['dense_producer_profile'] as String,
          frameBits: frames.map((f) => f.frameIdF64Bits).toList(),
          regularFile: (path) => gate.regularFile(gate.runRoot, path),
          verifyProduced: gate.verifyProduced, retained: retained);
      return;
    }
    final order = object(jsonDecode(await (await gate.regularFile(gate.runRoot, '$dir/order.json')).readAsString()));
    final entries = (order['entries'] as List).map(object).toList();
    if (order['schema'] != 1 || order['status'] != 'complete' || order['width'] != 1536 ||
        order['height'] != 1152 || order['depth_scale'] != 5000 || entries.length != count) {
      throw StateError('Native producer completion/order transport mismatch');
    }
    for (var i = 0; i < count; i++) {
      final stem = i.toString().padLeft(8, '0'), e = entries[i];
      final metadataPath = '$dir/$stem.json';
      final meta = object(jsonDecode(await (await gate.regularFile(gate.runRoot, metadataPath)).readAsString()));
      if (e['pack_index'] != i || e['original_index'] != i || e['frame_id_f64_bits'] != frames[i].frameIdF64Bits ||
          e['metadata'] != '$stem.json' || meta['schema'] != 1 || meta['pack_index'] != i || meta['original_index'] != i ||
          meta['frame_id_f64_bits'] != frames[i].frameIdF64Bits || meta['width'] != 1536 || meta['height'] != 1152 ||
          meta['depth_scale'] != 5000 || meta['d16'] != '$stem.d16' || meta['d16_bytes'] != 3538944 ||
          meta['camera'] != '$stem.camera.f64le' || meta['camera_bytes'] != 200 ||
          meta['camera_layout'] != 'K9_then_E16_row_major_f64le') throw StateError('Actual native tuple order/shape mismatch');
      final d16 = '$dir/$stem.d16', camera = '$dir/$stem.camera.f64le';
      await gate.verifyProduced(d16); await gate.verifyProduced(camera);
      retained[i] = {'d16': d16, 'camera_f64': camera};
    }
  }
}

/// Explicit original PIL fusion photographs; inference JPEGs remain separate.
List<Map<String, dynamic>> validateOriginalFusionJpegs(
    Map<String, dynamic> dense, Map<String, Pw38Artifact> material, {String profile = originalRetained97Profile}) {
  final count = frameTransportCount({'dense_producer_profile': profile}, actualCount: (dense['frames'] as List).length);
  final value = dense['original_fusion_jpegs'];
  if (value is! List || value.length != count) throw StateError('Explicit original fusion97 JPEG table required');
  final rows = value.map(object).toList();
  final paths = <String>{};
  for (var i = 0; i < count; i++) {
    final row = rows[i];
    final frame = object((dense['frames'] as List)[i]);
    final bits = ByteData(8)..setFloat64(0, (frame['frame_id'] as num).toDouble(), Endian.big);
    final identity = bits.getUint64(0, Endian.big).toRadixString(16).padLeft(16, '0');
    final a = artifact(row['artifact']);
    final bound = material[a.path];
    if (row['pack_index'] != i || row['original_index'] != i || row['frame_id_f64_bits'] != identity ||
        !paths.add(a.path) || !a.path.endsWith('/${i.toString().padLeft(8, '0')}.jpg') ||
        a.role != 'original_fusion_jpeg' || bound == null || bound.role != a.role ||
        bound.bytes != a.bytes || bound.sha256 != a.sha256) {
      throw StateError('Original fusion JPEG order/material binding mismatch: $i');
    }
  }
  return rows;
}
