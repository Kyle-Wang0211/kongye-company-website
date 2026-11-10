import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../config/backend_deployment.dart';
import '../ui/scan_record.dart';
import '../util/device_log.dart';
import 'cloud_library_backend.dart';
import 'cloud_library_payload.dart';
import 'scan_record_store.dart';
import 'work_identity.dart';

enum CloudLibraryStatus { pending, syncing, saved }

class CloudLibraryState {
  const CloudLibraryState(this.status, {this.reason});
  final CloudLibraryStatus status;
  final String? reason;
}

/// Account-bound product orchestration around official Supabase file and RPC
/// operations. Local originals are never an automatic cleanup target.
class CloudLibrary extends ChangeNotifier {
  CloudLibrary({
    required this.store,
    required this.backend,
    this.maxViewingCacheBytes = 250000000,
    this.onDiagnostic,
    this.beforeSourceReadForTesting,
  }) {
    if (maxViewingCacheBytes < 1) {
      throw ArgumentError.value(maxViewingCacheBytes);
    }
    _removeRevocation = store.addRevocationListener(dispose);
  }
  final ScanRecordStore store;
  final CloudLibraryBackend backend;
  final int maxViewingCacheBytes;

  /// Receives fixed phase names and exception types only, never SDK messages,
  /// object paths, account IDs, URLs, headers or credentials.
  final void Function(String event)? onDiagnostic;

  @visibleForTesting
  final Future<void> Function(String phase, ScanRecord record)?
  beforeSourceReadForTesting;

  final _retiredCaptureSources = <String>{};
  final _sourceReads = <String, Set<Completer<void>>>{};

  /// Close this record's capture-backed cloud readers without waiting for any
  /// network operation. Already-started local reads must actually return first.
  Future<void> retireCaptureSourcesFor(String recordId) async {
    _check();
    _retiredCaptureSources.add(recordId);
    final active = List<Completer<void>>.of(
      _sourceReads[recordId] ?? const <Completer<void>>{},
    );
    await _latestFinalSourceRecord(recordId);
    await Future.wait(active.map((read) => read.future));
    _check();
    await _latestFinalSourceRecord(recordId);
  }

  Future<ScanRecord> _latestFinalSourceRecord(String recordId) async {
    _check();
    final current = store.byId(recordId);
    if (current == null || !await verifyCloudFinalArtifact(store, current)) {
      throw StateError('Retired capture source requires a verified final GLB');
    }
    _check();
    final latest = store.byId(recordId);
    if (latest == null ||
        latest.accountNamespace != current.accountNamespace ||
        latest.artifactPath != current.artifactPath ||
        latest.finalGlbSha256 != current.finalGlbSha256 ||
        latest.finalGlbBytes != current.finalGlbBytes) {
      throw StateError('Final cloud source changed during retirement');
    }
    return latest;
  }

  Future<T> _readSource<T>(
    ScanRecord captured,
    String phase,
    Future<T> Function(ScanRecord current) read,
  ) async {
    // Register synchronously before the first await, so retirement captures all
    // source IO already started by an older synchronization snapshot.
    final done = Completer<void>();
    (_sourceReads[captured.id] ??= {}).add(done);
    try {
      _check();
      final source = _retiredCaptureSources.contains(captured.id)
          ? await _latestFinalSourceRecord(captured.id)
          : captured;
      await beforeSourceReadForTesting?.call(phase, source);
      _check();
      return await read(source);
    } finally {
      _sourceReads[captured.id]?.remove(done);
      if (_sourceReads[captured.id]?.isEmpty == true) {
        _sourceReads.remove(captured.id);
      }
      done.complete();
    }
  }

  void _diagnose(String phase, {Object? error}) {
    final rawType = error?.runtimeType.toString();
    final type =
        rawType != null &&
            RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(rawType)
        ? rawType
        : 'Other';
    final event = error == null
        ? 'phase=$phase result=saved'
        : 'phase=$phase result=failed error_type=$type';
    try {
      final sink = onDiagnostic;
      if (sink != null) {
        sink(event);
      } else {
        DeviceLog.log('PrivateCloudSync', event);
      }
    } catch (_) {
      // Diagnostics may never change synchronization or original-data safety.
    }
  }

  final _viewPins = <String, int>{};
  final _cacheAccess = <String, DateTime>{};
  Future<void> _cacheTail = Future<void>.value();
  Future<void> _recordTail = Future<void>.value();
  final _evictions = <String, Future<void>>{};
  late final void Function() _removeRevocation;
  bool _disposed = false;
  bool _loaded = false;
  Future<void>? _running;
  bool _synchronizeRequested = false;
  Future<void>? _loading;
  Future<void> _journalTail = Future<void>.value();
  final _remote = <String, CloudLibraryRemoteWork>{};
  final _identityConflicts = <String>{};
  final _states = <String, CloudLibraryState>{};
  final _fingerprints = <String, String>{};
  final _ackRevisions = <String, String>{};
  final _ackDigests = <String, String>{};
  final _pendingVersions = <String, Map<String, String>>{};
  final _pendingNames = <String, String>{};
  final _pendingDeletes = <String>{};
  final _deleted = <String>{};
  final _downloads = <String, Future<ScanRecord>>{};

