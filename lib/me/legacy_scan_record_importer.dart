import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../auth/account_workspace.dart';
import '../config/backend_deployment.dart';
import 'work_identity.dart';

/// A build-owned, opaque authorization for one exact legacy index.
class LegacyLibraryImportGrant {
  const LegacyLibraryImportGrant({
    required this.namespace,
    required this.indexSha256,
  });

  final String namespace;
  final String indexSha256;

  static LegacyLibraryImportGrant? fromEnvironment() {
    const namespace = String.fromEnvironment('PW_LEGACY_OWNER_NAMESPACE');
    const digest = String.fromEnvironment('PW_LEGACY_INDEX_SHA256');
    if (namespace.isEmpty && digest.isEmpty) return null;
    if (!_isHash(namespace) || !_isHash(digest)) {
      throw const LegacyScanRecordImportException(
        'Invalid legacy import grant',
      );
    }
    return const LegacyLibraryImportGrant(
      namespace: namespace,
      indexSha256: digest,
    );
  }
}

/// Messages never include record names, account identities, or local paths.
class LegacyScanRecordImportException implements Exception {
  const LegacyScanRecordImportException(this.message);
  final String message;
  @override
  String toString() => 'LegacyScanRecordImportException: $message';
}

class LegacyScanRecordImporter {
  LegacyScanRecordImporter._();
  static Future<void> _tail = Future<void>.value();

  /// Call before loading the scoped store. The caller must keep [isActive]
  /// tied to the originating account throughout this operation.
  static Future<bool> importAuthorized({
    required Directory documentsDirectory,
    required AccountWorkspace account,
    required LegacyLibraryImportGrant? grant,
    required bool Function() isActive,
    FutureOr<void> Function(String phase)? checkpointForTesting,
  }) async {
    if (grant == null ||
        account.deployment.region != BackendRegion.international ||
        account.namespace != grant.namespace) {
      return false;
    }
    if (!_isHash(grant.namespace) || !_isHash(grant.indexSha256)) {
      throw const LegacyScanRecordImportException(
        'Invalid legacy import grant',
      );
    }
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      return await _Import(
        documentsDirectory,
        account,
        grant,
        isActive,
        checkpointForTesting,
      ).run();
    } on LegacyScanRecordImportException {
      rethrow;
    } catch (_) {
      throw const LegacyScanRecordImportException(
        'Legacy import could not complete',
      );
    } finally {
      done.complete();
    }
  }
}

