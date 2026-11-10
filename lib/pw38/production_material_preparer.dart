import 'frame_transport.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'mobile_input_transport.dart' show pw38PillowEntry, pw38PillowErrorEntry;
import 'native_downstream.dart'
    show Arena, NativeSlot, PairN, PairD, TripleN, TripleD;
import 'production_capture_request.dart';
import 'original_retention_io.dart';
import 'production_original_fixture_binding.dart';
import 'production_runtime_closure.dart';
import 'production_image_binding.dart';
import 'production_scene_binding.dart';
import 'production_session_binding.dart';
import 'reconstruction_request.dart'
    show reconstructionRoute, reconstructionSchema;
import 'request.dart' show object, string, hashFile;
import 'vendor/dart_pipeline/lib/pw38_geometry_ffi.dart' show Pw38SystemMemory;
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart' show checkedRelativePath;
import 'vendor/production_downstream_bridge_v3/lib/pw38_downstream.dart'
    show Pw38IoRoots;

/// Sendable fields contain only strings, lists and maps. Snapshot/runtime
/// capabilities stay with their owning worker and are excluded from JSON.
/// Native bindings are opened in that existing reconstruction worker.
/// frameRows contains the actual already-ordered/refined production transport:
/// frame_id, frame_id_f64_bits, fx/fy/cx/cy, image_w/image_h, q_wxyz, t,
/// jpeg_path (absolute real photo resolver result). No selection or pose math.
final class ProductionMaterialPreparationConfig {
  const ProductionMaterialPreparationConfig({
    required this.bundleRoot,
    required this.templatePath,
    required this.templateSha256,
    required this.inputRoot,
    required this.outputRoot,
    required this.preparationRoot,
    required this.runId,
    required this.cleanupRoots,
    required this.frameRows,
    required this.sparseXyzSourcePath,
    required this.noiseSourceRoot,
    required this.sessionNativeRow,
    required this.cameraNativeRow,
    required this.imageNativeRow,
    required this.pillowNativeRow,
    this.originalFixtureSnapshot,
    this.runtimeClosure,
    this.originalFixtureNativeRow,
  });
  final String bundleRoot,
      templatePath,
      templateSha256,
      inputRoot,
      outputRoot,
      preparationRoot,
      runId,
      sparseXyzSourcePath,
      noiseSourceRoot;
  final OriginalFixtureSnapshot? originalFixtureSnapshot;
  final ProductionRuntimeClosure? runtimeClosure;
  final Map<String, dynamic>? originalFixtureNativeRow;
  final List<String> cleanupRoots;
  final List<Map<String, dynamic>> frameRows;
  final Map<String, dynamic> sessionNativeRow,
      cameraNativeRow,
      imageNativeRow,
      pillowNativeRow;

  Map<String, dynamic> toJson() => {
    'bundle_root': bundleRoot,
    'template_path': templatePath,
    'template_sha256': templateSha256,
    'input_root': inputRoot,
    'output_root': outputRoot,
    'preparation_root': preparationRoot,
    'run_id': runId,
    'cleanup_roots': cleanupRoots,
    'frame_rows': frameRows,
    'sparse_xyz_source_path': sparseXyzSourcePath,
    'noise_source_root': noiseSourceRoot,
    'session_native_row': sessionNativeRow,
    'camera_native_row': cameraNativeRow,
    'image_native_row': imageNativeRow,
    'pillow_native_row': pillowNativeRow,
    if (originalFixtureNativeRow != null)
      'original_fixture_native_row': originalFixtureNativeRow,
  };
  factory ProductionMaterialPreparationConfig.fromJson(
    Map<String, dynamic> j,
  ) => ProductionMaterialPreparationConfig(
    bundleRoot: string(j, 'bundle_root'),
    templatePath: string(j, 'template_path'),
    templateSha256: string(j, 'template_sha256'),
    inputRoot: string(j, 'input_root'),
    outputRoot: string(j, 'output_root'),
    preparationRoot: string(j, 'preparation_root'),
    runId: string(j, 'run_id'),
    cleanupRoots: (j['cleanup_roots'] as List).cast<String>(),
    frameRows: (j['frame_rows'] as List).map(object).toList(),
    sparseXyzSourcePath: string(j, 'sparse_xyz_source_path'),
    noiseSourceRoot: string(j, 'noise_source_root'),
    sessionNativeRow: object(j['session_native_row']),
    cameraNativeRow: object(j['camera_native_row']),
    imageNativeRow: object(j['image_native_row']),
    pillowNativeRow: object(j['pillow_native_row']),
    originalFixtureNativeRow: j['original_fixture_native_row'] == null
        ? null
        : object(j['original_fixture_native_row']),
  );
}

