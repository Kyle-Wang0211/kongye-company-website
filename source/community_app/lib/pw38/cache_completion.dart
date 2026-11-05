import 'frame_transport.dart';
import 'terminal_glb.dart';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'execution_identity_scope.dart';
import 'original_retention_io.dart';
import 'production_result_contract.dart';
import 'reconstruction_request.dart'
    show reconstructionSchema, reconstructionRoute;
import 'request.dart' show object, string, hashFile;
import 'vendor/dart_pipeline/lib/pw38_pipeline.dart' show checkedRelativePath;

const pw38CacheCompletionMarkerName = 'pw38_cache_complete.json';
const _schema = 'PW38_RETAINED_CACHE_COMPLETION_V1';
const _glbOnlySchema = 'PW38_GLB_ONLY_COMPLETION_V2';

String _hash(Map<String, dynamic> row, String key) {
  final value = string(row, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw StateError('Completion requires measured $key');
  }
  return value;
}

Future<File> _regular(String path) async {
  final file = File(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.resolveSymbolicLinks() != path) {
    throw StateError('Canonical regular completion file required: $path');
  }
  return file;
}

Future<Map<String, dynamic>> _readJson(File file) async {
  if (await file.length() > 8 * 1024 * 1024) {
    throw StateError('Oversized completion JSON');
  }
  return object(jsonDecode(await file.readAsString()));
}

String _under(String root, String path) {
  if (!path.startsWith('$root/'))
    throw StateError('Completion path escaped owner');
  return checkedRelativePath(path.substring(root.length + 1));
}

String _signature(FileStat stat) =>
    '${stat.type}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:'
    '${stat.changed.microsecondsSinceEpoch}:${stat.mode}';

bool _recordAttached(
  String documents,
  String recordId,
  String capture,
  String publishedGlb,
) {
  try {
    final file = File('$documents/scan_records.json');
    if (file.resolveSymbolicLinksSync() != file.path ||
        file.lengthSync() > 8 * 1024 * 1024) {
      return false;
    }
    final value = jsonDecode(file.readAsStringSync());
    if (value is! List) return false;
    final rows = value
        .whereType<Map>()
        .where((r) => r['id'] == recordId)
        .toList();
    if (rows.length != 1 || rows.single['pipeline_kind'] != 'official')
      return false;
    final row = rows.single;
    final capturePath = row['captureDir'], artifact = row['artifactPath'];
    if (capturePath is! String ||
        artifact is! String ||
        Directory(capturePath).resolveSymbolicLinksSync() != capture)
      return false;
    final uri = Uri.tryParse(artifact);
    final path = uri != null && uri.scheme == 'file'
        ? uri.toFilePath()
        : artifact;
    return File(path).resolveSymbolicLinksSync() == publishedGlb;
  } catch (_) {
    return false;
  }
}

/// This proof is created only after hashing actual bytes. Metadata may invalidate
/// a proof within this process; it never establishes a cold-start proof.
final class Pw38CacheCompletionProof {
  Pw38CacheCompletionProof(
    this.capture,
    this.documents,
    this.recordId,
    this.publishedGlb,
    this.fileSignatures,
    this.identityScope,
  );
  final Pw38ExecutionIdentityScope identityScope;
  final String capture, documents, recordId, publishedGlb;
  final Map<String, String> fileSignatures;

