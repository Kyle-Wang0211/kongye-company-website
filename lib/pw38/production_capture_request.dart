import 'frame_transport.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'production_session_binding.dart';
import 'reconstruction_artifact_gate.dart';
import 'reconstruction_request.dart';
import 'request.dart';
import 'original_retention_io.dart';
import 'production_original_fixture_binding.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart' show checkedRelativePath;
import 'vendor/production_downstream_bridge_v3/lib/pw38_downstream.dart'
    show Pw38IoRoots;

/// Paths name already-produced files under [Pw38ProductionCaptureInput.inputRoot].
/// The session frame contains the actual photo resolver result and refined pose.
/// This transport does not select photographs, resize pixels, or format CAMs.
final class Pw38ProductionCaptureFrame {
  const Pw38ProductionCaptureFrame({
    required this.sessionFrame,
    required this.textureImagePath,
    required this.textureCameraPath,
    required this.originalCameraPath,
    required this.normalImagePath,
  });
  final ProductionSessionFrame sessionFrame;
  final String textureImagePath,
      textureCameraPath,
      originalCameraPath,
      normalImagePath;
}

/// The template supplies only the frozen recipe/model/native/output declarations.
/// Scene and corrected-camera production must precede this call. Their receipt
/// must be frozen by the caller, bind the actual refined frame transport, and
/// enumerate actual measured outputs; historical fixture receipts cannot suffice.
final class Pw38ProductionCaptureInput {
  const Pw38ProductionCaptureInput({
    required this.templateFile,
    required this.templateSha256,
    required this.inputRoot,
    required this.outputRoot,
    required this.preparationRoot,
    required this.runId,
    required this.cleanupRoots,
    required this.textureSceneRelativePath,
    required this.frames,
    required this.sparseXyzPath,
    required this.materialProducerReceipt,
    required this.materialProducerReceiptSha256,
    required this.pillowReceipt,
    required this.pillowReceiptSha256,
    this.sessionBinding,
    this.originalFixtureProof,
  });
  final File templateFile, materialProducerReceipt, pillowReceipt;
  final String templateSha256,
      materialProducerReceiptSha256,
      pillowReceiptSha256,
      runId,
      textureSceneRelativePath,
      sparseXyzPath;
  final Directory inputRoot, outputRoot, preparationRoot;
  final List<String> cleanupRoots;
  final List<Pw38ProductionCaptureFrame> frames;
  final ProductionSessionBinding? sessionBinding;
  final OriginalFixtureExecutionProof? originalFixtureProof;
}

final class Pw38PreparedProductionCapture {
  const Pw38PreparedProductionCapture({
    required this.request,
    required this.requestFile,
    required this.requestSha256,
    required this.receiptFile,
    required this.receiptSha256,
    this.originalFixtureProof,
  });
  final ReconstructionRequest request;
  final File requestFile, receiptFile;
  final String requestSha256, receiptSha256;
  final OriginalFixtureExecutionProof? originalFixtureProof;
}

String _jsonHash(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

String _relative(String path) {
  checkedRelativePath(path);
  if (path.contains('\\') ||
      path.contains('\u0000') ||
      path.split('/').any((p) => p.isEmpty || p == '.' || p == '..')) {
    throw FormatException('Nonescaping production material path required');
  }
  return path;
}

Future<void> _noLinks(String path) async {
  if (!path.startsWith('/') ||
      path == '/' ||
      path.endsWith('/') ||
      path.contains('\\') ||
      path.contains('\u0000') ||
      path
          .substring(1)
          .split('/')
          .any((p) => p.isEmpty || p == '.' || p == '..')) {
    throw FormatException('Absolute production path required');
  }
  var prefix = '';
  for (final part in path.substring(1).split('/')) {
    prefix += '/$part';
    if (await FileSystemEntity.type(prefix, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Symlink in production path: $prefix');
    }
  }
}

Future<void> _fresh(String path) async {
  await _noLinks(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError(
      'Production preparation preserves existing artifacts: $path',
    );
  }
}

Future<Map<String, dynamic>> _measured(
  String root,
  String path,
  String role,
) async {
  final file = File('$root/${_relative(path)}');
  await _noLinks(file.path);
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError('Actual regular production material required: $path');
  }
  final size = await file.length();
  final hash = await hashFile(
    file,
  ); // Streaming; never buffer photographs/noise.
  if (size <= 0 || await file.length() != size) {
    throw StateError('Empty or changing production material: $path');
  }
  return {'path': path, 'role': role, 'bytes': size, 'sha256': hash};
}

Future<Map<String, dynamic>> _frozenJson(File file, String expected) async {
  await _noLinks(file.path);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected) ||
      await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await hashFile(file) != expected) {
    throw StateError(
      'Frozen production receipt/template changed: ${file.path}',
    );
  }
  final value = object(jsonDecode(await file.readAsString()));
  if (await hashFile(file) != expected)
    throw StateError('Receipt changed while reading');
  return value;
}