String _relative(String value) {
  checkedRelativePath(value);
  if (value.contains('\\') ||
      value.contains('\u0000') ||
      value.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
    throw FormatException('Nonescaping material path required');
  }
  return value;
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
          .any((s) => s.isEmpty || s == '.' || s == '..')) {
    throw FormatException('Absolute canonical material path required');
  }
  var prefix = '';
  for (final part in path.substring(1).split('/')) {
    prefix += '/$part';
    if (await FileSystemEntity.type(prefix, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Symlink material path rejected: $prefix');
    }
  }
}

Future<void> _fresh(String path) async {
  await _noLinks(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError(
      'Fresh material destination required; existing partials retained: $path',
    );
  }
}

Future<Map<String, dynamic>> _observe(
  File file,
  String relative,
  String role,
) async {
  await _noLinks(file.path);
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError('Actual regular material required: ${file.path}');
  }
  final length = await file.length(), hash = await hashFile(file);
  if (length <= 0 || await file.length() != length)
    throw StateError('Empty/changing material');
  return {
    'path': _relative(relative),
    'role': role,
    'bytes': length,
    'sha256': hash,
  };
}

void _same(Map<String, dynamic> a, Map<String, dynamic> b) {
  for (final key in ['path', 'role', 'bytes', 'sha256']) {
    if (a[key] != b[key])
      throw StateError('Measured material changed: ${a['path']} ($key)');
  }
}

Future<Map<String, dynamic>> _readFrozen(File file, String expected) async {
  await _noLinks(file.path);
  if (await hashFile(file) != expected)
    throw StateError('Frozen material evidence changed');
  final j = object(jsonDecode(await file.readAsString()));
  if (await hashFile(file) != expected)
    throw StateError('Evidence changed during read');
  return j;
}

Future<String> _writeNew(File file, Object value) async {
  await _fresh(file.path);
  await file.writeAsString('${jsonEncode(value)}\n', flush: true);
  return hashFile(file);
}

typedef _PillowErrorN = Pointer<Char> Function();
typedef _PillowErrorD = Pointer<Char> Function();
String _nativeError(Pointer<Char> pointer) {
  if (pointer == nullptr) return 'Native producer returned no error string';
  final bytes = <int>[];
  for (var i = 0; i < 4096; i++) {
    final b = (pointer.cast<Uint8>() + i).value;
    if (b == 0) return utf8.decode(bytes);
    bytes.add(b);
  }
  throw StateError('Native Pillow error exceeded bound');
}

