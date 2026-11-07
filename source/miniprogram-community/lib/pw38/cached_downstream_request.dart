import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'request.dart';
import 'cached_phone_segment.dart';
import 'reconstruction_artifact_gate.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';
import 'vendor/production_downstream_bridge_v3/lib/pw38_downstream.dart';

const cachedDownstreamSchema = 'PW38_CACHED_DOWNSTREAM_REQUEST_V1';
const cachedDownstreamRoute = 'CACHED_FILTERED_DEPTH_DIAGNOSTIC';
const cachedFilterResultSha256 = 'c80770f21b636d1117481754b1eb50619ba8d000de701fe450cc5d0d405608ba';
const cachedFilterManifestSha256 = 'fe2c763232752fdc0542912268005a62a3b3c76fdb5e0b3facd66073f92e937b';

String _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonical).join(',')}]';
  return jsonEncode(value);
}

final class CachedInputCopy {
  const CachedInputCopy(this.source, this.destination);
  final Pw38Artifact source;
  final String destination;
}

/// Frozen filtered cache transport only. No dense model, noise or MVS call.
final class CachedDownstreamRequest implements Pw38RequestTransport {
  CachedDownstreamRequest._(this.json, this.ioRoots, this.frames, this.material,
      this.ordered, this.outputs, this.copies, this.retained, this.phoneSegment);
  @override final Map<String, dynamic> json;
  @override final Pw38IoRoots ioRoots;
  @override final List<RequestFrame> frames;
  final List<Pw38Artifact> material;
  final List<Map<String, dynamic>> ordered;
  final Map<Pw38Stage, List<ReconstructionOutput>> outputs;
  final List<CachedInputCopy> copies;
  final List<Map<String, String>> retained;
  final CachedPhoneSegment? phoneSegment;
  List<Pw38Stage> get activeStages => phoneSegment?.activeStages ?? pw38StageOrder.skip(4).toList();
  String? get phoneSegmentRoot => phoneSegment?.parentRoot;
  List<Map<String, Object?>> get orderedFrameIdentity => cachedFrameIdentity(ordered);
  @override String get runId => string(json, 'run_id');
  @override Map<String, dynamic> get paths => object(json['stage_paths']);
  @override Map<String, dynamic> get native => object(json['native_libraries']);
  @override List<String> outputPaths(Pw38Stage stage, String role) =>
      outputs[stage]!.where((a) => a.role == role && !a.fileSet).map((a) => a.path).toList();
  @override String retainedOutputPath(int index, String key) => retained[index][key] ??
      (throw StateError('Unbound copied retained-cache field $key'));

  static Future<CachedDownstreamRequest> load(File file, String expectedHash) async {
    if (await hashFile(file) != expectedHash) throw StateError('Frozen cached downstream request changed');
    final j = object(jsonDecode(await file.readAsString()));
    return parse(j);
  }

