import 'frame_transport.dart';
import 'original_retention_io.dart' show originalRetained97Profile, usesOriginalRetained97;
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'native_downstream.dart' show Arena, NativeSlot, PairN, PairD;
import 'production_runtime_closure.dart';
import 'production_session_binding.dart' show ProductionSessionTableBytes;
import 'request.dart' show hashFile, object, string;
import 'vendor/dart_pipeline/lib/pw38_geometry_ffi.dart' show Pw38SystemMemory;
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart' show checkedRelativePath;

const originalFixtureSourceSha256 =
    'ebf789263da4420a08980d90ce13f5bb91951b696d5b0483441b34e3e45a8887';
const originalFixtureWrapperSha256 =
    'ef5c8791bdfc1ac6ab055f0495d797974b84764b2c4626ab0c6d852fbe2c5127';
const originalFixtureV2WrapperSha256 = 'ec43166afdb8bd413d9fd069d9511abe66ab7c92d25f58aee6530423cd474d1e';
const originalFixtureV2CombinedSourceSha256 = '892c514f29d89ff5489c5f37ab86f428f5b17f044c87e7fd2e649ae3425b9fb0';
String fixtureWrapperSha256(Map<String, dynamic> row) => row['fixture_wrapper_sha256'] == originalFixtureV2WrapperSha256 ? originalFixtureV2WrapperSha256 : originalFixtureWrapperSha256;
String fixtureCombinedSourceSha256(Map<String, dynamic> row) => fixtureWrapperSha256(row) == originalFixtureV2WrapperSha256 ? originalFixtureV2CombinedSourceSha256 : originalFixtureCombinedSourceSha256;
const originalFixtureHeaderSha256 =
    '8598f859f4dddd4c306115944ba2733b93f19cb388777084b47b65abe0204f0b';
const originalFixtureCombinedSourceSha256 =
    'cc569c6f2ec2a2deeaac4bac21fde88ba6a0cbd3fde547ddc2c66da4699b0656';
const originalFixtureEntry = 'pw38_original_fixture_prepare';
const originalFixtureErrorEntry = 'pw38_original_dense_raw_last_error';
const originalFixtureEnvironment = {
  'FIX_W': '768',
  'FIX_H': '576',
  'FIX_NSRC': '9',
  'USE_ARKIT': '0',
  'FRAME_GATE': '0',
  'DR_LO': '0.70',
  'DR_HI': '1.50',
  'DT_MAX': '0.10',
};
final Object _workerIdentity = Object();

typedef _PrepareN =
    Int32 Function(
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Char>,
    );
typedef _PrepareD =
    int Function(
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Char>,
      Pointer<Char>,
    );
typedef _ErrorN = Pointer<Char> Function();
typedef _ErrorD = Pointer<Char> Function();