bool _isHash(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
String _digest(List<int> bytes) => sha256.convert(bytes).toString();
String _deletionHash(String pipeline, String id) =>
    _digest(utf8.encode('pocketworld.project-deletion.v1:$pipeline:$id'));

class _Import {
  _Import(
    Directory documents,
    this.account,
    this.grant,
    this.active,
    this.checkpoint,
  ) : docs = documents.absolute.path.replaceFirst(RegExp(r'/+$'), '');

  final String docs;
  final AccountWorkspace account;
  final LegacyLibraryImportGrant grant;
  final bool Function() active;
  final FutureOr<void> Function(String phase)? checkpoint;
  late final root = '$docs/accounts/v1/${account.namespace}';
  late final staging = '$root/.legacy_import_v1';
  late final receiptPath = '$root/legacy_import_receipt_v1.json';
  late final journalPath = '$staging/journal.json';
  late final indexPath = '$root/scan_records.json';
  late final tombstonePath = '$root/scan_record_deletion_tombstones.json';
  late final sourceIndex = '$docs/scan_records.json';
  late final sourceTombstones = '$docs/scan_record_deletion_tombstones.json';
  late final importKey = _digest(
    utf8.encode(
      jsonEncode([
        'pocketworld.legacy-import.v1',
        grant.namespace,
        grant.indexSha256,
      ]),
    ),
  );

  static const _maxJsonBytes = 16 * 1024 * 1024;
  static const _maxEntries = 200000;
  static const _maxTotalBytes = 128 * 1024 * 1024 * 1024;
  var _entries = 0;
  var _totalBytes = 0;

  Never fail([String message = 'Legacy storage failed safety validation']) =>
      throw LegacyScanRecordImportException(message);
  void check() {
    if (!active()) fail('Legacy import account was revoked');
  }

  /// Check every existing component below Documents without following links.
  void guard(String path) {
    check();
    if (!path.startsWith('/') ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        path.split('/').any((part) => part == '.' || part == '..') ||
        !(path == docs || path.startsWith('$docs/'))) {
      fail();
    }
    var cursor = docs;
    final segments = path
        .substring(docs.length)
        .split('/')
        .where((s) => s.isNotEmpty);
    final components = <String>[docs];
    for (final segment in segments) {
      cursor = '$cursor/$segment';
      components.add(cursor);
    }
    for (var i = 0; i < components.length; i++) {
      final type = FileSystemEntity.typeSync(components[i], followLinks: false);
      if (type == FileSystemEntityType.link ||
          (i < components.length - 1 &&
              type != FileSystemEntityType.directory &&
              type != FileSystemEntityType.notFound)) {
        fail();
      }
    }
  }

  Future<T> io<T>(List<String> paths, Future<T> Function() operation) async {
    for (final path in paths) {
      guard(path);
    }
    final result = await operation();
    for (final path in paths) {
      guard(path);
    }
    return result;
  }

  Future<void> phase(String name) async {
    check();
    if (checkpoint != null) await checkpoint!(name);
    check();
  }

  Future<FileSystemEntityType> type(String path) =>
      io([path], () => FileSystemEntity.type(path, followLinks: false));
  Future<void> mkdir(String path) async {
    final kind = await type(path);
    if (kind == FileSystemEntityType.directory) return;
    if (kind != FileSystemEntityType.notFound) fail();
    await io([path], () => Directory(path).create(recursive: true));
  }

  Future<FileStat> regularStat(String path) async {
    if (await type(path) != FileSystemEntityType.file) fail();
    final stat = await io([path], () => File(path).stat());
    if (stat.type != FileSystemEntityType.file ||
        (stat.mode & 0xf000) != 0x8000 ||
        stat.size < 0 ||
        stat.size > _maxTotalBytes) {
      fail();
    }
    return stat;
  }

  Future<List<int>?> readOptional(String path) async {
    final kind = await type(path);
    if (kind == FileSystemEntityType.notFound) return null;
    final stat = await regularStat(path);
    if (stat.size > _maxJsonBytes) fail();
    return io([path], () async {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in File(path).openRead()) {
        check();
        if (bytes.length + chunk.length > _maxJsonBytes) fail();
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    });
  }

  Future<String> fileHash(String path) async {
    final before = await regularStat(path);
    final result = await io([path], () async {
      var length = 0;
      final stream = File(path).openRead().map((chunk) {
        check();
        length += chunk.length;
        if (length > _maxTotalBytes) fail();
        return chunk;
      });
      final digest = await sha256.bind(stream).single;
      if (length != before.size) fail('Legacy source changed during import');
      return digest.toString();
    });
    final after = await regularStat(path);
    if (before.size != after.size || before.modified != after.modified) {
      fail('Legacy source changed during import');
    }
    return result;
  }

  Future<void> atomicWrite(String path, List<int> bytes, String slot) async {
    final temporary = '$staging/$slot.pending';
    await mkdir(staging);
    final kind = await type(temporary);
    if (kind != FileSystemEntityType.notFound &&
        kind != FileSystemEntityType.file) {
      fail();
    }
    if (kind == FileSystemEntityType.file) await regularStat(temporary);
    await io([
      temporary,
    ], () => File(temporary).writeAsBytes(bytes, flush: true));
    await phase('beforeAtomicRename:$slot');
    guard(temporary);
    guard(path);
    // The metadata commit cannot yield between the final owner check and the
    // rename. A queued logout/revocation cannot commit an index afterwards.
    File(temporary).renameSync(path);
    guard(path);
  }

  Future<bool> run() async {
    guard(docs);
    if (await type(docs) != FileSystemEntityType.directory) fail();
    final receipt = await readOptional(receiptPath);
    if (receipt != null) {
      validateReceipt(receipt);
      return true; // A terminal receipt wins before ANY legacy read.
    }
    final journalBytes = await readOptional(journalPath);
    late Map<String, dynamic> plan;
    if (journalBytes == null) {
      plan = await prepare();
      await phase('afterInventory');
      await verifySource(plan);
      await mkdir(staging);
      await atomicWrite(journalPath, utf8.encode(jsonEncode(plan)), 'journal');
      await phase('afterJournal');
    } else {
      plan = decodeMap(journalBytes);
      validatePlan(plan);
    }
    // The index rename is the commit point. If a process stopped immediately
    // afterwards, finish only the receipt; never copy or restore files again.
    final currentIndex = await readOptional(indexPath);
    final currentHash = currentIndex == null ? null : _digest(currentIndex);
    if (plan['state'] == 'publishing' &&
        currentHash == plan['finalIndexHash']) {
      await complete();
      return true;
    }
    if (currentHash != plan['originalIndexHash']) {
      fail('Account library changed during import');
    }
    await verifySource(plan);
    await verifyTombstones(plan);
    if (journalBytes != null) {
      // A journal is recovery evidence, never a new authorization. Rebuild
      // the payload from the pinned index and the current unchanged account
      // baseline before trusting its paths or final index contents.
      final rebuilt = await prepare(resuming: true);
      for (final key in const [
        'sourceIndexHash',
        'sourceTombstoneHash',
        'finalIndexHash',
        'finalIndex',
        'finalTombstones',
        'inventory',
        'inventoryHash',
        'units',
        'probes',
      ]) {
        if (jsonEncode(rebuilt[key]) != jsonEncode(plan[key])) {
          fail('Legacy recovery journal failed validation');
        }
      }
    }
    await stage(plan);
    await phase('afterStage');
    await verifySource(plan);
    await verifyTombstones(plan);
    await publishFiles(plan);
    await phase('afterFilesPublish');
    await verifySource(plan);
    await verifyTombstones(plan);
    final finalTombstones = base64Decode(plan['finalTombstones'] as String);
    final currentTombstones = await readOptional(tombstonePath);
    if (currentTombstones == null ||
        _digest(currentTombstones) != _digest(finalTombstones)) {
      await atomicWrite(tombstonePath, finalTombstones, 'tombstones');
    }
    await phase('beforeIndexPublish');
    await verifySource(plan);
    await verifyTombstones(plan);
    final latest = await readOptional(indexPath);
    if ((latest == null ? null : _digest(latest)) !=
        plan['originalIndexHash']) {
      fail('Account library changed during import');
    }
    plan['state'] = 'publishing';
    await atomicWrite(journalPath, utf8.encode(jsonEncode(plan)), 'journal');
    final finalIndex = base64Decode(plan['finalIndex'] as String);
    await atomicWrite(indexPath, finalIndex, 'index');
    await phase('afterIndexPublish');
    await complete();
    return true;
  }

  void validateReceipt(List<int> bytes) {
    final value = decodeMap(bytes);
    if (value.length != 2 ||
        value['schema'] != 'pocketworld.legacy-import.receipt.v1' ||
        value['importKey'] != importKey) {
      fail('Legacy import receipt does not match grant');
    }
  }

  Future<void> complete() async {
    await atomicWrite(
      receiptPath,
      utf8.encode(
        jsonEncode({
          'schema': 'pocketworld.legacy-import.receipt.v1',
          'importKey': importKey,
        }),
      ),
      'receipt',
    );
  }

  Map<String, dynamic> decodeMap(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) fail();
    return value;
  }

  List<Map<String, dynamic>> decodeRecords(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! List || value.length > 10000) fail();
    final records = <Map<String, dynamic>>[];
    final keys = <String>{};
    for (final entry in value) {
      if (entry is! Map<String, dynamic>) fail();
      validateRecord(entry);
      if (!keys.add(recordKey(entry))) fail();
      records.add(entry);
    }
    return records;
  }

  String recordKey(Map<String, dynamic> record) => record['id'] as String;
  void validateRecord(Map<String, dynamic> value) {
    final id = value['id'];
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(id) ||
        value['name'] is! String ||
        (value['name'] as String).length > 10000 ||
        value['createdAt'] is! String ||
        DateTime.tryParse(value['createdAt'] as String) == null ||
        (value.containsKey('pipeline_kind') &&
            value['pipeline_kind'] != 'self' &&
            value['pipeline_kind'] != 'official')) {
      fail();
    }
    const strings = {
      'accountNamespace',
      'resultViewedAt',
      'thumbnailPath',
      'artifactPath',
      'captureDir',
      'photosDir',
      'captureManifestPath',
      'preferredCaptureMode',
      'cloudUploadStatus',
      'cloudScanId',
      'cloudManifestPath',
      'cloudWorkId',
      'cloudLibraryRevision',
      'cloudArtifactPath',
      'uploadedAt',
      'localRawDeletedAt',
      'cloudRawDeletedAt',
      'cloudUploadFailureMessage',
      'caption',
    };
    const integers = {'photoCount', 'uploadedFrameCount'};
    const booleans = {'localRawRetainedForDebug', 'cloudViewingOnly'};
    // These retired schema fields are deliberately not carried into the scoped
    // local store. Path-valued retired fields still have to pass path validation.
    const retired = {
      'jobStatus',
      'jobId',
      'pipelineStage',
      'publishedWorkId',
      'videoSizeBytes',
      'failureMessage',
      'videoFilePath',
      'curatedManifestPath',
    };
    for (final entry in value.entries) {
      if (const {
        'id',
        'name',
        'createdAt',
        'pipeline_kind',
      }.contains(entry.key)) {
        continue;
      }
      if (strings.contains(entry.key)) {
        if (entry.value != null &&
            (entry.value is! String ||
                (entry.value as String).length > 32768)) {
          fail();
        }
      } else if (integers.contains(entry.key)) {
        if (entry.value != null &&
            (entry.value is! int || (entry.value as int) < 0)) {
          fail();
        }
      } else if (booleans.contains(entry.key)) {
        if (entry.value != null && entry.value is! bool) fail();
      } else if (!retired.contains(entry.key)) {
        fail();
      } else if (entry.value != null &&
          entry.value is! String &&
          entry.value is! num) {
        fail();
      }
    }
    if (value['preferredCaptureMode'] != null &&
        !const {
          'local',
          'newRemote',
          'remoteLegacy',
        }.contains(value['preferredCaptureMode'])) {
      fail();
    }
    for (final key in const [
      'resultViewedAt',
      'uploadedAt',
      'localRawDeletedAt',
      'cloudRawDeletedAt',
    ]) {
      if (value[key] != null &&
          DateTime.tryParse(value[key] as String) == null) {
        fail();
      }
    }
  }

  Set<String> decodeTombstones(List<int>? bytes) {
    if (bytes == null) return {};
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! List || value.length > 100000 || !value.every(_isHash)) {
      fail();
    }
    return value.cast<String>().toSet();
  }

  /// Only known unscoped route roots below Documents can be reanchored after
  /// an iOS container UUID change. Account directories are never reinterpreted.
  String anchor(String raw, String route, String id) {
    String path = raw;
    if (raw.startsWith('file://')) {
      final uri = Uri.parse(raw);
      if (uri.scheme != 'file' ||
          uri.host.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        fail();
      }
      path = uri.toFilePath();
    }
    if (!path.startsWith('/') ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        path.split('/').any((part) => part == '.' || part == '..') ||
        path.contains('/accounts/') ||
        path.contains('//')) {
      fail();
    }
    final prefix = '$docs/';
    late String relative;
    if (path.startsWith(prefix)) {
      relative = path.substring(prefix.length);
    } else {
      final marker = '/Documents/';
      final offset = path.indexOf(marker);
      if (offset < 0 || path.indexOf(marker, offset + 1) >= 0) fail();
      relative = path.substring(offset + marker.length);
    }
    if (!relative.startsWith('$route/$id') ||
        (relative != '$route/$id' &&
            !relative.startsWith('$route/$id/') &&
            relative != '$route/$id.jpg' &&
            relative != '$route/$id.glb')) {
      fail();
    }
    guard('$docs/$relative');
    return relative;
  }

  Future<Map<String, dynamic>> prepare({bool resuming = false}) async {
    _entries = 0;
    _totalBytes = 0;
    final sourceBytes = await readOptional(sourceIndex);
    if (sourceBytes == null || _digest(sourceBytes) != grant.indexSha256) {
      fail('Legacy index does not match approved hash');
    }
    final legacy = decodeRecords(sourceBytes);
    final originalIndex = await readOptional(indexPath);
    final existing = originalIndex == null
        ? <Map<String, dynamic>>[]
        : decodeRecords(originalIndex);
    for (final record in existing) {
      if (record['accountNamespace'] != account.namespace) fail();
      for (final key in const [
        'thumbnailPath',
        'artifactPath',
        'captureDir',
        'photosDir',
        'captureManifestPath',
        'cloudManifestPath',
        'cloudArtifactPath',
      ]) {
        final raw = record[key] as String?;
        if (raw == null || raw.isEmpty) continue;
        final path = raw.startsWith('file://')
            ? Uri.parse(raw).toFilePath()
            : raw;
        if (!path.startsWith('$root/')) fail();
        guard(path);
      }
    }
    final globalTombstones = await readOptional(sourceTombstones);
    final accountTombstones = await readOptional(tombstonePath);
    final deleted = {
      ...decodeTombstones(globalTombstones),
      ...decodeTombstones(accountTombstones),
    };
    final finalTombstones = utf8.encode(jsonEncode(deleted.toList()..sort()));
    final records = <Map<String, dynamic>>[];
    final inventory = <Map<String, dynamic>>[];
    final units = <String>[];
    final probes = <String, String>{};
    final existingKeys = existing.map(recordKey).toSet();
    final existingNames = existing
        .map((r) => workNameKey(r['name'] as String))
        .toSet();
    if (existingNames.length != existing.length) {
      fail('Account library contains duplicate work names');
    }
    for (final old in legacy) {
      if (old['accountNamespace'] != null) fail();
      final id = old['id'] as String;
      final pipeline = old['pipeline_kind'] as String? ?? 'self';
      final captures = pipeline == 'official'
          ? 'captures_official'
          : 'captures';
      final scans = pipeline == 'official' ? 'scans_official' : 'scans';
      final record = Map<String, dynamic>.of(old)
        ..['pipeline_kind'] = pipeline
        ..['accountNamespace'] = account.namespace;
      for (final key in const [
        'jobStatus',
        'jobId',
        'pipelineStage',
        'publishedWorkId',
        'videoSizeBytes',
        'failureMessage',
      ]) {
        record.remove(key);
      }
      for (final key in const ['videoFilePath', 'curatedManifestPath']) {
        final value = record.remove(key);
        if (value != null && value != '') anchor(value as String, captures, id);
      }
      for (final key in const [
        'captureDir',
        'photosDir',
        'captureManifestPath',
        'cloudManifestPath',
      ]) {
        final raw = record[key] as String?;
        if (raw == null || raw.isEmpty) {
          record.remove(key);
          continue;
        }
        final relative = anchor(raw, captures, id);
        if (key == 'captureDir' && relative != '$captures/$id') fail();
        if (key == 'photosDir' &&
            relative != '$captures/$id/photos' &&
            relative != '$captures/$id/photos_highres') {
          fail();
        }
        if (key != 'captureDir' &&
            key != 'photosDir' &&
            !relative.startsWith('$captures/$id/')) {
          fail();
        }
        record[key] = '$root/$relative';
      }
      for (final key in const [
        'thumbnailPath',
        'artifactPath',
        'cloudArtifactPath',
      ]) {
        final raw = record[key] as String?;
        if (raw == null || raw.isEmpty) {
          record.remove(key);
          continue;
        }
        final relative = anchor(raw, scans, id);
        final expected = '$scans/$id.${key == 'thumbnailPath' ? 'jpg' : 'glb'}';
        if (relative != expected) fail();
        record[key] = key == 'thumbnailPath'
            ? '$root/$relative'
            : 'file://$root/$relative';
      }
      if (deleted.contains(_deletionHash(pipeline, id))) continue;
      for (final relative in [
        '$captures/$id',
        '$scans/$id.jpg',
        '$scans/$id.glb',
      ]) {
        final kind = await type('$docs/$relative');
        probes[relative] = kind == FileSystemEntityType.notFound
            ? 'absent'
            : kind == FileSystemEntityType.directory
            ? 'directory'
            : kind == FileSystemEntityType.file
            ? 'file'
            : fail();
        if (!resuming &&
            await type('$root/$relative') != FileSystemEntityType.notFound) {
          fail('Legacy import conflicts with existing account files');
        }
      }
      if (existingKeys.contains(recordKey(record))) {
        fail('Legacy import conflicts with an existing project');
      }
      if (!existingNames.add(workNameKey(record['name'] as String))) {
        fail('Legacy import conflicts with an existing work name');
      }
      final captureRelative = '$captures/$id';
      final captureType = await type('$docs/$captureRelative');
      if (captureType != FileSystemEntityType.notFound) {
        if (captureType != FileSystemEntityType.directory) fail();
        units.add(captureRelative);
        inventory.addAll(await inventoryTree(docs, captureRelative));
        record['captureDir'] = '$root/$captureRelative';
        final highres = await type('$docs/$captureRelative/photos_highres');
        final standard = await type('$docs/$captureRelative/photos');
        if ((highres != FileSystemEntityType.notFound &&
                highres != FileSystemEntityType.directory) ||
            (standard != FileSystemEntityType.notFound &&
                standard != FileSystemEntityType.directory)) {
          fail();
        }
        if (highres == FileSystemEntityType.directory ||
            standard == FileSystemEntityType.directory) {
          record['photosDir'] =
              '$root/$captureRelative/${highres == FileSystemEntityType.directory ? 'photos_highres' : 'photos'}';
        } else if (record.containsKey('photosDir')) {
          fail();
        }
        if (!record.containsKey('captureManifestPath')) {
          for (final name
              in pipeline == 'official'
                  ? const [
                      'official_photo_bundle.json',
                      'official_capture_manifest.json',
                      'capture_manifest.json',
                    ]
                  : const ['photo_bundle.json', 'capture_manifest.json']) {
            if (await type('$docs/$captureRelative/$name') ==
                FileSystemEntityType.file) {
              record['captureManifestPath'] = '$root/$captureRelative/$name';
              break;
            }
          }
        }
      } else if (const [
        'captureDir',
        'photosDir',
        'captureManifestPath',
        'cloudManifestPath',
      ].any(record.containsKey)) {
        fail();
      }
      for (final extension in const ['jpg', 'glb']) {
        final relative = '$scans/$id.$extension';
        final kind = await type('$docs/$relative');
        if (kind == FileSystemEntityType.notFound) continue;
        if (kind != FileSystemEntityType.file) fail();
        units.add(relative);
        inventory.add(await fileEntry(docs, relative));
      }
      for (final key in const [
        'thumbnailPath',
        'artifactPath',
        'cloudArtifactPath',
        'captureManifestPath',
        'cloudManifestPath',
      ]) {
        final raw = record[key] as String?;
        if (raw == null) continue;
        final path = raw.startsWith('file://')
            ? Uri.parse(raw).toFilePath()
            : raw;
        final relative = path.substring(root.length + 1);
        if (!inventory.any(
          (entry) => entry['path'] == relative && entry['type'] == 'file',
        )) {
          fail();
        }
      }
      records.add(record);
    }
    for (final relative in units) {
      if (!resuming &&
          await type('$root/$relative') != FileSystemEntityType.notFound) {
        fail('Legacy import conflicts with existing account files');
      }
    }
    inventory.sort(
      (a, b) => (a['path'] as String).compareTo(b['path'] as String),
    );
    final finalIndex = utf8.encode(jsonEncode([...existing, ...records]));
    return {
      'schema': 'pocketworld.legacy-import.journal.v1',
      'importKey': importKey,
      'state': 'prepared',
      'sourceIndexHash': grant.indexSha256,
      'sourceTombstoneHash': globalTombstones == null
          ? null
          : _digest(globalTombstones),
      'originalTombstoneHash': accountTombstones == null
          ? null
          : _digest(accountTombstones),
      'originalIndexHash': originalIndex == null
          ? null
          : _digest(originalIndex),
      'finalIndexHash': _digest(finalIndex),
      'finalIndex': base64Encode(finalIndex),
      'finalTombstones': base64Encode(finalTombstones),
      'inventory': inventory,
      'inventoryHash': _digest(utf8.encode(jsonEncode(inventory))),
      'units': units,
      'probes': probes,
    };
  }

  String validRelative(Object? value) {
    if (value is! String ||
        value.length > 4096 ||
        value.contains('\\') ||
        value.contains('\u0000') ||
        value
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      fail();
    }
    final parts = value.split('/');
    if (parts.length < 2 ||
        !const {
          'captures',
          'captures_official',
          'scans',
          'scans_official',
        }.contains(parts.first)) {
      fail();
    }
    if (parts.first.startsWith('captures')) {
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(parts[1])) {
        fail();
      }
    } else if (parts.length != 2 ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}\.(jpg|glb)$',
        ).hasMatch(parts[1])) {
      fail();
    }
    guard('$docs/$value');
    guard('$root/$value');
    return value;
  }

  void validatePlan(Map<String, dynamic> plan) {
    if (plan['schema'] != 'pocketworld.legacy-import.journal.v1' ||
        plan['importKey'] != importKey ||
        !const {'prepared', 'publishing'}.contains(plan['state']) ||
        plan['sourceIndexHash'] != grant.indexSha256 ||
        !_isHash(plan['finalIndexHash'])) {
      fail();
    }
    for (final key in const [
      'sourceTombstoneHash',
      'originalTombstoneHash',
      'originalIndexHash',
    ]) {
      if (plan[key] != null && !_isHash(plan[key])) fail();
    }
    final finalIndex = base64Decode(plan['finalIndex'] as String);
    if (finalIndex.length > _maxJsonBytes ||
        _digest(finalIndex) != plan['finalIndexHash']) {
      fail();
    }
    for (final record in decodeRecords(finalIndex)) {
      if (record['accountNamespace'] != account.namespace) fail();
    }
    decodeTombstones(base64Decode(plan['finalTombstones'] as String));
    final inventory = plan['inventory'];
    final units = plan['units'];
    final probes = plan['probes'];
    if (inventory is! List ||
        inventory.length > _maxEntries ||
        units is! List ||
        units.length > 30000 ||
        probes is! Map<String, dynamic> ||
        probes.length > 30000 ||
        _digest(utf8.encode(jsonEncode(inventory))) != plan['inventoryHash']) {
      fail();
    }
    for (final probe in probes.entries) {
      final relative = validRelative(probe.key);
      if (relative.split('/').length != 2 ||
          !const {'absent', 'directory', 'file'}.contains(probe.value)) {
        fail();
      }
    }
    final seen = <String>{};
    for (final entry in inventory) {
      if (entry is! Map<String, dynamic> ||
          !seen.add(validRelative(entry['path'])) ||
          !const {'directory', 'file'}.contains(entry['type'])) {
        fail();
      }
      if (entry['type'] == 'file' &&
          (!_isHash(entry['sha256']) ||
              entry['size'] is! int ||
              (entry['size'] as int) < 0)) {
        fail();
      }
    }
    final seenUnits = <String>{};
    for (final unit in units) {
      final relative = validRelative(unit);
      if (!seenUnits.add(relative) || !seen.contains(relative)) fail();
      if (relative.startsWith('captures') && relative.split('/').length != 2) {
        fail();
      }
    }
    for (final relative in seen) {
      if (!seenUnits.any(
        (unit) => relative == unit || relative.startsWith('$unit/'),
      )) {
        fail();
      }
    }
  }

  Future<Map<String, dynamic>> fileEntry(String base, String relative) async {
    if (++_entries > _maxEntries) {
      fail('Legacy inventory exceeds safety limits');
    }
    final stat = await regularStat('$base/$relative');
    _totalBytes += stat.size;
    if (_totalBytes > _maxTotalBytes) {
      fail('Legacy inventory exceeds safety limits');
    }
    return {
      'path': relative,
      'type': 'file',
      'size': stat.size,
      'sha256': await fileHash('$base/$relative'),
    };
  }

  Future<List<Map<String, dynamic>>> inventoryTree(
    String base,
    String relative, [
    int depth = 0,
  ]) async {
    if (depth > 32 ||
        ++_entries > _maxEntries ||
        await type('$base/$relative') != FileSystemEntityType.directory) {
      fail();
    }
    final out = <Map<String, dynamic>>[
      {'path': relative, 'type': 'directory'},
    ];
    final children = await io(['$base/$relative'], () async {
      final result = <FileSystemEntity>[];
      await for (final child in Directory(
        '$base/$relative',
      ).list(followLinks: false)) {
        check();
        if (result.length + _entries >= _maxEntries) {
          fail('Legacy inventory exceeds safety limits');
        }
        result.add(child);
      }
      return result;
    });
    for (final child in children) {
      final name = child.path.substring(child.parent.path.length + 1);
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains('\\') ||
          name.contains('\u0000')) {
        fail();
      }
      final childRelative = '$relative/$name';
      final kind = await type('$base/$childRelative');
      if (kind == FileSystemEntityType.directory) {
        out.addAll(await inventoryTree(base, childRelative, depth + 1));
      } else if (kind == FileSystemEntityType.file) {
        out.add(await fileEntry(base, childRelative));
      } else {
        fail();
      }
    }
    out.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
    return out;
  }

  List<Map<String, dynamic>> entries(Map<String, dynamic> plan) =>
      (plan['inventory'] as List).cast<Map<String, dynamic>>();
  List<String> units(Map<String, dynamic> plan) =>
      (plan['units'] as List).cast<String>();
  Future<List<Map<String, dynamic>>> inventoryUnits(
    String base,
    List<String> selected,
  ) async {
    _entries = 0;
    _totalBytes = 0;
    final out = <Map<String, dynamic>>[];
    for (final unit in selected) {
      if (unit.startsWith('captures')) {
        out.addAll(await inventoryTree(base, unit));
      } else {
        out.add(await fileEntry(base, unit));
      }
    }
    out.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
    return out;
  }

  Future<void> verifySource(Map<String, dynamic> plan) async {
    final bytes = await readOptional(sourceIndex);
    if (bytes == null || _digest(bytes) != grant.indexSha256) {
      fail('Legacy source changed during import');
    }
    final tombstones = await readOptional(sourceTombstones);
    if ((tombstones == null ? null : _digest(tombstones)) !=
        plan['sourceTombstoneHash']) {
      fail('Legacy source changed during import');
    }
    for (final probe in (plan['probes'] as Map<String, dynamic>).entries) {
      final kind = await type('$docs/${validRelative(probe.key)}');
      final found = kind == FileSystemEntityType.notFound
          ? 'absent'
          : kind == FileSystemEntityType.directory
          ? 'directory'
          : kind == FileSystemEntityType.file
          ? 'file'
          : fail();
      if (found != probe.value) fail('Legacy source changed during import');
    }
    final found = await inventoryUnits(docs, units(plan));
    if (jsonEncode(found) != jsonEncode(plan['inventory'])) {
      fail('Legacy source changed during import');
    }
  }

  Future<void> verifyTombstones(Map<String, dynamic> plan) async {
    final bytes = await readOptional(tombstonePath);
    final hash = bytes == null ? null : _digest(bytes);
    if (hash != plan['originalTombstoneHash'] &&
        hash != _digest(base64Decode(plan['finalTombstones'] as String))) {
      fail('Account deletion state changed during import');
    }
  }

  Future<void> stage(Map<String, dynamic> plan) async {
    final base = '$staging/files';
    await mkdir(base);
    final remaining = <String>[];
    for (final unit in units(plan)) {
      if (await type('$root/$unit') == FileSystemEntityType.notFound) {
        remaining.add(unit);
        continue;
      }
      final expected = entries(plan)
          .where(
            (entry) =>
                entry['path'] == unit ||
                (entry['path'] as String).startsWith('$unit/'),
          )
          .toList();
      final found = await inventoryUnits(root, [unit]);
      if (jsonEncode(found) != jsonEncode(expected)) {
        fail('Imported account files were modified');
      }
    }
    final pendingEntries = entries(plan)
        .where(
          (entry) => remaining.any(
            (unit) =>
                entry['path'] == unit ||
                (entry['path'] as String).startsWith('$unit/'),
          ),
        )
        .toList();
    for (final entry in pendingEntries) {
      final relative = validRelative(entry['path']);
      final target = '$base/$relative';
      if (entry['type'] == 'directory') {
        await mkdir(target);
        continue;
      }
      await mkdir(File(target).parent.path);
      final kind = await type(target);
      if (kind != FileSystemEntityType.notFound &&
          kind != FileSystemEntityType.file) {
        fail();
      }
      if (kind == FileSystemEntityType.file &&
          await fileHash(target) == entry['sha256']) {
        continue;
      }
      await io([
        '$docs/$relative',
        target,
      ], () => File('$docs/$relative').copy(target));
      if (await fileHash(target) != entry['sha256']) {
        fail('Legacy source changed during import');
      }
      await phase('afterFileCopy');
    }
    final found = await inventoryUnits(base, remaining);
    if (jsonEncode(found) != jsonEncode(pendingEntries)) {
      fail('Legacy staged copy failed verification');
    }
  }

  Future<void> publishFiles(Map<String, dynamic> plan) async {
    for (final unit in units(plan)) {
      final target = '$root/$unit';
      final staged = '$staging/files/$unit';
      final expected = entries(plan)
          .where(
            (entry) =>
                entry['path'] == unit ||
                (entry['path'] as String).startsWith('$unit/'),
          )
          .toList();
      if (await type(target) == FileSystemEntityType.notFound) {
        await mkdir(File(target).parent.path);
        // No awaited operation separates this final conflict check and rename.
        guard(target);
        guard(staged);
        if (FileSystemEntity.typeSync(target, followLinks: false) !=
            FileSystemEntityType.notFound) {
          fail();
        }
        if (unit.startsWith('captures')) {
          await io([staged, target], () => Directory(staged).rename(target));
        } else {
          await io([staged, target], () => File(staged).rename(target));
        }
      }
      final found = await inventoryUnits(root, [unit]);
      if (jsonEncode(found) != jsonEncode(expected)) {
        fail('Imported account files were modified');
      }
      await phase('afterUnitPublish');
    }
  }
}
