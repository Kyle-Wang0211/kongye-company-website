import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../dense/dense_stage_progress.dart';
import '../dense/dense_work_state.dart';
import '../official_capture/selection_box.dart' show kSelectionBoxFileName;
import '../point_cloud_lod/dense_lod_cache.dart';
import '../pw38/final_artifact_completion.dart';
import '../ui/scan_record.dart';
import 'scan_record_store.dart';

const int kCloudLibraryJsonMaxBytes = 1048576;

/// A paired final proof replaces capture-backed cloud viewing materials. An
/// invalid or partial proof is an error, never permission to fall back to raw
/// reconstruction inputs that are being retired.
Future<bool> verifyCloudFinalArtifact(
  ScanRecordStore store,
  ScanRecord record,
) async {
  if (record.finalGlbSha256 == null && record.finalGlbBytes == null) {
    return false;
  }
  if (!store.isActive ||
      store.account == null ||
      record.accountNamespace != store.account!.namespace ||
      record.finalGlbSha256 == null ||
      record.finalGlbBytes == null ||
      record.artifactPath == null) {
    throw StateError('Cloud final artifact requires an active owned proof');
  }
  final root = await store.accountDocumentsDirectory();
  final uri = Uri.tryParse(record.artifactPath!);
  final path = uri != null && uri.scheme == 'file'
      ? uri.toFilePath()
      : record.artifactPath!;
  // The store rejects symlinks below Documents before resolving the trusted
  // platform alias above it (/var -> /private/var on Apple platforms).
  await store.requireOwnedPath(path);
  await verifyPw38FinalArtifactCompletion(
    accountDocuments: Directory(await root.resolveSymbolicLinks()),
    accountNamespace: store.account!.namespace,
    recordId: record.id,
    artifactPath: await File(path).resolveSymbolicLinks(),
    expectedBytes: record.finalGlbBytes!,
    expectedSha256: record.finalGlbSha256!,
  );
  if (!store.isActive) throw StateError('Cloud final artifact account changed');
  return true;
}

/// Metadata has its own small bound, independent of binary transfer limits.
/// The bounded read also prevents a growing file from allocating an unbounded
/// string between the initial length check and JSON decoding.
Object? readCloudLibraryJson(File file) {
  final input = file.openSync();
  try {
    if (input.lengthSync() > kCloudLibraryJsonMaxBytes) {
      throw const CloudLibraryPayloadException('Cloud metadata is too large.');
    }
    final bytes = input.readSync(kCloudLibraryJsonMaxBytes + 1);
    if (bytes.length > kCloudLibraryJsonMaxBytes ||
        input.lengthSync() > kCloudLibraryJsonMaxBytes) {
      throw const CloudLibraryPayloadException('Cloud metadata is too large.');
    }
    return jsonDecode(utf8.decode(bytes));
  } finally {
    input.closeSync();
  }
}

/// Only authenticated deployment capabilities may raise a regional limit.
/// Binary descriptors can represent the absolute ceiling; transfers must also
/// enforce the deployment limit and the supported upload transport limit.
class CloudLibraryLimits {
  const CloudLibraryLimits._(this.maxFileBytes, this.maxTotalBytes);
  static const legacy = CloudLibraryLimits._(50000000, 1000000000);
  static const absoluteMaxBytes = 1000000000;
  // The pinned TUS transport reads at most one 6 MiB file chunk. Authenticated
  // server capabilities remain authoritative; legacy international storage
  // retains its 50 MB deployment ceiling.
  static const supportedUploadMaxBytes = absoluteMaxBytes;
  final int maxFileBytes;
  final int maxTotalBytes;
  int get maxUploadFileBytes => maxFileBytes < supportedUploadMaxBytes
      ? maxFileBytes
      : supportedUploadMaxBytes;

  factory CloudLibraryLimits.fromCapabilities(Object? value) {
    if (value is! Map ||
        value['max_file_bytes'] is! int ||
        value['max_total_bytes'] is! int) {
      throw const FormatException('Invalid cloud library capabilities');
    }
    final file = value['max_file_bytes'] as int;
    final total = value['max_total_bytes'] as int;
    if (file <= 0 ||
        total <= 0 ||
        file > total ||
        file > absoluteMaxBytes ||
        total > absoluteMaxBytes) {
      throw const FormatException('Invalid cloud library capabilities');
    }
    return CloudLibraryLimits._(file, total);
  }

