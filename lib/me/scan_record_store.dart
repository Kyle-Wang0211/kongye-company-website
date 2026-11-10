// ScanRecordStore — durable on-device store for the user's own scans.
//
// Persistence model:
//   • Each authenticated account owns an opaque root under
//     `${app_documents_dir}/accounts/v1/<namespace>/`. Its records live in
//     `scan_records.json`. JSON is plenty fast for
//     the ~tens-to-low-hundreds of records we expect per user; if the
//     file ever grows past ~1 MB we switch to sqflite.
//   • GLB artifacts live next to that file under
//     `<account_root>/scans/<recordId>.glb`.
//
// Lifecycle (Plan G W2 全本地, 2026-05-16):
//   1. Capture finishes → cell-admitted JPEGs live in
//      `<account_root>/captures/<captureId>/photos/`. A future
//      Drafts UI revamp will call `addOrUpdate` with a ScanRecord
//      pointing at that capture directory.
//   2. W3 local pipeline (待实现) iterates the JPEGs, runs DA3 +
//      ScaleAlign + PoissonRecon + texrecon + gltfpack, writes the
//      final GLB to `scans/<id>.glb` and calls `addOrUpdate` again with
//      `artifactPath` set.
//   3. UI (HomeViewModel / _MyWorksSection) listens via the broadcast
//      stream so the gallery refreshes without a manual reload.
//
// Concurrency: writes are serialized through `_writeLock`. Multiple
// readers are fine — `records` returns a snapshot list.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../auth/account_workspace.dart';
import '../dense/dense_work_state.dart'
    show kDensePlyFileName, kDenseStartedMarkerName, kDenseWorkDirName;
import '../pw38/cache_completion.dart' show pw38CacheCompletionMarkerName;
import '../pw38/pending_capture_retirement.dart';
import '../ui/me_page.dart' show sparsePlyFileNameForPipeline;
import '../ui/scan_record.dart';
import '../util/image_sanitize.dart';
import 'legacy_scan_record_importer.dart';
import 'legacy_original_adoption.dart';
import 'work_identity.dart';

Uint8List? _uprightLandscapeThumbnailBytes(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) return null;

  var image = img.bakeOrientation(decoded);
  if (image.width <= image.height) return null;

  image = img.copyRotate(image, angle: 90);
  const maxEdge = 1024;
  final longEdge = math.max(image.width, image.height);
  if (longEdge > maxEdge) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? maxEdge : null,
      height: image.height > image.width ? maxEdge : null,
      interpolation: img.Interpolation.average,
    );
  }
  // EXIF 剥离:实测确认元数据会穿过 resize/rotate 链路(见
  // util/image_sanitize.dart 与 test/image_sanitize_test.dart)。
  return encodeSanitizedJpg(image, quality: 88);
}

/// A result generation captured before its viewer dispatches a load. It is
/// intentionally transient; 177's resultViewedAt remains the durable seen state.
@immutable
final class ScanResultViewRevision {
  const ScanResultViewRevision._(this.record, this.readyAt, this.fileSignature);
  final ScanRecord record;
  final DateTime readyAt;
  final String fileSignature;
}

class ScanRecordStore {
  ScanRecordStore._({this.account, Directory? documentsDirectory})
    : _documentsDirectoryOverride = documentsDirectory,
      _legacyImportGrantOverride = null,
      _legacyOriginalAdoptionGrantOverride = null,
      _legacyImportCheckpoint = null,
      _captureCreationCheckpoint = null,
      _captureIdentifier = newCaptureWorkId,
      _legacyFixture = false;
  static ScanRecordStore _instance = ScanRecordStore._();
  static ScanRecordStore get instance => _instance;
  static AccountWorkspace? get activeAccount => _instance.account;

  /// Revocation is synchronous, before any disk access for the next account.
  /// An in-flight caller retains its original store and can never acquire the
  /// next account's paths through this instance.
  static Future<ScanRecordStore> activateAccount(
    AccountWorkspace? account, {
    Directory? documentsDirectory,
  }) async {
    final previous = _instance;
    if (previous.account == account &&
        !previous._revoked &&
        previous._documentsDirectoryOverride?.absolute.path ==
            documentsDirectory?.absolute.path) {
      if (account != null) await previous.ensureLoaded();
      return previous;
    }
    previous._revoked = true;
    previous._notifyRevoked();
    previous._records = const [];
    previous._emit();
    final next = ScanRecordStore._(
      account: account,
      documentsDirectory: documentsDirectory,
    );
    _instance = next;
    if (account != null) await next.ensureLoaded();
    return next;
  }

  /// Isolated store used by persistence contract tests. Production continues
  /// to use [instance] and `path_provider`.
  @visibleForTesting
  ScanRecordStore.forTesting({
    required Directory documentsDirectory,
    this.account,
    LegacyLibraryImportGrant? legacyImportGrant,
    LegacyOriginalAdoptionGrant? legacyOriginalAdoptionGrant,
    FutureOr<void> Function(String phase)? legacyImportCheckpoint,
    String Function()? captureIdentifier,
    FutureOr<void> Function(String prefix)? captureCreationCheckpoint,
  }) : _documentsDirectoryOverride = documentsDirectory,
       _legacyImportGrantOverride = legacyImportGrant,
       _legacyOriginalAdoptionGrantOverride = legacyOriginalAdoptionGrant,
       _legacyImportCheckpoint = legacyImportCheckpoint,
       _captureCreationCheckpoint = captureCreationCheckpoint,
       _captureIdentifier = captureIdentifier ?? newCaptureWorkId,
       _legacyFixture = account == null;

  final Directory? _documentsDirectoryOverride;
  final LegacyLibraryImportGrant? _legacyImportGrantOverride;
  final LegacyOriginalAdoptionGrant? _legacyOriginalAdoptionGrantOverride;
  final FutureOr<void> Function(String phase)? _legacyImportCheckpoint;
  final String Function() _captureIdentifier;
  final FutureOr<void> Function(String prefix)? _captureCreationCheckpoint;
  final AccountWorkspace? account;
  final bool _legacyFixture;
  bool _revoked = false;
  Directory? _resolvedDocumentsDirectory;
  Directory? _baseDocumentsDirectory;
  bool get isActive => !_revoked && (_legacyFixture || account != null);
  final Set<VoidCallback> _revocationListeners = {};

  /// One-shot synchronous cancellation, before activation reaches any await.
  /// Callers must still guard asynchronous continuation with [isActive].
  VoidCallback addRevocationListener(VoidCallback listener) {
    if (!isActive) {
      listener();
      return () {};
    }
    _revocationListeners.add(listener);
    return () => _revocationListeners.remove(listener);
  }