/// Run in the existing worker. Creates only fresh, caller-owned material roots,
/// retains every failure, and returns a strict measured reconstruction request.
/// No dense run, device action, cleanup, or complete reconstruction is claimed.
Future<Pw38PreparedProductionCapture> prepareProductionMaterials(
  ProductionMaterialPreparationConfig configuration,
) async {
  if (Isolate.current.debugName == 'main') {
    throw StateError('Material producers require the reconstruction worker');
  }
  // Freeze sendable caller data before the first async operation.
  final config = ProductionMaterialPreparationConfig.fromJson(
    object(jsonDecode(jsonEncode(configuration.toJson()))),
  );
  final originalSnapshot = configuration.originalFixtureSnapshot;
  OriginalFixtureExecutionProof? originalProof;
  final root = config.inputRoot;
  final work = '$root/production_material';
  const sceneRelative = 'scene1920';
  const sparseRelative = 'dense_inputs/sparse_xyz.f32';
  for (final path in [
    config.bundleRoot,
    config.templatePath,
    config.noiseSourceRoot,
    config.sparseXyzSourcePath,
    ...config.cleanupRoots,
  ]) {
    await _noLinks(path);
  }
  await _fresh(root);
  await _fresh(config.outputRoot);
  await _fresh(config.preparationRoot);
  Pw38IoRoots(
    durableInputRoot: root,
    downstreamOutputRoot: config.outputRoot,
    textureSceneRoot: '$root/$sceneRelative',
  ).validate(config.cleanupRoots);
  for (final other in [root, config.outputRoot, ...config.cleanupRoots]) {
    if (config.preparationRoot == other ||
        config.preparationRoot.startsWith('$other/') ||
        other.startsWith('${config.preparationRoot}/')) {
      throw StateError('Preparation root overlaps retained/cleanup roots');
    }
  }
  if (config.frameRows.isEmpty || config.runId.isEmpty)
    throw StateError('Exact97 input transport required');
  final template = await _readFrozen(
    File(config.templatePath),
    config.templateSha256,
  );
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
    throw StateError('Frozen original97 PNG recipe required');
  }
  final count = frameTransportTemplateActualCount(
    recipe,
    actualCount: config.frameRows.length,
  );
  final original = usesOriginalRetained97(recipe);
  final noisePrefixes = <String, dynamic>{};
  if (!original) requireProductionDenseProvenance(recipe);
  if (original &&
      (originalSnapshot == null ||
          config.originalFixtureNativeRow == null ||
          configuration.runtimeClosure == null)) {
    requireProductionDenseProvenance(recipe);
  }
  final normalRelative = _relative(
    string(
      object(object(recipe['stage_paths'])['avNormal']),
      'original_images',
    ),
  );
  // Template naming may not alias any coordinator-owned source/evidence output.
  for (final reserved in [
    'source_jpeg',
    'dense_inputs',
    'production_material',
    'scene_images1920',
    'camera_original12mp',
    'camera_uncorrected_evidence',
    'camera_corrected',
    sceneRelative,
    'production_session',
    'original_fixture_rgb',
  ]) {
    if (normalRelative == reserved ||
        normalRelative.startsWith('$reserved/') ||
        reserved.startsWith('$normalRelative/'))
      throw StateError('Normal input naming aliases material');
  }
  final denseRow = object(object(recipe['native_libraries'])['dense']);
  for (final key in [
    'bundle_relative_path',
    'binary_sha256',
    'source_receipt_path',
    'source_receipt_sha256',
    'header_sha256',
  ]) {
    if (config.sessionNativeRow[key] != denseRow[key])
      throw StateError('Session and run native binding differ');
  }
  // CPython initialization state belongs to one loaded runtime library. A second
  // GLB binary would reject the already initialized interpreter as foreign.
  // Source receipts may differ; NativeSlot verifies each against these same bytes.
  final glbRow = object(object(recipe['native_libraries'])['glb']);
  for (final key in [
    'bundle_relative_path',
    'binary_sha256',
    'runtime_home_bundle_relative_path',
    'native_modules_bundle_relative_path',
  ]) {
    final cameraValue = config.cameraNativeRow[key];
    if (cameraValue is! String ||
        cameraValue.isEmpty ||
        cameraValue != config.pillowNativeRow[key] ||
        cameraValue != glbRow[key]) {
      throw StateError(
        'Camera, Pillow and downstream GLB must use the same pinned runtime: $key',
      );
    }
  }
  await Directory(root).create(recursive: false);
  await Directory(work).create();
  final journal = File('$work/PROGRESS.json');
  final calls = <Map<String, Object?>>[], copies = <Map<String, dynamic>>[];
  var step = 'opening_native_bindings';
  Future<void> persist(String status, [Object? error]) async {
    await journal.writeAsString(
      '${jsonEncode({'schema': 'PW38_PRODUCTION_MATERIAL_PROGRESS_V1', 'status': status, 'step': step, 'run_id': config.runId, 'template_sha256': config.templateSha256, 'actual_native_calls': calls, 'copies': copies, 'error': error?.toString(), 'dense_run_status': 'NOT_STARTED'})}\n',
      flush: true,
    );
  }

  Future<Map<String, dynamic>> copy(
    File source,
    String relative,
    String role, {
    Map<String, dynamic>? frozen,
  }) async {
    relative = _relative(relative);
    final before = await _observe(source, relative, role);
    if (frozen != null) _same(frozen, before);
    final destination = File('$root/$relative');
    await _fresh(destination.path);
    await destination.parent.create(recursive: true);
    final row = <String, dynamic>{
      'source_path': source.path,
      'destination_path': relative,
      'source': before,
      'status': 'copy_started',
    };
    copies.add(row);
    await persist('preparing');
    row['copy_return_path'] = (await source.copy(destination.path)).path;
    final observed = await _observe(destination, relative, role);
    _same(before, observed);
    _same(before, await _observe(source, relative, role));
    row['observed'] = observed;
    row['status'] = 'copied_and_verified';
    await persist('preparing');
    return observed;
  }

  try {
    await persist('preparing');
    final sessionBinding = original
        ? null
        : await ProductionSessionBinding.open(
            config.sessionNativeRow,
            config.bundleRoot,
          );
    final cameraBinding = await ProductionCameraBinding.open(
      config.cameraNativeRow,
      config.bundleRoot,
    );
    final imageBinding = await ProductionImageBinding.open(
      config.imageNativeRow,
      config.bundleRoot,
    );
    final pillowSlot = await NativeSlot.open(
      config.pillowNativeRow,
      config.bundleRoot,
      {pw38PillowEntry, pw38PillowErrorEntry, 'pw38_glb_runtime_initialize'},
    );
    step = 'copying_actual_ordered_sources';
    await persist('preparing');
    final sourceRows = <Map<String, dynamic>>[], sourcePaths = <String>{};
    final frames = <Pw38ProductionCaptureFrame>[];
    for (var i = 0; i < count; i++) {
      final row = config.frameRows[i], sourcePath = string(row, 'jpeg_path');
      if (!sourcePaths.add(sourcePath))
        throw StateError('Duplicate actual resolved JPEG');
      final relative = 'source_jpeg/${i.toString().padLeft(8, '0')}.jpg';
      sourceRows.add(await copy(File(sourcePath), relative, 'source_jpeg'));
      final f = ProductionSessionFrame(
        frameId: (row['frame_id'] as num).toDouble(),
        frameIdF64Bits: string(row, 'frame_id_f64_bits'),
        fx: (row['fx'] as num).toDouble(),
        fy: (row['fy'] as num).toDouble(),
        cx: (row['cx'] as num).toDouble(),
        cy: (row['cy'] as num).toDouble(),
        imageW: (row['image_w'] as num).toDouble(),
        imageH: (row['image_h'] as num).toDouble(),
        qWxyz: (row['q_wxyz'] as List)
            .cast<num>()
            .map((v) => v.toDouble())
            .toList(),
        translation: (row['t'] as List)
            .cast<num>()
            .map((v) => v.toDouble())
            .toList(),
        jpegPath: '$root/$relative',
      );
      if (f.imageW != 4032 || f.imageH != 3024)
        throw StateError('Original4032x3024 recipe required');
      final stem = i.toString().padLeft(8, '0');
      frames.add(
        Pw38ProductionCaptureFrame(
          sessionFrame: f,
          textureImagePath: '$sceneRelative/$stem.jpg',
          textureCameraPath: '$sceneRelative/$stem.cam',
          originalCameraPath: 'camera_original12mp/$stem.cam',
          normalImagePath: '$normalRelative/$i.png',
        ),
      );
    }
    final sparse = await copy(
      File(config.sparseXyzSourcePath),
      sparseRelative,
      'sparse_xyz_f32',
    );
    if ((sparse['bytes'] as int) % 12 != 0 ||
        (sparse['bytes'] as int) ~/ 12 > 0x7fffffff) {
      throw StateError('Original native sparse f32 triple count required');
    }
    final oldDense = object(recipe['dense_inputs']);
    for (final key in [
      'low_noise_f32',
      'high_noise_f32',
      'noise_producer_json',
    ]) {
      final path = _relative(string(oldDense, key));
      final frozen = (oldDense['artifacts'] as List)
          .map(object)
          .singleWhere((a) => a['path'] == path);
      if (variableFrameTransport(recipe) && key != 'noise_producer_json') {
        final row = await copyOfficialNoisePrefix(
          source: File('${config.noiseSourceRoot}/$path'), destination: File('$root/$path'),
          count: count, high: key == 'high_noise_f32', expectedBankSha256: string(frozen, 'sha256'));
        noisePrefixes[key == 'high_noise_f32' ? 'high' : 'low'] = row;
        copies.add({'status': 'copied_and_verified', 'official_noise_prefix': row});
        await persist('preparing');
      } else {
        await copy(File('${config.noiseSourceRoot}/$path'), path, string(frozen, 'role'), frozen: frozen);
      }
    }
    final transport = frames
        .map(
          (f) => {
            'frame_id': f.sessionFrame.frameId,
            'fx': f.sessionFrame.fx,
            'fy': f.sessionFrame.fy,
            'cx': f.sessionFrame.cx,
            'cy': f.sessionFrame.cy,
            'image_w': f.sessionFrame.imageW,
            'image_h': f.sessionFrame.imageH,
            'q_wxyz': f.sessionFrame.qWxyz,
            't': f.sessionFrame.translation,
            'jpeg_path': f.sessionFrame.jpegPath.substring(root.length + 1),
          },
        )
        .toList();
    final transportJson = jsonEncode(transport);
    final transportHash = productionCaptureFrameTransportSha256(root, frames);
    if (sha256.convert(utf8.encode(transportJson)).toString() !=
        transportHash) {
      throw StateError('Producer/request refined-frame serialization differs');
    }
    await _writeNew(File('$work/SOURCE_OBSERVATION.json'), {
      'schema': 'PW38_PRODUCTION_SOURCE_OBSERVATION_V1',
      'dense_frames_sha256': transportHash,
      'original_frame_rows': config.frameRows,
      'copies': copies,
      'sparse_xyz': sparse,
    });
    step = 'actual_native_session';
    await persist('preparing');
    final sparseFile = File('$root/$sparseRelative');
    final sparseBytes = await sparseFile.readAsBytes();
    _same(sparse, await _observe(sparseFile, sparseRelative, 'sparse_xyz_f32'));
    final ProductionSessionTableBytes session;
    if (original) {
      step = 'actual_whole_original_fixture_producer';
      await persist('preparing');
      originalProof = await executeOriginalFixture(
        snapshot: originalSnapshot!,
        runtimeClosure: configuration.runtimeClosure,
        nativeRow: config.originalFixtureNativeRow!,
        providerRow: glbRow,
        bundleRoot: config.bundleRoot,
        outputRoot: '${Directory(root).parent.path}/original_fixture',
        receiptPath:
            '${Directory(root).parent.path}/ORIGINAL_FIXTURE_RECEIPT.json',
      );
      requireProductionDenseProvenance(recipe, proof: originalProof);
      session = await originalProof.sessionTables();
    } else {
      session = sessionBinding!.build(
        frames: frames.map((f) => f.sessionFrame).toList(),
        sparseXyzF32: sparseBytes,
      );
    }
    final camerasHash = sha256.convert(session.camerasF32).toString();
    final neighborsHash = sha256.convert(session.neighborsI32).toString();
    calls.add({
      ...session.receipt,
      'cameras_f32_sha256': camerasHash,
      'neighbors_i32_sha256': neighborsHash,
      'dense_frames_sha256': transportHash,
    });
    await _writeNew(File('$work/PRODUCER_SESSION_RECEIPT.json'), calls.last);
    final cameraManifest = File('$work/CAMERA_INPUT_MANIFEST.json');
    final cameraManifestHash = await _writeNew(cameraManifest, {
      'schema': 'PW38_PRODUCTION_CAMERA_SOURCE_V1',
      'dense_frames_json': transportJson,
      'dense_frames_sha256': transportHash,
      'cameras_f32_sha256': camerasHash,
      'frame_id_f64_bits': frames
          .map((f) => f.sessionFrame.frameIdF64Bits)
          .toList(),
      'source_jpegs': sourceRows,
    });
    step = 'actual_original_camera_producer';
    await persist('preparing');
    final camera = await cameraBinding.prepare(
      camerasF32: session.camerasF32,
      manifestFile: cameraManifest,
      manifestSha256: cameraManifestHash,
      inputRoot: Directory(root),
      originalCameraDirectory: Directory('$root/camera_uncorrected_evidence'),
      correctedCameraDirectory: Directory('$root/camera_corrected'),
      receiptFile: File('$work/CAMERA_RECEIPT.json'),
    );
    if (camera.document['dense_frames_sha256'] != transportHash ||
        camera.document['cameras_f32_sha256'] != camerasHash)
      throw StateError('Camera receipt/session input differs');
    calls.add(camera.nativeCall);
    final actualSourceManifest = object(camera.document['source_manifest']);
    step = 'actual_original_opencv411_images';
    await persist('preparing');
    final image = await imageBinding.prepare(
      manifestFile: File(
        '$root/${_relative(string(actualSourceManifest, 'path'))}',
      ),
      manifestSha256: string(actualSourceManifest, 'sha256'),
      inputRoot: Directory(root),
      outputDirectory: Directory('$root/scene_images1920'),
    );
    if (image.document['dense_frames_sha256'] != transportHash)
      throw StateError('Image producer frame binding differs');
    calls.add(image.nativeCall);
    step = 'copying_actual_scene_pairs';
    await persist('preparing');
    await _fresh('$root/$sceneRelative');
    await Directory('$root/$sceneRelative').create();
    final materials = <Map<String, dynamic>>[...sourceRows, sparse];
    if (originalProof != null) {
      await originalProof.revalidate();
      for (var i = 0; i < count; i++) {
        final stem = i.toString().padLeft(8, '0');
        materials.add(
          await copy(
            File('${originalProof.outputRoot}/rgb/$stem.jpg'),
            'original_fixture_rgb/$stem.jpg',
            'original_fusion_jpeg',
          ),
        );
      }
    }
    final imageOutputs = (image.document['material_outputs'] as List)
        .map(object)
        .toList();
    final cameraOutputs = (camera.document['material_outputs'] as List)
        .map(object)
        .toList();
    for (var i = 0; i < count; i++) {
      final stem = i.toString().padLeft(8, '0');
      final jpg = imageOutputs.singleWhere(
        (a) => a['path'] == 'scene_images1920/$stem.jpg',
      );
      final cam = cameraOutputs.singleWhere(
        (a) => a['path'] == 'camera_corrected/$stem.cam',
      );
      for (final pair in [
        (jpg, '$sceneRelative/$stem.jpg', 'texture_image'),
        (cam, '$sceneRelative/$stem.cam', 'texture_camera'),
      ]) {
        final bound = {...pair.$1, 'path': pair.$2, 'role': pair.$3};
        materials.add(
          await copy(
            File('$root/${pair.$1['path']}'),
            pair.$2,
            pair.$3,
            frozen: bound,
          ),
        );
      }
      // Original av_vis_k.py reads tex_scene12_fix CAMs at 4032x3024.
      // Both selected consumers therefore reuse corrected normalized CAM bytes.
      // The original producer's uncorrected directory stays as evidence only.
      final normalCamera = frames[i].originalCameraPath;
      materials.add(
        await copy(
          File('$root/${cam['path']}'),
          normalCamera,
          'original_4032_camera',
          frozen: {
            ...cam,
            'path': normalCamera,
            'role': 'original_4032_camera',
          },
        ),
      );
    }
    step = 'actual_original_pillow_pngs';
    await persist('preparing');
    final pillowManifest = File('$work/PILLOW_INPUT_MANIFEST.json');
    final pillowManifestHash = await _writeNew(pillowManifest, {
      'frames': [
        for (var i = 0; i < count; i++)
          {
            'pack_index': i,
            'path': '$root/${sourceRows[i]['path']}',
            'source_bytes': sourceRows[i]['bytes'],
            'source_sha256': sourceRows[i]['sha256'],
          },
      ],
    });
    final pillowReceiptFile = File('$work/PILLOW_RECEIPT.json');
    await _fresh('$root/$normalRelative');
    await _fresh(pillowReceiptFile.path);
    await Directory('$root/$normalRelative').parent.create(recursive: true);
    final arena = Arena(Pw38SystemMemory(DynamicLibrary.process()));
    try {
      final runtimeHome =
          '${config.bundleRoot}/${_relative(string(config.pillowNativeRow, 'runtime_home_bundle_relative_path'))}';
      final modules =
          '${config.bundleRoot}/${_relative(string(config.pillowNativeRow, 'native_modules_bundle_relative_path'))}';
      await _noLinks(runtimeHome);
      await _noLinks(modules);
      final init = pillowSlot.library.lookupFunction<PairN, PairD>(
        'pw38_glb_runtime_initialize',
      )(arena.path(runtimeHome), arena.path(modules));
      calls.add({
        'native_entry': 'pw38_glb_runtime_initialize',
        'return_code': init,
      });
      if (init != 0)
        throw StateError(
          'Original Pillow CPython initialization failed: $init',
        );
      final rc =
          pillowSlot.library.lookupFunction<TripleN, TripleD>(pw38PillowEntry)(
            arena.path(pillowManifest.path),
            arena.path('$root/$normalRelative'),
            arena.path(pillowReceiptFile.path),
          );
      final error = rc == 0
          ? ''
          : _nativeError(
              pillowSlot.library.lookupFunction<_PillowErrorN, _PillowErrorD>(
                pw38PillowErrorEntry,
              )(),
            );
      calls.add({
        'native_entry': pw38PillowEntry,
        'return_code': rc,
        'error': error,
        'binary_sha256': pillowSlot.binarySha256,
        'manifest_sha256': pillowManifestHash,
      });
      if (rc != 0)
        throw StateError('Original Pillow producer failed: $rc $error');
    } finally {
      arena.dispose();
    }
    final pillowHash = await hashFile(pillowReceiptFile);
    final pillow = await _readFrozen(pillowReceiptFile, pillowHash);
    final pngRows = (pillow['frames'] as List).map(object).toList();
    if (pillow['schema'] != 'pw38.normal_image_io.v1' ||
        pillow['status'] != 'complete' ||
        pillow['return_code'] != 0 ||
        pillow['prepared_count'] != count ||
        pngRows.length != count ||
        pillow['input_manifest_sha256'] != pillowManifestHash ||
        pillow['output_directory'] != '$root/$normalRelative')
      throw StateError('Actual complete97 Pillow receipt required');
    for (var i = 0; i < count; i++) {
      final png = pngRows[i],
          source = sourceRows[i],
          relative = '$normalRelative/$i.png';
      if (png['pack_index'] != i ||
          png['status'] != 'prepared' ||
          png['source_path'] != '$root/${source['path']}' ||
          png['actualpath'] != '$root/$relative' ||
          png['source_bytes'] != source['bytes'] ||
          png['actual_source_bytes'] != source['bytes'] ||
          png['source_sha256'] != source['sha256'] ||
          png['actual_source_sha256'] != source['sha256'] ||
          jsonEncode(png['size']) != '[4032,3024]' ||
          jsonEncode(png['source_pixel_size']) != '[4032,3024]') {
        throw StateError('Pillow actual source/PNG/frame binding mismatch');
      }
      final observed = await _observe(
        File('$root/$relative'),
        relative,
        'normal_image',
      );
      if (observed['bytes'] != png['bytes'] ||
          observed['sha256'] != png['sha256'])
        throw StateError('Pillow output bytes changed');
    }
    if (await hashFile(pillowManifest) != pillowManifestHash)
      throw StateError('Pillow source manifest changed');
    step = 'combined_actual_material_receipt';
    await persist('preparing');
    final combinedFile = File('$work/MATERIAL_RECEIPT.json');
    final combinedHash = await _writeNew(combinedFile, {
      'schema': 'PW38_PRODUCTION_MATERIAL_RECEIPT_V1',
      'status': 'complete$count',
      'return_code': 0,
      'ordered_frames': count,
      'dense_frames_sha256': transportHash,
      if (variableFrameTransport(recipe)) 'noise_prefix_streams': noisePrefixes,
      'session_cameras_f32_sha256': camerasHash,
      'session_neighbors_i32_sha256': neighborsHash,
      'material_outputs': materials,
      'source_manifest': actualSourceManifest,
      'camera_producer_command': camera.document['camera_producer_command'],
      'image_producer_command': image.document['image_producer_command'],
      'camera_receipt_sha256': camera.sha256,
      'image_receipt_sha256': image.sha256,
      'pillow_receipt_sha256': pillowHash,
      'actual_native_calls': calls,
      if (originalProof != null)
        'original_fixture_receipt': originalProof.nativeCall,
      'scene_copy_journal': journal.path,
      'historical_A100_byte_parity': 'NOT_CLAIMED',
      'dense_run_status': 'NOT_STARTED',
    });
    await _readFrozen(camera.file, camera.sha256);
    await _readFrozen(image.file, image.sha256);
    step = 'strict_request_builder';
    await persist('preparing');
    final result = await prepareProductionCaptureRequest(
      Pw38ProductionCaptureInput(
        templateFile: File(config.templatePath),
        templateSha256: config.templateSha256,
        inputRoot: Directory(root),
        outputRoot: Directory(config.outputRoot),
        preparationRoot: Directory(config.preparationRoot),
        runId: config.runId,
        cleanupRoots: config.cleanupRoots,
        textureSceneRelativePath: sceneRelative,
        frames: frames,
        sparseXyzPath: sparseRelative,
        materialProducerReceipt: combinedFile,
        materialProducerReceiptSha256: combinedHash,
        pillowReceipt: pillowReceiptFile,
        pillowReceiptSha256: pillowHash,
        sessionBinding: sessionBinding,
        originalFixtureProof: originalProof,
      ),
    );
    // Independent readback: both session builds must supply identical camera and
    // neighbor bytes; root-owned builder also enforces this before publication.
    final sessionReceipt = object(
      jsonDecode(
        await File(
          '${config.preparationRoot}/SESSION_RECEIPT.json',
        ).readAsString(),
      ),
    );
    if (object(sessionReceipt['cameras'])['sha256'] != camerasHash ||
        object(sessionReceipt['neighbors'])['sha256'] != neighborsHash) {
      throw StateError(
        'Material and dense sessions differ; request is not returned',
      );
    }
    step = 'request_prepared_dense_not_started';
    await persist('PREPARED_REQUEST_ONLY');
    return result;
  } catch (error) {
    await persist('failed', error);
    rethrow;
  }
}