  void requireAsset(CloudLibraryAsset asset, {bool upload = false}) {
    CloudLibraryAsset.fromJson(asset.toJson());
    if (asset.bytes > (upload ? maxUploadFileBytes : maxFileBytes) ||
        asset.bytes > maxTotalBytes) {
      throw const CloudLibraryPayloadException(
        'Viewing file exceeds the supported cloud file limit. Originals are retained.',
      );
    }
  }

  void requireAssets(List<CloudLibraryAsset> assets, {bool upload = false}) {
    var total = 0;
    for (final asset in assets) {
      requireAsset(asset, upload: upload);
      total += asset.bytes;
      if (total > maxTotalBytes) {
        throw const CloudLibraryPayloadException(
          'Viewing files exceed the cloud storage limit. Originals are retained.',
        );
      }
    }
  }
}

class CloudLibraryPayloadException implements Exception {
  const CloudLibraryPayloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CloudLibraryAsset {
  CloudLibraryAsset({
    required this.key,
    required this.bytes,
    required this.sha256,
    this.localPath,
  }) {
    if (!_safeKey(key) ||
        bytes <= 0 ||
        bytes > CloudLibraryLimits.absoluteMaxBytes ||
        (key.endsWith('.json') && bytes > kCloudLibraryJsonMaxBytes) ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw const CloudLibraryPayloadException(
        'Invalid cloud viewing file descriptor.',
      );
    }
  }
  final String key;
  final int bytes;
  final String sha256;
  final String? localPath;

  Map<String, dynamic> toJson() => {
    'key': key,
    'bytes': bytes,
    'sha256': sha256,
  };
  factory CloudLibraryAsset.fromJson(Map<String, dynamic> json) {
    if (json['key'] is! String ||
        json['bytes'] is! int ||
        json['sha256'] is! String) {
      throw const CloudLibraryPayloadException(
        'Invalid cloud viewing file descriptor.',
      );
    }
    return CloudLibraryAsset(
      key: json['key'] as String,
      bytes: json['bytes'] as int,
      sha256: json['sha256'] as String,
    );
  }
  static bool _safeKey(String key) =>
      key.length <= 256 &&
      key
          .split('/')
          .every(
            (part) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(part),
          );
}

class CloudLibraryPayload {
  CloudLibraryPayload({
    required this.revision,
    required Map<String, dynamic> record,
    required List<CloudLibraryAsset> assets,
  }) : record = Map.unmodifiable(record),
       assets = List.unmodifiable(assets);
  final String revision;
  final Map<String, dynamic> record;
  final List<CloudLibraryAsset> assets;
  int get totalBytes => assets.fold(0, (sum, asset) => sum + asset.bytes);
}

/// Lossless viewing snapshot only. Never modifies reconstruction originals and
/// never builds or migrates a LOD tree.
class CloudLibraryPayloadBuilder {
  CloudLibraryPayloadBuilder({
    required this.store,
    this.maxFileBytes = 50000000,
    this.maxTotalBytes = 1000000000,
  });
  final ScanRecordStore store;
  final int maxFileBytes;
  final int maxTotalBytes;

