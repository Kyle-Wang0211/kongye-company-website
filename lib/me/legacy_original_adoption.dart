import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../auth/account_workspace.dart';
import 'legacy_scan_record_importer.dart' show LegacyScanRecordImportException;

/// A private build may authorize one exact recovery manifest for one account.
/// No IDs, account identity or source hashes are a public/global default.
class LegacyOriginalAdoptionGrant {
  LegacyOriginalAdoptionGrant({
    required this.namespace,
    required this.manifestSha256,
    required List<int> manifestBytes,
  }) : manifestBytes = List<int>.unmodifiable(manifestBytes);

  final String namespace, manifestSha256;
  final List<int> manifestBytes;

  static LegacyOriginalAdoptionGrant? fromEnvironment() {
    const namespace = String.fromEnvironment(
      'PW_LEGACY_ORIGINAL_ADOPTION_NAMESPACE',
    );
    const digest = String.fromEnvironment(
      'PW_LEGACY_ORIGINAL_ADOPTION_MANIFEST_SHA256',
    );
    const encoded = String.fromEnvironment(
      'PW_LEGACY_ORIGINAL_ADOPTION_MANIFEST_BASE64',
    );
    if (namespace.isEmpty && digest.isEmpty && encoded.isEmpty) return null;
    if (!_hash(namespace) ||
        !_hash(digest) ||
        encoded.length > 2 * 1024 * 1024) {
      throw const LegacyScanRecordImportException(
        'Invalid original recovery grant',
      );
    }
    try {
      return LegacyOriginalAdoptionGrant(
        namespace: namespace,
        manifestSha256: digest,
        manifestBytes: base64Decode(encoded),
      );
    } catch (_) {
      throw const LegacyScanRecordImportException(
        'Invalid original recovery manifest',
      );
    }
  }
}

bool _hash(Object? s) => s is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(s);
String _digest(List<int> bytes) => sha256.convert(bytes).toString();

/// Restore explicitly authorized originals beside an existing viewing cache.
/// The account index rename is the sole commit point; source/cache never change.
class LegacyOriginalAdoption {
  static Future<void> _tail = Future<void>.value();

  static Future<bool> adoptAuthorized({
    required Directory documentsDirectory,
    required AccountWorkspace account,
    required LegacyOriginalAdoptionGrant? grant,
    required bool Function() isActive,
    FutureOr<void> Function(String phase)? checkpointForTesting,
  }) async {
    if (grant == null || account.namespace != grant.namespace) return false;
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      return await _Adoption(
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
        'Original recovery needs retry; originals retained',
      );
    } finally {
      done.complete();
    }
  }
}

class _Adoption {
  _Adoption(
    Directory docs,
    this.account,
    this.grant,
    this.active,
    this.checkpoint,
  ) : base = docs.absolute.path.replaceFirst(RegExp(r'/+$'), '');
  final String base;
  final AccountWorkspace account;
  final LegacyOriginalAdoptionGrant grant;
  final bool Function() active;
  final FutureOr<void> Function(String)? checkpoint;
  late final root = '$base/accounts/v1/${account.namespace}';
  late final stage =
      '$root/.legacy_original_adoption_v1/${grant.manifestSha256}';
  late final index = '$root/scan_records.json';
  late final receipt = '$stage/COMPLETE.json';
  late final journal = '$stage/JOURNAL.json';
  static const jsonLimit = 1024 * 1024;
  static const fileLimit = 512 * 1024 * 1024;
  static const totalLimit = 16 * 1024 * 1024 * 1024;

  Never fail([
    String message = 'Original recovery identity validation failed',
  ]) => throw LegacyScanRecordImportException(message);
  void check() {
    if (!active()) fail('Original recovery account was revoked');
  }