String _sourceRelative(String root, String absolute) {
  if (!absolute.startsWith('$root/')) {
    throw StateError('Actual JPEG must be under durable input root');
  }
  return _relative(absolute.substring(root.length + 1));
}

Map<String, dynamic> _frameTransport(String root, ProductionSessionFrame f) => {
  'frame_id': f.frameId,
  'fx': f.fx,
  'fy': f.fy,
  'cx': f.cx,
  'cy': f.cy,
  'image_w': f.imageW,
  'image_h': f.imageH,
  'q_wxyz': f.qWxyz,
  't': f.translation,
  'jpeg_path': _sourceRelative(root, f.jpegPath),
};

/// Producer receipts use this exact JSON transport digest to bind poses, real
/// photograph names, intrinsics and order. No camera arithmetic occurs here.
String productionCaptureFrameTransportSha256(
  String inputRoot,
  List<Pw38ProductionCaptureFrame> frames,
) => _jsonHash(
  frames.map((f) => _frameTransport(inputRoot, f.sessionFrame)).toList(),
);

void _sameArtifact(
  Map<String, dynamic> expected,
  Map<String, dynamic> measured,
) {
  for (final key in ['path', 'role', 'bytes', 'sha256']) {
    if (expected[key] != measured[key]) {
      throw StateError(
        'Producer receipt does not bind actual $key: ${measured['path']}',
      );
    }
  }
}