  static CloudLibrary? _attached;
  static CloudLibrary? forStore(ScanRecordStore store) {
    final library = _attached;
    return library != null &&
            identical(library.store, store) &&
            library.isActive
        ? library
        : null;
  }

  static void attach(CloudLibrary? library) {
    if (identical(_attached, library)) return;
    _attached?.dispose();
    _attached = library;
  }

  bool get isActive => !_disposed && store.isActive;
  bool isDeleted(String id) =>
      _deleted.contains(id) || _pendingDeletes.contains(id);
  CloudLibraryState stateFor(String id) =>
      _states[id] ??
      CloudLibraryState(
        _remote[id]?.deleted == false
            ? CloudLibraryStatus.saved
            : CloudLibraryStatus.pending,
      );

  void _check() {
    if (!isActive) throw StateError('Cloud library account revoked');
  }

  void _changed() {
    if (isActive) notifyListeners();
  }

  Future<CloudLibraryLimits> _storageLimits() async {
    _check();
    if (store.account?.deployment.region != BackendRegion.china) {
      return CloudLibraryLimits.legacy;
    }
    if (backend is! CloudLibraryLimitsProvider) {
      throw StateError('Cloud library capabilities unavailable');
    }
    final limits = await (backend as CloudLibraryLimitsProvider)
        .storageLimits();
    _check();
    return limits;
  }

  Future<File> _journalFile() async {
    _check();
    final root = await store.accountDocumentsDirectory();
    final file = File('${root.path}/personal_cloud_library.json');
    await store.requireOwnedPath(file.path);
    _check();
    return file;
  }