  void _notifyRevoked() {
    final listeners = List<VoidCallback>.of(_revocationListeners);
    _revocationListeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (error) {
        // A failing subscriber cannot prevent other owners being cancelled.
        debugPrint('[ScanRecordStore] revocation callback failed: $error');
      }
    }
  }

  /// Snapshot of the current store. Modifying this list directly is a
  /// no-op (we always return a defensive copy from `records`).
  List<ScanRecord> _records = const <ScanRecord>[];
  Set<String> _deletionTombstones = const <String>{};
  Future<void>? _loadFuture;
  Object? _loadFailure;
  String? _originalAdoptionIssue;

  /// A failed optional recovery does not hide an otherwise valid library.
  /// Messages come from the recovery's fixed diagnostics, without private paths.
  String? get originalAdoptionIssue => isActive ? _originalAdoptionIssue : null;
  final _ctrl = StreamController<List<ScanRecord>>.broadcast();
  Future<void> _writeLock = Future<void>.value();

  /// Snapshot of records, sorted newest-first by createdAt. UI binds
  /// to this through HomeViewModel which forwards changes via
  /// notifyListeners() each time the store fires.
  List<ScanRecord> get records =>
      isActive ? List<ScanRecord>.unmodifiable(_records) : const [];

  /// Fires every time the records list changes. Delayed subscriptions also
  /// lose access to previously queued snapshots when their store is revoked.
  Stream<List<ScanRecord>> get changes =>
      _ctrl.stream.map((snapshot) => isActive ? snapshot : const []);

  /// Resolves once the disk store has been read for the first time.
  /// Callers that want to display records on first frame should `await`
  /// this in initState.
  Future<void> ensureLoaded() async {
    _checkActive();
    await (_loadFuture ??= _load());
    _checkActive();
    if (!_legacyFixture) _ensureWritable();
  }

  Future<void> _load() async {
    var accountPathRewrites = 0;
    try {
      final file = await _storeFile();
      if (!_legacyFixture) {
        await LegacyScanRecordImporter.importAuthorized(
          documentsDirectory: _baseDocumentsDirectory!,
          account: account!,
          grant:
              _legacyImportGrantOverride ??
              LegacyLibraryImportGrant.fromEnvironment(),
          isActive: () => isActive,
          checkpointForTesting: _legacyImportCheckpoint,
        );
        _checkActive();
        try {
          await LegacyOriginalAdoption.adoptAuthorized(
            documentsDirectory: _baseDocumentsDirectory!,
            account: account!,
            grant:
                _legacyOriginalAdoptionGrantOverride ??
                LegacyOriginalAdoptionGrant.fromEnvironment(),
            isActive: () => isActive,
          );
        } on LegacyScanRecordImportException catch (error) {
          _originalAdoptionIssue = error.message;
          debugPrint(
            '[ScanRecordStore] original recovery deferred: ${error.message}',
          );
        }
        _checkActive();
      }
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
          final parsed = list.map(_recordFromJson).toList(growable: false);
          if (!_legacyFixture) {
            final validated = <ScanRecord>[];
            final ids = <String>{};
            final names = <String>{};
            for (final record in parsed) {
              if (record.name.trim().isEmpty ||
                  record.name.length > 256 ||
                  !ids.add(record.id) ||
                  !names.add(workNameKey(record.name))) {
                throw StateError(
                  'Account library contains conflicting identities or names',
                );
              }
              _requireOwner(record);
              final anchored = _reanchorAccountPaths(record);
              if (record.thumbnailPath != anchored.thumbnailPath ||
                  record.artifactPath != anchored.artifactPath ||
                  record.captureDir != anchored.captureDir ||
                  record.photosDir != anchored.photosDir ||
                  record.captureManifestPath != anchored.captureManifestPath) {
                accountPathRewrites++;
              }
              await _ensureRouteOwnedPaths(anchored);
              validated.add(anchored);
            }
            _checkActive();
            _records = validated;
          } else {
            _records = parsed;
          }
        }
      }
    } catch (e, st) {
      debugPrint('[ScanRecordStore] load failed: $e\n$st');
      _loadFailure = e;
      _records = const <ScanRecord>[];
      _emit();
      return;
    }
    try {
      _deletionTombstones = await _loadDeletionTombstones();
    } catch (e, st) {
      debugPrint('[ScanRecordStore] deletion tombstone load failed: $e\n$st');
      _loadFailure = e;
      _records = const <ScanRecord>[];
      _emit();
      return;
    }
    final retained = <ScanRecord>[];
    var deletedRecordsPurged = 0;
    for (final record in _records) {
      if (!_isPermanentlyDeleted(record.id, record.pipelineKind)) {
        retained.add(record);
        continue;
      }
      deletedRecordsPurged++;
      try {
        await _deleteProjectFiles(record);
      } catch (e, st) {
        // Keep the opaque tombstone even when storage is temporarily
        // unavailable. The project remains hidden and cleanup retries on the
        // next load instead of resurrecting user-deleted content.
        debugPrint(
          '[ScanRecordStore] tombstoned project cleanup deferred: $e\n$st',
        );
      }
    }
    _records = retained;
    final recovered = await _recoverOrphanCaptures();
    // Re-anchor stale absolute paths.
    //
    // `thumbnailPath` / `artifactPath` are persisted as ABSOLUTE paths
    // (including the iOS sandbox UUID, e.g.
    //   `/var/mobile/Containers/Data/Application/<UUID>/Documents/...`).
    // The UUID rotates on app reinstall and occasionally on OS upgrades,
    // which makes the stored path point at a non-existent location even
    // though the file is still on disk under the CURRENT UUID's
    // Documents directory.
    //
    // User-facing symptom (caught 2026-05-10): all "Failed to process"
    // cards lose their thumbnail JPEG and fall back to the gray sparkle
    // placeholder, even though `Documents/scans/<id>.jpg` is sitting
    // right there.
    //
    // Fix: after deserializing, walk every record. If `thumbnailPath`
    // points at a missing file but `thumbnailFileFor(id)` exists, patch
    // the record's path. Same logic for `artifactPath` (`<id>.glb`).
    final patched = <ScanRecord>[];
    // The account pass already repaired rotated sandbox paths in memory.
    // Persist those repairs too: cold38 verification reads the durable index.
    var rewrites = accountPathRewrites;
    for (final r in _records) {
      var rec = r;
      if (rec.thumbnailPath != null && rec.thumbnailPath!.isNotEmpty) {
        final crossesRoute = _crossesPipelineNamespace(
          rec.thumbnailPath!,
          pipelineKind: rec.pipelineKind,
        );
        if (!File(rec.thumbnailPath!).existsSync() || crossesRoute) {
          final fresh = await thumbnailFileFor(
            rec.id,
            pipelineKind: rec.pipelineKind,
          );
          if (await fresh.exists()) {
            rec = rec.copyWith(thumbnailPath: fresh.path);
            rewrites++;
          } else if (crossesRoute) {
            // A path into the other route must not become valid later merely
            // because a same-id artifact is created there.
            rec = rec.copyWith(clearThumbnailPath: true);
            rewrites++;
          }
        }
      }
      if (rec.artifactPath != null && rec.artifactPath!.isNotEmpty) {
        // artifactPath is stored as `file://<absolute>` (Image / 3D
        // viewer's URI convention).
        final p = rec.artifactPath!.startsWith('file://')
            ? rec.artifactPath!.substring(7)
            : rec.artifactPath!;
        final crossesRoute = _crossesPipelineNamespace(
          p,
          pipelineKind: rec.pipelineKind,
        );
        if (!File(p).existsSync() || crossesRoute) {
          final fresh = await glbFileFor(
            rec.id,
            pipelineKind: rec.pipelineKind,
          );
          if (await fresh.exists()) {
            rec = rec.copyWith(artifactPath: 'file://${fresh.path}');
            rewrites++;
          } else if (crossesRoute) {
            rec = rec.copyWith(clearArtifactPath: true);
            rewrites++;
          }
        }
      }
      final captureMetadata = <String?>[
        rec.captureDir,
        rec.photosDir,
        rec.captureManifestPath,
      ].whereType<String>().where((path) => path.isNotEmpty).toList();
      if (captureMetadata.isNotEmpty) {
        final routeRoot = await _capturesRoot(pipelineKind: rec.pipelineKind);
        final suppliedCaptureDir = rec.captureDir == null
            ? null
            : Directory(rec.captureDir!);
        final allPathsOwned = captureMetadata.every(
          (path) =>
              !_crossesPipelineNamespace(
                path,
                pipelineKind: rec.pipelineKind,
              ) &&
              _isWithinDirectory(path, routeRoot.path),
        );
        var captureDir = allPathsOwned && suppliedCaptureDir != null
            ? suppliedCaptureDir
            : await captureDirFor(rec.id, pipelineKind: rec.pipelineKind);
        if (!await captureDir.exists()) {
          captureDir = await captureDirFor(
            rec.id,
            pipelineKind: rec.pipelineKind,
          );
        }
        if (await captureDir.exists() &&
            _isWithinDirectory(captureDir.path, routeRoot.path)) {
          final paths = await _capturePaths(
            captureDir,
            pipelineKind: rec.pipelineKind,
          );
          if (rec.captureDir != captureDir.path ||
              rec.photosDir != paths.photosDir.path ||
              rec.captureManifestPath != paths.manifestFile.path) {
            rec = rec.copyWith(
              captureDir: captureDir.path,
              photosDir: paths.photosDir.path,
              captureManifestPath: paths.manifestFile.path,
            );
            rewrites++;
          }
        } else {
          // Never retain stale or cross-route capture metadata. In particular,
          // an official record must not spring back to life if a self capture
          // with the same id later appears (and vice versa).
          rec = _withoutCaptureMetadata(rec);
          rewrites++;
        }
      }
      if (rec.captureDir != null &&
          rec.thumbnailPath != null &&
          rec.thumbnailPath!.isNotEmpty) {
        final thumbnail = File(rec.thumbnailPath!);
        if (await thumbnail.exists() &&
            await _normalizePortraitCaptureThumbnail(thumbnail)) {
          rewrites++;
        }
      }
      patched.add(rec);
    }
    _records = _sortNewestFirst(patched);
    if (rewrites > 0 || recovered > 0 || deletedRecordsPurged > 0) {
      debugPrint(
        '[ScanRecordStore] re-anchored $rewrites stale path(s), '
        'recovered $recovered orphan capture(s), '
        'purged $deletedRecordsPurged deleted record(s)',
      );
      // Persist the patched paths so the next load doesn't have to
      // re-scan + re-write.
      await _flush();
    }
    // 🔴 必须在 _emit() **之前**:UI 第一次读到 records 时"已看过"标记就得在位,
    // 否则历史项目会先闪一屏"完成"。此前放在草稿页 initState 里 unawaited 调用,
    // 那时 _records 还是空的 ⇒ 整个迁移空转 ⇒ 用户实机看到"每次更新完 app 所有
    // 项目都显示完成,还要一个一个点掉"。
    await _markExistingSparseAsViewed();
    _emit();
  }

  Future<bool> _normalizePortraitCaptureThumbnail(File thumbnail) async {
    try {
      _guardPath(thumbnail.path);
      final bytes = await compute(
        _uprightLandscapeThumbnailBytes,
        thumbnail.path,
        debugLabel: 'scan-record-thumbnail-upright',
      );
      _guardPath(thumbnail.path);
      if (bytes == null) return false;
      await thumbnail.writeAsBytes(bytes, flush: true);
      _checkActive();
      return true;
    } catch (e) {
      debugPrint('[ScanRecordStore] thumbnail normalize skipped: $e');
      return false;
    }
  }

  /// Recovery net for interrupted capture finalization.
  ///
  /// The native capture path writes JPEG/JSON sidecars incrementally during
  /// recording. If the app is backgrounded or killed after those files are on
  /// disk but before `_persistDraft()` writes scan_records.json, we would have
  /// valuable raw material with no user-visible draft card. On load, scan
  /// `Documents/captures/*/photos` and rehydrate any missing record.
  Future<int> _recoverOrphanCaptures() async {
    try {
      final root = await _documentsDirectory();
      final existingIds = _records.map((r) => r.id).toSet();
      final recovered = <ScanRecord>[];
      final roots = <(Directory, CapturePipelineKind)>[
        (Directory('${root.path}/captures'), CapturePipelineKind.self),
        (
          Directory('${root.path}/captures_official'),
          CapturePipelineKind.official,
        ),
      ];
      for (final (capturesRoot, pipelineKind) in roots) {
        _guardPath(capturesRoot.path);
        if (!await capturesRoot.exists()) continue;
        await for (final entity in capturesRoot.list(followLinks: false)) {
          _checkActive();
          if (entity is! Directory) continue;
          _guardPath(entity.path);
          final captureId = entity.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .lastOrNull;
          if (captureId == null) continue;
          if (_isPermanentlyDeleted(captureId, pipelineKind)) {
            try {
              await _deleteProjectFiles(
                ScanRecord(
                  id: captureId,
                  accountNamespace: account?.namespace,
                  name: '',
                  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
                  pipelineKind: pipelineKind,
                ),
              );
            } catch (e, st) {
              debugPrint(
                '[ScanRecordStore] late deleted capture cleanup deferred: '
                '$e\n$st',
              );
            }
            continue;
          }
          if (existingIds.contains(captureId)) continue;
          _validateId(captureId);
          final paths = await _capturePaths(entity, pipelineKind: pipelineKind);
          final photosDir = paths.photosDir;
          if (!await photosDir.exists()) continue;
          final photos = <File>[];
          await for (final photoEntity in photosDir.list(followLinks: false)) {
            _checkActive();
            if (photoEntity is! File) continue;
            _guardPath(photoEntity.path);
            final path = photoEntity.path.toLowerCase();
            if (!path.endsWith('.jpg') && !path.endsWith('.jpeg')) continue;
            final metadata = File(
              photoEntity.path.replaceFirst(RegExp(r'\.[^.]+$'), '.json'),
            );
            _guardPath(metadata.path);
            if (await metadata.exists()) photos.add(photoEntity);
          }
          if (photos.isEmpty) continue;
          photos.sort((a, b) => a.path.compareTo(b.path));
          final manifestFile = paths.manifestFile;
          final stat = await entity.stat();
          final createdAt = stat.modified;
          if (!await manifestFile.exists()) {
            await _writeRecoveredCaptureManifest(
              manifestFile: manifestFile,
              captureId: captureId,
              createdAt: createdAt,
              captureDir: entity,
              photosDir: photosDir,
              photos: photos,
              pipelineKind: pipelineKind,
            );
          }
          String? thumbnailPath;
          try {
            final thumbnail = await thumbnailFileFor(
              captureId,
              pipelineKind: pipelineKind,
            );
            await thumbnail.parent.create(recursive: true);
            _guardPath(thumbnail.path);
            _guardPath(photos.first.path);
            await photos.first.copy(thumbnail.path);
            _checkActive();
            thumbnailPath = thumbnail.path;
          } on FileSystemException {
            thumbnailPath = photos.first.path;
          }
          recovered.add(
            ScanRecord(
              id: captureId,
              accountNamespace: account?.namespace,
              name: nextUntitledScanName([
                ..._records.map((r) => r.name),
                ...recovered.map((r) => r.name),
              ]),
              createdAt: createdAt,
              pipelineKind: pipelineKind,
              preferredCaptureMode: CaptureMode.newRemote,
              thumbnailPath: thumbnailPath,
              captureDir: entity.path,
              photosDir: photosDir.path,
              captureManifestPath: manifestFile.path,
              photoCount: photos.length,
              cloudUploadStatus: ScanCloudUploadStatus.localPending,
              localRawRetainedForDebug: true,
            ),
          );
          existingIds.add(captureId);
        }
      }
      if (recovered.isEmpty) return 0;
      _checkActive();
      _records = _sortNewestFirst([..._records, ...recovered]);
      return recovered.length;
    } catch (e, st) {
      debugPrint('[ScanRecordStore] orphan capture recovery failed: $e\n$st');
      return 0;
    }
  }

  /// Resolve the route-owned image directory and manifest without ever mixing
  /// the recovery manifest schema into the canonical photo-bundle filename.
  /// Existing canonical and legacy manifests are left untouched; when neither
  /// exists, callers receive the route-specific legacy filename.
  Future<({Directory photosDir, File manifestFile})> _capturePaths(
    Directory captureDir, {
    required CapturePipelineKind pipelineKind,
  }) async {
    final photosHighres = Directory('${captureDir.path}/photos_highres');
    _guardPath(photosHighres.path);
    final photosDir = await photosHighres.exists()
        ? photosHighres
        : Directory('${captureDir.path}/photos');
    final preferredManifest = pipelineKind == CapturePipelineKind.official
        ? File('${captureDir.path}/official_photo_bundle.json')
        : File('${captureDir.path}/photo_bundle.json');
    final legacyManifest = pipelineKind == CapturePipelineKind.official
        ? File('${captureDir.path}/official_capture_manifest.json')
        : File('${captureDir.path}/capture_manifest.json');
    _guardPath(photosDir.path);
    _guardPath(preferredManifest.path);
    _guardPath(legacyManifest.path);
    final manifestFile = await preferredManifest.exists()
        ? preferredManifest
        : legacyManifest;
    _checkActive();
    return (photosDir: photosDir, manifestFile: manifestFile);
  }

  Future<void> _writeRecoveredCaptureManifest({
    required File manifestFile,
    required String captureId,
    required DateTime createdAt,
    required Directory captureDir,
    required Directory photosDir,
    required List<File> photos,
    required CapturePipelineKind pipelineKind,
  }) async {
    final frames = <Map<String, Object?>>[];
    for (final photo in photos) {
      final metadata = File(
        photo.path.replaceFirst(RegExp(r'\.[^.]+$'), '.json'),
      );
      frames.add(<String, Object?>{
        'image_path': photo.path,
        'metadata_path': metadata.path,
        'image_file': photo.uri.pathSegments.last,
        'metadata_file': metadata.uri.pathSegments.last,
      });
    }
    final manifest = <String, Object?>{
      'schema': 'pocketworld.capture_manifest.v1',
      'capture_id': captureId,
      'pipeline_kind': pipelineKind.wireName,
      'created_at': createdAt.toIso8601String(),
      'capture_dir': captureDir.path,
      'photos_dir': photosDir.path,
      'photo_count': photos.length,
      'frames': frames,
      'recovered_from_orphan_capture': true,
    };
    _guardPath(manifestFile.path);
    await manifestFile.writeAsString(jsonEncode(manifest), flush: true);
    _checkActive();
  }

  /// Insert or replace by id. The store keeps records sorted newest-
  /// first so the gallery natural order is "most recent on top".
  /// 稀疏点云 PLY 的落盘时刻;还没生成出来则 null。
  ///
  /// [2026-08-06 用户签决] "正在训练"= 拍完后管线在生成**稀疏点云**,PLY 出来
  /// 就算完成。所以状态不入库,直接探测文件系统 —— 拍摄链路一行都不用改(它
  /// 正被另一条线在改),而且断点续跑、App 被杀重启这些情况天然都对。
  DateTime? sparseReadyAt(ScanRecord r) {
    _checkActive();
    _requireOwner(r);
    final dir = r.captureDir;
    if (dir == null) return null;
    DateTime? readyAt(String filename) {
      final f = File('$dir/$filename');
      _guardPath(f.path);
      try {
        final st = f.statSync();
        if (st.type == FileSystemEntityType.notFound || st.size <= 0) {
          return null;
        }
        return st.modified;
      } catch (_) {
        return null;
      }
    }

    final sparse = readyAt(sparsePlyFileNameForPipeline(r.pipelineKind));
    if (sparse != null || !r.cloudViewingOnly) return sparse;
    // Verified cloud manifests can contain a dense result without its sparse
    // intermediate. Local captures still use the existing sparse-stage rule.
    return readyAt(kDensePlyFileName);
  }

  /// The unread-result marker follows the delivered result, not an earlier
  /// sparse preview. Reuse 177's persisted resultViewedAt acknowledgement.
  DateTime? resultReadyAt(ScanRecord r) {
    _checkActive();
    _requireOwner(r);
    final artifact = r.artifactPath;
    if (artifact != null && artifact.isNotEmpty) {
      final uri = Uri.tryParse(artifact);
      if (uri == null || (uri.hasScheme && uri.scheme != 'file')) return null;
      final path = uri.scheme == 'file' ? uri.toFilePath() : artifact;
      _guardPath(path);
      try {
        final stat = File(path).statSync();
        return stat.type == FileSystemEntityType.file && stat.size > 0
            ? stat.modified
            : null;
      } on FileSystemException {
        return null;
      }
    }
    final capture = r.captureDir;
    if (r.pipelineKind == CapturePipelineKind.official &&
        !r.cloudViewingOnly &&
        capture != null) {
      // These are the existing persistent downstream-entry markers. Reading
      // them does not start proof validation, hash a GLB, or modify the job.
      for (final name in [
        kDenseStartedMarkerName,
        pw38CacheCompletionMarkerName,
      ]) {
        final path = '$capture/$name';
        _guardPath(path);
        if (File(path).existsSync()) return null;
      }
      final work = '$capture/$kDenseWorkDirName';
      _guardPath(work);
      if (Directory(work).existsSync()) return null;
    }
    return sparseReadyAt(r);
  }

  ScanResultViewRevision? captureResultViewRevision(ScanRecord record) {
    final ready = resultReadyAt(record);
    if (ready == null) return null;
    return ScanResultViewRevision._(
      record,
      ready,
      _resultViewSignature(record),
    );
  }

  String _resultViewSignature(ScanRecord record) {
    final artifact = record.artifactPath;
    final path = artifact == null
        ? '${record.captureDir}/${sparsePlyFileNameForPipeline(record.pipelineKind)}'
        : (Uri.tryParse(artifact)?.scheme == 'file'
              ? Uri.parse(artifact).toFilePath()
              : artifact);
    _guardPath(path);
    final stat = File(path).statSync();
    return '$path:${stat.type}:${stat.size}:'
        '${stat.modified.microsecondsSinceEpoch}:'
        '${stat.changed.microsecondsSinceEpoch}:${stat.mode}';
  }

  /// [activeReconstructionCaptureDir] = App 当前真的在重建的那个 capture 目录
  /// (没有则 null)—— 用来区分"生成中"和"未完成"。
  ScanProcessingBadge badgeOf(
    ScanRecord r, {
    String? activeReconstructionCaptureDir,
  }) => r.badgeFor(
    resultReadyAt(r),
    isActivelyReconstructing:
        activeReconstructionCaptureDir != null &&
        r.captureDir != null &&
        _matchesActiveCapture(activeReconstructionCaptureDir, r.captureDir!),
  );

  bool _matchesActiveCapture(String activePath, String recordPath) {
    if (_legacyFixture) return _sameDir(activePath, recordPath);
    try {
      _guardPath(activePath);
      String normalized(String path) =>
          _normalizedFilePath(path).replaceFirst(RegExp(r'/+$'), '');
      return normalized(activePath) == normalized(recordPath);
    } catch (_) {
      // A reconstruction retained from a previous account is not activity in
      // this workspace, even when the capture directory names are identical.
      return false;
    }
  }

  /// 容器 UUID 会变,所以按**目录名**比而不是整条绝对路径。
  static bool _sameDir(String a, String b) {
    String tail(String p) {
      final parts = p.split('/').where((e) => e.isNotEmpty).toList();
      return parts.isEmpty ? p : parts.last;
    }

    return tail(a) == tail(b);
  }

  /// 用户点进去看过了 ⇒ 胶囊消失。写"当前 PLY 的落盘时刻"而不是 now:
  /// 若这中间又重新生成过,mtime 会更晚,胶囊仍应重新出现。
  Future<void> markResultViewed(
    ScanRecord r, {
    ScanResultViewRevision? revision,
  }) async {
    // Viewer callers supply the identity captured before their asynchronous
    // load. Never acknowledge a replacement discovered only at callback time.
    final intended = revision ?? captureResultViewRevision(r);
    if (intended == null) return;
    final source = intended.record;
    if (source.id != r.id ||
        source.accountNamespace != r.accountNamespace ||
        source.pipelineKind != r.pipelineKind ||
        source.captureDir != r.captureDir ||
        source.artifactPath != r.artifactPath ||
        source.cloudLibraryRevision != r.cloudLibraryRevision) {
      return;
    }
    final intendedReady = intended.readyAt;
    await ensureLoaded();
    _requireOwner(r);
    await _ensureRouteOwnedPaths(r);
    final previousWrite = _writeLock;
    final completeWrite = Completer<void>();
    _writeLock = completeWrite.future;
    try {
      await previousWrite;
      _ensureWritable();
      // Read after asynchronous validation and queued writes. No yield between
      // this lookup and mutation: a viewer must not restore stale metadata or
      // apply an old revision's acknowledgement to a replacement result.
      final current = byId(r.id);
      if (current == null ||
          current.pipelineKind != r.pipelineKind ||
          current.captureDir != r.captureDir ||
          current.artifactPath != r.artifactPath ||
          current.cloudLibraryRevision != r.cloudLibraryRevision ||
          _isPermanentlyDeleted(r.id, r.pipelineKind)) {
        return;
      }
      final ready = resultReadyAt(current);
      if (ready == null ||
          !ready.isAtSameMomentAs(intendedReady) ||
          _resultViewSignature(current) != intended.fileSignature) {
        return;
      }
      final cur = current.resultViewedAt;
      if (cur != null && !cur.isBefore(ready)) return;
      _records = [
        for (final record in _records)
          record.id == r.id ? current.copyWith(resultViewedAt: ready) : record,
      ];
      _emit();
    } finally {
      completeWrite.complete();
    }
    await _flush();
  }

  /// Merge a real preview cover without restoring stale work metadata. Caller
  /// binds isCurrent to the selected run/stage/artifact and account lifetime.
  Future<bool> attachPreviewThumbnail({
    required ScanRecord expected,
    required String thumbnailPath,
    required bool Function() isCurrent,
    String? finalCoverSha256,
    String? finalCoverGlbSha256,
  }) async {
    await ensureLoaded();
    _requireOwner(expected);
    bool sameSource(ScanRecord? current) =>
        isCurrent() &&
        current != null &&
        current.accountNamespace == expected.accountNamespace &&
        current.pipelineKind == expected.pipelineKind &&
        current.captureDir == expected.captureDir &&
        current.artifactPath == expected.artifactPath &&
        current.cloudLibraryRevision == expected.cloudLibraryRevision &&
        !_isPermanentlyDeleted(expected.id, expected.pipelineKind);
    if (finalCoverSha256 != null || finalCoverGlbSha256 != null) {
      if (finalCoverSha256 == null ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(finalCoverSha256) ||
          finalCoverGlbSha256 != expected.finalGlbSha256 ||
          finalCoverGlbSha256 == null) {
        throw StateError('Final cover proof does not match final GLB');
      }
    }
    final initial = byId(expected.id);
    if (!sameSource(initial)) return false;
    await _ensureRouteOwnedPaths(
      initial!.copyWith(thumbnailPath: thumbnailPath),
    );
    final previousWrite = _writeLock;
    final completeWrite = Completer<void>();
    _writeLock = completeWrite.future;
    var attached = false;
    try {
      await previousWrite;
      _ensureWritable();
      _requireOwner(expected);
      _guardPath(thumbnailPath);
      final durableFile = finalCoverSha256 == null ? null : await _storeFile();
      final current = byId(expected.id);
      if (!sameSource(current)) return false;
      if (FileSystemEntity.typeSync(thumbnailPath, followLinks: false) !=
              FileSystemEntityType.file ||
          File(thumbnailPath).lengthSync() <= 0) {
        return false;
      }
      final next = [
        for (final record in _records)
          record.id == expected.id
              ? current!.copyWith(
                  thumbnailPath: thumbnailPath,
                  finalCoverSha256: finalCoverSha256,
                  finalCoverGlbSha256: finalCoverGlbSha256,
                )
              : record,
      ];
      if (durableFile != null) {
        _guardPath(durableFile.path);
        final staged = File('${durableFile.path}.final-cover-pending');
        _guardPath(staged.path);
        final encoded = jsonEncode(next.map(_recordToJson).toList());
        staged.writeAsStringSync(encoded, flush: true);
        if (staged.readAsStringSync() != encoded) {
          throw StateError('Final cover manifest staging changed');
        }
        staged.renameSync(durableFile.path);
        if (durableFile.readAsStringSync() != encoded) {
          throw StateError('Final cover manifest commit changed');
        }
      }
      _records = next;
      attached = true;
      _emit();
    } finally {
      completeWrite.complete();
    }
    if (attached) {
      if (finalCoverSha256 == null) await _flush();
      if (finalCoverSha256 != null) {
        final persisted =
            jsonDecode(await (await _storeFile()).readAsString()) as List;
        final saved = persisted
            .whereType<Map>()
            .where((r) => r['id'] == expected.id)
            .single;
        if (!sameSource(byId(expected.id)) ||
            saved['thumbnailPath'] != thumbnailPath ||
            saved['finalCoverSha256'] != finalCoverSha256 ||
            saved['finalCoverGlbSha256'] != finalCoverGlbSha256 ||
            saved['finalGlbSha256'] != finalCoverGlbSha256 ||
            (await sha256.bind(File(thumbnailPath).openRead()).first)
                    .toString() !=
                finalCoverSha256) {
          throw StateError('Final cover publication was not durable');
        }
      }
    }
    return attached;
  }

  /// Attach a rendered cover only to the result generation it came from.
  /// Latest metadata is read under the existing write queue, so a long render
  /// cannot restore stale names, cloud metadata or viewed-result state.
  Future<bool> attachFinalMeshThumbnail({
    required ScanResultViewRevision revision,
    required String thumbnailPath,
  }) async {
    final expected = revision.record;
    await ensureLoaded();
    _requireOwner(expected);
    bool sameGeneration(ScanRecord? current) =>
        current != null &&
        current.accountNamespace == expected.accountNamespace &&
        current.pipelineKind == expected.pipelineKind &&
        current.captureDir == expected.captureDir &&
        current.artifactPath != null &&
        current.artifactPath == expected.artifactPath &&
        current.cloudLibraryRevision == expected.cloudLibraryRevision &&
        !_isPermanentlyDeleted(expected.id, expected.pipelineKind);
    final initial = byId(expected.id);
    if (!sameGeneration(initial)) return false;
    await _ensureRouteOwnedPaths(
      initial!.copyWith(thumbnailPath: thumbnailPath),
    );
    final previousWrite = _writeLock;
    final completeWrite = Completer<void>();
    _writeLock = completeWrite.future;
    var attached = false;
    try {
      await previousWrite;
      _ensureWritable();
      _requireOwner(expected);
      _guardPath(thumbnailPath);
      final current = byId(expected.id);
      if (!sameGeneration(current)) return false;
      final ready = resultReadyAt(current!);
      if (ready == null ||
          !ready.isAtSameMomentAs(revision.readyAt) ||
          _resultViewSignature(current) != revision.fileSignature) {
        return false;
      }
      if (FileSystemEntity.typeSync(thumbnailPath, followLinks: false) !=
              FileSystemEntityType.file ||
          File(thumbnailPath).lengthSync() <= 0) {
        return false;
      }
      if (current.thumbnailPath == thumbnailPath) return true;
      _records = [
        for (final record in _records)
          record.id == expected.id
              ? current.copyWith(thumbnailPath: thumbnailPath)
              : record,
      ];
      attached = true;
      _emit();
    } finally {
      completeWrite.complete();
    }
    if (attached) await _flush();
    return attached;
  }

  /// 按 capture 目录标记"看过" —— 给拍摄等待页/续跑等待页用:它们手里只有
  /// captureDir,没有 ScanRecord。按**目录名**匹配(与 [_sameDir] 同一口径,
  /// 容器 UUID 会变,整条绝对路径比不得)。找不到对应记录就静默 no-op。
  ///
  /// [2026-08-24 修] 用户在拍摄等待页看完 refined 点云退出后,"我的"页卡片
  /// 右上角的绿色"完成"胶囊仍然挂着 —— 因为 markResultViewed 此前只挂在
  /// 卡片点击入口上。凡是把稀疏点云真正呈现给用户的路径都该算"看过"。
  Future<void> markResultViewedByCaptureDir(String captureDir) async {
    await ensureLoaded();
    _guardPath(captureDir);
    for (final r in List<ScanRecord>.from(_records)) {
      final dir = r.captureDir;
      if (dir != null &&
          (_legacyFixture
              ? _sameDir(dir, captureDir)
              : _normalizedFilePath(dir) == _normalizedFilePath(captureDir))) {
        await markResultViewed(r);
        return;
      }
    }
  }

  /// 升级迁移:把**已有** PLY 且从没标记过的老记录一次性视为"已看过"。
  ///
  /// [2026-08-06 用户签决] "不需要每次更新完 app 所有项目都显示完成,用户还要
  /// 一个一个点掉。咱们的更新就跟应用商城里一样,不要重置。" —— 升级不该给用户
  /// 造出一堆待处理提示。
  ///
  /// 在 [_load] 的 _emit() 之前 await 调用(时机是关键,见那里的注释)。幂等:
  /// 靠 record 自身是否已有 resultViewedAt 判断,不需要额外的全局版本标记,所以
  /// 反复调用也只会标记新出现的那些。
  Future<void> _markExistingSparseAsViewed() async {
    _checkActive();
    var changed = false;
    for (final r in List<ScanRecord>.from(_records)) {
      if (r.resultViewedAt != null) continue;
      // 177's old sparse-only migration must not silently consume a new GLB
      // that finished off-screen before the next process launch.
      if (r.artifactPath != null) continue;
      final ready = resultReadyAt(r);
      if (ready == null) continue;
      final i = _records.indexWhere((e) => e.id == r.id);
      if (i < 0) continue;
      _records[i] = r.copyWith(resultViewedAt: ready);
      changed = true;
    }
    if (changed) await _flush();
  }

  /// 公开入口(幂等)—— 正常路径由 [_load] 自己调用,这里给测试和兜底用。
  Future<void> migrateExistingSparseAsViewed() => _markExistingSparseAsViewed();

  void requireAvailableName(String id, String name) {
    _checkActive();
    if (name.trim().isEmpty || name.length > 256) {
      throw ArgumentError('Invalid work name');
    }
    final key = workNameKey(name);
    if (_records.any(
      (other) => other.id != id && workNameKey(other.name) == key,
    )) {
      throw DuplicateWorkNameException();
    }
  }

  Future<void> insertNew(ScanRecord r) => addOrUpdate(r, requireNew: true);

  /// Claim a new capture before writing its cover/manifest. A continuation
  /// must refer to the same existing local capture, never merely the same ID.
  Future<ScanRecord> registerCaptureDraft(
    ScanRecord draft, {
    required bool continuing,
  }) async {
    await ensureLoaded();
    if (!continuing) {
      await insertNew(draft);
    } else {
      final existing = byId(draft.id);
      if (existing == null ||
          existing.cloudViewingOnly ||
          existing.pipelineKind != draft.pipelineKind ||
          existing.captureDir != draft.captureDir) {
        throw StateError('Capture does not belong to the existing work');
      }
      _requireOwner(existing);
      await _ensureRouteOwnedPaths(existing);
    }
    _checkActive();
    return byId(draft.id)!;
  }

  Future<void> updateNames(Map<String, String> updates) async {
    await ensureLoaded();
    final next = [
      for (final r in _records) r.copyWith(name: updates[r.id] ?? r.name),
    ];
    final names = <String>{};
    for (final r in next) {
      if (!names.add(workNameKey(r.name))) throw DuplicateWorkNameException();
      if (r.name.trim().isEmpty || r.name.length > 256) {
        throw ArgumentError('Invalid work name');
      }
    }
    _checkActive();
    _records = next;
    _emit();
    await _flush();
  }

  Future<void> addOrUpdate(ScanRecord r, {bool requireNew = false}) async {
    await ensureLoaded();
    _ensureWritable();
    _validateId(r.id);
    if (!_legacyFixture && r.accountNamespace == null) {
      r = ScanRecord(
        id: r.id,
        accountNamespace: account!.namespace,
        name: r.name,
        createdAt: r.createdAt,
        pipelineKind: r.pipelineKind,
        preferredCaptureMode: r.preferredCaptureMode,
        thumbnailPath: r.thumbnailPath,
        artifactPath: r.artifactPath,
        finalGlbSha256: r.finalGlbSha256,
        finalGlbBytes: r.finalGlbBytes,
        captureDir: r.captureDir,
        photosDir: r.photosDir,
        captureManifestPath: r.captureManifestPath,
        photoCount: r.photoCount,
        cloudUploadStatus: r.cloudUploadStatus,
        cloudScanId: r.cloudScanId,
        cloudManifestPath: r.cloudManifestPath,
        cloudWorkId: r.cloudWorkId,
        publicationSubmissionId: r.publicationSubmissionId,
        publicationIdempotencyKey: r.publicationIdempotencyKey,
        publicationStatus: r.publicationStatus,
        publicationTitle: r.publicationTitle,
        publicationDescription: r.publicationDescription,
        cloudLibraryRevision: r.cloudLibraryRevision,
        cloudViewingOnly: r.cloudViewingOnly,
        cloudArtifactPath: r.cloudArtifactPath,
        uploadedFrameCount: r.uploadedFrameCount,
        uploadedAt: r.uploadedAt,
        localRawDeletedAt: r.localRawDeletedAt,
        cloudRawDeletedAt: r.cloudRawDeletedAt,
        cloudUploadFailureMessage: r.cloudUploadFailureMessage,
        resultViewedAt: r.resultViewedAt,
        localRawRetainedForDebug: r.localRawRetainedForDebug,
        authorHandle: r.authorHandle,
        caption: r.caption,
        bundledGlbAsset: r.bundledGlbAsset,
      );
    }
    _requireOwner(r);
    await _ensureRouteOwnedPaths(r);
    _checkActive();
    if (_isPermanentlyDeleted(r.id, r.pipelineKind)) {
      // A native/Dart finalize callback can arrive after the user has
      // confirmed deletion. Never let that late result recreate either the
      // card or its files.
      await _deleteProjectFiles(r);
      return;
    }
    final previous = byId(r.id);
    if (requireNew && previous != null) {
      throw StateError('Work identifier already exists');
    }
    if (requireNew &&
        kUntitledScanNamePattern.hasMatch(r.name) &&
        _records.any(
          (other) => workNameKey(other.name) == workNameKey(r.name),
        )) {
      r = r.copyWith(
        name: nextUntitledScanName(_records.map((other) => other.name.trim())),
      );
    }
    requireAvailableName(r.id, r.name);
    if (previous != null && previous.pipelineKind != r.pipelineKind) {
      throw StateError(
        'Cannot change pipeline kind for existing scan ${r.id}: '
        '${previous.pipelineKind.wireName} -> ${r.pipelineKind.wireName}',
      );
    }
    final next = <ScanRecord>[
      r,
      for (final old in _records)
        if (old.id != r.id) old,
    ];
    _records = _sortNewestFirst(next);
    _emit();
    await _flush();
  }

  /// Look up by id. Returns null if no record matches.
  ScanRecord? byId(String id) {
    if (!isActive) return null;
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Attach a completed local artifact without replacing edits made while a
  /// reconstruction was running. Completion requires the link on disk, because
  /// legacy [_flush] intentionally logs IO errors instead of propagating them.
  Future<void> attachVerifiedLocalArtifact({
    required String id,
    required String captureDir,
    required String artifactPath,
    String? finalGlbSha256,
    int? finalGlbBytes,
  }) async {
    _validateFinalGlbProof(finalGlbSha256, finalGlbBytes);
    await ensureLoaded();
    _ensureWritable();
    final before = byId(id);
    if (before == null ||
        before.captureDir != captureDir ||
        before.artifactPath != null ||
        _isPermanentlyDeleted(id, before.pipelineKind)) {
      throw StateError(
        'Completed artifact must attach to an unchanged existing capture',
      );
    }
    await _ensureRouteOwnedPaths(before.copyWith(artifactPath: artifactPath));
    _ensureWritable();
    _requireOwner(before);
    // Reserve the existing writer queue, but keep completion out of the UI
    // snapshot until the actual manifest has been written and read back.
    final previousWrite = _writeLock;
    final completeWrite = Completer<void>();
    _writeLock = completeWrite.future;
    try {
      await previousWrite;
      _ensureWritable();
      final file = await _storeFile();
      void requireCompletionWrite() {
        _ensureWritable();
        _requireOwner(before);
        _guardPath(file.path);
        _guardPath(captureDir);
        _guardPath(artifactPath);
      }

      while (true) {
        requireCompletionWrite();
        final latest = byId(id);
        if (latest == null ||
            latest.captureDir != captureDir ||
            latest.pipelineKind != before.pipelineKind ||
            latest.artifactPath != null ||
            _isPermanentlyDeleted(id, latest.pipelineKind)) {
          throw StateError(
            'Capture changed while validating completed artifact',
          );
        }
        _requireOwner(latest);
        final originalJson = jsonEncode(_records.map(_recordToJson).toList());
        final next = _sortNewestFirst([
          latest.copyWith(
            artifactPath: artifactPath,
            finalGlbSha256: finalGlbSha256,
            finalGlbBytes: finalGlbBytes,
            clearThumbnailPath:
                latest.thumbnailPath?.contains('/.pw_preview_covers/') == true,
          ),
          for (final old in _records)
            if (old.id != id) old,
        ]);
        final expectedJson = jsonEncode(next.map(_recordToJson).toList());
        requireCompletionWrite();
        final pending = await file.parent.createTemp('.pw38_record_');
        requireCompletionWrite();
        _guardPath(pending.path);
        final staged = File('${pending.path}/scan_records.json');
        _guardPath(staged.path);
        // A same-filesystem rename keeps the previous manifest intact when
        // writing fails. Failed staging files remain available for diagnosis.
        await staged.writeAsString(expectedJson, flush: true);
        requireCompletionWrite();
        _guardPath(staged.path);
        if (await staged.readAsString() != expectedJson) {
          throw StateError('Completed artifact manifest staging changed');
        }
        requireCompletionWrite();
        _guardPath(staged.path);
        // Commit the tiny, same-filesystem manifest without yielding between
        // the final account/path guards and submitting the atomic rename.
        staged.renameSync(file.path);
        requireCompletionWrite();
        if (await file.readAsString() != expectedJson) {
          throw StateError('Completed artifact link was not durably saved');
        }
        requireCompletionWrite();
        _guardPath(pending.path);
        try {
          await pending.delete();
        } catch (e) {
          // The committed manifest is authoritative; empty staging-directory
          // cleanup cannot turn a verified completion into a failed result.
          debugPrint(
            '[ScanRecordStore] completed artifact staging retained: $e',
          );
        }
        requireCompletionWrite();
        // Other existing store operations can edit memory while IO awaits.
        // Rebuild from those edits before publishing, without exposing a
        // speculative artifact link or overwriting the user's latest fields.
        if (jsonEncode(_records.map(_recordToJson).toList()) != originalJson) {
          continue;
        }
        _records = next;
        _emit();
        return;
      }
    } finally {
      completeWrite.complete();
    }
  }

  static void _validateFinalGlbProof(String? hash, int? bytes) {
    if ((hash == null) != (bytes == null) ||
        (hash != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) ||
        (bytes != null && bytes <= 0)) {
      throw ArgumentError(
        'Final GLB proof requires a SHA-256 and positive size',
      );
    }
  }

  /// Retire only metadata after the independently verified artifact is durable
  /// and the caller has already removed the capture. This never deletes data.
  Future<void> retireCaptureMetadataAfterGlbValidation({
    required String id,
    required String captureDir,
    required String artifactPath,
    required String expectedSha256,
    required int expectedBytes,
    PendingCaptureRetirementToken? pendingToken,
  }) async {
    _validateFinalGlbProof(expectedSha256, expectedBytes);
    await ensureLoaded();
    _ensureWritable();
    final before = byId(id);
    File? pendingProofFile;
    String? pendingProofFileSha256;
    var pendingVerified = false;
    // Normalize only the existing parent. The capture leaf may already have
    // been removed by the previous process; never recreate it to recover.
    String canonicalCapture(String raw) {
      final directory = Directory(_normalizedFilePath(raw));
      return '${directory.parent.resolveSymbolicLinksSync()}/${directory.uri.pathSegments.where((p) => p.isNotEmpty).last}';
    }

    if (pendingToken != null) {
      if (before == null ||
          _legacyFixture ||
          account == null ||
          before.pipelineKind != CapturePipelineKind.official) {
        throw StateError(
          'Pending retirement requires an owned official record',
        );
      }
      _requireOwner(before);
      _guardPath(captureDir);
      _guardPath(artifactPath);
      final documents = await _documentsDirectory();
      final canonicalAccount = Directory(
        await documents.resolveSymbolicLinks(),
      );
      final pendingStore = PendingCaptureRetirementStore(
        accountRoot: canonicalAccount,
        accountNamespace: account!.namespace,
        recordId: id,
      );
      final actual = await pendingStore.load(
        requirePublicationAndConsumersDrained: () async {
          _ensureWritable();
          _requireOwner(before);
        },
      );
      if (actual == null ||
          actual.identitySha256 != pendingToken.identitySha256 ||
          actual.accountNamespace != pendingToken.accountNamespace ||
          actual.recordId != pendingToken.recordId ||
          actual.captureRelative != pendingToken.captureRelative ||
          actual.publishedGlbRelative != pendingToken.publishedGlbRelative ||
          actual.finalGlbSha256 != pendingToken.finalGlbSha256 ||
          actual.finalGlbBytes != pendingToken.finalGlbBytes ||
          actual.accountNamespace != account!.namespace ||
          actual.recordId != id ||
          pendingStore.captureRootFor(actual).path !=
              canonicalCapture(captureDir) ||
          pendingStore.publishedGlbFor(actual).path !=
              await File(
                _normalizedFilePath(artifactPath),
              ).resolveSymbolicLinks() ||
          actual.finalGlbSha256 != expectedSha256 ||
          actual.finalGlbBytes != expectedBytes) {
        throw StateError(
          'Persisted pending retirement does not match this record',
        );
      }
      // Preserve the record-id capture namespace enforced by normal Store IO.
      if (actual.captureRelative != 'captures_official/$id') {
        throw StateError('Pending capture is outside this record namespace');
      }
      pendingProofFile = File(
        '${canonicalAccount.path}/.pw_capture_retirement/$id.json',
      );
      _guardPath(pendingProofFile.path);
      pendingProofFileSha256 = sha256
          .convert(await pendingProofFile.readAsBytes())
          .toString();
      pendingVerified = true;
    }
    bool captureIdentityMatches(ScanRecord record) {
      if (record.captureDir == captureDir) return true;
      if (!pendingVerified) return false;
      if (record.captureDir == null) return true;
      return canonicalCapture(record.captureDir!) ==
          canonicalCapture(captureDir);
    }

    if (before == null ||
        !captureIdentityMatches(before) ||
        before.artifactPath != artifactPath ||
        before.finalGlbSha256 != expectedSha256 ||
        before.finalGlbBytes != expectedBytes ||
        _isPermanentlyDeleted(id, before.pipelineKind)) {
      throw StateError('Final GLB proof does not match this capture record');
    }
    _requireOwner(before);
    await _ensureRouteOwnedPaths(before);
    _ensureWritable();
    _guardPath(artifactPath);
    final artifact = File(_normalizedFilePath(artifactPath));
    if (await artifact.length() != expectedBytes ||
        (await sha256.bind(artifact.openRead()).first).toString() !=
            expectedSha256) {
      throw StateError('Final GLB bytes no longer match the completion proof');
    }
    _ensureWritable();
    // Reserve the existing writer queue, but keep completion out of the UI
    // snapshot until the actual manifest has been written and read back.
    final previousWrite = _writeLock;
    final completeWrite = Completer<void>();
    _writeLock = completeWrite.future;
    try {
      await previousWrite;
      _ensureWritable();
      final file = await _storeFile();
      void requireCompletionWrite() {
        _ensureWritable();
        _requireOwner(before);
        _guardPath(file.path);
        _guardPath(captureDir);
        _guardPath(artifactPath);
        if (pendingProofFile != null) {
          _guardPath(pendingProofFile.path);
          if (FileSystemEntity.typeSync(
                    pendingProofFile.path,
                    followLinks: false,
                  ) !=
                  FileSystemEntityType.file ||
              sha256.convert(pendingProofFile.readAsBytesSync()).toString() !=
                  pendingProofFileSha256) {
            throw StateError(
              'Pending retirement token changed during record commit',
            );
          }
        }
        if (FileSystemEntity.typeSync(captureDir, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw StateError('Capture still exists; metadata cannot be retired');
        }
      }

      while (true) {
        requireCompletionWrite();
        final latest = byId(id);
        if (latest == null ||
            !captureIdentityMatches(latest) ||
            latest.pipelineKind != before.pipelineKind ||
            latest.artifactPath != artifactPath ||
            latest.finalGlbSha256 != expectedSha256 ||
            latest.finalGlbBytes != expectedBytes ||
            _isPermanentlyDeleted(id, latest.pipelineKind)) {
          throw StateError(
            'Capture changed while validating completed artifact',
          );
        }
        _requireOwner(latest);
        final originalJson = jsonEncode(_records.map(_recordToJson).toList());
        final next = _sortNewestFirst([
          _withoutCaptureMetadata(latest).copyWith(
            localRawDeletedAt: latest.localRawDeletedAt ?? DateTime.now(),
          ),
          for (final old in _records)
            if (old.id != id) old,
        ]);
        final expectedJson = jsonEncode(next.map(_recordToJson).toList());
        requireCompletionWrite();
        final pending = await file.parent.createTemp('.pw38_record_');
        requireCompletionWrite();
        _guardPath(pending.path);
        final staged = File('${pending.path}/scan_records.json');
        _guardPath(staged.path);
        // A same-filesystem rename keeps the previous manifest intact when
        // writing fails. Failed staging files remain available for diagnosis.
        await staged.writeAsString(expectedJson, flush: true);
        requireCompletionWrite();
        _guardPath(staged.path);
        if (await staged.readAsString() != expectedJson) {
          throw StateError('Completed artifact manifest staging changed');
        }
        requireCompletionWrite();
        _guardPath(staged.path);
        // Commit the tiny, same-filesystem manifest without yielding between
        // the final account/path guards and submitting the atomic rename.
        staged.renameSync(file.path);
        requireCompletionWrite();
        if (await file.readAsString() != expectedJson) {
          throw StateError('Completed artifact link was not durably saved');
        }
        requireCompletionWrite();
        try {
          await pending.delete();
        } catch (e) {
          debugPrint('[ScanRecordStore] retirement staging retained: $e');
        }
        requireCompletionWrite();
        // Other existing store operations can edit memory while IO awaits.
        // Rebuild from those edits before publishing, without exposing a
        // speculative artifact link or overwriting the user's latest fields.
        if (jsonEncode(_records.map(_recordToJson).toList()) != originalJson) {
          continue;
        }
        _records = next;
        _emit();
        return;
      }
    } finally {
      completeWrite.complete();
    }
  }

  /// Permanently delete one complete user project.
  ///
  /// The opaque tombstone is persisted first so an interrupted delete or a
  /// late reconstruction writer cannot make the project reappear through
  /// orphan recovery. All files in the route-owned capture namespace
  /// The record is then dropped from the list and the manifest flushed, so the
  /// card disappears immediately (see the ordering note inside). Only after
  /// that are the route-owned capture files (photos, metadata, databases,
  /// point clouds, caches) and scan artifacts removed.
  Future<void> delete(String id) async {
    await ensureLoaded();
    _ensureWritable();
    _validateId(id);
    final record = byId(id);
    if (record == null) return;
    await _addDeletionTombstone(record);
    _checkActive();
    // [2026-08-08 用户实机指认] "删除一个项目的时候,项目卡片没有直接消失,而且先
    // 显示了'未完成'状态几秒,然后再消失。我需要直接立刻消失。"
    //
    // 🔴 顺序是关键,别改回去:记录必须在**碰文件之前**就从列表里消失。原先是
    // 先 _deleteProjectFiles 再移除记录 —— 而 `_deleteProjectFiles` 要删掉照片、
    // 数据库、点云,几百 MB 时能跑好几秒;这段窗口里记录还在列表上,但 PLY 已经
    // 被删了,于是 badgeOf → sparseReadyAt 返回 null → 胶囊算成红色"未完成"
    // (草稿页每 2 秒轮询一次,正好把这个中间态显示出来)。
    //
    // 提前移除是安全的:墓碑上面已经落盘了,所以即使删文件中途 App 被杀,orphan
    // recovery 也不会让这个项目复活(见 _addDeletionTombstone 的注释)。先 flush
    // 清单再删文件,反而让"重启后不复现"更稳。
    _records = _records.where((r) => r.id != id).toList(growable: false);
    _emit();
    await _flush();
    await _deleteProjectFiles(record);
  }

  Future<void> _deleteProjectFiles(ScanRecord record) async {
    _checkActive();
    _requireOwner(record);
    await _ensureRouteOwnedPaths(record);
    final routeRoot = await _capturesRoot(pipelineKind: record.pipelineKind);
    final canonicalCaptureDir = await captureDirFor(
      record.id,
      pipelineKind: record.pipelineKind,
    );
    final captureDirs = <String>{canonicalCaptureDir.path};
    final storedCaptureDir = record.captureDir;
    if (storedCaptureDir != null &&
        _isWithinDirectory(storedCaptureDir, routeRoot.path)) {
      captureDirs.add(storedCaptureDir);
    }
    for (final path in captureDirs) {
      _guardPath(path);
      final captureDir = Directory(path);
      if (await captureDir.exists()) {
        _guardPath(path);
        await captureDir.delete(recursive: true);
        _checkActive();
      }
    }

    final scansDir = await _scansDir(pipelineKind: record.pipelineKind);
    if (!await scansDir.exists()) return;
    await for (final entity in scansDir.list(followLinks: false)) {
      _checkActive();
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .lastOrNull;
      if (name == null ||
          (name != record.id && !name.startsWith('${record.id}.'))) {
        continue;
      }
      _guardPath(entity.path);
      await entity.delete(recursive: entity is Directory);
      _checkActive();
    }
  }

  Future<void> _addDeletionTombstone(ScanRecord record) async {
    final next = <String>{
      ..._deletionTombstones,
      _deletionHash(record.id, record.pipelineKind),
    };
    final file = await _deletionTombstoneFile();
    _guardPath(file.path);
    await file.writeAsString(jsonEncode(next.toList()..sort()), flush: true);
    _checkActive();
    _deletionTombstones = next;
  }

  Future<Set<String>> _loadDeletionTombstones() async {
    final file = await _deletionTombstoneFile();
    if (!await file.exists()) return const <String>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) {
      throw const FormatException('deletion tombstones must be a JSON list');
    }
    final hashes = <String>{};
    for (final value in decoded) {
      if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
        throw const FormatException('invalid deletion tombstone hash');
      }
      hashes.add(value);
    }
    return hashes;
  }

  bool _isPermanentlyDeleted(String id, CapturePipelineKind pipelineKind) {
    return _deletionTombstones.contains(_deletionHash(id, pipelineKind));
  }

  static String _deletionHash(String id, CapturePipelineKind pipelineKind) {
    final bytes = utf8.encode(
      'pocketworld.project-deletion.v1:${pipelineKind.wireName}:$id',
    );
    return sha256.convert(bytes).toString();
  }

  /// Where on disk to persist `<id>.glb` for a given record. W3 (待实现)
  /// will write the local-generated GLB here.
  Future<File> glbFileFor(
    String id, {
    CapturePipelineKind pipelineKind = CapturePipelineKind.self,
  }) async {
    _checkActive();
    _validateId(id);
    final dir = await _scansDir(pipelineKind: pipelineKind);
    final file = File('${dir.path}/$id.glb');
    _guardPath(file.path);
    return file;
  }

  Future<Directory> captureDirFor(
    String id, {
    CapturePipelineKind pipelineKind = CapturePipelineKind.self,
  }) async {
    _checkActive();
    _validateId(id);
    final root = await _capturesRoot(pipelineKind: pipelineKind);
    final directory = Directory('${root.path}/$id');
    _guardPath(directory.path);
    return directory;
  }

  static Future<void> _captureCreationTail = Future<void>.value();

  /// New capture creation never wipes an existing project. Serialize local
  /// creation and reject collisions across both capture routes and artifacts.
  Future<Directory> createCaptureDirectory({
    CapturePipelineKind pipelineKind = CapturePipelineKind.self,
  }) {
    final pending = _captureCreationTail.then((_) async {
      await ensureLoaded();
      for (var attempt = 0; attempt < 8; attempt++) {
        final id = _captureIdentifier();
        _validateId(id);
        if (byId(id) != null ||
            _isPermanentlyDeleted(id, CapturePipelineKind.self) ||
            _isPermanentlyDeleted(id, CapturePipelineKind.official)) {
          continue;
        }
        var occupied = false;
        for (final route in CapturePipelineKind.values) {
          for (final path in [
            (await captureDirFor(id, pipelineKind: route)).path,
            (await thumbnailFileFor(id, pipelineKind: route)).path,
            (await glbFileFor(id, pipelineKind: route)).path,
          ]) {
            await requireOwnedPath(path);
            if (await FileSystemEntity.type(path, followLinks: false) !=
                FileSystemEntityType.notFound) {
              occupied = true;
            }
          }
        }
        if (occupied) continue;
        final parent = await _capturesRoot(pipelineKind: pipelineKind);
        await requireOwnedPath(parent.path);
        await parent.create(recursive: true);
        await requireOwnedPath(parent.path);
        if (_captureCreationCheckpoint != null) {
          await _captureCreationCheckpoint(id);
        }
        _checkActive();
        // SDK/OS exclusive unique creation, rather than check-then-mkdir.
        // Its suffix is part of the permanent opaque ID; UUIDv4 stays intact.
        final root = await parent.createTemp('$id-');
        _checkActive();
        final allocatedId = root.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last;
        _validateId(allocatedId);
        var allocatedConflict =
            byId(allocatedId) != null ||
            _isPermanentlyDeleted(allocatedId, CapturePipelineKind.self) ||
            _isPermanentlyDeleted(allocatedId, CapturePipelineKind.official);
        for (final route in CapturePipelineKind.values) {
          for (final path in [
            if (route != pipelineKind)
              (await captureDirFor(allocatedId, pipelineKind: route)).path,
            (await thumbnailFileFor(allocatedId, pipelineKind: route)).path,
            (await glbFileFor(allocatedId, pipelineKind: route)).path,
          ]) {
            await requireOwnedPath(path);
            if (await FileSystemEntity.type(path, followLinks: false) !=
                FileSystemEntityType.notFound) {
              allocatedConflict = true;
            }
          }
        }
        _checkActive();
        if (allocatedConflict) continue; // Keep even unused directories intact.
        return root;
      }
      throw StateError('Unable to allocate a new work identifier');
    });
    _captureCreationTail = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return pending;
  }

  Future<Directory> _capturesRoot({
    required CapturePipelineKind pipelineKind,
  }) async {
    final root = await _documentsDirectory();
    final directoryName = pipelineKind == CapturePipelineKind.official
        ? 'captures_official'
        : 'captures';
    final directory = Directory('${root.path}/$directoryName');
    _guardPath(directory.path);
    return directory;
  }

  /// Where on disk to persist the scan card's cover thumbnail. Plan G
  /// W2 全本地 (2026-05-16) — a future Drafts UI revamp can populate
  /// this from the first cell-admitted JPEG in `<captureDir>/photos/`.
  Future<File> thumbnailFileFor(
    String id, {
    CapturePipelineKind pipelineKind = CapturePipelineKind.self,
  }) async {
    _checkActive();
    _validateId(id);
    final dir = await _scansDir(pipelineKind: pipelineKind);
    final file = File('${dir.path}/$id.jpg');
    _guardPath(file.path);
    return file;
  }

  Future<Directory> _scansDir({
    required CapturePipelineKind pipelineKind,
  }) async {
    final root = await _documentsDirectory();
    final directoryName = pipelineKind == CapturePipelineKind.official
        ? 'scans_official'
        : 'scans';
    final dir = Directory('${root.path}/$directoryName');
    _guardPath(dir.path);
    if (!await dir.exists()) {
      _guardPath(dir.path);
      await dir.create(recursive: true);
    }
    _guardPath(dir.path);
    return dir;
  }

  Future<File> _storeFile() async {
    final root = await _documentsDirectory();
    final file = File('${root.path}/scan_records.json');
    _guardPath(file.path);
    return file;
  }

  Future<File> _deletionTombstoneFile() async {
    final root = await _documentsDirectory();
    final file = File('${root.path}/scan_record_deletion_tombstones.json');
    _guardPath(file.path);
    return file;
  }

  /// Capture allocation and account-specific auxiliary storage share this root.
  Future<Directory> accountDocumentsDirectory() => _documentsDirectory();

  /// For viewers, resume and upload callers holding an originating store.
  Future<void> requireOwnedPath(String path) async {
    await _documentsDirectory();
    _guardPath(path);
  }

  Future<Directory> _documentsDirectory() async {
    _checkActive();
    var root = _resolvedDocumentsDirectory;
    if (root == null) {
      final base =
          _documentsDirectoryOverride ??
          await getApplicationDocumentsDirectory();
      _checkActive();
      _baseDocumentsDirectory = base.absolute;
      root = _legacyFixture
          ? base
          : Directory('${base.path}/accounts/v1/${account!.namespace}');
      _resolvedDocumentsDirectory = root;
    }
    _guardPath(root.path);
    if (!await root.exists()) {
      _guardPath(root.path);
      await root.create(recursive: true);
    }
    _guardPath(root.path);
    return root;
  }

  void _checkActive() {
    if (!isActive) throw StateError('Account workspace is locked or revoked');
  }

  void _validateId(String id) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Unsafe scan identifier');
    }
  }

  void _requireOwner(ScanRecord record) {
    _checkActive();
    _validateId(record.id);
    if (!_legacyFixture && record.accountNamespace != account!.namespace) {
      throw StateError('Record belongs to a different account workspace');
    }
  }

  static String _safeAbsolutePath(String rawPath) {
    final String path;
    try {
      final decoded = rawPath.startsWith('file://')
          ? Uri.decodeComponent(rawPath.substring(7))
          : rawPath;
      if (decoded.split('/').any((part) => part == '.' || part == '..')) {
        throw StateError('Traversal is not allowed in account storage');
      }
      path = rawPath.startsWith('file://')
          ? Uri.parse(rawPath).toFilePath()
          : rawPath;
    } catch (_) {
      throw StateError('Invalid local file path');
    }
    if (!path.startsWith('/') ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        path.split('/').any((segment) => segment == '..' || segment == '.')) {
      throw StateError('Unsafe local file path');
    }
    return path;
  }

  void _guardPath(String rawPath) {
    _checkActive();
    if (_legacyFixture) return;
    var path = _safeAbsolutePath(rawPath);
    final root = _resolvedDocumentsDirectory;
    final base = _baseDocumentsDirectory;
    // Native/full38 IO resolves the OS alias above Documents (for example
    // /var -> /private/var on iOS). Rebase only that known Documents prefix;
    // never resolve caller-controlled descendants, which must still pass the
    // account boundary and per-component symlink checks below.
    if (base != null && base.existsSync()) {
      final canonicalBase = base.resolveSymbolicLinksSync();
      if (_isWithinDirectory(path, canonicalBase)) {
        path = '${base.path}${path.substring(canonicalBase.length)}';
      }
    }
    if (root == null || base == null || !_isWithinDirectory(path, root.path)) {
      throw StateError('Path belongs to a different account workspace');
    }
    // Do not follow a link anywhere below Documents, including accounts/v1,
    // the account directory itself, indexes, and not-yet-created leaf paths.
    var cursor = base.path;
    final relative = _normalizedFilePath(
      path,
    ).substring(_normalizedFilePath(base.path).length);
    for (final segment in relative.split('/').where((s) => s.isNotEmpty)) {
      cursor = '$cursor/$segment';
      if (FileSystemEntity.typeSync(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Symbolic links are not allowed in account storage');
      }
    }
  }

  ScanRecord _reanchorAccountPaths(ScanRecord record) {
    final json = _recordToJson(record);
    for (final key in const [
      'thumbnailPath',
      'artifactPath',
      'captureDir',
      'photosDir',
      'captureManifestPath',
    ]) {
      final value = json[key] as String?;
      if (value == null || value.isEmpty) continue;
      final path = _safeAbsolutePath(value);
      if (_isWithinDirectory(path, _resolvedDocumentsDirectory!.path)) {
        _guardPath(path);
        continue;
      }
      // Only the same explicit namespace can survive an iOS sandbox UUID
      // change. Never reinterpret an unscoped or another account's path.
      final marker = '/accounts/v1/${account!.namespace}/';
      final offset = path.indexOf(marker);
      if (offset < 0 ||
          path.indexOf('/accounts/v1/') != offset ||
          path.indexOf('/accounts/', offset + 1) >= 0) {
        throw StateError('Stored path belongs to a different account');
      }
      final anchored =
          '${_resolvedDocumentsDirectory!.path}/'
          '${path.substring(offset + marker.length)}';
      _guardPath(anchored);
      json[key] = value.startsWith('file://') ? 'file://$anchored' : anchored;
    }
    return _recordFromJson(json);
  }

  static bool _crossesPipelineNamespace(
    String rawPath, {
    required CapturePipelineKind pipelineKind,
  }) {
    final path = rawPath.startsWith('file://') ? rawPath.substring(7) : rawPath;
    final segments = path
        .split(RegExp(r'[/\\]+'))
        .where((segment) => segment.isNotEmpty)
        .toSet();
    final otherRouteDirectories = pipelineKind == CapturePipelineKind.official
        ? const <String>{'scans', 'captures'}
        : const <String>{'scans_official', 'captures_official'};
    return segments.any(otherRouteDirectories.contains);
  }

  Future<void> _ensureRouteOwnedPaths(ScanRecord record) async {
    _requireOwner(record);
    final paths = <String?>[record.thumbnailPath, record.artifactPath];
    for (final path in paths) {
      if (path == null || path.isEmpty) continue;
      _guardPath(path);
      if (_crossesPipelineNamespace(path, pipelineKind: record.pipelineKind)) {
        throw StateError(
          'Scan ${record.id} (${record.pipelineKind.wireName}) references '
          'an artifact owned by the other pipeline: $path',
        );
      }
    }

    final captureRoot = await _capturesRoot(pipelineKind: record.pipelineKind);
    final capturePaths = <String?>[
      record.captureDir,
      record.photosDir,
      record.captureManifestPath,
    ];
    for (final path in capturePaths) {
      if (path == null || path.isEmpty) continue;
      _guardPath(path);
      if (_crossesPipelineNamespace(path, pipelineKind: record.pipelineKind) ||
          !_isWithinDirectory(
            path,
            _legacyFixture
                ? captureRoot.path
                : '${captureRoot.path}/${record.id}',
          )) {
        throw StateError(
          'Scan ${record.id} (${record.pipelineKind.wireName}) references '
          'capture metadata outside its route-owned namespace: $path',
        );
      }
    }
    _checkActive();
  }

  static bool _isWithinDirectory(String rawPath, String rawRoot) {
    final path = _normalizedFilePath(rawPath);
    final root = _normalizedFilePath(rawRoot);
    return path == root || path.startsWith('$root${Platform.pathSeparator}');
  }

  static String _normalizedFilePath(String rawPath) {
    final path = rawPath.startsWith('file://')
        ? Uri.parse(rawPath).toFilePath()
        : File(rawPath).absolute.path;
    return Uri.file(path).normalizePath().toFilePath();
  }

  static ScanRecord _withoutCaptureMetadata(ScanRecord record) {
    final json = _recordToJson(record)
      ..remove('captureDir')
      ..remove('photosDir')
      ..remove('captureManifestPath');
    return _recordFromJson(json);
  }

  void _ensureWritable() {
    _checkActive();
    final failure = _loadFailure;
    if (failure != null) {
      if (failure is LegacyScanRecordImportException) throw failure;
      throw StateError(
        'scan_records.json failed validation; refusing to overwrite it: '
        '$failure',
      );
    }
  }

  void _emit() {
    if (!_ctrl.isClosed) _ctrl.add(records);
  }

  Future<void> _flush() async {
    // Serialize writes — two concurrent updates would otherwise race
    // on the JSON file.
    final last = _writeLock;
    final completer = Completer<void>();
    _writeLock = completer.future;
    try {
      await last;
      _ensureWritable();
      final file = await _storeFile();
      final json = jsonEncode(_records.map(_recordToJson).toList());
      _guardPath(file.path);
      await file.writeAsString(json, flush: true);
      _checkActive();
    } catch (e, st) {
      debugPrint('[ScanRecordStore] flush failed: $e\n$st');
      if (!_legacyFixture) rethrow;
    } finally {
      completer.complete();
    }
  }

  static List<ScanRecord> _sortNewestFirst(List<ScanRecord> rs) {
    final out = [...rs]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  // ─── (de)serialization ──────────────────────────────────────────────

  static Map<String, dynamic> _recordToJson(ScanRecord r) => <String, dynamic>{
    'id': r.id,
    if (r.accountNamespace != null) 'accountNamespace': r.accountNamespace,
    'name': r.name,
    'createdAt': r.createdAt.toIso8601String(),
    'pipeline_kind': r.pipelineKind.wireName,
    if (r.preferredCaptureMode != CaptureMode.local)
      'preferredCaptureMode': r.preferredCaptureMode.name,
    if (r.resultViewedAt != null)
      'resultViewedAt': r.resultViewedAt!.toIso8601String(),
    if (r.thumbnailPath != null) 'thumbnailPath': r.thumbnailPath,
    if (r.finalCoverSha256 != null) 'finalCoverSha256': r.finalCoverSha256,
    if (r.finalCoverGlbSha256 != null)
      'finalCoverGlbSha256': r.finalCoverGlbSha256,
    if (r.artifactPath != null) 'artifactPath': r.artifactPath,
    if (r.finalGlbSha256 != null) 'finalGlbSha256': r.finalGlbSha256,
    if (r.finalGlbBytes != null) 'finalGlbBytes': r.finalGlbBytes,
    if (r.captureDir != null) 'captureDir': r.captureDir,
    if (r.photosDir != null) 'photosDir': r.photosDir,
    if (r.captureManifestPath != null)
      'captureManifestPath': r.captureManifestPath,
    if (r.photoCount != null) 'photoCount': r.photoCount,
    if (r.cloudUploadStatus != ScanCloudUploadStatus.none)
      'cloudUploadStatus': r.cloudUploadStatus.wireName,
    if (r.cloudScanId != null) 'cloudScanId': r.cloudScanId,
    if (r.cloudManifestPath != null) 'cloudManifestPath': r.cloudManifestPath,
    if (r.cloudWorkId != null) 'cloudWorkId': r.cloudWorkId,
    if (r.publicationSubmissionId != null)
      'publicationSubmissionId': r.publicationSubmissionId,
    if (r.publicationIdempotencyKey != null)
      'publicationIdempotencyKey': r.publicationIdempotencyKey,
    if (r.publicationStatus != null) 'publicationStatus': r.publicationStatus,
    if (r.publicationTitle != null) 'publicationTitle': r.publicationTitle,
    if (r.publicationDescription != null)
      'publicationDescription': r.publicationDescription,
    if (r.cloudLibraryRevision != null)
      'cloudLibraryRevision': r.cloudLibraryRevision,
    if (r.cloudViewingOnly) 'cloudViewingOnly': true,
    if (r.cloudArtifactPath != null) 'cloudArtifactPath': r.cloudArtifactPath,
    if (r.uploadedFrameCount != null)
      'uploadedFrameCount': r.uploadedFrameCount,
    if (r.uploadedAt != null) 'uploadedAt': r.uploadedAt!.toIso8601String(),
    if (r.localRawDeletedAt != null)
      'localRawDeletedAt': r.localRawDeletedAt!.toIso8601String(),
    if (r.cloudRawDeletedAt != null)
      'cloudRawDeletedAt': r.cloudRawDeletedAt!.toIso8601String(),
    if (r.cloudUploadFailureMessage != null)
      'cloudUploadFailureMessage': r.cloudUploadFailureMessage,
    if (r.localRawRetainedForDebug)
      'localRawRetainedForDebug': r.localRawRetainedForDebug,
    if (r.caption != null) 'caption': r.caption,
    // Plan G W2 全本地 (2026-05-16): jobStatus / jobId / pipelineStage
    // / publishedWorkId / videoSizeBytes / failureMessage were
    // cloud-lifecycle fields. Legacy on-disk records that still have
    // those keys are dropped silently by `_recordFromJson`.
  };

  static ScanRecord _recordFromJson(Map<String, dynamic> j) {
    _validateFinalGlbProof(
      j['finalGlbSha256'] as String?,
      j['finalGlbBytes'] as int?,
    );
    final captureModeName = j['preferredCaptureMode'] as String?;
    final pipelineKind = j.containsKey('pipeline_kind')
        ? CapturePipelineKindWire.fromWireName(j['pipeline_kind'])
        : CapturePipelineKind.self;
    return ScanRecord(
      id: j['id'] as String,
      accountNamespace: j['accountNamespace'] as String?,
      name: j['name'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      pipelineKind: pipelineKind,
      preferredCaptureMode: captureModeName == null
          ? CaptureMode.local
          : CaptureMode.values.firstWhere(
              (m) => m.name == captureModeName,
              orElse: () => CaptureMode.local,
            ),
      resultViewedAt: j['resultViewedAt'] == null
          ? null
          : DateTime.tryParse(j['resultViewedAt'] as String),
      thumbnailPath: j['thumbnailPath'] as String?,
      finalCoverSha256: j['finalCoverSha256'] as String?,
      finalCoverGlbSha256: j['finalCoverGlbSha256'] as String?,
      artifactPath: j['artifactPath'] as String?,
      finalGlbSha256: j['finalGlbSha256'] as String?,
      finalGlbBytes: j['finalGlbBytes'] as int?,
      captureDir: j['captureDir'] as String?,
      photosDir: j['photosDir'] as String?,
      captureManifestPath: j['captureManifestPath'] as String?,
      photoCount: (j['photoCount'] as num?)?.toInt(),
      cloudUploadStatus: ScanCloudUploadStatusWire.fromWireName(
        j['cloudUploadStatus'] as String?,
      ),
      cloudScanId: j['cloudScanId'] as String?,
      cloudManifestPath: j['cloudManifestPath'] as String?,
      cloudWorkId: j['cloudWorkId'] as String?,
      publicationSubmissionId: j['publicationSubmissionId'] as String?,
      publicationIdempotencyKey: j['publicationIdempotencyKey'] as String?,
      publicationStatus: j['publicationStatus'] as String?,
      publicationTitle: j['publicationTitle'] as String?,
      publicationDescription: j['publicationDescription'] as String?,
      cloudLibraryRevision: j['cloudLibraryRevision'] as String?,
      cloudViewingOnly: j['cloudViewingOnly'] == true,
      cloudArtifactPath: j['cloudArtifactPath'] as String?,
      uploadedFrameCount: (j['uploadedFrameCount'] as num?)?.toInt(),
      uploadedAt: DateTime.tryParse(j['uploadedAt'] as String? ?? ''),
      localRawDeletedAt: DateTime.tryParse(
        j['localRawDeletedAt'] as String? ?? '',
      ),
      cloudRawDeletedAt: DateTime.tryParse(
        j['cloudRawDeletedAt'] as String? ?? '',
      ),
      cloudUploadFailureMessage: j['cloudUploadFailureMessage'] as String?,
      localRawRetainedForDebug:
          (j['localRawRetainedForDebug'] as bool?) ?? false,
      caption: j['caption'] as String?,
      // Plan G W2 全本地 (2026-05-16): legacy records may still have
      // `jobStatus`, `jobId`, `pipelineStage`, `publishedWorkId`,
      // `videoSizeBytes`, `failureMessage`, `videoFilePath`,
      // `curatedManifestPath` keys from the cloud-upload era. All
      // dropped silently here.
    );
  }
}