/// Call from the existing reconstruction worker. All input files are read-only;
/// only fresh session transports and preparation evidence are created. Failures
/// remain on disk. This does not start a dense run or declare any stage success.
Future<Pw38PreparedProductionCapture> prepareProductionCaptureRequest(
  Pw38ProductionCaptureInput input,
) async {
  if (input.frames.isEmpty || input.runId.isEmpty) {
    throw StateError('Exact97 actually ordered production frames required');
  }
  final root = input.inputRoot.path, output = input.outputRoot.path;
  final prep = input.preparationRoot.path;
  await _noLinks(root);
  if (await FileSystemEntity.type(root, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw StateError('Already-produced durable material root required');
  }
  await _fresh(output);
  await _fresh(prep);
  final scene = '$root/${_relative(input.textureSceneRelativePath)}';
  Pw38IoRoots(
    durableInputRoot: root,
    downstreamOutputRoot: output,
    textureSceneRoot: scene,
  ).validate(input.cleanupRoots);
  for (final path in input.cleanupRoots) {
    await _noLinks(path);
  }
  // Use the same root separation gate as the strict reconstruction transport.
  final template = await _frozenJson(input.templateFile, input.templateSha256);
  final recipe = template['request'] == null
      ? template
      : object(template['request']);
  if (recipe['schema'] != reconstructionSchema ||
      recipe['route_id'] != reconstructionRoute ||
      recipe['ordered_frames'] != 97 ||
      recipe['algorithm_revision'] !=
          'c0f26ee018a2b3f9d0fa773a49711cf203da9277' ||
      (recipe['normal_input_format'] ??
              template['normal_input_format'] ??
              'png') !=
          'png') {
    throw StateError('Frozen selected97 PNG reconstruction recipe required');
  }
  final count = frameTransportTemplateActualCount(
    recipe,
    actualCount: input.frames.length,
  );
  requireProductionDenseProvenance(recipe, proof: input.originalFixtureProof);
  await input.originalFixtureProof?.revalidate();
  // Deliberate whitelist: stale fixture identity/origin/success fields never copy.
  final request = <String, dynamic>{
    for (final key in [
      'schema',
      'route_id',
      'algorithm_revision',
      'ordered_frames',
      'stage_paths',
      'output_specs',
      'model_manifest_sha256',
      'environment_manifest_sha256',
      'native_libraries',
      'noise_identity',
    ])
      key: jsonDecode(jsonEncode(recipe[key])),
  };
  if (recipe.containsKey('dense_producer_profile')) {
    request['dense_producer_profile'] = recipe['dense_producer_profile'];
  }
  request['ordered_frames'] = count;
  // CER declarations bind actual N; spatial resolution and numerical recipe stay fixed.
  for (final raw in object(request['output_specs'])['cer'] as List) {
    final row = object(raw);
    if (['depth', 'conf0', 'conf1', 'conf2'].contains(row['role'])) {
      if (row['shape_bytes'] != mergedCerBytes(officialNoiseBankCapacity)) throw StateError('Frozen capacity97 CER shape required');
      row['shape_bytes'] = mergedCerBytes(count);
    }
  }
  request['run_id'] = input.runId;
  request['io_roots'] = {
    'durable_input_root': root,
    'downstream_output_root': output,
    'texture_scene_root': scene,
  };
  request['cleanup_roots'] = List<String>.of(input.cleanupRoots);
  final normalRoot = _relative(
    string(
      object(object(request['stage_paths'])['avNormal']),
      'original_images',
    ),
  );
  if (prep == root ||
      prep.startsWith('$root/') ||
      root.startsWith('$prep/') ||
      prep == output ||
      prep.startsWith('$output/') ||
      output.startsWith('$prep/')) {
    throw StateError('Disjoint preparation/input/output roots required');
  }
  // Obtain root/order/schema checks without adopting historical material hashes.
  final producer = await _frozenJson(
    input.materialProducerReceipt,
    input.materialProducerReceiptSha256,
  );
  final transport = input.frames
      .map((f) => _frameTransport(root, f.sessionFrame))
      .toList();
  final transportHash = _jsonHash(transport);
  if (producer['schema'] != 'PW38_PRODUCTION_MATERIAL_RECEIPT_V1' ||
      producer['status'] != 'complete$count' ||
      producer['return_code'] != 0 ||
      producer['dense_frames_sha256'] != transportHash ||
      producer['ordered_frames'] != count) {
    throw StateError(
      'Actual refined97 scene/camera producer receipt required; producer is not implemented here',
    );
  }
  final producerOutputs = (producer['material_outputs'] as List)
      .map(object)
      .toList();
  final boundOutputs = {
    for (final row in producerOutputs) string(row, 'path'): row,
  };
  if (boundOutputs.length != producerOutputs.length)
    throw StateError('Duplicate producer output');
  final materials = <Map<String, dynamic>>[],
      ordered = <Map<String, dynamic>>[];
  final paths = <String>{};
  Future<Map<String, dynamic>> measure(String path, String role) async {
    if (!paths.add(path))
      throw StateError('Aliased production material: $path');
    final observed = await _measured(root, path, role);
    materials.add(observed);
    return observed;
  }

  Future<Map<String, dynamic>> produced(String path, String role) async {
    final observed = await measure(path, role);
    final bound = boundOutputs[path];
    if (bound == null)
      throw StateError('Unbound scene/camera producer output: $path');
    _sameArtifact(bound, observed);
    return observed;
  }

  double? previous;
  for (var i = 0; i < count; i++) {
    final frame = input.frames[i], f = frame.sessionFrame;
    final bits = ByteData(8)..setFloat64(0, f.frameId, Endian.big);
    final identity = bits
        .getUint64(0, Endian.big)
        .toRadixString(16)
        .padLeft(16, '0');
    final numbers = [
      f.frameId,
      f.fx,
      f.fy,
      f.cx,
      f.cy,
      f.imageW,
      f.imageH,
      ...f.qWxyz,
      ...f.translation,
    ];
    if (numbers.any((n) => !n.isFinite) ||
        identity != f.frameIdF64Bits ||
        (previous != null && f.frameId <= previous) ||
        f.qWxyz.length != 4 ||
        f.translation.length != 3 ||
        f.fx <= 0 ||
        f.fy <= 0 ||
        f.imageW != 4032 ||
        f.imageH != 3024 ||
        f.qWxyz.every((n) => n == 0) ||
        frame.normalImagePath != '$normalRoot/$i.png' ||
        !frame.textureImagePath.startsWith(
          '${input.textureSceneRelativePath}/',
        ) ||
        !frame.textureCameraPath.startsWith(
          '${input.textureSceneRelativePath}/',
        )) {
      throw StateError(
        'Selected recipe needs original12MP actual refined frame $i',
      );
    }
    previous = f.frameId;
    ordered.add({
      'pack_index': i,
      'original_index': i,
      'frame_id': f.frameId,
      'frame_id_f64_bits': identity,
      'q_wxyz': f.qWxyz,
      't': f.translation,
      'source_jpeg': await produced(
        _sourceRelative(root, f.jpegPath),
        'source_jpeg',
      ),
      'texture_image': await produced(frame.textureImagePath, 'texture_image'),
      'texture_camera': await produced(
        frame.textureCameraPath,
        'texture_camera',
      ),
      'original_camera': await produced(
        frame.originalCameraPath,
        'original_4032_camera',
      ),
      'normal_image': await measure(frame.normalImagePath, 'normal_image'),
    });
  }
  final pillow = await _frozenJson(
    input.pillowReceipt,
    input.pillowReceiptSha256,
  );
  final pillowRows = (pillow['frames'] as List).map(object).toList();
  if (pillow['schema'] != 'pw38.normal_image_io.v1' ||
      pillow['status'] != 'complete' ||
      pillow['return_code'] != 0 ||
      pillow['prepared_count'] != count ||
      pillowRows.length != count ||
      pillow['output_directory'] != '$root/$normalRoot') {
    throw StateError(
      'Actual original Pillow raw RGB PNG completion receipt required',
    );
  }
  for (var i = 0; i < count; i++) {
    final row = pillowRows[i], source = object(ordered[i]['source_jpeg']);
    final normal = object(ordered[i]['normal_image']);
    if (row['pack_index'] != i ||
        row['status'] != 'prepared' ||
        row['source_path'] != '$root/${source['path']}' ||
        row['actualpath'] != '$root/${normal['path']}' ||
        row['source_bytes'] != source['bytes'] ||
        row['source_sha256'] != source['sha256'] ||
        row['actual_source_bytes'] != source['bytes'] ||
        row['actual_source_sha256'] != source['sha256'] ||
        row['bytes'] != normal['bytes'] ||
        row['sha256'] != normal['sha256'] ||
        jsonEncode(row['size']) != '[4032,3024]' ||
        jsonEncode(row['source_pixel_size']) != '[4032,3024]') {
      throw StateError('Pillow receipt/source/output binding failed: $i');
    }
  }
  final evidence = <String, Map<String, dynamic>>{};
  for (final key in [
    'source_manifest',
    'image_producer_command',
    'camera_producer_command',
  ]) {
    final declared = object(producer[key]);
    final measured = await measure(
      string(declared, 'path'),
      string(declared, 'role'),
    );
    _sameArtifact(declared, measured);
    evidence[key] = measured;
  }
  final sourceManifest = object(
    jsonDecode(
      await File(
        '$root/${evidence['source_manifest']!['path']}',
      ).readAsString(),
    ),
  );
  final sourceRows = (sourceManifest['source_jpegs'] as List)
      .map(object)
      .toList();
  if (sourceManifest['schema'] != 'PW38_PRODUCTION_SOURCE_MANIFEST_V1' ||
      sourceManifest['dense_frames_sha256'] != transportHash ||
      sourceRows.length != count) {
    throw StateError(
      'Measured source manifest must bind current refined97 transport',
    );
  }
  for (var i = 0; i < count; i++) {
    _sameArtifact(sourceRows[i], object(ordered[i]['source_jpeg']));
  }
  final sparse = await produced(input.sparseXyzPath, 'sparse_xyz_f32');
  if ((sparse['bytes'] as int) % 12 != 0 ||
      (sparse['bytes'] as int) ~/ 12 > 0x7fffffff) {
    throw StateError('Original native sparse xyz triple count required');
  }
  final oldDense = object(recipe['dense_inputs']);
  final denseArtifacts = <Map<String, dynamic>>[
    ...ordered.map((f) => object(f['source_jpeg'])),
    sparse,
  ];
  for (final key in [
    'low_noise_f32',
    'high_noise_f32',
    'noise_producer_json',
  ]) {
    final path = string(oldDense, key);
    final declared = (oldDense['artifacts'] as List)
        .map(object)
        .singleWhere((a) => a['path'] == path);
    final measured = await measure(path, string(declared, 'role'));
    if (variableFrameTransport(request) && key != 'noise_producer_json') {
      final prefixes = object(producer['noise_prefix_streams']);
      final prefix = object(prefixes[key == 'high_noise_f32' ? 'high' : 'low']);
      if (measured['bytes'] != prefix['bytes'] || measured['sha256'] != prefix['sha256']) throw StateError('Measured request noise differs from exact bank prefix');
    } else { _sameArtifact(declared, measured); }
    denseArtifacts.add(measured);
  }
  final originalFusionRows = <Map<String, dynamic>>[];
  if (usesOriginalRetained97(request)) {
    final proof = input.originalFixtureProof!;
    await proof.revalidate();
    for (var i = 0; i < count; i++) {
      final path = 'original_fixture_rgb/${i.toString().padLeft(8, '0')}.jpg';
      final actual = await produced(path, 'original_fusion_jpeg');
      final generated = (proof.receipt['outputs'] as List)
          .map(object)
          .singleWhere(
            (row) => row['path'] == 'rgb/${i.toString().padLeft(8, '0')}.jpg',
          );
      if (actual['bytes'] != generated['bytes'] ||
          actual['sha256'] != generated['sha256']) {
        throw StateError(
          'Current original producer fusion JPEG was substituted',
        );
      }
      originalFusionRows.add({
        'pack_index': i,
        'original_index': i,
        'frame_id_f64_bits': ordered[i]['frame_id_f64_bits'],
        'artifact': actual,
      });
      denseArtifacts.add(actual);
    }
  }
  // Reserve every output before invoking native work. Never overwrite old tables.
  const cameraPath = 'production_session/cams.f32';
  const neighborPath = 'production_session/neighbors.i32';
  await _fresh('$root/production_session');
  await _fresh(output);
  await _fresh(prep);
  final sparseBytes = await File('$root/${input.sparseXyzPath}').readAsBytes();
  if (await hashFile(File('$root/${input.sparseXyzPath}')) !=
      sparse['sha256']) {
    throw StateError('Sparse input changed before actual native session build');
  }
  final session = usesOriginalRetained97(request)
      ? await input.originalFixtureProof!.sessionTables()
      : input.sessionBinding!.build(
          frames: input.frames.map((f) => f.sessionFrame).toList(),
          sparseXyzF32: sparseBytes,
        );
  if (producer['session_cameras_f32_sha256'] !=
          sha256.convert(session.camerasF32).toString() ||
      producer['session_neighbors_i32_sha256'] !=
          sha256.convert(session.neighborsI32).toString()) {
    throw StateError(
      'Scene producer and dense inference must use identical native session tables',
    );
  }
  await Directory('$root/production_session').create();
  await File('$root/$cameraPath').writeAsBytes(session.camerasF32, flush: true);
  await File(
    '$root/$neighborPath',
  ).writeAsBytes(session.neighborsI32, flush: true);
  denseArtifacts.add(
    await measure(cameraPath, 'production_session_cameras_f32'),
  );
  denseArtifacts.add(
    await measure(neighborPath, 'production_session_neighbors_i32'),
  );
  final dense = <String, dynamic>{
    'input_root': root,
    'frames': transport,
    'sparse_xyz_f32': input.sparseXyzPath,
    'cameras_f32': cameraPath,
    'neighbors_i32': neighborPath,
    'artifacts': denseArtifacts,
    if (usesOriginalRetained97(request))
      'original_fusion_jpegs': originalFusionRows,
    for (final key in [
      'low_noise_f32',
      'high_noise_f32',
      'noise_producer_json',
    ])
      key: oldDense[key],
  };
  if (variableFrameTransport(request)) {
    final noise = object(request['noise_identity']);
    noise['kind'] = 'official_PyTorch_CPU_E0_seed0_prefix';
    noise['ordered_frames'] = count;
    noise['prefix_streams'] = producer['noise_prefix_streams'];
    noise['source_producer_sha256'] = officialNoiseProducerSha256;
    for (final high in [false, true]) {
      final row = denseArtifacts.singleWhere((a) => a['path'] == oldDense[high ? 'high_noise_f32' : 'low_noise_f32']);
      noise[high ? 'high_sha256' : 'low_sha256'] = row['sha256'];
    }
    validateNoisePrefixIdentity(noise, count);
  }
  request['dense_inputs'] = dense;
  request['ordered_material'] = ordered;
  request['material_inputs'] = materials;
  await input.preparationRoot.create(recursive: false);
  Future<(File, String)> write(String name, Object value) async {
    final file = File('$prep/$name');
    await _fresh(file.path);
    await file.writeAsString('${jsonEncode(value)}\n', flush: true);
    return (file, await hashFile(file));
  }

  final sourceManifestHash = evidence['source_manifest']!['sha256'];
  final (_, sceneHash) = await write('SCENE_MANIFEST.json', {
    'schema': 'PW38_PRODUCTION_OBSERVED_SCENE_V1',
    'ordered_frames': count,
    'dense_frames_sha256': transportHash,
    'frames': ordered
        .map(
          (f) => {
            'pack_index': f['pack_index'],
            'frame_id_f64_bits': f['frame_id_f64_bits'],
            'texture_image': f['texture_image'],
            'texture_camera': f['texture_camera'],
          },
        )
        .toList(),
  });
  final (_, inputHash) = await write('OBSERVED_INPUT_MANIFEST.json', {
    'schema': 'PW38_PRODUCTION_OBSERVED_INPUTS_V1',
    'dense_frames': transport,
    'ordered_material': ordered,
    'material_inputs': materials,
    'material_producer_receipt_sha256': input.materialProducerReceiptSha256,
    'pillow_receipt_sha256': input.pillowReceiptSha256,
  });
  request['ordered_input_manifest_sha256'] = inputHash;
  object(request['noise_identity'])['ordered_input_manifest_sha256'] =
      inputHash;
  request['input_identity_status'] = 'ACCEPTED_REGENERATED_INPUTS';
  request['original1920_identity_status'] = 'ORIGINAL_BYTES_NOT_CLAIMED';
  request['regenerated1920_scene_manifest_sha256'] = sceneHash;
  request['input_origin'] = {
    'kind': 'regenerated_from_frozen_local97',
    'source_manifest_sha256': sourceManifestHash,
    'producer_command_sha256': evidence['image_producer_command']!['sha256'],
    'camera_producer_command_sha256':
        evidence['camera_producer_command']!['sha256'],
  };
  request['normal_material_origin'] =
      'ACCEPTED_REGENERATED_INPUTS_OFFICIAL_PILLOW_RAW_EXIF_RGB_PNG';
  request['normal_png_generation_status'] =
      'OBSERVED97_BOUND_ACTUAL_PILLOW_RECEIPT';
  final (_, sessionHash) = await write('SESSION_RECEIPT.json', {
    ...session.receipt,
    'dense_frames_sha256': transportHash,
    'sparse_xyz': sparse,
    'cameras': denseArtifacts[denseArtifacts.length - 2],
    'neighbors': denseArtifacts.last,
  });
  final (requestFile, requestHash) = await write(
    'EFFECTIVE_REQUEST.json',
    request,
  );
  final loaded = await ReconstructionRequest.load(requestFile, requestHash);
  final gate = ReconstructionArtifactGate(
    input.inputRoot,
    input.outputRoot,
    loaded.outputs,
  );
  await gate.requireFresh();
  await loaded.verifyMaterial(gate);
  // Ensure caller-frozen evidence survived the native call and final material scan.
  await _frozenJson(
    input.materialProducerReceipt,
    input.materialProducerReceiptSha256,
  );
  await _frozenJson(input.pillowReceipt, input.pillowReceiptSha256);
  await _frozenJson(input.templateFile, input.templateSha256);
  final (receiptFile, receiptHash) = await write('INPUT_BINDING.json', {
    'schema': 'PW38_PRODUCTION_INPUT_BINDING_V1',
    'status': 'PREPARED_REQUEST_ONLY',
    'template_sha256': input.templateSha256,
    'request_sha256': requestHash,
    'request_path': requestFile.path,
    'ordered_input_manifest_sha256': inputHash,
    'scene_manifest_sha256': sceneHash,
    'session_receipt_sha256': sessionHash,
    'material_producer_receipt_sha256': input.materialProducerReceiptSha256,
    'pillow_receipt_sha256': input.pillowReceiptSha256,
    'production_dense_run': 'NOT_STARTED',
    'historical_A100_parity': 'NOT_CLAIMED',
  });
  await input.originalFixtureProof?.bindRequest(requestFile, requestHash);
  return Pw38PreparedProductionCapture(
    request: loaded,
    requestFile: requestFile,
    requestSha256: requestHash,
    receiptFile: receiptFile,
    receiptSha256: receiptHash,
    originalFixtureProof: input.originalFixtureProof,
  );
}