  bool stillMatches() {
    try {
      identityScope.requireCapture(capture);
      if (!_recordAttached(documents, recordId, capture, publishedGlb))
        return false;
      for (final entry in fileSignatures.entries) {
        final file = File(entry.key);
        if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
                FileSystemEntityType.file ||
            file.resolveSymbolicLinksSync() != file.path ||
            _signature(file.statSync()) != entry.value)
          return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Persist a binding to the exact engine RESULT and official record. The caller
/// has already verified producer outputs and persisted the artifact attachment.
/// A claim prevents another writer from replacing an existing completion marker.
Future<void> publishPw38CacheCompletion({
  required String captureDir,
  required String workRoot,
  required String recordId,
  required String publishedGlbPath,
  required Map<String, Object?> receipt,
  bool preserveReceiptOnly = false,
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) async {
  await identityScope.revalidate();
  identityScope.requireCapture(captureDir);
  final capture = await Directory(captureDir).resolveSymbolicLinks();
  final work = await Directory(workRoot).resolveSymbolicLinks();
  final documents = Directory(capture).parent.parent.path;
  final publishedGlb = await File(publishedGlbPath).resolveSymbolicLinks();
  checkedRelativePath(recordId);
  if (recordId.contains('/') ||
      capture != '$documents/captures_official/$recordId' ||
      publishedGlb != '$documents/scans_official/$recordId.glb') {
    throw StateError(
      'Official cache completion requires the exact record namespace',
    );
  }
  final run = _under(capture, work);
  if (run.split('/').length != 2 || !run.startsWith('pw38_full_runs_v1/')) {
    throw StateError('Cache completion must belong to its retained full38 run');
  }
  final outputs = Pw38ProductionOutputContract.fromReceipt(
    receipt,
    workRoot: work,
    identityScope: identityScope,
  );
  if (outputs.dense is! Pw38OriginalRetainedOutput) {
    throw StateError('Cache completion cannot relabel legacy dense PLY output');
  }
  final glbOnly = receipt['generated_retirement'] is Map;
  final externalResult =
      '$capture/pw38_completion_evidence/${run.split('/').last}/RESULT.json';
  final liveResult = '${outputs.glb.root}/RESULT.json';
  final result = await _regular(
    glbOnly &&
            await FileSystemEntity.type(liveResult, followLinks: false) ==
                FileSystemEntityType.notFound
        ? externalResult
        : liveResult,
  );
  final expectedResult = sha256
      .convert(utf8.encode(jsonEncode(receipt)))
      .toString();
  if (await hashFile(result) != expectedResult ||
      !_recordAttached(documents, recordId, capture, publishedGlb)) {
    throw StateError(
      'Actual engine receipt and durable record attachment required',
    );
  }
  File persistedResult = result;
  if (glbOnly) {
    final published = await _regular(publishedGlb);
    if (await published.length() != outputs.glb.bytes ||
        await hashFile(published) != outputs.glb.sha256) {
      throw StateError('Published GLB bytes differ before retirement');
    }
    await validateTerminalGlb(published);
    final evidence = Directory(
      '$capture/pw38_completion_evidence/${run.split('/').last}',
    );
    await evidence.create(recursive: true);
    if (await evidence.resolveSymbolicLinks() != evidence.path)
      throw StateError('Noncanonical external completion evidence');
    persistedResult = File('${evidence.path}/RESULT.json');
    if (await FileSystemEntity.type(persistedResult.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      await persistedResult.create(exclusive: true);
      await persistedResult.writeAsString(jsonEncode(receipt), flush: true);
    }
    if (await hashFile(await _regular(persistedResult.path)) != expectedResult)
      throw StateError('External receipt readback failed');
  }
  if (preserveReceiptOnly) {
    if (!glbOnly)
      throw StateError('Only generated retirement may externalize evidence');
    return;
  }
  final marker = <String, Object?>{
    'schema': glbOnly ? _glbOnlySchema : _schema,
    'bundle_id': receipt['bundle_id'],
    'build': receipt['build'],
    'identity_scope': identityScope.toJson(),
    'dense_producer_profile': receipt['dense_producer_profile'],
    'ordered_frames': receipt['ordered_frames'] ?? 97,
    'record_id': recordId,
    'capture_relative_path': 'captures_official/$recordId',
    'published_glb_relative_path': 'scans_official/$recordId.glb',
    'work_relative_path': run,
    'source_work_root': work,
    'result_relative_path': _under(capture, persistedResult.path),
    'result_sha256': expectedResult,
    'run_id': string(object(receipt), 'run_id'),
    'request_sha256': _hash(object(receipt), 'request_sha256'),
    'published_glb_bytes': outputs.glb.bytes,
    'published_glb_sha256': outputs.glb.sha256,
  };
  final target = File('$capture/$pw38CacheCompletionMarkerName');
  if (await FileSystemEntity.type(target.path, followLinks: false) !=
      FileSystemEntityType.notFound)
    throw StateError('Completion marker already exists');
  final staging = await Directory(capture).createTemp('.pw38_completion_');
  final staged = File('${staging.path}/marker.json');
  await staged.writeAsString(jsonEncode(marker), flush: true);
  // Exclusive permanent claim + one capture writer; stale claims are retained
  // on failure rather than silently overwriting an earlier publication.
  await File('$capture/.pw38_cache_completion_claim').create(exclusive: true);
  if (await FileSystemEntity.type(target.path, followLinks: false) !=
      FileSystemEntityType.notFound)
    throw StateError('Completion marker appeared');
  await staged.rename(target.path);
}

/// Execute on a worker isolate for cold restart and explicit integrity rechecks.
/// Paths recorded by an earlier iOS container are relocated only beneath the
/// bound run. No external path or historical receipt may become a new run.
Future<Pw38CacheCompletionProof> verifyPw38CacheCompletion(
  String captureDir, {
  Pw38ExecutionIdentityScope identityScope =
      Pw38ExecutionIdentityScope.production,
}) async {
  await identityScope.revalidate();
  identityScope.requireCapture(captureDir);
  final capture = await Directory(captureDir).resolveSymbolicLinks();
  final documents = Directory(capture).parent.parent.path;
  final signatures = <String, String>{};
  Future<void> verify(String path, {int? bytes, String? hash}) async {
    final file = await _regular(path);
    final before = _signature(await file.stat());
    if ((bytes != null && await file.length() != bytes) ||
        (hash != null && await hashFile(file) != hash)) {
      throw StateError('Cache completion byte identity mismatch: $path');
    }
    final after = _signature(await file.stat());
    if (before != after)
      throw StateError('Completion file changed while hashing');
    signatures[path] = after;
  }

  final markerFile = await _regular('$capture/$pw38CacheCompletionMarkerName');
  final markerHash = await hashFile(markerFile);
  final marker = await _readJson(markerFile);
  final markerCount = frameTransportCount(marker);
  if (marker['schema'] == _glbOnlySchema) {
    identityScope.requireReceipt(marker);
    final id = checkedRelativePath(string(marker, 'record_id'));
    final run = checkedRelativePath(string(marker, 'work_relative_path'));
    final published = checkedRelativePath(
      string(marker, 'published_glb_relative_path'),
    );
    final resultRelative = checkedRelativePath(
      string(marker, 'result_relative_path'),
    );
    if (id.contains('/') ||
        capture != '$documents/captures_official/$id' ||
        marker['capture_relative_path'] != 'captures_official/$id' ||
        published != 'scans_official/$id.glb' ||
        run.split('/').length != 2 ||
        !run.startsWith('pw38_full_runs_v1/') ||
        resultRelative !=
            'pw38_completion_evidence/${run.split('/').last}/RESULT.json') {
      throw StateError('GLB-only completion escaped its account/work/run');
    }
    final resultFile = await _regular('$capture/$resultRelative');
    await verify(resultFile.path, hash: _hash(marker, 'result_sha256'));
    final receipt = await _readJson(resultFile);
    if (receipt['run_id'] != marker['run_id'] ||
        receipt['request_sha256'] != _hash(marker, 'request_sha256') ||
        receipt['dense_producer_profile'] != marker['dense_producer_profile'] ||
        (receipt['ordered_frames'] ?? 97) != markerCount ||
        receipt['generated_retirement'] is! Map)
      throw StateError('GLB-only receipt identity mismatch');
    final outputs = Pw38ProductionOutputContract.fromReceipt(
      receipt,
      workRoot: string(marker, 'source_work_root'),
      identityScope: identityScope,
    );
    if (marker['published_glb_bytes'] != outputs.glb.bytes ||
        _hash(marker, 'published_glb_sha256') != outputs.glb.sha256 ||
        !_recordAttached(documents, id, capture, '$documents/$published'))
      throw StateError('GLB-only record/publication mismatch');
    await verify(
      '$documents/$published',
      bytes: outputs.glb.bytes,
      hash: outputs.glb.sha256,
    );
    await validateTerminalGlb(File('$documents/$published'));
    await verify(markerFile.path, hash: markerHash);
    return Pw38CacheCompletionProof(
      capture,
      documents,
      id,
      '$documents/$published',
      Map.unmodifiable(signatures),
      identityScope,
    );
  }

  // Production markers written before identity scopes remain valid only under
  // the production default; independent markers must bind the complete scope.
  if (marker.containsKey('identity_scope') || identityScope.isIndependentTest) {
    identityScope.requireReceipt(marker);
  }
  final id = checkedRelativePath(string(marker, 'record_id'));
  final run = checkedRelativePath(string(marker, 'work_relative_path'));
  final published = checkedRelativePath(
    string(marker, 'published_glb_relative_path'),
  );
  if (marker['schema'] != _schema ||
      !usesOriginalRetained97(marker) ||
      id.contains('/') ||
      marker['capture_relative_path'] != 'captures_official/$id' ||
      capture != '$documents/captures_official/$id' ||
      published != 'scans_official/$id.glb' ||
      run.split('/').length != 2 ||
      !run.startsWith('pw38_full_runs_v1/')) {
    throw StateError('Invalid official cache completion binding');
  }
  final work = '$capture/$run';
  if (await Directory(work).resolveSymbolicLinks() != work) {
    throw StateError('Noncanonical completion run');
  }
  final source = string(marker, 'source_work_root');
  if (!source.startsWith('/') ||
      source.endsWith('/') ||
      Uri.directory(source).normalizePath().toFilePath() != '$source/') {
    throw StateError('Invalid original completion root');
  }
  String relocated(String path) => '$work/${_under(source, path)}';
  final resultPath = checkedRelativePath(
    string(marker, 'result_relative_path'),
  );
  if (!resultPath.startsWith('$run/'))
    throw StateError('Completion receipt outside run');
  final resultFile = await _regular('$capture/$resultPath');
  await verify(resultFile.path, hash: _hash(marker, 'result_sha256'));
  final receipt = await _readJson(resultFile);
  if (receipt['run_id'] != marker['run_id'] ||
      receipt['request_sha256'] != _hash(marker, 'request_sha256') ||
      receipt['dense_producer_profile'] != marker['dense_producer_profile'] ||
      (receipt['ordered_frames'] ?? 97) != markerCount) {
    throw StateError('Completion request/run identity differs');
  }
  final outputs = Pw38ProductionOutputContract.fromReceipt(
    receipt,
    workRoot: source,
    identityScope: identityScope,
  );
  final dense = outputs.dense;
  if (dense is! Pw38OriginalRetainedOutput ||
      relocated('${outputs.glb.root}/RESULT.json') != resultFile.path) {
    throw StateError(
      'Completion requires its actual original cache-only result',
    );
  }
  final inputBinding = relocated(string(receipt, 'input_binding_path'));
  await verify(inputBinding, hash: _hash(receipt, 'input_binding_sha256'));
  final binding = await _readJson(File(inputBinding));
  if (binding['schema'] != 'PW38_PRODUCTION_INPUT_BINDING_V1' ||
      binding['status'] != 'PREPARED_REQUEST_ONLY' ||
      binding['request_sha256'] != receipt['request_sha256']) {
    throw StateError('Durable production input/request binding required');
  }
  final requestPath = relocated(string(binding, 'request_path'));
  await verify(requestPath, hash: _hash(receipt, 'request_sha256'));
  final request = await _readJson(File(requestPath));
  if (request['schema'] != reconstructionSchema ||
      request['route_id'] != reconstructionRoute ||
      request['algorithm_revision'] !=
          'c0f26ee018a2b3f9d0fa773a49711cf203da9277' ||
      request['run_id'] != receipt['run_id'] ||
      request['ordered_frames'] != markerCount ||
      request['dense_producer_profile'] != marker['dense_producer_profile'] ||
      !usesOriginalRetained97(request)) {
    throw StateError('Completion requires its original97 effective request');
  }
  await verify(
    relocated(outputs.glb.path),
    bytes: outputs.glb.bytes,
    hash: outputs.glb.sha256,
  );
  if (marker['published_glb_bytes'] != outputs.glb.bytes ||
      _hash(marker, 'published_glb_sha256') != outputs.glb.sha256 ||
      !_recordAttached(documents, id, capture, '$documents/$published')) {
    throw StateError('Completion GLB/durable record identity differs');
  }
  await verify(
    '$documents/$published',
    bytes: outputs.glb.bytes,
    hash: outputs.glb.sha256,
  );
  for (final file in dense.files) {
    await verify(relocated(file.path), bytes: file.bytes, hash: file.sha256);
  }
  await verify(markerFile.path, hash: markerHash);
  return Pw38CacheCompletionProof(
    capture,
    documents,
    id,
    '$documents/$published',
    Map.unmodifiable(signatures),
    identityScope,
  );
}