  Future<void> _load() => _loading ??= _loadOnce();
  Future<void> _loadOnce() async {
    if (_loaded) return;
    await store.ensureLoaded();
    final file = await _journalFile();
    if (await file.exists()) {
      final data = readCloudLibraryJson(file);
      _check();
      if (data is! Map ||
          data['schema'] != 'pw_library/1' ||
          data['remote'] is! List ||
          data['deleted'] is! List ||
          data['pending_deletes'] is! List ||
          data['fingerprints'] is! Map) {
        throw const FormatException('Invalid cloud library journal');
      }
      for (final value in data['remote']) {
        final work = CloudLibraryRemoteWork.fromJson(
          Map<String, dynamic>.from(value as Map),
        );
        _remote[work.workId] = work;
      }
      for (final key in ['deleted', 'pending_deletes']) {
        for (final id in data[key]) {
          if (id is! String ||
              !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
            throw const FormatException('Invalid cloud deletion journal');
          }
          (key == 'deleted' ? _deleted : _pendingDeletes).add(id);
        }
      }
      for (final entry in (data['fingerprints'] as Map).entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException('Invalid cloud fingerprint');
        }
        _fingerprints[entry.key] = entry.value;
      }
      for (final entry in ((data['ack_revisions'] ?? {}) as Map).entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException('Invalid cloud acknowledgement');
        }
        _ackRevisions[entry.key] = entry.value;
      }
      for (final entry in ((data['pending_names'] ?? {}) as Map).entries) {
        if (entry.key is! String ||
            entry.value is! String ||
            (entry.value as String).length > 256) {
          throw const FormatException('Invalid pending cloud metadata');
        }
        _pendingNames[entry.key] = entry.value;
      }
      for (final entry in ((data['cache_access'] ?? {}) as Map).entries) {
        _cacheAccess[entry.key as String] = DateTime.parse(
          entry.value as String,
        );
      }
      _ackDigests.addAll(Map<String, String>.from(data['ack_digests'] ?? {}));
      for (final entry in ((data['pending_versions'] ?? {}) as Map).entries) {
        _pendingVersions[entry.key as String] = Map<String, String>.from(
          entry.value as Map,
        );
      }
    }
    _loaded = true;
  }

  Map<String, dynamic> _workJson(CloudLibraryRemoteWork w) => {
    'work_id': w.workId,
    'revision': w.revision,
    'record': w.record,
    'assets': w.assets.map((a) => a.toJson()).toList(),
    'deleted': w.deleted,
  };

  Future<void> _persist() {
    final data = jsonEncode({
      'schema': 'pw_library/1',
      'remote': _remote.values.map(_workJson).toList(),
      'deleted': _deleted.toList(),
      'pending_deletes': _pendingDeletes.toList(),
      'fingerprints': _fingerprints,
      'ack_revisions': _ackRevisions,
      'pending_names': _pendingNames,
      'ack_digests': _ackDigests,
      'pending_versions': _pendingVersions,
      'cache_access': _cacheAccess.map(
        (k, v) => MapEntry(k, v.toUtc().toIso8601String()),
      ),
    });
    final next = _journalTail.then((_) async {
      if (utf8.encode(data).length > kCloudLibraryJsonMaxBytes) {
        throw const FormatException(
          'Cloud library journal exceeds metadata limit',
        );
      }
      final file = await _journalFile();
      final temp = File('${file.path}.tmp');
      await store.requireOwnedPath(temp.path);
      _check();
      await temp.writeAsString(data, flush: true);
      _check();
      await store.requireOwnedPath(file.path);
      _check();
      await temp.rename(file.path);
      _check();
    });
    _journalTail = next.catchError((Object _) {});
    return next;
  }

  Future<ScanRecord> _writeRecord(String id, ScanRecord Function() choose) {
    final next = _recordTail.then((_) async {
      _check();
      if (isDeleted(id)) throw StateError('Cloud work deleted');
      final record = choose();
      await store.addOrUpdate(record);
      _check();
      return store.byId(id)!;
    });
    _recordTail = next.then<void>((_) {}).catchError((Object _) {});
    return next;
  }

  Future<String> _fingerprint(ScanRecord record) =>
      _readSource(record, 'fingerprint', _fingerprintSources);

  Future<String> _fingerprintSources(ScanRecord record) async {
    final finalOnly = await verifyCloudFinalArtifact(store, record);
    _check();
    final paths = <String>[];
    for (final path in [
      record.artifactPath,
      if (!finalOnly) record.thumbnailPath,
    ]) {
      if (path != null) {
        paths.add(path.startsWith('file://') ? path.substring(7) : path);
      }
    }
    final dir = finalOnly ? null : record.captureDir;
    if (dir != null) {
      for (final name in const [
        'sfm_sparse.ply',
        'official_sfm_sparse.ply',
        'official_sfm_sparse_meta.json',
        'official_dense.ply',
        'dense_started.json',
        'official_selection_box.json',
        'lod/metadata.json',
        'lod/hierarchy.bin',
        'lod/octree.bin',
        'lod/pw_lod_source.json',
      ]) {
        paths.add('$dir/$name');
      }
    }
    final values = <Object?>[
      record.id,
      record.name,
      record.caption,
      record.pipelineKind.wireName,
    ];
    for (final path in paths) {
      await store.requireOwnedPath(path);
      _check();
      final stat = await File(path).stat();
      _check();
      final contentHash = stat.type == FileSystemEntityType.file
          ? (await sha256.bind(File(path).openRead()).first).toString()
          : null;
      await store.requireOwnedPath(path);
      _check();
      final after = await File(path).stat();
      if (after.size != stat.size ||
          after.modified != stat.modified ||
          after.type != stat.type) {
        throw StateError('Viewing source changed during acknowledgement check');
      }
      values.add([
        path,
        contentHash,
        stat.type.toString(),
        stat.size,
        stat.modified.microsecondsSinceEpoch,
      ]);
    }
    return sha256.convert(utf8.encode(jsonEncode(values))).toString();
  }

  Future<void> synchronize() {
    if (!isActive) return Future<void>.value();
    final running = _running;
    if (running != null) {
      // Store changes and manual refresh share this coordinator. A final GLB
      // attached during an earlier upload must run after that pass, rather than
      // merely join its stale snapshot and wait for the periodic retry.
      _synchronizeRequested = true;
      return running;
    }
    return _running = _drainSynchronizations().whenComplete(() {
      _running = null;
    });
  }

  Future<void> _drainSynchronizations() async {
    do {
      _synchronizeRequested = false;
      await _synchronize();
    } while (_synchronizeRequested && isActive);
  }

  Future<void> _synchronize() async {
    var phase = 'load';
    try {
      await _load();
      _check();
      phase = 'capabilities';
      final limits = await _storageLimits();
      _check();
      for (final id in _pendingDeletes.toList()) {
        phase = 'delete';
        await backend.deleteWork(id);
        _check();
        _pendingDeletes.remove(id);
        _deleted.add(id);
        _remote.remove(id);
        await _persist();
      }
      if (backend is CloudLibraryMaintenance) {
        phase = 'maintenance';
        await (backend as CloudLibraryMaintenance).cleanupUnused();
        _check();
      }
      phase = 'list';
      final remote = await backend.listWorks();
      _check();
      phase = 'reconcile';
      for (final work in remote) {
        if (!work.deleted) limits.requireAssets(work.assets);
      }
      _identityConflicts.clear();
      for (final work in remote) {
        final local = store.byId(work.workId);
        if (!work.deleted &&
            local != null &&
            !local.cloudViewingOnly &&
            _ackRevisions[work.workId] == null &&
            _pendingVersions[work.workId]?['revision'] != work.revision) {
          _identityConflicts.add(work.workId);
          _states[work.workId] = const CloudLibraryState(
            CloudLibraryStatus.pending,
            reason: '作品编号冲突，本地作品已保留',
          );
        }
      }
      final remoteNames = <String, String>{
        for (final work in remote)
          if (!work.deleted && !isDeleted(work.workId))
            work.workId: work.record['name'] as String,
      };
      if (remoteNames.values.map(workNameKey).toSet().length !=
          remoteNames.length) {
        throw DuplicateWorkNameException();
      }
      final occupiedNames = Map<String, String>.from(remoteNames);
      final localNames = <String, String>{};
      final retainAcknowledgements = <String>{};
      for (final record in store.records) {
        final desired =
            _pendingNames[record.id] ??
            (record.cloudViewingOnly || _ackRevisions.containsKey(record.id)
                ? remoteNames[record.id]
                : null) ??
            record.name;
        final others = [
          for (final entry in occupiedNames.entries)
            if (entry.key != record.id) entry.value,
        ];
        final conflict = others.any(
          (name) => workNameKey(name) == workNameKey(desired),
        );
        final name = conflict && kUntitledScanNamePattern.hasMatch(desired)
            ? nextUntitledScanName(others.map((name) => name.trim()))
            : availableWorkName(desired, others);
        occupiedNames[record.id] = name;
        if (record.name != name) {
          localNames[record.id] = name;
          final work = remote
              .where((w) => w.workId == record.id && !w.deleted)
              .firstOrNull;
          if (work != null &&
              !_pendingNames.containsKey(record.id) &&
              _ackRevisions[record.id] == work.revision &&
              _ackDigests[record.id] == _assetDigest(work.assets) &&
              _fingerprints[record.id] == await _fingerprint(record)) {
            retainAcknowledgements.add(record.id);
          }
        }
        if (_pendingNames.containsKey(record.id)) {
          _pendingNames[record.id] = name;
        }
      }
      if (localNames.isNotEmpty) await store.updateNames(localNames);
      _check();
      for (final id in retainAcknowledgements) {
        _fingerprints[id] = await _fingerprint(store.byId(id)!);
        _check();
      }
      for (final work in remote) {
        if (work.deleted) {
          // Preserve any local source bytes, including unsynced edits. Hide
          // the deleted identity and never upload it again.
          _deleted.add(work.workId);
          _remote.remove(work.workId);
          continue;
        }
        if (isDeleted(work.workId)) continue;
        _remote[work.workId] = work;
        if (_identityConflicts.contains(work.workId)) continue;
        final local = store.byId(work.workId);
        if (local == null) {
          await _writeRecord(
            work.workId,
            () => _recordFor(_remote[work.workId]!),
          );
        } else if (local.cloudViewingOnly) {
          final sameRevision = local.cloudLibraryRevision == work.revision;
          final name =
              _pendingNames[work.workId] ?? work.record['name'] as String;
          if (!sameRevision) {
            await _writeRecord(
              work.workId,
              () => _recordFor(_remote[work.workId]!).copyWith(
                name:
                    _pendingNames[work.workId] ??
                    _remote[work.workId]!.record['name'] as String,
              ),
            );
          } else if (local.name != name ||
              local.caption != work.record['caption']) {
            await _writeRecord(
              work.workId,
              () => store
                  .byId(work.workId)!
                  .copyWith(
                    name:
                        _pendingNames[work.workId] ??
                        _remote[work.workId]!.record['name'] as String,
                    caption: _remote[work.workId]!.record['caption'] as String?,
                  ),
            );
          }
        }
        _check();
      }
      await _persist();
      _changed();
      for (final entry in _pendingNames.entries.toList()) {
        _check();
        if (_identityConflicts.contains(entry.key)) continue;
        if (isDeleted(entry.key)) {
          _pendingNames.remove(entry.key);
          continue;
        }
        final work = _remote[entry.key];
        if (work?.revision == null) {
          continue; // First upload carries its local name.
        }
        try {
          final metadata = {...work!.record, 'name': entry.value};
          await backend.reserve(
            entry.key,
            CloudLibraryPayload(
              revision: work.revision!,
              record: metadata,
              assets: work.assets,
            ),
          );
          _check();
          await backend.commit(entry.key, work.revision!);
          _check();
          await _verifyAcknowledgement(
            entry.key,
            work.revision!,
            metadata,
            work.assets,
          );
          _remote[entry.key] = CloudLibraryRemoteWork(
            workId: work.workId,
            revision: work.revision,
            record: metadata,
            assets: work.assets,
          );
          if (_pendingNames[entry.key] == entry.value) {
            _pendingNames.remove(entry.key);
            _states[entry.key] = const CloudLibraryState(
              CloudLibraryStatus.saved,
            );
          }
          await _persist();
        } catch (error) {
          if (!isActive) return;
          _states[entry.key] = CloudLibraryState(
            CloudLibraryStatus.pending,
            reason: _reason(error),
          );
        }
      }
      for (final record in store.records) {
        _check();
        if (_identityConflicts.contains(record.id)) continue;
        if (isDeleted(record.id) || record.cloudViewingOnly) continue;
        var recordPhase = 'fingerprint';
        try {
          final fingerprint = await _fingerprint(record);
          if (_fingerprints[record.id] == fingerprint &&
              _remote.containsKey(record.id)) {
            final work = _remote[record.id]!;
            final sameRevision =
                _ackRevisions[record.id] == work.revision &&
                _ackDigests[record.id] == _assetDigest(work.assets) &&
                work.record['id'] == record.id &&
                DateTime.parse(work.record['created_at'] as String) ==
                    record.createdAt &&
                work.record['pipeline_kind'] == record.pipelineKind.wireName &&
                work.record['preferred_capture_mode'] ==
                    record.preferredCaptureMode.name;
            if (sameRevision &&
                !_pendingNames.containsKey(record.id) &&
                (record.name != work.record['name'] ||
                    record.caption != work.record['caption'])) {
              final renamed = await _writeRecord(
                record.id,
                () => store
                    .byId(record.id)!
                    .copyWith(
                      name: _remote[record.id]!.record['name'] as String,
                      caption: _remote[record.id]!.record['caption'] as String?,
                    ),
              );
              _fingerprints[record.id] = await _fingerprint(renamed);
              await _persist();
            }
            _states[record.id] =
                sameRevision && !_pendingNames.containsKey(record.id)
                ? const CloudLibraryState(CloudLibraryStatus.saved)
                : const CloudLibraryState(
                    CloudLibraryStatus.pending,
                    reason: '云端已有新版本，本地版本已保留',
                  );
            continue;
          }
          _states[record.id] = const CloudLibraryState(
            CloudLibraryStatus.syncing,
          );
          _changed();
          recordPhase = 'snapshot';
          final snapshotPayload = await _readSource(
            record,
            'snapshot',
            (source) => CloudLibraryPayloadBuilder(
              store: store,
              maxFileBytes: limits.maxUploadFileBytes,
              maxTotalBytes: limits.maxTotalBytes,
            ).build(source),
          );
          _check();
          if (isDeleted(record.id) || store.byId(record.id) == null) continue;
          // Existing standard random source supplies opaque revision IDs.
          // Persist the attempt before contacting the server, so a relaunch
          // retries the same immutable version rather than reserving twice.
          final digest = snapshotPayload.revision;
          String revision;
          if (_ackDigests[record.id] == digest &&
              _ackRevisions[record.id] == _remote[record.id]?.revision) {
            revision = _ackRevisions[record.id]!;
          } else if (_pendingVersions[record.id]?['digest'] == digest) {
            revision = _pendingVersions[record.id]!['revision']!;
          } else {
            final random = Random.secure();
            revision = List.generate(
              32,
              (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
            ).join();
            _pendingVersions[record.id] = {
              'digest': digest,
              'revision': revision,
            };
            await _persist();
            _check();
          }
          final payload = CloudLibraryPayload(
            revision: revision,
            record: snapshotPayload.record,
            assets: snapshotPayload.assets,
          );
          recordPhase = 'reserve';
          await backend.reserve(record.id, payload);
          _check();
          for (final asset in payload.assets) {
            recordPhase = 'upload';
            if (_remote[record.id]?.revision == payload.revision) continue;
            if (isDeleted(record.id)) {
              throw StateError('Work deleted during upload');
            }
            await store.requireOwnedPath(asset.localPath!);
            _check();
            await backend.upload(record.id, payload.revision, asset);
            _check();
          }
          if (isDeleted(record.id) || store.byId(record.id) == null) continue;
          recordPhase = 'commit';
          await backend.commit(record.id, payload.revision);
          _check();
          recordPhase = 'acknowledge';
          await _verifyAcknowledgement(
            record.id,
            payload.revision,
            payload.record,
            payload.assets,
          );
          _remote[record.id] = CloudLibraryRemoteWork(
            workId: record.id,
            revision: payload.revision,
            record: payload.record,
            assets: payload.assets,
          );
          _fingerprints[record.id] = fingerprint;
          _ackRevisions[record.id] = payload.revision;
          _ackDigests[record.id] = digest;
          _pendingVersions.remove(record.id);
          if (_pendingNames[record.id] == payload.record['name']) {
            _pendingNames.remove(record.id);
          }
          final current = store.byId(record.id);
          final unchanged =
              current != null && await _fingerprint(current) == fingerprint;
          _states[record.id] = CloudLibraryState(
            unchanged ? CloudLibraryStatus.saved : CloudLibraryStatus.pending,
          );
          await _persist();
          if (unchanged) _diagnose('acknowledge');
          // This directory contains immutable upload copies, never source data.
          recordPhase = 'local_cleanup';
          if (payload.assets.isNotEmpty) {
            final first = payload.assets.first.localPath!;
            final suffix = '/${payload.assets.first.key}';
            final snapshot = Directory(
              first.substring(0, first.length - suffix.length),
            );
            final root = await store.accountDocumentsDirectory();
            if (snapshot.path.startsWith('${root.path}/library_uploads/')) {
              await store.requireOwnedPath(snapshot.path);
              _check();
              await snapshot.delete(recursive: true);
            }
          }
        } catch (error) {
          if (!isActive) return;
          _diagnose(recordPhase, error: error);
          _states[record.id] = CloudLibraryState(
            CloudLibraryStatus.pending,
            reason: _reason(error),
          );
        }
        _changed();
      }
      await trimViewingCache();
    } catch (error) {
      if (!isActive) return;
      _diagnose(phase, error: error);
      // Backend/schema failures may not convert existing original work into
      // empty cloud records or remove their files.
      for (final record in store.records.where((r) => !r.cloudViewingOnly)) {
        _states[record.id] = CloudLibraryState(
          CloudLibraryStatus.pending,
          reason: _reason(error),
        );
      }
      _changed();
    }
  }

  Future<void> _verifyAcknowledgement(
    String id,
    String revision,
    Map<String, dynamic> record,
    List<CloudLibraryAsset> assets,
  ) async {
    final rows = await backend.listWorks();
    _check();
    final limits = await _storageLimits();
    for (final work in rows) {
      if (!work.deleted) limits.requireAssets(work.assets);
    }
    final matches = rows.where((w) => w.workId == id && !w.deleted).toList();
    if (matches.length != 1 ||
        matches.single.revision != revision ||
        !mapEquals(matches.single.record, record) ||
        _assetDigest(matches.single.assets) != _assetDigest(assets)) {
      throw StateError('Cloud acknowledgement differs from requested work');
    }
  }

  String _assetDigest(List<CloudLibraryAsset> assets) {
    final ordered = [...assets]..sort((a, b) => a.key.compareTo(b.key));
    return sha256
        .convert(
          utf8.encode(jsonEncode(ordered.map((a) => a.toJson()).toList())),
        )
        .toString();
  }

  String _reason(Object error) {
    if (error is CloudLibraryPayloadException) return error.message;
    if (error is DuplicateWorkNameException) return '存在同名作品，作品已保留，请重命名';
    // SDK errors can contain URLs/headers; never surface or persist those.
    return '云端暂不可用或额度不足，作品已保留，稍后自动重试';
  }

  ScanRecord _recordFor(CloudLibraryRemoteWork work, {String? cacheRoot}) {
    final metadata = work.record;
    final previous = store.byId(work.workId);
    String? path(String key) =>
        cacheRoot != null && work.assets.any((a) => a.key == key)
        ? '$cacheRoot/$key'
        : null;
    final hasCapture = work.assets.any((a) => a.key.startsWith('capture/'));
    return ScanRecord(
      id: work.workId,
      accountNamespace: store.account!.namespace,
      name: metadata['name'] as String,
      createdAt: DateTime.parse(metadata['created_at'] as String),
      pipelineKind: CapturePipelineKindWire.fromWireName(
        metadata['pipeline_kind'],
      ),
      preferredCaptureMode: CaptureMode.values.firstWhere(
        (m) => m.name == metadata['preferred_capture_mode'],
        orElse: () => CaptureMode.local,
      ),
      caption: metadata['caption'] as String?,
      cloudLibraryRevision: work.revision,
      cloudViewingOnly: true,
      // Cache eviction and repeated hydration are not new results. Keep the
      // local acknowledgement for this revision; a new revision starts unseen.
      resultViewedAt:
          previous?.cloudViewingOnly == true &&
              previous?.cloudLibraryRevision == work.revision
          ? previous?.resultViewedAt
          : null,
      thumbnailPath: path('thumbnail.jpg'),
      artifactPath: path('artifact.glb') == null
          ? null
          : 'file://${path('artifact.glb')}',
      captureDir: cacheRoot != null && hasCapture ? '$cacheRoot/capture' : null,
    );
  }

  Future<ScanRecord> ensureAvailable(String id) =>
      _downloads[id] ??= _ensureAvailable(id).whenComplete(() {
        _downloads.remove(id);
      });

  Future<ScanRecord> _ensureAvailable(String id) async {
    await _load();
    _check();
    if (isDeleted(id)) throw StateError('Cloud work deleted');
    await _evictions[id]?.catchError((Object _) {});
    _check();
    final local = store.byId(id);
    if (local == null) throw StateError('Cloud work unavailable');
    if (!local.cloudViewingOnly) return local;
    final work = _remote[id];
    if (work == null || work.revision == null) {
      throw StateError('Cloud work unavailable');
    }
    final limits = await _storageLimits();
    limits.requireAssets(work.assets);
    _checkDownload(id, work.revision!);
    final canonical = await store.captureDirFor(
      id,
      pipelineKind: local.pipelineKind,
    );
    final cache = Directory('${canonical.path}/cloud_cache/${work.revision}');
    await store.requireOwnedPath(cache.path);
    _checkDownload(id, work.revision!);
    final accountRoot = await store.accountDocumentsDirectory();
    _checkDownload(id, work.revision!);
    final physicalAccountRoot = Directory(
      await accountRoot.resolveSymbolicLinks(),
    );
    await store.requireOwnedPath(accountRoot.path);
    _checkDownload(id, work.revision!);
    for (final asset in work.assets) {
      CloudLibraryAsset.fromJson(asset.toJson());
      final file = File('${cache.path}/${asset.key}');
      await store.requireOwnedPath(file.path);
      _checkDownload(id, work.revision!);
      final exists = await file.exists();
      await store.requireOwnedPath(file.path);
      _checkDownload(id, work.revision!);
      if (exists) {
        final length = await file.length();
        await store.requireOwnedPath(file.path);
        _checkDownload(id, work.revision!);
        if (length == asset.bytes) {
          final digest = await sha256.bind(file.openRead()).first;
          await store.requireOwnedPath(file.path);
          _checkDownload(id, work.revision!);
          if (digest.toString() == asset.sha256) continue;
        }
      }
      // Per-ID deduplication owns this transfer. A unique exclusive temporary
      // file also leaves any unrelated or interrupted .part file untouched.
      final nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
      final temp = File('${file.path}.$nonce.part');
      RandomAccessFile? output;
      var ownsTemp = false;
      try {
        await store.requireOwnedPath(temp.path);
        _checkDownload(id, work.revision!);
        await temp.parent.create(recursive: true);
        await store.requireOwnedPath(temp.path);
        _checkDownload(id, work.revision!);
        await temp.create(exclusive: true);
        ownsTemp = true;
        await store.requireOwnedPath(temp.path);
        _checkDownload(id, work.revision!);
        output = await temp.open(mode: FileMode.writeOnly);
        await store.requireOwnedPath(temp.path);
        _checkDownload(id, work.revision!);
        try {
          await for (final chunk in checkedCloudLibraryAssetStream(
            backend.download(id, work.revision!, asset),
            asset,
            check: () => _checkDownload(id, work.revision!),
          )) {
            await store.requireOwnedPath(temp.path);
            _checkDownload(id, work.revision!);
            await output.writeFrom(chunk);
            await store.requireOwnedPath(temp.path);
            _checkDownload(id, work.revision!);
          }
        } finally {
          try {
            await output.flush();
          } finally {
            final closing = output;
            output = null;
            await closing.close();
          }
        }
        await store.requireOwnedPath(temp.path);
        _checkDownload(id, work.revision!);
        await store.requireOwnedPath(file.path);
        _checkDownload(id, work.revision!);
        // No asynchronous gap between the final account/revision check and
        // publication in the same filesystem.
        temp.renameSync(file.path);
        ownsTemp = false;
      } finally {
        try {
          if (output != null) {
            try {
              await output.flush();
            } finally {
              await output.close();
            }
          }
        } finally {
          if (ownsTemp) {
            _removeDownloadTemp(temp, accountRoot, physicalAccountRoot);
          }
        }
      }
    }
    _check();
    if (isDeleted(id) || _remote[id]?.revision != work.revision) {
      throw StateError('Cloud work changed during download');
    }
    final hydrated = await _writeRecord(id, () {
      final current = _remote[id]!;
      if (current.revision != work.revision) {
        throw StateError('Cloud work changed during download');
      }
      return _recordFor(
        current,
        cacheRoot: cache.path,
      ).copyWith(name: _pendingNames[id] ?? current.record['name'] as String);
    });
    _check();
    _cacheAccess[id] = DateTime.now().toUtc();
    await _persist();
    await trimViewingCache(keepId: id);
    // Only a fully verified, published download counts as acknowledged. Never
    // mark a partial transfer, nor a revision replaced while awaiting writes.
    _checkDownload(id, work.revision!);
    await store.markResultViewed(hydrated);
    _checkDownload(id, work.revision!);
    return store.byId(id)!;
  }

  void _checkDownload(String id, String revision) {
    _check();
    if (isDeleted(id) ||
        store.byId(id) == null ||
        _remote[id]?.revision != revision) {
      throw StateError('Cloud work changed during download');
    }
  }

  void _removeDownloadTemp(
    File temp,
    Directory accountRoot,
    Directory physicalAccountRoot,
  ) {
    // Revocation forbids new store operations, but this request still owns its
    // exclusive partial. Use the frozen account path; never resolve a new
    // account or recursively remove a directory during failure cleanup.
    if (!temp.path.startsWith('${accountRoot.path}/')) {
      throw StateError('Invalid cloud download temporary path');
    }
    // macOS exposes the system temporary folder through /var, a trusted
    // platform symlink. Freeze its resolved root while the store is active,
    // then reject any links introduced below that physical path.
    final physicalTemp = File(
      '${physicalAccountRoot.path}/${temp.path.substring(accountRoot.path.length + 1)}',
    );
    var cursor = '';
    for (final segment
        in physicalTemp.path.split('/').where((s) => s.isNotEmpty)) {
      cursor = '$cursor/$segment';
      if (FileSystemEntity.typeSync(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Unsafe cloud download cleanup path');
      }
    }
    final type = FileSystemEntity.typeSync(
      physicalTemp.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.file) {
      physicalTemp.deleteSync();
    } else if (type != FileSystemEntityType.notFound) {
      throw StateError('Unexpected cloud download temporary artifact');
    }
  }

  Future<void> evictViewingCache(String id) =>
      _evictions[id] ??= _evictViewingCache(id).whenComplete(() {
        _evictions.remove(id);
      });

  Future<void> _evictViewingCache(String id) async {
    await _load();
    _check();
    final record = store.byId(id);
    final work = _remote[id];
    // Locally captured/imported originals remain protected even if saved.
    if (record == null ||
        !record.cloudViewingOnly ||
        work?.revision == null ||
        isDeleted(id) ||
        _downloads.containsKey(id) ||
        (_viewPins[id] ?? 0) > 0) {
      throw StateError(
        'Only acknowledged downloaded viewing copies can be evicted',
      );
    }
    final canonical = await store.captureDirFor(
      id,
      pipelineKind: record.pipelineKind,
    );
    final cache = Directory('${canonical.path}/cloud_cache');
    await store.requireOwnedPath(cache.path);
    _check();
    // Drop only disposable path references; the private cloud row survives.
    await _writeRecord(id, () => _recordFor(_remote[id]!));
    _check();
    if (await cache.exists()) {
      await store.requireOwnedPath(cache.path);
      _check();
      await cache.delete(recursive: true);
    }
  }

  /// Protect the viewer's files until its route has closed.
  VoidCallback pinViewingCopy(String id) {
    _check();
    _viewPins[id] = (_viewPins[id] ?? 0) + 1;
    bool released = false;
    return () {
      if (released) return;
      released = true;
      final count = (_viewPins[id] ?? 1) - 1;
      if (count > 0) {
        _viewPins[id] = count;
      } else {
        _viewPins.remove(id);
      }
      if (isActive) unawaited(trimViewingCache().catchError((Object _) {}));
    };
  }

  /// A soft budget while viewers are open: pinned/in-flight works stay intact.
  /// Only downloaded copies are eligible; capture originals never enter it.
  Future<void> trimViewingCache({String? keepId}) {
    final next = _cacheTail.then((_) async {
      await _load();
      _check();
      final copies = <MapEntry<String, int>>[];
      for (final record in store.records.where((r) => r.cloudViewingOnly)) {
        if (isDeleted(record.id) || _remote[record.id]?.revision == null) {
          continue;
        }
        final canonical = await store.captureDirFor(
          record.id,
          pipelineKind: record.pipelineKind,
        );
        final cache = Directory('${canonical.path}/cloud_cache');
        await store.requireOwnedPath(cache.path);
        _check();
        if (!await cache.exists()) continue;
        int bytes = 0;
        await for (final entry in cache.list(
          recursive: true,
          followLinks: false,
        )) {
          await store.requireOwnedPath(entry.path);
          _check();
          if (entry is File) bytes += await entry.length();
        }
        copies.add(MapEntry(record.id, bytes));
      }
      copies.sort(
        (a, b) =>
            (_cacheAccess[a.key] ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  _cacheAccess[b.key] ?? DateTime.fromMillisecondsSinceEpoch(0),
                ),
      );
      int total = copies.fold(0, (n, e) => n + e.value);
      for (final copy in copies) {
        if (total <= maxViewingCacheBytes) break;
        if (copy.key == keepId ||
            _downloads.containsKey(copy.key) ||
            (_viewPins[copy.key] ?? 0) > 0) {
          continue;
        }
        await evictViewingCache(copy.key);
        _cacheAccess.remove(copy.key);
        total -= copy.value;
      }
      await _persist();
    });
    _cacheTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> deleteWork(String id) async {
    await _load();
    _check();
    _pendingDeletes.add(id);
    await _persist(); // Durable before the user-confirmed original deletion.
    _check();
    await store.delete(id);
    _changed();
    if (_running != null) await _running;
    await synchronize();
  }

  Future<void> renameWork(String id, String name) async {
    name = name.trim();
    if (name.trim().isEmpty || name.length > 256) {
      throw ArgumentError('Invalid work name');
    }
    await _load();
    _check();
    if (isDeleted(id)) throw StateError('Cloud work deleted');
    final record = store.byId(id);
    if (_identityConflicts.contains(id)) {
      throw StateError('Work identifier conflict');
    }
    if (record == null) throw StateError('Cloud work unavailable');
    store.requireAvailableName(id, name);
    if (_remote.values.any(
      (work) =>
          !work.deleted &&
          work.workId != id &&
          workNameKey(work.record['name'] as String) == workNameKey(name),
    )) {
      throw DuplicateWorkNameException();
    }
    final previousName = _pendingNames[id];
    _pendingNames[id] = name;
    try {
      await _writeRecord(id, () => store.byId(id)!.copyWith(name: name));
    } catch (_) {
      if (_pendingNames[id] == name) {
        if (previousName == null) {
          _pendingNames.remove(id);
        } else {
          _pendingNames[id] = previousName;
        }
      }
      rethrow;
    }
    await _persist();
    _check();
    _states[id] = const CloudLibraryState(CloudLibraryStatus.pending);
    _changed();
    if (_running != null) await _running;
    await synchronize();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _removeRevocation();
    if (backend is SupabaseCloudLibraryBackend) {
      (backend as SupabaseCloudLibraryBackend).dispose();
    }
    if (identical(_attached, this)) _attached = null;
    super.dispose();
  }
}