  Future<CloudLibraryPayload> build(ScanRecord record) async {
    Directory? pending;
    Directory? root;
    try {
      _owner(record);
      if (maxFileBytes <= 0 ||
          maxFileBytes > CloudLibraryLimits.absoluteMaxBytes ||
          maxFileBytes > maxTotalBytes ||
          maxTotalBytes <= 0 ||
          maxTotalBytes > CloudLibraryLimits.absoluteMaxBytes) {
        throw const CloudLibraryPayloadException(
          'Invalid cloud library storage limits.',
        );
      }
      root = await store.accountDocumentsDirectory();
      _owner(record);
      _guard(root.path, root);
      final finalOnly = await verifyCloudFinalArtifact(store, record);
      _owner(record);
      final sources = <String, String>{};
      void add(String key, String? raw) {
        if (raw == null ||
            raw.isEmpty ||
            raw.startsWith('asset://') ||
            raw.startsWith('https://') ||
            raw.startsWith('http://')) {
          return;
        }
        final path = _local(raw);
        _guard(path, root!);
        final type = FileSystemEntity.typeSync(path, followLinks: false);
        if (type == FileSystemEntityType.notFound) return;
        if (type != FileSystemEntityType.file) {
          throw const CloudLibraryPayloadException(
            'Viewing files must be regular local files.',
          );
        }
        if (key.endsWith('.json')) _requireJsonSize(path, root);
        sources[key] = path;
      }

      add('artifact.glb', record.artifactPath);
      if (!finalOnly) add('thumbnail.jpg', record.thumbnailPath);
      final capture = finalOnly || record.captureDir == null
          ? null
          : _local(record.captureDir!);
      if (capture != null) {
        _checkDense(capture, root);
        for (final name in [
          'sfm_sparse.ply',
          'official_sfm_sparse.ply',
          'official_sfm_sparse_meta.json',
          kDensePlyFileName,
          // GLB viewing copies need no local reconstruction authorization.
          // The marker can bind private sandbox paths; keep it only in the
          // original capture and retain legacy PLY-only snapshot behavior.
          if (!sources.containsKey('artifact.glb')) kDenseStartedMarkerName,
          kSelectionBoxFileName,
        ]) {
          add('capture/$name', '$capture/$name');
        }
        final tree = Directory('$capture/lod');
        _guard(tree.path, root);
        // Guard every path the existing validator reads before it performs IO.
        for (final name in [
          'metadata.json',
          'hierarchy.bin',
          'octree.bin',
          'pw_lod_source.json',
        ]) {
          _guard('${tree.path}/$name', root);
          if (name.endsWith('.json')) {
            _requireJsonSize('${tree.path}/$name', root);
          }
        }
        final points = densePlyPoints('$capture/$kDensePlyFileName');
        if (points != null && DenseLodCache.isValidTree(tree, points)) {
          for (final name in [
            'metadata.json',
            'hierarchy.bin',
            'octree.bin',
            'pw_lod_source.json',
          ]) {
            add('capture/lod/$name', '${tree.path}/$name');
          }
        }
      }
      if (!sources.keys.any(
        (key) => key == 'artifact.glb' || key.endsWith('.ply'),
      )) {
        throw const CloudLibraryPayloadException(
          'Viewing result is not finished; cloud save remains pending.',
        );
      }
      var total = 0;
      for (final path in sources.values) {
        _guard(path, root);
        final bytes = File(path).lengthSync();
        if (bytes <= 0 || bytes > maxFileBytes) {
          throw const CloudLibraryPayloadException(
            'Viewing file exceeds the cloud file limit or is empty. Originals are retained.',
          );
        }
        total += bytes;
        if (total > maxTotalBytes) {
          throw const CloudLibraryPayloadException(
            'Viewing files exceed the cloud storage limit. Originals are retained.',
          );
        }
      }
      final uploads = Directory('${root.path}/library_uploads/${record.id}');
      _guard(uploads.path, root);
      await uploads.create(recursive: true);
      _owner(record);
      _guard(uploads.path, root);
      pending = await uploads.createTemp('pending-');
      _owner(record);
      _guard(pending.path, root);
      final keys = sources.keys.toList()..sort();
      final descriptors = <CloudLibraryAsset>[];
      for (final key in keys) {
        _owner(record);
        final source = sources[key]!;
        final target = '${pending.path}/$key';
        _guard(source, root);
        _guard(target, root);
        await Directory(File(target).parent.path).create(recursive: true);
        _owner(record);
        _guard(source, root);
        _guard(target, root);
        final copied = await _copy(source, target, root, record);
        total =
            descriptors.fold<int>(0, (sum, a) => sum + a.bytes) + copied.bytes;
        if (total > maxTotalBytes) {
          throw const CloudLibraryPayloadException(
            'Viewing files exceed the cloud storage limit. Originals are retained.',
          );
        }
        final sourceHash = await _hash(source, root, record);
        final snapshotHash = await _hash(target, root, record);
        if (sourceHash.sha256 != copied.sha256 ||
            snapshotHash.sha256 != copied.sha256 ||
            sourceHash.bytes != copied.bytes ||
            snapshotHash.bytes != copied.bytes) {
          throw const CloudLibraryPayloadException(
            'Viewing files changed during cloud save; retry after processing finishes.',
          );
        }
        if (key.endsWith('.json')) _requireSafeJson(target, root);
        descriptors.add(
          CloudLibraryAsset(
            key: key,
            bytes: copied.bytes,
            sha256: copied.sha256,
          ),
        );
      }
      for (final asset in descriptors) {
        final current = await _hash(sources[asset.key]!, root, record);
        if (current.sha256 != asset.sha256 || current.bytes != asset.bytes) {
          throw const CloudLibraryPayloadException(
            'Viewing files changed during cloud save; retry after processing finishes.',
          );
        }
      }
      if (capture != null) {
        _checkDense(capture, root);
        if (sources.keys.any((key) => key.startsWith('capture/lod/'))) {
          final points = densePlyPoints('$capture/$kDensePlyFileName');
          if (points == null ||
              !DenseLodCache.isValidTree(Directory('$capture/lod'), points) ||
              !DenseLodCache.isValidTree(
                Directory('${pending.path}/capture/lod'),
                points,
              )) {
            throw const CloudLibraryPayloadException(
              'Viewing tree changed during cloud save; retry after processing finishes.',
            );
          }
        }
      }
      _owner(record);
      final revision = sha256
          .convert(
            utf8.encode(
              jsonEncode(descriptors.map((a) => a.toJson()).toList()),
            ),
          )
          .toString();
      final destination = Directory('${uploads.path}/$revision');
      _guard(destination.path, root);
      if (destination.existsSync()) {
        for (final asset in descriptors) {
          final existing = await _hash(
            '${destination.path}/${asset.key}',
            root,
            record,
          );
          if (existing.sha256 != asset.sha256 ||
              existing.bytes != asset.bytes) {
            throw const CloudLibraryPayloadException(
              'Existing cloud snapshot failed integrity validation.',
            );
          }
        }
        _owner(record);
        _guard(pending.path, root);
        pending.deleteSync(recursive: true);
      } else {
        _owner(record);
        _guard(pending.path, root);
        pending.renameSync(destination.path);
      }
      pending = null;
      return CloudLibraryPayload(
        revision: revision,
        record: {
          'id': record.id,
          'name': record.name,
          'created_at': record.createdAt.toUtc().toIso8601String(),
          'pipeline_kind': record.pipelineKind.wireName,
          'preferred_capture_mode': record.preferredCaptureMode.name,
          'caption': record.caption ?? '',
        },
        assets: descriptors
            .map(
              (a) => CloudLibraryAsset(
                key: a.key,
                bytes: a.bytes,
                sha256: a.sha256,
                localPath: '${destination.path}/${a.key}',
              ),
            )
            .toList(),
      );
    } on CloudLibraryPayloadException {
      rethrow;
    } catch (_) {
      throw const CloudLibraryPayloadException(
        'Cloud viewing snapshot could not be prepared safely. Originals are retained.',
      );
    } finally {
      // After revocation, leave the partial snapshot in its original account.
      // A revoked operation must perform no more account filesystem mutations.
      if (pending != null && root != null && store.isActive) {
        try {
          _guard(pending.path, root);
          if (pending.existsSync()) pending.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  void _owner(ScanRecord record) {
    if (!store.isActive ||
        store.account == null ||
        record.accountNamespace != store.account!.namespace) {
      throw const CloudLibraryPayloadException(
        'Cloud save stopped because the account changed or is unavailable.',
      );
    }
    if (record.name.length > 256 || (record.caption?.length ?? 0) > 2000) {
      throw const CloudLibraryPayloadException(
        'Work title or caption exceeds the cloud library limit.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(record.id)) {
      throw const CloudLibraryPayloadException('Invalid work identifier.');
    }
  }

  String _local(String raw) {
    try {
      if (raw.startsWith('file://')) {
        final uri = Uri.parse(raw);
        if (uri.host.isNotEmpty) {
          throw const FormatException();
        }
        final decoded = Uri.decodeComponent(raw.substring(7));
        if (decoded.split('/').any((p) => p == '.' || p == '..')) {
          throw const FormatException();
        }
        return uri.toFilePath();
      }
      return raw;
    } catch (_) {
      throw const CloudLibraryPayloadException(
        'Invalid local viewing file path.',
      );
    }
  }

  void _guard(String path, Directory root) {
    if (!store.isActive) {
      throw const CloudLibraryPayloadException(
        'Cloud save stopped because the account changed.',
      );
    }
    final parts = path.split('/');
    if (!path.startsWith('/') ||
        path.contains('\\') ||
        path.contains('\u0000') ||
        parts.any((p) => p == '.' || p == '..') ||
        !(path == root.path || path.startsWith('${root.path}/'))) {
      throw const CloudLibraryPayloadException(
        'Viewing file is outside this account workspace.',
      );
    }
    // The store has validated the Documents base. Check that base and every
    // account-owned ancestor; platform aliases such as macOS /var are trusted
    // ancestors outside Documents, not account-controlled links.
    final marker = '/accounts/v1/${store.account!.namespace}';
    final offset = root.path.lastIndexOf(marker);
    if (offset <= 0) {
      throw const CloudLibraryPayloadException(
        'Invalid account workspace root.',
      );
    }
    final base = root.path.substring(0, offset);
    var cursor = base;
    if (FileSystemEntity.typeSync(base, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const CloudLibraryPayloadException(
        'Symbolic links cannot be used for cloud viewing files.',
      );
    }
    for (final part
        in path
            .substring(base.length)
            .split('/')
            .where((part) => part.isNotEmpty)) {
      cursor = '$cursor/$part';
      if (FileSystemEntity.typeSync(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const CloudLibraryPayloadException(
          'Symbolic links cannot be used for cloud viewing files.',
        );
      }
    }
  }

  void _checkDense(String capture, Directory root) {
    _guard(capture, root);
    for (final name in [
      kDensePlyFileName,
      kDenseStartedMarkerName,
      kDenseWorkDirName,
    ]) {
      _guard('$capture/$name', root);
    }
    final progress = denseStageProgress.value;
    if ((progress?.captureDir == capture &&
            progress?.state == DenseStageState.running) ||
        denseWorkStateOf(capture) == DenseWorkState.startedIncomplete) {
      throw const CloudLibraryPayloadException(
        'Dense processing has not finished; cloud save remains pending.',
      );
    }
  }

  Future<_FileDigest> _copy(
    String source,
    String target,
    Directory root,
    ScanRecord record,
  ) async {
    _guard(source, root);
    _guard(target, root);
    final input = await File(source).open();
    RandomAccessFile? output;
    try {
      _owner(record);
      _guard(source, root);
      _guard(target, root);
      output = await File(target).open(mode: FileMode.write);
      _owner(record);
      _guard(source, root);
      _guard(target, root);
      return await _consume(
        input,
        source,
        root,
        record,
        output: output,
        target: target,
      );
    } finally {
      await input.close();
      await output?.close();
    }
  }

  Future<_FileDigest> _hash(
    String path,
    Directory root,
    ScanRecord record,
  ) async {
    _owner(record);
    _guard(path, root);
    final input = await File(path).open();
    try {
      _owner(record);
      _guard(path, root);
      return await _consume(input, path, root, record);
    } finally {
      await input.close();
    }
  }

  Future<_FileDigest> _consume(
    RandomAccessFile input,
    String source,
    Directory root,
    ScanRecord record, {
    RandomAccessFile? output,
    String? target,
  }) async {
    Digest? digest;
    final sink = sha256.startChunkedConversion(
      _DigestSink((value) => digest = value),
    );
    var bytes = 0;
    while (true) {
      _owner(record);
      _guard(source, root);
      final chunk = await input.read(65536);
      _owner(record);
      _guard(source, root);
      if (chunk.isEmpty) break;
      bytes += chunk.length;
      if (bytes > maxFileBytes) {
        throw const CloudLibraryPayloadException(
          'Viewing file exceeds the cloud file limit. Originals are retained.',
        );
      }
      sink.add(chunk);
      if (output != null) {
        _guard(target!, root);
        await output.writeFrom(chunk);
        _owner(record);
        _guard(source, root);
        _guard(target, root);
      }
    }
    sink.close();
    if (bytes == 0) {
      throw const CloudLibraryPayloadException(
        'Viewing file is empty; cloud save remains pending.',
      );
    }
    if (output != null) {
      _guard(target!, root);
      await output.flush();
      _owner(record);
      _guard(target, root);
    }
    return _FileDigest(bytes, digest!.toString());
  }

  void _requireSafeJson(String path, Directory root) {
    _guard(path, root);
    final json = readCloudLibraryJson(File(path));
    _guard(path, root);
    bool safe(Object? value) {
      if (value is String) {
        return !value.startsWith('/') &&
            !value.startsWith('file://') &&
            !RegExp(r'^[A-Za-z]:\\').hasMatch(value);
      }
      if (value is List) return value.every(safe);
      if (value is Map) {
        return value.entries.every(
          (e) =>
              !RegExp(
                r'^(password|authorization|access_token|refresh_token|service_role_key|anon_key|credentials)$',
                caseSensitive: false,
              ).hasMatch(e.key.toString()) &&
              safe(e.value),
        );
      }
      return true;
    }

    if (!safe(json)) {
      throw const CloudLibraryPayloadException(
        'Viewing metadata contains private local paths or credentials; cloud save remains pending.',
      );
    }
  }

  void _requireJsonSize(String path, Directory root) {
    _guard(path, root);
    final file = File(path);
    if (file.existsSync() && file.lengthSync() > kCloudLibraryJsonMaxBytes) {
      throw const CloudLibraryPayloadException(
        'Viewing metadata exceeds the cloud metadata limit; cloud save remains pending. Originals are retained.',
      );
    }
  }
}

class _FileDigest {
  const _FileDigest(this.bytes, this.sha256);
  final int bytes;
  final String sha256;
}

class _DigestSink implements Sink<Digest> {
  _DigestSink(this.onDigest);
  final void Function(Digest) onDigest;
  @override
  void add(Digest data) => onDigest(data);
  @override
  void close() {}
}
