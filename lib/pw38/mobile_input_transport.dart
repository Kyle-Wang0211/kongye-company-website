import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'vendor/dart_pipeline/lib/pw38_geometry_ffi.dart';
import 'native_downstream.dart';
import 'reconstruction_request.dart';
import 'reconstruction_artifact_gate.dart';
import 'request.dart';
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart';

const pw38DocumentsToken = '/__PW38_DOCUMENTS__';
const pw38MobileTemplateSchema = 'PW38_PHONE_ACTUAL97_TEMPLATE_V4';
const pw38PillowEntry = 'pw38_normal_images_prepare';
const pw38PillowErrorEntry = 'pw38_normal_images_last_error';
typedef _PillowErrorN = Pointer<Char> Function();
typedef _PillowErrorD = Pointer<Char> Function();
String _nativeError(Pointer<Char> text) {
  if (text == nullptr) return 'Native producer returned no error string';
  final bytes = <int>[];
  for (var i = 0; i < 4096; i++) {
    final value = (text + i).value & 255;
    if (value == 0) return utf8.decode(bytes);
    bytes.add(value);
  }
  throw StateError('Unterminated native error string');
}

/// Root calls this before runMainline: only a measured effective request is returned.
Future<Map<String, String>> prepareMobileInputTransport(Map<String, String> bootstrap) async {
  final documents = bootstrap['documents_path']!;
  _absolute(documents);
  String path(String key) {
    final value = bootstrap[key]!;
    if (value.startsWith(pw38DocumentsToken)) return _bind(value, documents);
    _absolute(value);
    if (!value.startsWith('$documents/')) throw StateError('$key outside actual Documents');
    return value;
  }
  final prepared = await preparePw38MobileInputs(
    bootstrap: {...bootstrap, 'request_path': path('request_path')},
    packageBindingsFile: File(path('input_package_bindings_path')),
    packageBindingsSha256: bootstrap['input_package_bindings_sha256']!);
  return prepared.bootstrap;
}

final class Pw38PreparedMobileRequest {
  const Pw38PreparedMobileRequest(this.bootstrap, this.receipt);
  final Map<String, String> bootstrap;
  final Map<String, dynamic> receipt;
}

void _absolute(String path) {
  if (!path.startsWith('/') || path == '/' || path.endsWith('/') ||
      path.contains('\\') || path.contains('\u0000') ||
      path.substring(1).split('/').any((p) => p.isEmpty || p == '.' || p == '..')) {
    throw FormatException('Absolute, nonescaping phone path required');
  }
}
String _relative(String path) {
  checkedRelativePath(path);
  if (path.contains('\\') || path.contains('\u0000') ||
      path.split('/').any((p) => p.isEmpty || p == '.' || p == '..')) {
    throw FormatException('Nonescaping relative material path required');
  }
  return path;
}
String _bind(String path, String documents) {
  if (!path.startsWith('$pw38DocumentsToken/') ||
      path.indexOf(pw38DocumentsToken, 1) != -1) {
    throw FormatException('Only the exact Documents prefix may be rebound');
  }
  final result = '$documents/${_relative(path.substring(pw38DocumentsToken.length + 1))}';
  _absolute(result);
  return result;
}
Future<void> _noLinks(String root, String relative) async {
  _absolute(root);
  _relative(relative);
  var current = root;
  for (final part in relative.split('/')) {
    current = '$current/$part';
    if (await FileSystemEntity.type(current, followLinks: false) == FileSystemEntityType.link) {
      throw StateError('Symlink in phone input path: $relative');
    }
  }
}
Future<void> _verify(String root, Map<String, dynamic> row) async {
  final a = artifact(row);
  await _noLinks(root, a.path);
  final file = File('$root/${_relative(a.path)}');
  if (await FileSystemEntity.type(file.path, followLinks: false) != FileSystemEntityType.file ||
      await file.length() != a.bytes || await hashFile(file) != a.sha256) {
    throw StateError('Frozen phone input mismatch: ${a.path}');
  }
}
Future<String> _writeNew(File file, Object value) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) != FileSystemEntityType.notFound) {
    throw StateError('Preparation never overwrites an existing artifact');
  }
  await file.writeAsString('${jsonEncode(value)}\n', flush: true);
  return hashFile(file);
}