Future<void> _canonical(String path) async {
  if (!path.startsWith('/') ||
      path == '/' ||
      path.endsWith('/') ||
      path.contains('\\') ||
      path.contains('\u0000') ||
      path
          .substring(1)
          .split('/')
          .any((p) => p.isEmpty || p == '.' || p == '..')) {
    throw StateError('Canonical absolute fixture path required');
  }
  var prefix = '';
  for (final part in path.substring(1).split('/')) {
    prefix += '/$part';
    if (await FileSystemEntity.type(prefix, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Symlink fixture input rejected');
    }
  }
}

Future<Map<String, dynamic>> _row(
  String path,
  String relative,
  String role,
) async {
  await _canonical(path);
  final file = File(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError('Real regular fixture file required: $path');
  }
  final size = await file.length(), hash = await hashFile(file);
  if (size <= 0 || await file.length() != size)
    throw StateError('Empty/changing fixture input');
  return {'path': relative, 'role': role, 'bytes': size, 'sha256': hash};
}

void _equal(Object? actual, Object? expected, String reason) {
  // Compare decoded JSON values without relying on map insertion order.
  if (actual is Map && expected is Map) {
    if (actual.length != expected.length) throw StateError(reason);
    for (final key in expected.keys) {
      if (!actual.containsKey(key)) throw StateError(reason);
      _equal(actual[key], expected[key], reason);
    }
  } else if (actual is List && expected is List) {
    if (actual.length != expected.length) throw StateError(reason);
    for (var i = 0; i < actual.length; i++) {
      _equal(actual[i], expected[i], reason);
    }
  } else if (actual != expected) {
    throw StateError(reason);
  }
}

bool _finite(Object? values, int count) =>
    values is List &&
    values.length == count &&
    values.every((v) => v is num && v.isFinite);
String _name(Object? value) {
  if (value is! String) throw StateError('Actual fed JPEG path required');
  final name = value.split('/').last;
  if (!name.endsWith('.jpg') ||
      name.contains('\\') ||
      name.contains('\u0000') ||
      name == '.jpg' ||
      name.contains('..'))
    throw StateError('Safe exact fed JPEG basename required');
  return name;
}

/// Frozen archive provenance is observed before the existing sidecar resolver
/// extracts any bytes. The archive and its manifest remain durable sources;
/// only the resolver's verified scratch files may be disposed.
final class OriginalFixtureSidecarArchive {
  OriginalFixtureSidecarArchive._(
    this.captureRoot,
    this._sourcesJson,
    this._filesJson,
  );
  final String captureRoot, _sourcesJson, _filesJson;

  static Future<OriginalFixtureSidecarArchive?> capture(
    String captureRoot,
  ) async {
    await _canonical(captureRoot);
    const manifestName = 'official_aux_archive.json';
    final path = '$captureRoot/$manifestName';
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    final manifestRow = await _row(
      path,
      manifestName,
      'original_sidecar_archive_manifest',
    );
    final bytes = await File(path).readAsBytes();
    if (bytes.length > 8 * 1024 * 1024 ||
        bytes.length != manifestRow['bytes'] ||
        sha256.convert(bytes).toString() != manifestRow['sha256']) {
      throw StateError('Sidecar archive manifest changed while parsing');
    }
    final manifest = object(jsonDecode(utf8.decode(bytes)));
    if (manifest['schema'] != 'pw_aux_archive_v1') {
      throw StateError('Actual sidecar archive manifest required');
    }
    final bundles = object(manifest['bundles']);
    if (!bundles.containsKey('sidecars_v1')) return null;
    final bundle = object(bundles['sidecars_v1']);
    final archiveName = checkedRelativePath(
      string(bundle, 'archive_file_name'),
    );
    final archiveRow = await _row(
      '$captureRoot/$archiveName',
      archiveName,
      'original_sidecar_archive',
    );
    if (archiveRow['bytes'] != bundle['archive_bytes'] ||
        archiveRow['sha256'] != bundle['archive_sha256'] ||
        bundle['files'] is! List) {
      throw StateError('Actual sidecar archive differs from frozen manifest');
    }
    final paths = <String>{};
    for (final raw in bundle['files'] as List) {
      final row = object(raw);
      final relative = checkedRelativePath(string(row, 'path'));
      if (!paths.add(relative) ||
          !relative.startsWith('photos_highres/') ||
          row['bytes'] is! int ||
          (row['bytes'] as int) <= 0 ||
          row['sha256'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['sha256'] as String)) {
        throw StateError('Distinct measured sidecar archive members required');
      }
    }
    final source = OriginalFixtureSidecarArchive._(
      captureRoot,
      jsonEncode([
        {'source_path': path, 'observed': manifestRow},
        {'source_path': '$captureRoot/$archiveName', 'observed': archiveRow},
      ]),
      jsonEncode(bundle['files']),
    );
    await source.revalidate();
    return source;
  }

  Future<void> revalidate() async {
    for (final raw in jsonDecode(_sourcesJson) as List) {
      final source = object(raw), expected = object(source['observed']);
      _equal(
        await _row(
          string(source, 'source_path'),
          string(expected, 'path'),
          string(expected, 'role'),
        ),
        expected,
        'Actual sidecar archive source changed',
      );
    }
  }

  void _requireSidecar(String name, Map<String, dynamic> observed) {
    final entries = (jsonDecode(_filesJson) as List)
        .map(object)
        .where((row) => row['path'] == 'photos_highres/$name')
        .toList();
    if (entries.length != 1 ||
        entries.single['bytes'] != observed['bytes'] ||
        entries.single['sha256'] != observed['sha256']) {
      throw StateError(
        'Extracted sidecar differs from original archive member',
      );
    }
  }
}

/// The private constructor records byte-copy observations, never numerical data.
/// Full source JSON/PLY/sidecars are retained byte-for-byte. Only already ordered
/// gathered frame identities determine copy lookup; the Python producer owns its
/// original pose sorting and every numerical/image operation.
final class OriginalFixtureSnapshot {
  OriginalFixtureSnapshot._(
    this.root,
    this.manifestPath,
    this.manifestSha256,
    this._manifestJson,
    this._sourceJson,
    this._framesJson,
  );
  final String root,
      manifestPath,
      manifestSha256,
      _manifestJson,
      _sourceJson,
      _framesJson;
  Map<String, dynamic> get manifest => object(jsonDecode(_manifestJson));
  Future<void> revalidate() async {
    await _canonical(manifestPath);
    if (await hashFile(File(manifestPath)) != manifestSha256)
      throw StateError('Fixture manifest changed');
    _equal(
      jsonDecode(await File(manifestPath).readAsString()),
      manifest,
      'Fixture manifest binding changed',
    );
    for (final raw in jsonDecode(_sourceJson) as List) {
      final source = object(raw), expected = object(source['observed']);
      _equal(
        await _row(
          string(source, 'source_path'),
          string(expected, 'path'),
          string(expected, 'role'),
        ),
        expected,
        'Actual capture source changed',
      );
    }
    for (final raw in manifest['artifacts'] as List) {
      final expected = object(raw);
      _equal(
        await _row(
          '$root/${expected['path']}',
          string(expected, 'path'),
          string(expected, 'role'),
        ),
        expected,
        'Snapshot bytes changed',
      );
    }
  }
}

Future<OriginalFixtureSnapshot> snapshotOriginalFixtureCapture({
  required String captureRoot,
  required String sidecarsRoot,
  OriginalFixtureSidecarArchive? sidecarArchive,
  required String destinationRoot,
  required String manifestPath,
  required List<Map<String, dynamic>> orderedFrames,
  String profile = originalRetained97Profile,
  required List<String> jpegOrigins,
}) async {
  final count = frameTransportCount({'dense_producer_profile': profile}, actualCount: orderedFrames.length);
  for (final path in [
    captureRoot,
    sidecarsRoot,
    destinationRoot,
    manifestPath,
  ]) {
    await _canonical(path);
  }
  if (orderedFrames.length != count ||
      jpegOrigins.length != count ||
      destinationRoot == captureRoot ||
      destinationRoot.startsWith('$captureRoot/photos_highres/') ||
      FileSystemEntity.typeSync(destinationRoot, followLinks: false) !=
          FileSystemEntityType.notFound ||
      FileSystemEntity.typeSync(manifestPath, followLinks: false) !=
          FileSystemEntityType.notFound ||
      manifestPath.startsWith('$destinationRoot/')) {
    throw StateError(
      'Fresh exact97 disjoint fixture snapshot/evidence required',
    );
  }
  final temporarySidecars = sidecarsRoot != '$captureRoot/photos_highres';
  if (temporarySidecars &&
      (sidecarArchive == null || sidecarArchive.captureRoot != captureRoot)) {
    throw StateError(
      'Temporary sidecars require frozen actual archive provenance',
    );
  }
  if (temporarySidecars) await sidecarArchive!.revalidate();
  final metaPath = '$captureRoot/official_sfm_sparse_meta.json';
  final fedPath = '$captureRoot/official_sfm_fed_frames.jsonl';
  // Capture the raw identities before parsing, then confirm them after copying.
  final initial = <String, Map<String, dynamic>>{};
  for (final name in [
    'official_sfm_sparse_meta.json',
    'official_sfm_fed_frames.jsonl',
    'official_sfm_sparse.ply',
  ]) {
    initial[name] = await _row('$captureRoot/$name', name, 'raw_source');
  }
  final metadata = object(jsonDecode(await File(metaPath).readAsString()));
  final poses = <num, Map<String, dynamic>>{};
  for (final raw in metadata['poses'] as List) {
    final pose = object(raw);
    if (pose['registered'] != true) continue;
    final id = pose['frame_id'];
    if (id is! num ||
        !id.isFinite ||
        id != id.toInt() ||
        poses.containsKey(id) ||
        !_finite(pose['quat_wxyz'], 4) ||
        !_finite(pose['t'], 3)) {
      throw StateError(
        'Unique exact registered frame identity and full refined pose required',
      );
    }
    poses[id] = pose;
  }
  final fed = <num, Map<String, dynamic>>{};
  for (final line in await File(fedPath).readAsLines()) {
    if (line.trim().isEmpty) continue;
    final row = object(jsonDecode(line)), id = row['frameId'];
    if (id is! num || !id.isFinite || id != id.toInt())
      throw StateError('Actual exact fed frame identity required');
    fed[id] = row; // Original producer's exact last-row semantics.
  }
  if (poses.length != count)
    throw StateError('Exact97 registered raw poses required');
  final copies = <({String source, String relative, String role})>[
    (
      source: metaPath,
      relative: 'official_sfm_sparse_meta.json',
      role: 'refined_metadata',
    ),
    (
      source: fedPath,
      relative: 'official_sfm_fed_frames.jsonl',
      role: 'fed_photo_mapping',
    ),
    (
      source: '$captureRoot/official_sfm_sparse.ply',
      relative: 'official_sfm_sparse.ply',
      role: 'original_sparse_ply',
    ),
  ];
  final names = <String>[], ids = <num>[], used = <String>{};
  final sidecarObservations = <String, Map<String, dynamic>>{};
  for (var i = 0; i < count; i++) {
    final frame = orderedFrames[i], id = frame['frame_id'];
    if (id is! num ||
        !id.isFinite ||
        (i > 0 && id <= ids.last) ||
        !poses.containsKey(id) ||
        !fed.containsKey(id)) {
      throw StateError(
        'Gathered frame order differs from exact raw producer identities',
      );
    }
    final pose = poses[id]!, name = _name(fed[id]!['jpegPath']);
    if (!used.add(name)) throw StateError('Duplicate fed JPEG basename');
    _equal(
      frame['q_wxyz'],
      pose['quat_wxyz'],
      'Gathered refined quaternion differs from raw metadata',
    );
    _equal(
      frame['t'],
      pose['t'],
      'Gathered refined translation differs from raw metadata',
    );
    final side =
        '$sidecarsRoot/${name.replaceFirst(RegExp(r'\.jpg$'), '.json')}';
    final relative =
        'sidecars/${name.replaceFirst(RegExp(r'\.jpg$'), '.json')}';
    final sidecarRow = await _row(side, relative, 'original_full_sidecar');
    final sidecarBytes = await File(side).readAsBytes();
    _equal(
      {
        'path': relative,
        'role': 'original_full_sidecar',
        'bytes': sidecarBytes.length,
        'sha256': sha256.convert(sidecarBytes).toString(),
      },
      sidecarRow,
      'Sidecar parse bytes differ from observed identity',
    );
    final sc = object(jsonDecode(utf8.decode(sidecarBytes)));
    _equal(
      await _row(side, relative, 'original_full_sidecar'),
      sidecarRow,
      'Sidecar changed while parsing',
    );
    if (temporarySidecars) {
      sidecarArchive!._requireSidecar(side.split('/').last, sidecarRow);
    }
    sidecarObservations[side] = sidecarRow;
    if (!_finite(sc['intrinsics_fxfycxcy'], 4) ||
        !_finite(sc['extrinsic'], 16) ||
        !_finite([sc['image_w'], sc['image_h']], 2)) {
      throw StateError('Real complete original sidecar/extrinsic required');
    }
    _equal(
      [frame['fx'], frame['fy'], frame['cx'], frame['cy']],
      sc['intrinsics_fxfycxcy'],
      'Gathered intrinsics differ',
    );
    _equal(
      [frame['image_w'], frame['image_h']],
      [sc['image_w'], sc['image_h']],
      'Gathered dimensions differ',
    );
    if (!const {
      'actual_plain_jpeg',
      'byte_restored_archive_jpeg',
      'pwva_decoded_reencoded_jpeg',
    }.contains(jpegOrigins[i])) {
      throw StateError('Actual JPEG materialization route required');
    }
    names.add(name);
    ids.add(id);
    copies.add((
      source: side,
      relative: 'sidecars/${name.replaceFirst(RegExp(r'\.jpg$'), '.json')}',
      role: 'original_full_sidecar',
    ));
    copies.add((
      source: string(frame, 'jpeg_path'),
      relative: 'photos_jpg/$name',
      role: 'actual_resolved_jpeg',
    ));
  }
  final observed = <Map<String, dynamic>>[];
  for (final copy in copies) {
    observed.add(
      sidecarObservations[copy.source] ??
          await _row(copy.source, copy.relative, copy.role),
    );
  }
  await Directory(destinationRoot).create();
  await Directory('$destinationRoot/sidecars').create();
  await Directory('$destinationRoot/photos_jpg').create();
  for (var i = 0; i < copies.length; i++) {
    final copy = copies[i], target = File('$destinationRoot/${copy.relative}');
    await target.create(exclusive: true);
    await File(copy.source).openRead().pipe(target.openWrite());
    _equal(
      await _row(copy.source, copy.relative, copy.role),
      observed[i],
      'Source changed during snapshot',
    );
    _equal(
      await _row(target.path, copy.relative, copy.role),
      observed[i],
      'Snapshot copy identity mismatch',
    );
  }
  for (final entry in initial.entries) {
    _equal(
      await _row('$captureRoot/${entry.key}', entry.key, 'raw_source'),
      entry.value,
      'Raw source changed while parsing',
    );
  }
  if (temporarySidecars) await sidecarArchive!.revalidate();
  final manifest = {
    'schema': 'PW38_ORIGINAL_CAPTURE_INPUTS_V1',
    'root': destinationRoot,
    'selected_frames': count,
    'ordered_source_names': names,
    'frame_ids': ids,
    'artifacts': observed,
  };
  await File(manifestPath).create(exclusive: true);
  await File(
    manifestPath,
  ).writeAsString('${jsonEncode(manifest)}\n', flush: true);
  final sources = [
    for (var i = 0; i < copies.length; i++)
      {'source_path': copies[i].source, 'observed': observed[i]},
  ];
  // Actual on-disk sidecars remain durable. Only verified archive extraction
  // scratch may disappear; retain its original archive and manifest identities.
  final durableSources = [
    for (final row in sources)
      if (!temporarySidecars ||
          !string(object(row['observed']), 'path').startsWith('sidecars/'))
        row,
    if (temporarySidecars) ...jsonDecode(sidecarArchive!._sourcesJson) as List,
  ];
  final journal = File('$manifestPath.sources.json');
  await journal.create(exclusive: true);
  await journal.writeAsString(
    jsonEncode({
      'sources': sources,
      'durable_sources': durableSources,
      'sidecars_materialized_from_archive': temporarySidecars,
      'jpeg_origins': jpegOrigins,
      'sidecars_preserved_as_whole_bytes': true,
      'historical_byte_parity': 'NOT_CLAIMED',
    }),
    flush: true,
  );
  final snapshot = OriginalFixtureSnapshot._(
    destinationRoot,
    manifestPath,
    await hashFile(File(manifestPath)),
    jsonEncode(manifest),
    jsonEncode(durableSources),
    jsonEncode(orderedFrames),
  );
  await snapshot.revalidate();
  return snapshot;
}

/// Validate declarations without loading native code. The accepted source closure
/// must also prove this additive bridge links to the sole packaged GLB provider.
void validateOriginalFixturePackageRow(
  Map<String, dynamic> row,
  Map<String, dynamic> provider,
) {
  if (row['fixture_header_sha256'] != originalFixtureHeaderSha256 ||
      row['fixture_source_sha256'] != originalFixtureSourceSha256 ||
      row['fixture_wrapper_sha256'] != fixtureWrapperSha256(row) ||
      row['fixture_combined_source_sha256'] !=
          fixtureCombinedSourceSha256(row) ||
      row['runtime_provider_binary_sha256'] != provider['binary_sha256'] ||
      row['runtime_provider_bundle_relative_path'] !=
          provider['bundle_relative_path']) {
    throw StateError(
      'Exact whole producer/header and same GLB provider binding required',
    );
  }
  final modules = checkedRelativePath(
    string(provider, 'native_modules_bundle_relative_path'),
  );
  if (row['fixture_wrapper_bundle_relative_path'] !=
          '$modules/pw38_original_fixture_bridge.py' ||
      row['fixture_source_bundle_relative_path'] !=
          '$modules/selected_original_prep_phone_fixture.py') {
    throw StateError(
      'Whole producer must reside in the existing provider module root',
    );
  }
  checkedRelativePath(string(row, 'fixture_header_bundle_relative_path'));
}

/// Pure receipt contract validation. It does not construct execution authority.
void validateOriginalFixtureReceipt({
  required Map<String, dynamic> receipt,
  required Map<String, dynamic> contract,
  required Map<String, dynamic> manifest,
  required String manifestPath,
  required String manifestSha256,
  required String outputRoot,
  required String contractSha256,
  required String sourcePath,
}) {
  final count = checkedFrameCount(manifest['selected_frames'] as int);
  final v2 = receipt['schema'] == 'PW38_INTACT_FIXTURE_EXECUTION_RECEIPT_V2';
  if ((!v2 && count != 97) || (v2 && (receipt['producer_profile'] != originalRetainedProfile || receipt['actual_frames'] != count || contract['producer_profile'] != originalRetainedProfile || contract['actual_frames'] != count || contract['noise_bank_capacity'] != officialNoiseBankCapacity))) throw StateError('Exact version-specific fixture count/profile binding required');
  if (receipt['schema'] != (v2 ? 'PW38_INTACT_FIXTURE_EXECUTION_RECEIPT_V2' : 'PW38_INTACT_FIXTURE_EXECUTION_RECEIPT_V1') ||
      receipt['status'] != 'returned' ||
      receipt['source_and_inputs_unchanged'] != true ||
      receipt['contract_sha256'] != contractSha256 ||
      receipt['error_type'] != null ||
      receipt.containsKey('verification_error_type') ||
      receipt['outputs'] is! List ||
      (receipt['outputs'] as List).length != count + 4)
    throw StateError('Observed complete original97 producer receipt required');
  if (contract['schema'] != (v2 ? 'PW38_INTACT_FIXTURE_EXECUTION_CONTRACT_V2' : 'PW38_INTACT_FIXTURE_EXECUTION_CONTRACT_V1') ||
      contract['source_sha256'] != originalFixtureSourceSha256 ||
      contract['wrapper_sha256'] != (v2 ? originalFixtureV2WrapperSha256 : originalFixtureWrapperSha256) ||
      contract['classification'] != 'actual_execution_no_parity_claim')
    throw StateError('Exact whole producer execution contract required');
  _equal(contract['inputs'], manifest, 'Actual producer inputs differ');
  _equal(
    contract['environment'],
    originalFixtureEnvironment,
    'Fixed producer recipe differs',
  );
  _equal(contract['argv'], [
    sourcePath,
    manifest['root'],
    outputRoot,
  ], 'Actual whole script argv differs');
  final binding = object(contract['input_manifest_binding']);
  if (binding['path'] != manifestPath || binding['sha256'] != manifestSha256)
    throw StateError('Producer manifest binding differs');
  final runtime = object(contract['runtime']);
  if (runtime['python'] != '3.10.21' ||
      runtime['numpy'] != '1.26.4' ||
      runtime['Pillow'] != '12.3.0')
    throw StateError('Pinned provider runtime versions required');
  final outputs = <String, Map<String, dynamic>>{};
  for (final raw in receipt['outputs'] as List) {
    final row = object(raw),
        path = checkedRelativePath(string(object(raw), 'path'));
    if (outputs.containsKey(path) ||
        row['role'] != 'actual_producer_output' ||
        row['bytes'] is! int ||
        (row['bytes'] as int) <= 0 ||
        row['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['sha256'] as String))
      throw StateError('Distinct measured original producer outputs required');
    outputs[path] = row;
  }
  final expected = {
    'cams.f32',
    'neighbors.i32',
    'images.f16',
    'frames.json',
    for (var i = 0; i < count; i++) 'rgb/${i.toString().padLeft(8, '0')}.jpg',
  };
  if (outputs.length != expected.length ||
      !outputs.keys.toSet().containsAll(expected) ||
      outputs['cams.f32']!['bytes'] != cameraTableBytes(count) ||
      outputs['neighbors.i32']!['bytes'] != neighborTableBytes(count) ||
      outputs['images.f16']!['bytes'] != originalImageTableBytes(count) ||
      outputs.values.fold<int>(0, (sum, row) => sum + (row['bytes'] as int)) >
          104857600)
    throw StateError(
      'Exact101 original97 output layout/transport lengths required',
    );
}

/// Actual IO verification is independently testable; it cannot mint an execution
/// capability. Every listed file and the complete output file set are measured.
Future<void> verifyOriginalFixtureOutputs({
  required String outputRoot,
  required Map<String, dynamic> receipt,
  required Map<String, dynamic> manifest,
}) async {
  final count = checkedFrameCount(manifest['selected_frames'] as int);
  await _canonical(outputRoot);
  final rows = (receipt['outputs'] as List).map(object).toList();
  final actualPaths = <String>{};
  await for (final entity in Directory(
    outputRoot,
  ).list(recursive: true, followLinks: false)) {
    if (entity is Directory) continue;
    if (entity is! File)
      throw StateError('Original producer output link/nonfile rejected');
    actualPaths.add(entity.path.substring(outputRoot.length + 1));
  }
  if (actualPaths.length != count + 4 ||
      rows.length != count + 4 ||
      !actualPaths.containsAll(rows.map((row) => string(row, 'path')))) {
    throw StateError('Actual101 original producer output file set differs');
  }
  for (final row in rows) {
    final relative = checkedRelativePath(string(row, 'path'));
    _equal(
      await _row('$outputRoot/$relative', relative, 'actual_producer_output'),
      row,
      'Actual producer output changed',
    );
  }
  final frames = object(
    jsonDecode(await File('$outputRoot/frames.json').readAsString()),
  );
  if (frames['count'] != count ||
      frames['width'] != 768 ||
      frames['height'] != 576 ||
      frames['num_src'] != 9) {
    throw StateError('Original frame output shape differs');
  }
  _equal(
    frames['names'],
    manifest['ordered_source_names'],
    'Original names differ',
  );
  _equal(
    frames['frame_ids'],
    manifest['frame_ids'],
    'Original frame identities differ',
  );
}

final class OriginalFixtureExecutionProof {
  OriginalFixtureExecutionProof._(
    this._snapshot,
    this._runtimeClosure,
    this.outputRoot,
    this.receiptPath,
    this._receiptSha256,
    this._contractSha256,
    this._receiptJson,
    this._packageJson,
    this._owner,
  );
  final OriginalFixtureSnapshot _snapshot;
  final ProductionRuntimeClosure _runtimeClosure;
  final String outputRoot,
      receiptPath,
      _receiptSha256,
      _contractSha256,
      _receiptJson,
      _packageJson;
  final Object _owner;
  String? _requestPath, _requestSha256;
  Map<String, dynamic> get receipt => object(jsonDecode(_receiptJson));
  Map<String, Object?> get nativeCall => {
    ..._runtimeClosure.identity,
    'native_entry': originalFixtureEntry,
    'return_code': 0,
    'receipt_sha256': _receiptSha256,
    'manifest_sha256': _snapshot.manifestSha256,
    'fixture_source_sha256': originalFixtureSourceSha256,
    'classification': 'ACTUAL_WORKER_FFI_EXECUTION_NO_PHONE_ACCEPTANCE',
  };
  Future<void> revalidate() async {
    if (!identical(_owner, _workerIdentity))
      throw StateError('Original execution proof belongs to another worker');
    await _snapshot.revalidate();
    await _runtimeClosure.revalidate();
    for (final raw in jsonDecode(_packageJson) as List) {
      final row = object(raw);
      _equal(
        await _row(
          string(row, 'absolute_path'),
          string(row, 'path'),
          string(row, 'role'),
        ),
        {...row}..remove('absolute_path'),
        'Packaged original producer identity changed',
      );
    }
    await _canonical(receiptPath);
    await _canonical('$receiptPath.contract.json');
    if (await hashFile(File(receiptPath)) != _receiptSha256 ||
        await hashFile(File('$receiptPath.contract.json')) != _contractSha256)
      throw StateError('Actual producer receipt/contract changed');
    await verifyOriginalFixtureOutputs(
      outputRoot: outputRoot,
      receipt: receipt,
      manifest: _snapshot.manifest,
    );
  }

  Future<ProductionSessionTableBytes> sessionTables() async {
    await revalidate();
    return ProductionSessionTableBytes(
      await File('$outputRoot/cams.f32').readAsBytes(),
      await File('$outputRoot/neighbors.i32').readAsBytes(),
      nativeCall,
    );
  }

  Future<void> bindRequest(File requestFile, String requestSha256) async {
    if (_requestPath != null)
      throw StateError('Original execution proof already bound to a request');
    await _verifyRequest(requestFile, requestSha256);
    _requestPath = requestFile.path;
    _requestSha256 = requestSha256;
  }

  Future<void> requireBoundRequest(File file, String sha256) async {
    if (_requestPath != file.path || _requestSha256 != sha256)
      throw StateError('Actual worker proof does not authorize this request');
    await _verifyRequest(file, sha256);
  }

  Future<void> _verifyRequest(File file, String sha256) async {
    await revalidate();
    if (await hashFile(file) != sha256)
      throw StateError('Proof-bound request changed');
    final request = object(jsonDecode(await file.readAsString()));
    final dense = object(request['dense_inputs']),
        root = string(dense, 'input_root');
    final runRoot = Directory(_snapshot.root).parent.path;
    final count = frameTransportCount(request);
    if (!usesOriginalRetained97(request) || variableFrameTransport(request) != (receipt['schema'] == 'PW38_INTACT_FIXTURE_EXECUTION_RECEIPT_V2') || count != _snapshot.manifest['selected_frames'] ||
        root != '$runRoot/inputs' ||
        !file.path.startsWith('$runRoot/preparation/')) {
      throw StateError(
        'Original worker execution proof must stay in its actual capture run',
      );
    }
    final outputRows = {
      for (final raw in receipt['outputs'] as List)
        string(object(raw), 'path'): object(raw),
    };
    Future<void> copied(String source, Map<String, dynamic> actual) async {
      final produced = outputRows[source]!;
      if (actual['bytes'] != produced['bytes'] ||
          actual['sha256'] != produced['sha256'])
        throw StateError('Request substituted original producer bytes');
      _equal(
        await _row(
          '$root/${actual['path']}',
          string(actual, 'path'),
          string(actual, 'role'),
        ),
        actual,
        'Copied producer bytes changed',
      );
    }

    final material = {
      for (final raw in dense['artifacts'] as List)
        string(object(raw), 'path'): object(raw),
    };
    await copied('cams.f32', material[string(dense, 'cameras_f32')]!);
    await copied('neighbors.i32', material[string(dense, 'neighbors_i32')]!);
    final fusion = dense['original_fusion_jpegs'] as List;
    final frames = dense['frames'] as List;
    if (fusion.length != count || frames.length != count)
      throw StateError('Proof requires actual original97 frame binding');
    for (var i = 0; i < count; i++) {
      final row = object(fusion[i]);
      if (row['pack_index'] != i ||
          row['original_index'] != i ||
          object(frames[i])['frame_id'] !=
              (_snapshot.manifest['frame_ids'] as List)[i])
        throw StateError('Proof request original frame order changed');
      final source = object((jsonDecode(_snapshot._framesJson) as List)[i]);
      final actualFrame = object(frames[i]);
      for (final key in [
        'frame_id',
        'fx',
        'fy',
        'cx',
        'cy',
        'image_w',
        'image_h',
        'q_wxyz',
        't',
      ]) {
        _equal(
          actualFrame[key],
          source[key],
          'Request substituted original refined frame transport',
        );
      }
      final sourceName =
          (_snapshot.manifest['ordered_source_names'] as List)[i];
      final sourceRow = (_snapshot.manifest['artifacts'] as List)
          .map(object)
          .singleWhere((value) => value['path'] == 'photos_jpg/$sourceName');
      final actualSource = material[string(actualFrame, 'jpeg_path')];
      if (actualSource == null ||
          actualSource['bytes'] != sourceRow['bytes'] ||
          actualSource['sha256'] != sourceRow['sha256'])
        throw StateError('Request substituted original resolved JPEG');
      _equal(
        await _row(
          '$root/${actualSource['path']}',
          string(actualSource, 'path'),
          string(actualSource, 'role'),
        ),
        actualSource,
        'Copied original resolved JPEG changed',
      );
      await copied(
        'rgb/${i.toString().padLeft(8, '0')}.jpg',
        object(row['artifact']),
      );
    }
    if (await hashFile(file) != sha256)
      throw StateError('Request changed while proof was checked');
  }
}

/// A Map-compatible bootstrap keeps existing legacy preparers valid. The proof
/// is an in-memory capability, never serialized into bootstrap JSON labels.
final class OriginalFixtureBoundBootstrap extends MapBase<String, String> {
  OriginalFixtureBoundBootstrap(Map<String, String> values, this.proof)
    : _values = Map<String, String>.unmodifiable(values);
  final Map<String, String> _values;
  final OriginalFixtureExecutionProof proof;
  @override
  String? operator [](Object? key) => _values[key];
  @override
  Iterable<String> get keys => _values.keys;
  @override
  void operator []=(String key, String value) =>
      throw UnsupportedError('Frozen bootstrap');
  @override
  void clear() => throw UnsupportedError('Frozen bootstrap');
  @override
  String? remove(Object? key) => throw UnsupportedError('Frozen bootstrap');
}

Future<OriginalFixtureExecutionProof> executeOriginalFixture({
  required OriginalFixtureSnapshot snapshot,
  ProductionRuntimeClosure? runtimeClosure,
  required Map<String, dynamic> nativeRow,
  required Map<String, dynamic> providerRow,
  required String bundleRoot,
  required String outputRoot,
  required String receiptPath,
}) async {
  if (Isolate.current.debugName == 'main')
    throw StateError('Original fixture requires reconstruction worker');
  if (runtimeClosure == null || runtimeClosure.bundleRoot != bundleRoot) {
    throw StateError(
      'Measured complete original producer runtime closure required',
    );
  }
  runtimeClosure.requireProvider(providerRow);
  await runtimeClosure.revalidate();
  validateOriginalFixturePackageRow(nativeRow, providerRow);
  await snapshot.revalidate();
  for (final path in [outputRoot, receiptPath, '$receiptPath.contract.json']) {
    await _canonical(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        path.startsWith('${snapshot.root}/') ||
        snapshot.root.startsWith('$path/'))
      throw StateError('Fresh disjoint producer output/evidence required');
  }
  final package = <Map<String, dynamic>>[];
  Future<void> pinned(String relative, String expected, String role) async {
    final path = '$bundleRoot/${checkedRelativePath(relative)}';
    final row = await _row(path, relative, role);
    if (row['sha256'] != expected)
      throw StateError(
        'Exact packaged original producer identity required: $relative',
      );
    package.add({...row, 'absolute_path': path});
  }

  for (final pair in [
    ('fixture_header_bundle_relative_path', originalFixtureHeaderSha256),
    ('fixture_source_bundle_relative_path', originalFixtureSourceSha256),
    ('fixture_wrapper_bundle_relative_path', fixtureWrapperSha256(nativeRow)),
  ]) {
    await pinned(string(nativeRow, pair.$1), pair.$2, 'producer_source');
  }
  for (final row in [nativeRow, providerRow]) {
    await pinned(
      string(row, 'bundle_relative_path'),
      string(row, 'binary_sha256'),
      'native_binary',
    );
    await pinned(
      string(row, 'source_receipt_path'),
      string(row, 'source_receipt_sha256'),
      'native_source_receipt',
    );
  }
  await runtimeClosure.revalidate();
  final slot = await NativeSlot.open(nativeRow, bundleRoot, {
    originalFixtureEntry,
    originalFixtureErrorEntry,
  });
  if (slot.sourceEvidence['fixture_combined_source_sha256'] !=
          fixtureCombinedSourceSha256(nativeRow) ||
      slot.sourceEvidence['fixture_header_sha256'] !=
          originalFixtureHeaderSha256 ||
      slot.sourceEvidence['runtime_provider_binary_sha256'] !=
          providerRow['binary_sha256'])
    throw StateError('Actual additive source/provider link closure required');
  final provider = await NativeSlot.open(providerRow, bundleRoot, {
    'pw38_glb_runtime_initialize',
  });
  final arena = Arena(Pw38SystemMemory(DynamicLibrary.process()));
  int rc;
  try {
    final init =
        provider.library.lookupFunction<PairN, PairD>(
          'pw38_glb_runtime_initialize',
        )(
          arena.path(
            '$bundleRoot/${checkedRelativePath(string(providerRow, 'runtime_home_bundle_relative_path'))}',
          ),
          arena.path(
            '$bundleRoot/${checkedRelativePath(string(providerRow, 'native_modules_bundle_relative_path'))}',
          ),
        );
    if (init != 0)
      throw StateError(
        'Same GLB CPython provider initialization failed: $init',
      );
    final hash = arena.bytes(65);
    hash.asTypedList(64).setAll(0, ascii.encode(snapshot.manifestSha256));
    rc =
        slot.library.lookupFunction<_PrepareN, _PrepareD>(originalFixtureEntry)(
          arena.path(snapshot.root),
          arena.path(outputRoot),
          arena.path(snapshot.manifestPath),
          hash.cast<Char>(),
          arena.path(receiptPath),
        );
    // Copy TLS error immediately on this calling thread, with no async boundary.
    if (rc != 0) {
      final pointer = slot.library.lookupFunction<_ErrorN, _ErrorD>(
        originalFixtureErrorEntry,
      )();
      var error = 'missing original producer TLS error';
      if (pointer != nullptr) {
        final bytes = pointer.cast<Uint8>().asTypedList(2048),
            end = bytes.indexOf(0);
        error = utf8.decode(
          bytes.sublist(0, end < 0 ? bytes.length : end),
          allowMalformed: true,
        );
      }
      throw StateError('Original whole producer failed: $rc $error');
    }
  } finally {
    arena.dispose();
  }
  final receiptFile = File(receiptPath),
      contractFile = File('$receiptPath.contract.json');
  final receiptSha = await hashFile(receiptFile),
      contractSha = await hashFile(contractFile);
  final receiptJson = await receiptFile.readAsString(),
      contractJson = await contractFile.readAsString();
  validateOriginalFixtureReceipt(
    receipt: object(jsonDecode(receiptJson)),
    contract: object(jsonDecode(contractJson)),
    manifest: snapshot.manifest,
    manifestPath: snapshot.manifestPath,
    manifestSha256: snapshot.manifestSha256,
    outputRoot: outputRoot,
    contractSha256: contractSha,
    sourcePath:
        '$bundleRoot/${nativeRow['fixture_source_bundle_relative_path']}',
  );
  if (object(
        object(jsonDecode(contractJson))['input_manifest_binding'],
      )['bytes'] !=
      await File(snapshot.manifestPath).length())
    throw StateError('Actual manifest byte count differs');
  final proof = OriginalFixtureExecutionProof._(
    snapshot,
    runtimeClosure,
    outputRoot,
    receiptPath,
    receiptSha,
    contractSha,
    receiptJson,
    jsonEncode(package),
    _workerIdentity,
  );
  await proof.revalidate();
  return proof;
}