  static CachedDownstreamRequest parse(Map<String, dynamic> j) {
    if (j['schema'] != cachedDownstreamSchema || j['route_id'] != cachedDownstreamRoute ||
        j['frame_count'] != 97 || j['normal_input_format'] != 'jpeg' ||
        j['classification'] != 'cached_filtered_depth_diagnostic_not_original38_or_production' ||
        ['dense_inputs', 'noise_identity', 'model_manifest_sha256', 'retained_upstream',
         'upstream_stage_receipts', 'outputs', 'full38_complete'].any(j.containsKey)) {
      throw StateError('Explicit97 cached-filter diagnostic request required; upstream success cannot be imported');
    }
    final io = object(j['io_roots']);
    final roots = Pw38IoRoots(durableInputRoot: string(io, 'durable_input_root'),
      downstreamOutputRoot: string(io, 'downstream_output_root'), textureSceneRoot: string(io, 'texture_scene_root'));
    roots.validate((j['cleanup_roots'] as List).cast<String>());
    final material = (j['material_inputs'] as List).map(artifact).toList();
    final lookup = {for (final a in material) a.path: a};
    if (lookup.length != material.length) throw StateError('Duplicate cached material path');
    Pw38Artifact bound(Object? value) {
      final a = artifact(value), actual = lookup[artifact(value).path];
      if (actual == null || actual.role != a.role || actual.bytes != a.bytes || actual.sha256 != a.sha256) {
        throw StateError('Cached ordered/manifest input absent from frozen material: ${a.path}');
      }
      return a;
    }
    final manifest = bound(j['input_manifest']);
    if (manifest.sha256 != j['ordered_input_manifest_sha256']) throw StateError('Ordered input manifest SHA binding required');
    final filter = bound(j['filter_result']);
    final filterManifest = bound(j['filter_output_manifest']);
    if (filter.sha256 != cachedFilterResultSha256 || filterManifest.sha256 != cachedFilterManifestSha256) {
      throw StateError('Exact existing selected-filter result and97 NPZ source manifest required');
    }
    final order = bound(j['retention_order']);
    if (!order.path.contains('/')) throw StateError('Scoped retention order path required');
    final sourceDir = order.path.substring(0, order.path.lastIndexOf('/'));
    if (order.path != '$sourceDir/order.json') throw StateError('Existing retention order.json required');
    final destinationDir = checkedRelativePath(string(j, 'retained_run_directory'));
    if (['RESULT.json', 'CACHE_COPY.json'].any((name) => destinationDir == name || destinationDir.startsWith('$name/'))) {
      throw StateError('Retained cache directory aliases run evidence');
    }
    final rows = (j['ordered_frames'] as List).map(object).toList();
    if (rows.length != 97) throw StateError('Exact97 retained tuples required');
    final frames = <RequestFrame>[];
    final copies = <CachedInputCopy>[CachedInputCopy(order, '$destinationDir/order.json')];
    final retained = <Map<String, String>>[];
    final originals = <int>{};
    final ids = <String>{};
    final scene = <String>{};
    final normals = <String>{};
    final photographs = <String>{};
    final originalCameras = <String>{};
    double? previous;
    for (var i = 0; i < 97; i++) {
      final row = rows[i];
      final original = row['original_index'] as int;
      final bits = string(row, 'frame_id_f64_bits');
      if (row['pack_index'] != i || original < 0 || !originals.add(original) ||
          !RegExp(r'^[0-9a-f]{16}$').hasMatch(bits) || !ids.add(bits)) throw StateError('Unique ordered cached identity required');
      final data = ByteData(8)..setUint64(0, int.parse(bits, radix: 16), Endian.big);
      final id = data.getFloat64(0, Endian.big);
      final width = row['width'] as int, height = row['height'] as int;
      if (!id.isFinite || (previous != null && id <= previous) || width != 768 || height != 576 || row['depth_scale'] != 5000) {
        throw StateError('This frozen Mac768 cache must retain actual768x576 order/shape and scale5000');
      }
      previous = id;
      final stem = original.toString().padLeft(8, '0');
      final d16 = bound(row['d16']), camera = bound(row['camera_f64']), metadata = bound(row['metadata']);
      if (d16.path != '$sourceDir/$stem.d16' || d16.bytes != width * height * 2 ||
          camera.path != '$sourceDir/$stem.camera.f64le' || camera.bytes != 200 || metadata.path != '$sourceDir/$stem.json') {
        throw StateError('Existing d16/K9-E16-f64 retention tuple layout required');
      }
      final destination = <String, String>{'d16': '$destinationDir/$stem.d16',
        'camera_f64': '$destinationDir/$stem.camera.f64le', 'metadata': '$destinationDir/$stem.json'};
      copies.addAll([CachedInputCopy(d16, destination['d16']!), CachedInputCopy(camera, destination['camera_f64']!),
        CachedInputCopy(metadata, destination['metadata']!)]);
      retained.add(destination);
      final originalCamera = bound(row['original_camera']);
      final source = bound(row['source_jpeg']), normal = bound(row['normal_image']);
      if (source.role != 'source_jpeg' || originalCamera.role != 'original_4032_camera' ||
          !photographs.add(source.path) || !originalCameras.add(originalCamera.path)) {
        throw StateError('Explicit original JPEG/camera material roles required');
      }
      if (normal.sha256 != source.sha256 || normal.bytes != source.bytes || normal.role != 'normal_image') {
        throw StateError('Normal JPEG must bind the same existing ordered source photograph');
      }
      if (!normals.add(normal.path)) throw StateError('Duplicate normal photograph');
      for (final key in ['texture_image', 'texture_camera']) {
        final a = bound(row[key]);
        if (!('${roots.durableInputRoot}/${a.path}').startsWith('${roots.textureSceneRoot}/') || !scene.add(a.path)) {
          throw StateError('Distinct complete texture JPG/CAM scene required');
        }
      }
      frames.add(RequestFrame(bits, width, height, originalCamera.path));
    }
    if (scene.length != 194) throw StateError('Exact97 texture JPG/CAM identities required');
    final specs = object(j['output_specs']), stagePaths = object(j['stage_paths']);
    final stages = pw38StageOrder.skip(4).toList();
    if (specs.length != 9 || stagePaths.length != 9 ||
        !stages.every((s) => specs.containsKey(s.name) && stagePaths.containsKey(s.name))) {
      throw StateError('Exactly nine real downstream stages, without dense stage declarations, required');
    }
    final outputs = {for (final s in stages) s: (specs[s.name] as List).map(ReconstructionOutput.fromJson).toList()};
    final declared = <String>{};
    for (final list in outputs.values) {
      for (final a in list) {
        if (!declared.add(a.path) || a.path == 'RESULT.json' || a.path == 'CACHE_COPY.json' ||
            a.path == destinationDir || a.path.startsWith('$destinationDir/') || destinationDir.startsWith('${a.path}/')) {
          throw StateError('Native output/cache-copy path alias forbidden');
        }
      }
    }
    final segment = j.containsKey('phone_process_segment')
        ? CachedPhoneSegment.parse(object(j['phone_process_segment']), roots.durableInputRoot,
            roots.downstreamOutputRoot, (j['cleanup_roots'] as List).cast<String>()) : null;
    final request = CachedDownstreamRequest._(j, roots, frames, material, rows, outputs, copies, retained, segment);
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
    for (final stage in pw38StageOrder.skip(4)) {
      if (!outputs[stage]!.map((a) => a.role).toSet().containsAll(pw38RequiredOutputRoles[stage]!)) {
        throw StateError('Complete ${stage.name} output roles required');
      }
    }
    for (final s in [Pw38Stage.tsdf, Pw38Stage.trim, Pw38Stage.meshopt, Pw38Stage.lagrange]) {
      if (one(s, 'mesh_ply') != p(s, 'output_ply')) throw StateError('${s.name} PLY output binding');
    }
    for (final pair in [(Pw38Stage.trim, Pw38Stage.tsdf), (Pw38Stage.meshopt, Pw38Stage.trim),
        (Pw38Stage.lagrange, Pw38Stage.meshopt), (Pw38Stage.texture, Pw38Stage.lagrange)]) {
      if (p(pair.$1, 'input_ply') != one(pair.$2, 'mesh_ply')) throw StateError('Current mesh dependency binding');
    }
    final prefix = p(Pw38Stage.texture, 'output_prefix');
    if (!prefix.contains('/')) throw StateError('Scoped texture output prefix required');
    final color = outputs[Pw38Stage.texture]!.where((a) => a.role == 'color_png').toList();
    final normal = outputs[Pw38Stage.avNormal]!.where((a) => a.role == 'normal_png').toList();
    final visibility = outputs[Pw38Stage.avVisibility]!.where((a) => a.role == 'visibility_byte_gate').toList();
    if (color.length != 1 || !color.single.fileSet || color.single.path != prefix.substring(0, prefix.lastIndexOf('/')) ||
        color.single.prefix != '${prefix.split('/').last}_' || color.single.suffix != '_map_Kd.png' ||
        normal.length != 1 || !normal.single.fileSet || normal.single.path != p(Pw38Stage.avNormal, 'normal_directory') ||
        normal.single.suffix != '.png' || visibility.length != 7 || visibility.any((a) => a.fileSet) ||
        !visibility.map((a) => a.path).toSet().containsAll([for (final name in ['V.f64le', 'col.u8', 'vi.i64le', 'cj.i64le', 'ox.f64le', 'oy.f64le', 'cams.f64le'])
          '${p(Pw38Stage.avVisibility, 'gate_directory')}/$name'])) throw StateError('Native dynamic output directory binding mismatch');
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
      throw StateError('Normal photograph roots differ');
    }
    for (var i = 0; i < 97; i++) {
      if (artifact(ordered[i]['normal_image']).path != '${p(Pw38Stage.avNormal, 'original_images')}/$i.jpg') {
        throw StateError('Exact view-ID normal JPEG path required');
      }
    }
  }

  Future<void> verifyMaterial(ReconstructionArtifactGate gate) async {
    for (final a in material) { await gate.verifyInput(a); }
    final input = artifact(json['input_manifest']);
    final document = object(jsonDecode(await (await gate.regularFile(gate.inputRoot, input.path)).readAsString()));
    final declaredMaterial = material.where((a) => a.path != input.path).map((a) =>
      {'path': a.path, 'role': a.role, 'bytes': a.bytes, 'sha256': a.sha256}).toList();
    if (document['schema'] != 'PW38_CACHED_INPUT_MANIFEST_V1' ||
        _canonical(document['ordered_frames']) != _canonical(ordered) ||
        _canonical(document['material_inputs']) != _canonical(declaredMaterial)) {
      throw StateError('Actual cached input manifest does not bind complete material and ordered tuples');
    }
    final filter = object(jsonDecode(await (await gate.regularFile(gate.inputRoot, artifact(json['filter_result']).path)).readAsString()));
    if (filter['status'] != 'PASS_EXISTING_DEPTH_SELECTED_FILTER_DIAGNOSTIC' || filter['frames'] != 97 ||
        filter['kept_pixels'] != 22610262 || filter['exit_code'] != 0 ||
        filter['output_manifest_sha256'] != artifact(json['filter_output_manifest']).sha256) {
      throw StateError('Existing filtered cache diagnostic receipt mismatch');
    }
    final filteredRows = (jsonDecode(await (await gate.regularFile(gate.inputRoot,
      artifact(json['filter_output_manifest']).path)).readAsString()) as List).map(object).toList();
    if (filteredRows.length != 98 || !(filteredRows.last['path'] as String).endsWith('/order.json') ||
        filteredRows.last['bytes'] != 413 ||
        filteredRows.last['sha256'] != '8c31b6c0bc81532bd6a6e8d615df3f4922ccca510c43ae9be177ef49d9b20d5a') {
      throw StateError('Exact97 source-filter NPZ plus original order manifest required');
    }
    var keptPixels = 0;
    for (var i = 0; i < 97; i++) {
      final source = filteredRows[i];
      if (source['frame'] != i || ordered[i]['source_npz_sha256'] != source['sha256'] ||
          ordered[i]['source_npz_bytes'] != source['bytes']) {
        throw StateError('Cached handoff must bind its corresponding existing filtered NPZ $i');
      }
      keptPixels += source['nonzero_depth_pixels'] as int;
    }
    if (keptPixels != 22610262) throw StateError('Existing filtered NPZ selected pixel total changed');
    final orderPath = artifact(json['retention_order']).path;
    final order = object(jsonDecode(await (await gate.regularFile(gate.inputRoot, orderPath)).readAsString()));
    final entries = (order['entries'] as List).map(object).toList();
    if (order['schema'] != 1 || order['status'] != 'complete' || order['width'] != 768 ||
        order['height'] != 576 || order['depth_scale'] != 5000 || entries.length != 97) {
      throw StateError('Actual existing retention order/shape mismatch');
    }
    for (var i = 0; i < 97; i++) {
      final row = ordered[i], e = entries[i];
      final original = row['original_index'] as int;
      final stem = original.toString().padLeft(8, '0');
      final metadata = artifact(row['metadata']);
      final meta = object(jsonDecode(await (await gate.regularFile(gate.inputRoot, metadata.path)).readAsString()));
      if (e['pack_index'] != i || e['original_index'] != original || e['frame_id_f64_bits'] != row['frame_id_f64_bits'] ||
          e['metadata'] != '$stem.json' || meta['schema'] != 1 || meta['pack_index'] != i || meta['original_index'] != original ||
          meta['frame_id_f64_bits'] != frames[i].frameIdF64Bits || meta['width'] != frames[i].width ||
          meta['height'] != frames[i].height || meta['depth_scale'] != 5000 || meta['d16'] != '$stem.d16' ||
          meta['d16_bytes'] != frames[i].width * frames[i].height * 2 || meta['camera'] != '$stem.camera.f64le' ||
          meta['camera_bytes'] != 200 || meta['camera_layout'] != 'K9_then_E16_row_major_f64le') {
        throw StateError('Existing retention metadata/order tuple mismatch $i');
      }
    }
    final expected = {for (final f in ordered) ...[artifact(f['texture_image']).path, artifact(f['texture_camera']).path]};
    final actual = <String>{};
    await for (final e in Directory(ioRoots.textureSceneRoot).list(recursive: true, followLinks: false)) {
      final kind = await FileSystemEntity.type(e.path, followLinks: false);
      if (kind == FileSystemEntityType.file) actual.add(e.path.substring(ioRoots.durableInputRoot.length + 1));
      else if (kind != FileSystemEntityType.directory) throw StateError('Nonregular cached texture material');
    }
    if (actual.length != 194 || !actual.containsAll(expected)) throw StateError('Actual complete97 JPG/CAM scene mismatch');
    final normalRoot = Directory('${ioRoots.durableInputRoot}/${checkedRelativePath(string(object(paths['avNormal']), 'original_images'))}');
    final normalNames = <String>{};
    await for (final e in normalRoot.list(followLinks: false)) {
      if (await FileSystemEntity.type(e.path, followLinks: false) != FileSystemEntityType.file) throw StateError('Nonregular normal JPEG material');
      normalNames.add(e.path.split('/').last);
    }
    if (normalNames.length != 97 || !normalNames.containsAll([for (var i = 0; i < 97; i++) '$i.jpg'])) {
      throw StateError('Actual exact97 normal JPEG set required');
    }
  }

  Future<void> verifyCopiedFrame(int index, ReconstructionArtifactGate gate) async {
    for (final key in ['d16', 'camera_f64', 'metadata']) {
      final source = artifact(ordered[index][key]);
      final file = await gate.regularFile(gate.runRoot, retainedOutputPath(index, key));
      if (await file.length() != source.bytes || await hashFile(file) != source.sha256) {
        throw StateError('Copied immutable retained input changed: $index/$key');
      }
    }
  }
}