  void guard(String path) {
    check();
    if (!(path == base || path.startsWith('$base/')) ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        path.split('/').any((s) => s == '.' || s == '..')) {
      fail();
    }
    var current = base;
    final parts = [
      base,
      ...path.substring(base.length).split('/').where((s) => s.isNotEmpty),
    ];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) current += '/${parts[i]}';
      final t = FileSystemEntity.typeSync(current, followLinks: false);
      if (t == FileSystemEntityType.link ||
          (i < parts.length - 1 &&
              t != FileSystemEntityType.directory &&
              t != FileSystemEntityType.notFound)) {
        fail();
      }
    }
  }

  Future<T> io<T>(String path, Future<T> Function() f) async {
    guard(path);
    final result = await f();
    guard(path);
    return result;
  }

  Future<void> phase(String name) async {
    check();
    if (checkpoint != null) await checkpoint!(name);
    check();
  }

  Future<void> mkdir(String path) async {
    guard(path);
    final t = FileSystemEntity.typeSync(path, followLinks: false);
    if (t == FileSystemEntityType.directory) return;
    if (t != FileSystemEntityType.notFound) fail();
    await io(path, () => Directory(path).create(recursive: true));
  }

  Future<List<int>?> read(String path) async {
    guard(path);
    final t = FileSystemEntity.typeSync(path, followLinks: false);
    if (t == FileSystemEntityType.notFound) return null;
    if (t != FileSystemEntityType.file) fail();
    final size = File(path).lengthSync();
    if (size > jsonLimit) fail();
    final bytes = await io(path, () => File(path).readAsBytes());
    if (bytes.length != size || bytes.length > jsonLimit) fail();
    return bytes;
  }

  Map<String, dynamic> map(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) fail();
    return value;
  }

  String rel(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 1024 ||
        value.startsWith('/') ||
        value.contains('\\') ||
        value.contains('\u0000') ||
        value.split('/').any((s) => s.isEmpty || s == '.' || s == '..') ||
        value.split('/').first == 'cloud_cache') {
      fail();
    }
    return value;
  }

  Future<bool> matches(String path, Map<String, dynamic> row) async {
    guard(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    final before = File(path).statSync();
    if (before.size != row['bytes']) return false;
    var length = 0;
    final stream = File(path).openRead().map((chunk) {
      check();
      length += chunk.length;
      if (length > fileLimit) fail();
      return chunk;
    });
    final digest = await sha256.bind(stream).single;
    guard(path);
    final after = File(path).statSync();
    return before.size == after.size &&
        before.modified == after.modified &&
        length == row['bytes'] &&
        digest.toString() == row['sha256'];
  }

  Future<void> writeJson(String path, Object value) async {
    final bytes = utf8.encode(jsonEncode(value));
    if (bytes.length > jsonLimit) fail();
    await mkdir(File(path).parent.path);
    final tmp = '$path.pending';
    guard(tmp);
    // Only this manifest's journal owns these generated staging files.
    if (FileSystemEntity.typeSync(tmp, followLinks: false) !=
            FileSystemEntityType.notFound &&
        FileSystemEntity.typeSync(tmp, followLinks: false) !=
            FileSystemEntityType.file) {
      fail();
    }
    await io(tmp, () => File(tmp).writeAsBytes(bytes, flush: true));
    guard(tmp);
    guard(path);
    File(tmp).renameSync(path);
    check();
  }

  List<Map<String, dynamic>> works(Map<String, dynamic> manifest) {
    if (manifest['schema'] != 'pw_legacy_original_adoption/1' ||
        manifest['namespace'] != account.namespace ||
        !_hash(manifest['legacy_index_sha256']) ||
        manifest['works'] is! List ||
        (manifest['works'] as List).length != 3) {
      fail();
    }
    final result = (manifest['works'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    final ids = <String>{};
    var total = 0;
    for (final w in result) {
      final id = w['id'];
      if (id is! String ||
          !RegExp(r'^cap_[0-9]{1,25}$').hasMatch(id) ||
          !ids.add(id) ||
          !_hash(w['cloud_revision']) ||
          w['photo_count'] is! int ||
          w['photo_count'] <= 0 ||
          w['photo_count'] > 10000 ||
          w['photo_directory'] != 'photos_highres' ||
          w['capture_manifest'] != 'official_photo_bundle.json' ||
          w['files'] is! List ||
          (w['files'] as List).length > 10000 ||
          w['directories'] is! List) {
        fail();
      }
      final names = <String>{};
      for (final raw in w['files'] as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final path = rel(row['path']);
        if (!names.add(path) ||
            !_hash(row['sha256']) ||
            row['bytes'] is! int ||
            row['bytes'] < 0 ||
            row['bytes'] > fileLimit) {
          fail();
        }
        total += row['bytes'] as int;
        if (total > totalLimit) fail();
      }
      if (!names.containsAll({
        'official_sfm_sparse.ply',
        'official_sfm_sparse_meta.json',
        'official_sfm_fed_frames.jsonl',
        'official_photo_bundle.json',
        'official_sfm_live.db',
      })) {
        fail();
      }
      final dirs = <String>{};
      for (final d in w['directories'] as List) {
        if (!dirs.add(rel(d))) fail();
      }
      if (!dirs.contains('photos_highres')) fail();
    }
    return result;
  }

  List<Map<String, dynamic>> records(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List || decoded.length > 10000) fail();
    final rows = decoded
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    final ids = <String>{};
    for (final r in rows) {
      if (r['id'] is! String ||
          !ids.add(r['id'] as String) ||
          r['accountNamespace'] != account.namespace) {
        fail();
      }
    }
    return rows;
  }

  Future<void> verifyInputs(Map<String, dynamic> w) async {
    final source = '$base/captures_official/${w['id']}';
    final rows = {
      for (final r in w['files'] as List)
        r['path'] as String: Map<String, dynamic>.from(r as Map),
    };
    // Existing dense evidence may never be dropped to make a work editable.
    for (final name in [
      'official_dense.ply',
      'dense_started.json',
      'dense_work',
      'pw38_full_runs_v1',
      'pw38_cache_complete.json',
    ]) {
      guard('$source/$name');
      final t = FileSystemEntity.typeSync('$source/$name', followLinks: false);
      if (t == FileSystemEntityType.file && !rows.containsKey(name)) fail();
      if (t == FileSystemEntityType.directory &&
          !(w['directories'] as List).contains(name)) {
        fail();
      }
    }
    for (final row in rows.values) {
      if (!await matches('$source/${row['path']}', row)) {
        fail('Original input bytes changed; recovery stopped');
      }
    }
    final metadata = map(
      (await read('$source/official_sfm_sparse_meta.json'))!,
    );
    final fed = <num, String>{};
    for (final line
        in utf8
            .decode((await read('$source/official_sfm_fed_frames.jsonl'))!)
            .split('\n')) {
      if (line.trim().isEmpty) continue;
      final r = jsonDecode(line) as Map;
      if (r['frameId'] is! num || r['jpegPath'] is! String) fail();
      final name = (r['jpegPath'] as String).split('/').last;
      fed[r['frameId'] as num] = name;
    }
    final registered = (metadata['poses'] as List)
        .where((p) => p['registered'] == true)
        .toList();
    if (metadata['refined'] != true || registered.length != w['photo_count']) {
      fail();
    }
    final seen = <num>{};
    for (final p in registered) {
      final id = p['frame_id'];
      if (id is! num || !id.isFinite || !seen.add(id)) fail();
      final name = fed[id];
      if (name == null ||
          !name.endsWith('.jpg') ||
          !rows.containsKey('photos_highres/$name') ||
          !rows.containsKey(
            'photos_highres/${name.substring(0, name.length - 4)}.json',
          )) {
        fail();
      }
    }
  }

  Future<void> verifyTarget(Map<String, dynamic> w) async {
    final target = '$root/captures_official/${w['id']}';
    guard(target);
    if (FileSystemEntity.typeSync(target, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    if (FileSystemEntity.typeSync(target, followLinks: false) !=
        FileSystemEntityType.directory) {
      fail();
    }
    final rows = {
      for (final r in w['files'] as List)
        r['path'] as String: Map<String, dynamic>.from(r as Map),
    };
    await for (final f in Directory(
      target,
    ).list(recursive: true, followLinks: false)) {
      guard(f.path);
      final name = f.path.substring(target.length + 1);
      // This subtree belongs to the cloud viewing cache and is never touched.
      if (name == 'cloud_cache' || name.startsWith('cloud_cache/')) continue;
      final t = FileSystemEntity.typeSync(f.path, followLinks: false);
      if (t == FileSystemEntityType.directory) {
        if (!(w['directories'] as List).contains(name)) {
          fail('Conflicting local original retained');
        }
      } else if (t != FileSystemEntityType.file ||
          !rows.containsKey(name) ||
          !await matches(f.path, rows[name]!)) {
        fail('Conflicting local original retained');
      }
    }
  }

  Future<void> copyInputs(Map<String, dynamic> w) async {
    final id = w['id'];
    final source = '$base/captures_official/$id';
    final staged = '$stage/files/$id';
    final target = '$root/captures_official/$id';
    await mkdir(staged);
    await mkdir(target);
    for (final d in w['directories'] as List) {
      await mkdir('$target/$d');
    }
    for (final raw in w['files'] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final name = row['path'];
      final destination = '$target/$name';
      guard(destination);
      if (FileSystemEntity.typeSync(destination, followLinks: false) ==
          FileSystemEntityType.file) {
        if (!await matches(destination, row)) fail();
        continue;
      }
      final tmp = '$staged/$name';
      await mkdir(File(tmp).parent.path);
      if (!await matches(tmp, row)) {
        guard(tmp);
        guard('$source/$name');
        final sink = File(tmp).openWrite();
        try {
          await sink.addStream(
            File('$source/$name').openRead().map((chunk) {
              check();
              return chunk;
            }),
          );
          await sink.flush();
        } finally {
          await sink.close();
        }
        guard(tmp);
        guard('$source/$name');
        if (!await matches(tmp, row)) {
          fail('Copied original did not match its manifest');
        }
        await phase('afterFileStage');
      }
      await mkdir(File(destination).parent.path);
      // No await between last absence/ownership check and publication.
      guard(tmp);
      guard(destination);
      if (FileSystemEntity.typeSync(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        fail();
      }
      File(tmp).renameSync(destination);
      check();
      await phase('afterFilePublish');
    }
    await verifyTarget(w);
  }

  Future<bool> run() async {
    check();
    if (!_hash(grant.namespace) ||
        !_hash(grant.manifestSha256) ||
        grant.manifestBytes.length > jsonLimit ||
        _digest(grant.manifestBytes) != grant.manifestSha256) {
      fail();
    }
    final manifest = map(grant.manifestBytes);
    final selected = works(manifest);
    final done = await read(receipt);
    if (done != null) {
      final r = map(done);
      if (r['schema'] != 'pw_legacy_original_adoption_complete/1' ||
          r['namespace'] != account.namespace ||
          r['manifest_sha256'] != grant.manifestSha256 ||
          jsonEncode(r['work_ids']) !=
              jsonEncode(selected.map((w) => w['id']).toList())) {
        fail();
      }
      return true; // Completed import never restores deleted/edited work again.
    }
    final pending = await read(journal);
    final current = await read(index);
    if (current == null) fail();
    List<int> original = current;
    if (pending != null) {
      final p = map(pending);
      if (p['schema'] != 'pw_legacy_original_adoption_journal/1' ||
          p['manifest_sha256'] != grant.manifestSha256 ||
          p['namespace'] != account.namespace ||
          p['original_index_base64'] is! String) {
        fail();
      }
      original = base64Decode(p['original_index_base64'] as String);
      if (original.length > jsonLimit ||
          _digest(original) != p['original_index_sha256']) {
        fail();
      }
    }
    final rows = records(original);
    final byId = {for (final r in rows) r['id']: r};
    for (final w in selected) {
      final r = byId[w['id']];
      if (r == null ||
          r['cloudViewingOnly'] != true ||
          r['pipeline_kind'] != 'official' ||
          r['cloudLibraryRevision'] != w['cloud_revision'] ||
          r['artifactPath'] != null) {
        fail();
      }
      final expected =
          'accounts/v1/${account.namespace}/captures_official/${w['id']}/cloud_cache/${w['cloud_revision']}/capture';
      final path = r['captureDir'];
      if (path is! String || !path.endsWith('/Documents/$expected')) fail();
      final target = '$root/captures_official/${w['id']}';
      r['captureDir'] = target;
      r['photosDir'] = '$target/${w['photo_directory']}';
      r['captureManifestPath'] = '$target/${w['capture_manifest']}';
      r['photoCount'] = w['photo_count'];
      r['cloudViewingOnly'] = false;
      r['localRawRetainedForDebug'] = true;
    }
    final finalBytes = utf8.encode(jsonEncode(rows));
    if (pending != null && _digest(current) == _digest(finalBytes)) {
      await phase('afterIndexCommit');
    } else {
      if (_digest(current) != _digest(original)) {
        fail('Account index changed; original recovery paused');
      }
      final legacy = await read('$base/scan_records.json');
      if (legacy == null ||
          _digest(legacy) != manifest['legacy_index_sha256']) {
        fail();
      }
      final tombstones = <String, List<int>?>{};
      for (final path in [
        '$base/scan_record_deletion_tombstones.json',
        '$root/scan_record_deletion_tombstones.json',
      ]) {
        final bytes = await read(path);
        tombstones[path] = bytes;
        if (bytes == null) continue;
        final values = jsonDecode(utf8.decode(bytes));
        if (values is! List || !values.every(_hash)) fail();
        for (final work in selected) {
          // The existing store/importer's exact deletion-identity recipe.
          final deletion = _digest(
            utf8.encode(
              'pocketworld.project-deletion.v1:official:${work['id']}',
            ),
          );
          if (values.contains(deletion)) {
            fail('A selected original was deleted; recovery stopped');
          }
        }
      }
      for (final w in selected) {
        await verifyInputs(w);
        await verifyTarget(w);
        final proofs = {
          for (final r in w['files'] as List)
            r['path'] as String: Map<String, dynamic>.from(r as Map),
        };
        final cache =
            '$root/captures_official/${w['id']}/cloud_cache/${w['cloud_revision']}/capture';
        for (final name in [
          'official_sfm_sparse.ply',
          'official_sfm_sparse_meta.json',
        ]) {
          if (!await matches('$cache/$name', proofs[name]!)) {
            fail('Viewing copy differs from approved original');
          }
        }
      }
      if (pending == null) {
        await writeJson(journal, {
          'schema': 'pw_legacy_original_adoption_journal/1',
          'namespace': account.namespace,
          'manifest_sha256': grant.manifestSha256,
          'original_index_sha256': _digest(original),
          'original_index_base64': base64Encode(original),
        });
      }
      await phase('afterJournal');
      for (final w in selected) {
        await copyInputs(w);
      }
      await phase('afterFilesPublish');
      final tmp = '$stage/INDEX.pending';
      await mkdir(stage);
      await io(tmp, () => File(tmp).writeAsBytes(finalBytes, flush: true));
      guard(index);
      guard(tmp);
      for (final entry in tombstones.entries) {
        guard(entry.key);
        final type = FileSystemEntity.typeSync(entry.key, followLinks: false);
        if (entry.value == null) {
          if (type != FileSystemEntityType.notFound) {
            fail('Deletion state changed during recovery');
          }
        } else if (type != FileSystemEntityType.file ||
            _digest(File(entry.key).readAsBytesSync()) !=
                _digest(entry.value!)) {
          fail('Deletion state changed during recovery');
        }
      }
      if (_digest(File(index).readAsBytesSync()) != _digest(original)) {
        fail('Account index changed; originals retained');
      }
      File(tmp).renameSync(index);
      check();
      await phase('afterIndexCommit');
    }
    await writeJson(receipt, {
      'schema': 'pw_legacy_original_adoption_complete/1',
      'namespace': account.namespace,
      'manifest_sha256': grant.manifestSha256,
      'work_ids': selected.map((w) => w['id']).toList(),
      'status': 'VERIFIED_ORIGINALS_ADOPTED',
    });
    return true;
  }
}