/// IO preparation only. Root supplies the actual package/source receipts and
/// Pillow FFI adapter; the existing reconstruction loader and stages stay strict.
/// No PNG hash or native success is declared before the corresponding call.
Future<Pw38PreparedMobileRequest> preparePw38MobileInputs({
  required Map<String, String> bootstrap,
  required File packageBindingsFile,
  required String packageBindingsSha256,
}) async {
  _absolute(bootstrap['request_path']!);
  _absolute(packageBindingsFile.path);
  _absolute(bootstrap['bundle_path']!);
  final templateFile = File(bootstrap['request_path']!);
  final templateSha = bootstrap['request_sha256']!;
  if (await hashFile(templateFile) != templateSha) throw StateError('Frozen mobile template changed');
  final envelope = object(jsonDecode(await templateFile.readAsString()));
  if (envelope['schema'] != pw38MobileTemplateSchema) throw FormatException('Phone template V4 required');
  if (await hashFile(packageBindingsFile) != packageBindingsSha256) {
    throw StateError('Root-frozen actual package bindings changed');
  }
  final package = object(jsonDecode(await packageBindingsFile.readAsString()));
  if (package['schema'] != 'PW38_ACTUAL_PACKAGE_BINDINGS_V3' ||
      package['template_sha256'] != templateSha) throw StateError('Package must bind this immutable template');
  final suppliedDocuments = bootstrap['documents_path']!;
  _absolute(suppliedDocuments);
  final documents = await Directory(suppliedDocuments).resolveSymbolicLinks();
  _absolute(documents);
  final bundle = await Directory(bootstrap['bundle_path']!).resolveSymbolicLinks();
  _absolute(bundle);
  final normalInputFormat = envelope.containsKey('normal_input_format')
      ? envelope['normal_input_format'] : 'png';
  if (normalInputFormat != 'png' && normalInputFormat != 'jpeg') {
    throw FormatException('Explicit normal input format must be png or jpeg');
  }
  final request = object(envelope['request']);
  if (request.containsKey('normal_input_format') && request['normal_input_format'] != normalInputFormat) {
    throw StateError('Envelope/request normal input format mismatch');
  }
  if (normalInputFormat == 'jpeg') request['normal_input_format'] = 'jpeg';
  final io = object(request['io_roots']);
  final pathBinding = <String, String>{};
  String bind(String path) => pathBinding.putIfAbsent(path, () => _bind(path, documents));
  for (final key in ['durable_input_root', 'downstream_output_root', 'texture_scene_root']) {
    io[key] = bind(string(io, key));
  }
  request['cleanup_roots'] = (request['cleanup_roots'] as List).cast<String>().map(bind).toList();
  final root = string(io, 'durable_input_root');
  await _noLinks(documents, root.substring(documents.length + 1));
  if (await FileSystemEntity.type(root, followLinks: false) != FileSystemEntityType.notFound) {
    throw StateError('Fresh App-owned durable input root required; old roots are preserved');
  }
  final uploadedRoot = bind(string(envelope, 'uploaded_input_root'));
  await _noLinks(documents, uploadedRoot.substring(documents.length + 1));
  if (await Directory(uploadedRoot).resolveSymbolicLinks() != uploadedRoot ||
      root == uploadedRoot || root.startsWith('$uploadedRoot/') || uploadedRoot.startsWith('$root/')) {
    throw StateError('Distinct uploaded and App-owned input roots required');
  }
  final dense = object(request['dense_inputs']);
  dense['input_root'] = bind(string(dense, 'input_root'));
  final outputRoot = string(io, 'downstream_output_root');
  await _noLinks(documents, outputRoot.substring(documents.length + 1));
  if (await FileSystemEntity.type(outputRoot, followLinks: false) != FileSystemEntityType.notFound) {
    throw StateError('Fresh reconstruction output root required before PNG preparation');
  }
  final preparationRoot = bind(string(envelope, 'preparation_root'));
  await _noLinks(documents, preparationRoot.substring(documents.length + 1));
  if (await FileSystemEntity.type(preparationRoot, followLinks: false) != FileSystemEntityType.notFound) {
    throw StateError('Fresh mobile preparation directory required; failed work is preserved');
  }
  final materials = (request['material_inputs'] as List).map(object).toList();
  if (materials.map((a) => a['path']).toSet().length != materials.length) throw StateError('Duplicate frozen material');
  if (materials.length != 495) throw StateError('Exact495 already-uploaded material files required');
  for (final a in materials) { await _verify(uploadedRoot, a); }
  for (final model in (envelope['models'] as List).map(object)) {
    await _verify(bundle, {'path': model['bundle_relative_path'], 'role': 'model',
      'bytes': model['bytes'], 'sha256': model['sha256']});
  }
  final libraries = object(package['native_libraries']);
  for (final name in ['dense', 'tsdf', 'meshio', 'meshopt_ply', 'geometry', 'texture', 'normal', 'glb']) {
    // Source closure and actual binary bytes are checked by the existing loader.
    final row = object(libraries[name]);
    await _noLinks(bundle, string(row, 'bundle_relative_path'));
    await _noLinks(bundle, string(row, 'source_receipt_path'));
    await NativeSlot.open(row, bundle, <String>{});
  }
  request['native_libraries'] = libraries;
  request['environment_manifest_sha256'] = string(package, 'environment_manifest_sha256');
  final environmentRelative = _relative(string(package, 'environment_manifest_bundle_relative_path'));
  await _noLinks(bundle, environmentRelative);
  if (await hashFile(File('$bundle/$environmentRelative')) != request['environment_manifest_sha256']) {
    throw StateError('Actual environment manifest changed');
  }
  final normalSpec = object((object(request['output_specs'])['avNormal'] as List).single);
  ReconstructionOutput.fromJson(normalSpec);
  if (normalSpec['kind'] != 'file_set' || normalSpec['role'] != 'normal_png' ||
      normalSpec['path'] != object(object(request['stage_paths'])['avNormal'])['normal_directory'] ||
      normalSpec['suffix'] != '.png' || normalSpec.containsKey('bytes') || normalSpec.containsKey('sha256')) {
    throw StateError('Actual normal output naming binding required');
  }
  object(request['output_specs'])['avNormal'] = [normalSpec];
  late final Map<String, dynamic> pillowRow;
  late final NativeSlot pillowSlot;
  final ordered = (request['ordered_material'] as List).map(object).toList();
  if (ordered.length != 97) throw StateError('Exact97 normal source order required');
  if (normalInputFormat == 'png') {
    pillowRow = object(package['pillow_library']);
    await _noLinks(bundle, string(pillowRow, 'bundle_relative_path'));
    await _noLinks(bundle, string(pillowRow, 'source_receipt_path'));
    pillowSlot = await NativeSlot.open(pillowRow, bundle,
      {pw38PillowEntry, pw38PillowErrorEntry, 'pw38_glb_runtime_initialize'});
    final plans = (envelope['normal_png_plan'] as List).map(object).toList();
    if (plans.length != 97) throw StateError('Exact97 source/Pillow order required');
    for (var i = 0; i < 97; i++) {
      final source = artifact(ordered[i]['source_jpeg']);
      if (ordered[i]['pack_index'] != i || ordered[i]['original_index'] != i ||
          plans[i]['pack_index'] != i || plans[i]['source_jpeg'] != source.path ||
          plans[i]['png_path'] != 'normal_original12mp/$i.png' ||
          plans[i]['width'] != 4032 || plans[i]['height'] != 3024 || ordered[i]['normal_image'] != null) {
        throw StateError('Exact97 Pillow plan required before any output generation');
      }
    }
  } else {
    for (var i = 0; i < 97; i++) {
      if (ordered[i]['pack_index'] != i || ordered[i]['original_index'] != i || ordered[i]['normal_image'] != null) {
        throw StateError('Exact97 JPEG copy order required before any output generation');
      }
    }
  }
  final sourcePaths = ordered.map((row) => artifact(row['source_jpeg']).path).toSet();
  final frozenLookup = {for (final row in materials) string(row, 'path'): row};
  if (sourcePaths.length != 97 || !sourcePaths.every(frozenLookup.containsKey)) {
    throw StateError('Exact97 distinct source JPEGs must bind uploaded material before writes');
  }
  for (final row in ordered) {
    final source = artifact(row['source_jpeg']);
    final frozen = artifact(frozenLookup[source.path]);
    if (source.bytes != frozen.bytes || source.sha256 != frozen.sha256 || source.role != frozen.role) {
      throw StateError('Ordered source JPEG differs from frozen upload');
    }
  }
  final normalDir = _relative(string(object(object(request['stage_paths'])['avNormal']), 'original_images'));
  await _noLinks(root, normalDir);
  if (await FileSystemEntity.type('$root/$normalDir', followLinks: false) != FileSystemEntityType.notFound) {
    throw StateError('Fresh PNG directory required; existing material is preserved');
  }
  await Directory(preparationRoot).create(recursive: true);
  final calls = <Map<String, dynamic>>[];
  final copies = <Map<String, dynamic>>[];
  final uploadedCount = materials.length;
  var copyJournalCompleted = false;
  final copyJournal = File('$preparationRoot/COPY_PROGRESS.json');
  Future<void> persistCopy(String status, [String? error]) async {
    if (copyJournalCompleted) return;
    await copyJournal.writeAsString(jsonEncode({
      'schema': 'PW38_APP_OWNED_INPUT_COPY_V4', 'status': status,
      'template_sha256': templateSha, 'uploaded_input_root': uploadedRoot,
      'durable_input_root': root, 'verified_uploaded_count': uploadedCount,
      'copied_count': copies.where((row) => row['status'] == 'copied_and_verified').length,
      'copy_api': 'dart:io File.copy', 'numeric_return_code': 'NOT_EXPOSED_BY_DART_FILE_COPY',
      'files': copies, 'error': error}), flush: true);
  }
  try {
    await persistCopy('uploaded495_verified_before_copy');
    // App creates this fresh directory, so future Pillow PNGs are App-writable.
    await Directory(root).create(recursive: false);
    for (final row in materials) {
      final relative = _relative(string(row, 'path'));
      final source = File('$uploadedRoot/$relative');
      final destination = File('$root/$relative');
      final observed = <String, dynamic>{'path': relative, 'status': 'copy_started',
        'source_path': source.path, 'destination_path': destination.path,
        'started_at_utc': DateTime.now().toUtc().toIso8601String()};
      copies.add(observed);
      await _noLinks(uploadedRoot, relative);
      await _noLinks(root, relative);
      await destination.parent.create(recursive: true);
      if (await FileSystemEntity.type(destination.path, followLinks: false) != FileSystemEntityType.notFound) {
        throw StateError('App-owned copy destination must be fresh: $relative');
      }
      final copiedFile = await source.copy(destination.path);
      observed['copy_return_path'] = copiedFile.path;
      observed['source_bytes_after_copy'] = await source.length();
      observed['source_sha256_after_copy'] = await hashFile(source);
      observed['destination_bytes'] = await destination.length();
      observed['destination_sha256'] = await hashFile(destination);
      await _noLinks(uploadedRoot, relative);
      await _noLinks(root, relative);
      if (await FileSystemEntity.type(source.path, followLinks: false) != FileSystemEntityType.file ||
          await FileSystemEntity.type(destination.path, followLinks: false) != FileSystemEntityType.file ||
          observed['source_bytes_after_copy'] != row['bytes'] ||
          observed['destination_bytes'] != row['bytes'] ||
          observed['source_sha256_after_copy'] != row['sha256'] ||
          observed['destination_sha256'] != row['sha256']) {
        throw StateError('Actual source/destination copy identity mismatch: $relative');
      }
      observed['status'] = 'copied_and_verified';
      observed['completed_at_utc'] = DateTime.now().toUtc().toIso8601String();
      await persistCopy('copying');
    }
    await persistCopy('complete495_before_pillow');
    copyJournalCompleted = true;
    await Directory(outputRoot).parent.create(recursive: true);
    final produced = <Map<String, dynamic>>[];
    String? normalCopyReceiptSha;
    File? pngProducerReceipt;
    if (normalInputFormat == 'png') {
      final producerManifest = File('$preparationRoot/PILLOW_INPUT_MANIFEST.json');
      final producerManifestSha = await _writeNew(producerManifest, {'frames': [
        for (var i = 0; i < 97; i++) {
          'pack_index': i, 'path': '$root/${artifact(ordered[i]['source_jpeg']).path}',
          'source_bytes': artifact(ordered[i]['source_jpeg']).bytes,
          'source_sha256': artifact(ordered[i]['source_jpeg']).sha256,
        }
      ]});
      final producerReceipt = File('$preparationRoot/PILLOW_RECEIPT.json');
      final arena = Arena(Pw38SystemMemory(DynamicLibrary.process()));
      int rc;
      try {
        final home = '$bundle/${_relative(string(pillowRow, 'runtime_home_bundle_relative_path'))}';
        final modules = '$bundle/${_relative(string(pillowRow, 'native_modules_bundle_relative_path'))}';
        final initRc = pillowSlot.library.lookupFunction<PairN, PairD>('pw38_glb_runtime_initialize')(
          arena.path(home), arena.path(modules));
        calls.add({'native_entry': 'pw38_glb_runtime_initialize', 'return_code': initRc});
        if (initRc != 0) throw StateError('Existing pinned Python runtime initialization failed $initRc');
        rc = pillowSlot.library.lookupFunction<TripleN, TripleD>(pw38PillowEntry)(
          arena.path(producerManifest.path), arena.path('$root/$normalDir'), arena.path(producerReceipt.path));
        // Copy the thread-local error immediately, before another native call.
        final error = rc == 0 ? '' : _nativeError(pillowSlot.library
          .lookupFunction<_PillowErrorN, _PillowErrorD>(pw38PillowErrorEntry)());
        calls.add({'native_entry': pw38PillowEntry, 'return_code': rc, 'error': error,
          'manifest_sha256': producerManifestSha, 'receipt_path': producerReceipt.path});
        if (rc != 0) throw StateError('Actual Pillow IO failed $rc: $error');
      } finally { arena.dispose(); }
      await _noLinks(preparationRoot, 'PILLOW_RECEIPT.json');
      final report = object(jsonDecode(await producerReceipt.readAsString()));
      produced.addAll((report['frames'] as List).map(object));
      if (report['schema'] != 'pw38.normal_image_io.v1' || report['status'] != 'complete' ||
          report['prepared_count'] != 97 || report['return_code'] != 0 || produced.length != 97 ||
          report['input_manifest_sha256'] != producerManifestSha || report['output_directory'] != '$root/$normalDir') {
        throw StateError('Actual Pillow completion/manifest receipt required');
      }
      for (var i = 0; i < 97; i++) {
        final source = artifact(ordered[i]['source_jpeg']);
        final relative = '$normalDir/$i.png';
        final row = produced[i];
        if (row['pack_index'] != i || row['status'] != 'prepared' ||
            row['source_path'] != '$root/${source.path}' || row['source_bytes'] != source.bytes ||
            row['source_sha256'] != source.sha256 || row['actual_source_bytes'] != source.bytes ||
            row['actual_source_sha256'] != source.sha256 || row['actualpath'] != '$root/$relative' ||
            jsonEncode(row['size']) != '[4032,3024]' || jsonEncode(row['source_pixel_size']) != '[4032,3024]') {
          throw StateError('Observed Pillow frame/source identity mismatch $i');
        }
        final observed = <String, dynamic>{'path': relative, 'role': 'normal_image',
          'bytes': row['bytes'], 'sha256': row['sha256']};
        await _verify(root, observed);
        await _verify(root, object(ordered[i]['source_jpeg']));
        ordered[i]['normal_image'] = observed;
        materials.add(observed);
      }
      pngProducerReceipt = producerReceipt;
    } else {
      await Directory('$root/$normalDir').create(recursive: false);
      final jpegCopies = <Map<String, dynamic>>[];
      final journal = File('$preparationRoot/NORMAL_JPEG_COPY.json');
      Future<void> persistNormalCopies(String status) async {
        await journal.writeAsString(jsonEncode({
          'schema': 'PW38_NORMAL_JPEG_BYTE_COPY_V1', 'status': status,
          'normal_input_format': 'jpeg', 'copies': jpegCopies,
          'copied_count': jpegCopies.where((row) => row['status'] == 'copied_and_verified').length,
          'copy_api': 'dart:io File.copy', 'numeric_return_code': 'NOT_EXPOSED_BY_DART_FILE_COPY',
          'pixel_sizes': 'NOT_OBSERVED_BY_BYTE_COPY',
          'native_oiio_metadata_gate': 'PENDING_ACTUAL_ALICEVISION_CONSUMER',
          'deviation': 'Original JPEG bytes reused for opt-in normal input; no Pillow RGB/PNG preparation'}), flush: true);
      }
      try {
        await persistNormalCopies('copying');
        for (var i = 0; i < 97; i++) {
          final source = artifact(ordered[i]['source_jpeg']);
          final relative = '$normalDir/$i.jpg';
          await _verify(root, object(ordered[i]['source_jpeg']));
          await _noLinks(root, relative);
          final destination = File('$root/$relative');
          if (await FileSystemEntity.type(destination.path, followLinks: false) != FileSystemEntityType.notFound) {
            throw StateError('Fresh JPEG copy destination required');
          }
          final row = <String, dynamic>{'pack_index': i, 'source_path': source.path,
            'source_bytes': source.bytes, 'source_sha256': source.sha256,
            'destination_path': relative, 'status': 'copy_started'};
          jpegCopies.add(row);
          final sourceFile = File('$root/${source.path}');
          row['copy_return_path'] = (await sourceFile.copy(destination.path)).path;
          row['source_bytes_after_copy'] = await sourceFile.length();
          row['source_sha256_after_copy'] = await hashFile(sourceFile);
          final observed = <String, dynamic>{'path': relative, 'role': 'normal_image',
            'bytes': await destination.length(), 'sha256': await hashFile(destination)};
          row['observed'] = observed;
          await _verify(root, observed);
          await _verify(root, object(ordered[i]['source_jpeg']));
          if (observed['bytes'] != source.bytes || observed['sha256'] != source.sha256 ||
              row['source_bytes_after_copy'] != source.bytes || row['source_sha256_after_copy'] != source.sha256) {
            throw StateError('Byte-identical normal JPEG copy required for frame $i');
          }
          row['status'] = 'copied_and_verified';
          ordered[i]['normal_image'] = observed;
          materials.add(observed);
          produced.add(row);
          await persistNormalCopies('copying');
        }
        await persistNormalCopies('complete97');
        normalCopyReceiptSha = await hashFile(journal);
      } catch (error) {
        if (jpegCopies.isNotEmpty && jpegCopies.last['status'] == 'copy_started') {
          jpegCopies.last['status'] = 'failed';
          jpegCopies.last['error'] = error.toString();
          jpegCopies.last['os_error_code'] = error is FileSystemException ? error.osError?.errorCode : null;
        }
        await persistNormalCopies('failed');
        rethrow;
      }
    }
    final actualNames = <String>{};
    await for (final entry in Directory('$root/$normalDir').list(followLinks: false)) {
      if (await FileSystemEntity.type(entry.path, followLinks: false) != FileSystemEntityType.file) {
        throw StateError(normalInputFormat == 'png' ? 'Nonregular Pillow directory member' : 'Nonregular normal JPEG directory member');
      }
      actualNames.add(entry.path.substring('$root/$normalDir/'.length));
    }
    if (actualNames.length != 97 || !actualNames.containsAll([for (var i = 0; i < 97; i++) '$i.${normalInputFormat == 'png' ? 'png' : 'jpg'}'])) {
      throw StateError(normalInputFormat == 'png' ? 'Exact97 observed Pillow directory required' : 'Exact97 observed JPEG directory required');
    }
    if (normalInputFormat == 'png') calls.last['receipt_sha256'] = await hashFile(pngProducerReceipt!);
    request['material_inputs'] = materials;
    request['ordered_material'] = ordered;
    final manifestSha = await _writeNew(File('$preparationRoot/OBSERVED_INPUT_MANIFEST.json'),
      {'schema': 'PW38_PHONE_OBSERVED_INPUTS_V4', 'ordered_material': ordered, 'material_inputs': materials});
    request['ordered_input_manifest_sha256'] = manifestSha;
    object(request['noise_identity'])['ordered_input_manifest_sha256'] = manifestSha;
    if (normalInputFormat == 'png') {
      request['normal_material_origin'] = 'ACCEPTED_REGENERATED_INPUTS_OFFICIAL_PILLOW_RAW_EXIF_RGB_PNG';
      request['normal_png_generation_status'] = 'OBSERVED97_THIS_PHONE_PREPARATION';
    } else {
      request['normal_material_origin'] = 'OPT_IN_ORIGINAL_SOURCE_JPEG_BYTE_IDENTICAL_COPY';
      request['normal_png_generation_status'] = 'NOT_RUN_JPEG_INPUT_MODE';
      request['normal_input_metadata_runtime_gate'] = 'PENDING_ACTUAL_ALICEVISION_OIIO_CONSUMER';
      request['normal_input_copy_receipt_sha256'] = normalCopyReceiptSha;
    }
    request['input_transport_identity'] = {'template_sha256': templateSha,
      'package_bindings_sha256': packageBindingsSha256, 'observed_input_manifest_sha256': manifestSha};
    final effective = File('$preparationRoot/EFFECTIVE_REQUEST.json');
    final effectiveSha = await _writeNew(effective, request);
    await ReconstructionRequest.load(effective, effectiveSha);
    final receipt = <String, dynamic>{'schema': 'PW38_PHONE_INPUT_BINDING_V4',
      'template_path': templateFile.path, 'template_sha256': templateSha,
      'package_bindings_path': packageBindingsFile.path, 'package_bindings_sha256': packageBindingsSha256,
      'bootstrap_documents_path': suppliedDocuments, 'resolved_documents_path': documents,
      'path_binding': pathBinding, 'effective_request_path': effective.path,
      'effective_request_sha256': effectiveSha, 'ordered_input_manifest_sha256': manifestSha,
      'copy_journal_path': copyJournal.path, 'copy_journal_sha256': await hashFile(copyJournal),
      'copied_input_count': copies.length, 'uploaded_input_root': uploadedRoot,
      'normal_png_count': normalInputFormat == 'png' ? produced.length : 0, 'actual_pillow_calls': calls,
      if (normalInputFormat == 'png') 'pillow_binary_sha256': pillowSlot.binarySha256,
      if (normalInputFormat == 'jpeg') ...{
        'normal_input_format': 'jpeg', 'normal_jpeg_count': produced.length,
        'normal_input_copy_receipt_path': '$preparationRoot/NORMAL_JPEG_COPY.json',
        'normal_input_copy_receipt_sha256': normalCopyReceiptSha,
        'native_oiio_metadata_gate': 'PENDING_ACTUAL_ALICEVISION_CONSUMER',
        'deviation': 'Original JPEG bytes reused for normal input; PNG input preparation omitted'}, 'historical_png_byte_parity': 'NOT_CLAIMED',
      'reconstruction_stage_execution': 'NOT_STARTED'};
    final receiptSha = await _writeNew(File('$preparationRoot/INPUT_BINDING.json'), receipt);
    return Pw38PreparedMobileRequest({...bootstrap, 'request_path': effective.path,
      'request_sha256': effectiveSha, 'template_request_sha256': templateSha,
      'input_binding_path': '$preparationRoot/INPUT_BINDING.json', 'input_binding_sha256': receiptSha}, receipt);
  } catch (e) {
    if (!copyJournalCompleted) {
      if (copies.isNotEmpty && copies.last['status'] == 'copy_started') {
        copies.last['status'] = 'failed';
        copies.last['error'] = e.toString();
        copies.last['os_error_code'] = e is FileSystemException ? e.osError?.errorCode : null;
      }
      await persistCopy('failed', e.toString());
    }
    await File('$preparationRoot/PREPARATION_FAILED.json').writeAsString(jsonEncode({
      'template_sha256': templateSha, 'package_bindings_sha256': packageBindingsSha256,
      'error': e.toString(), 'actual_pillow_calls': calls,
      if (normalInputFormat == 'jpeg') ...{'normal_input_format': 'jpeg',
        'normal_input_copy_receipt_path': '$preparationRoot/NORMAL_JPEG_COPY.json',
        'native_oiio_metadata_gate': 'PENDING_ACTUAL_ALICEVISION_CONSUMER'},
      'reconstruction_stage_execution': 'NOT_STARTED'}), flush: true);
    rethrow;
  }
}
