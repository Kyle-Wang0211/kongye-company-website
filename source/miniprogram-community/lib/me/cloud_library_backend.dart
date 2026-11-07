import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tusc/tusc.dart' show ProtocolException;

import '../config/backend_deployment.dart';
import 'cloud_library_payload.dart';
import 'cloud_library_resumable.dart';
import 'scan_record_store.dart';

class CloudLibraryRemoteWork {
  CloudLibraryRemoteWork({
    required this.workId,
    this.revision,
    this.record = const {},
    this.assets = const [],
    this.deleted = false,
  });
  final String workId;
  final String? revision;
  final Map<String, dynamic> record;
  final List<CloudLibraryAsset> assets;
  final bool deleted;

  factory CloudLibraryRemoteWork.fromJson(Map<String, dynamic> json) {
    final id = json['work_id'];
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid cloud work identity');
    }
    if (json['deleted'] == true) {
      return CloudLibraryRemoteWork(workId: id, deleted: true);
    }
    final revision = json['revision'];
    final record = json['record'];
    final rawAssets = json['assets'];
    if (revision is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(revision) ||
        record is! Map ||
        record['id'] != id ||
        record['name'] is! String ||
        (record['name'] as String).length > 256 ||
        record['created_at'] is! String ||
        DateTime.tryParse(record['created_at']) == null ||
        !['self', 'official'].contains(record['pipeline_kind']) ||
        rawAssets is! List ||
        rawAssets.isEmpty ||
        rawAssets.length > 512) {
      throw const FormatException('Invalid cloud work manifest');
    }
    final assets = rawAssets
        .map(
          (e) =>
              CloudLibraryAsset.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    if (assets.map((a) => a.key).toSet().length != assets.length ||
        assets.fold<int>(0, (n, a) => n + a.bytes) > 1000000000 ||
        !assets.any(
          (a) =>
              a.key == 'artifact.glb' ||
              a.key.endsWith('sfm_sparse.ply') ||
              a.key == 'capture/official_dense.ply',
        )) {
      throw const FormatException('Invalid cloud viewing assets');
    }
    return CloudLibraryRemoteWork(
      workId: id,
      revision: revision,
      record: Map<String, dynamic>.from(record),
      assets: assets,
    );
  }
}

abstract interface class CloudLibraryBackend {
  Future<List<CloudLibraryRemoteWork>> listWorks();
  Future<void> reserve(String workId, CloudLibraryPayload payload);
  Future<void> upload(String workId, String revision, CloudLibraryAsset asset);
  Future<void> commit(String workId, String revision);
  Stream<List<int>> download(
    String workId,
    String revision,
    CloudLibraryAsset asset,
  );
  Future<void> deleteWork(String workId);
}

/// Optional so existing local and test backends retain their interface. China
/// orchestration requires it; the international deployment keeps fixed limits.
abstract interface class CloudLibraryLimitsProvider {
  Future<CloudLibraryLimits> storageLimits();
}

/// Validate a bounded transfer while retaining only its current chunk and hash
/// state. Bytes beyond the descriptor are never passed to the consumer.
Stream<List<int>> checkedCloudLibraryAssetStream(
  Stream<List<int>> source,
  CloudLibraryAsset asset, {
  void Function()? check,
}) async* {
  CloudLibraryAsset.fromJson(asset.toJson());
  final digest = _CloudLibraryDigestSink();
  final hash = sha256.startChunkedConversion(digest);
  var received = 0;
  try {
    await for (final chunk in source) {
      check?.call();
      if (chunk.length > asset.bytes - received) {
        throw StateError('Cloud object exceeds declared size');
      }
      received += chunk.length;
      hash.add(chunk);
      yield chunk;
    }
  } finally {
    hash.close();
  }
  check?.call();
  if (received != asset.bytes || digest.value?.toString() != asset.sha256) {
    throw StateError('Cloud object failed integrity validation');
  }
}

class _CloudLibraryDigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) => value = digest;
  @override
  void close() {}
}

abstract interface class CloudLibraryMaintenance {
  Future<void> cleanupUnused();
}

/// Supabase owns metadata and immutable object validation; the pinned community
/// TUS SDK supplies the shared Dart resumable byte transport.
class SupabaseCloudLibraryBackend
    implements
        CloudLibraryBackend,
        CloudLibraryMaintenance,
        CloudLibraryLimitsProvider {
  SupabaseCloudLibraryBackend({
    required this.store,
    required this.client,
    this.downloadClientFactory,
    CloudLibraryUploadTransport? uploadTransport,
  }) {
    final deployment = store.account?.deployment;
    if (deployment == null ||
        Uri.parse(client.rest.url).origin !=
            BackendDeployment.httpsOrigin(deployment.supabaseUrl)) {
      throw StateError('Cloud library deployment mismatch');
    }
    _uploadTransport =
        uploadTransport ??
        TusCloudLibraryUploadTransport(
          apiKey: deployment.anonKey,
          accessToken: () => client.auth.currentSession?.accessToken,
          check: _check,
          requireOwnedPath: store.requireOwnedPath,
        );
    _removeRevocation = store.addRevocationListener(_cancelTransfers);
  }
  static const bucket = 'personal-library';
  final ScanRecordStore store;
  final SupabaseClient client;

  /// Only the byte transport is replaceable. Signed URL trust validation and
  /// request headers remain owned by this backend.
  final HttpClient Function()? downloadClientFactory;
  late final CloudLibraryUploadTransport _uploadTransport;
  final _downloads = <HttpClient>{};
  bool _disposed = false;
  late final void Function() _removeRevocation;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelTransfers();
    _uploadTransport.dispose();
    _removeRevocation();
  }

  void _cancelTransfers() {
    _uploadTransport.pause();
    for (final transport in _downloads.toList()) {
      transport.close(force: true);
    }
  }

  void _check() {
    if (_disposed ||
        !store.isActive ||
        client.auth.currentUser?.id != store.account?.userId ||
        client.auth.currentSession == null) {
      throw StateError('Cloud library authentication unavailable');
    }
    if (BackendDeployment.httpsOrigin(Uri.parse(client.rest.url).origin) !=
        BackendDeployment.httpsOrigin(store.account!.deployment.supabaseUrl)) {
      throw StateError('Cloud library deployment mismatch');
    }
  }

  String _objectPath(String id, String revision, CloudLibraryAsset asset) {
    _check();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(revision)) {
      throw const FormatException('Invalid cloud object identity');
    }
    // Validate remote keys before passing them to an SDK which normalizes paths.
    CloudLibraryAsset.fromJson(asset.toJson());
    return '${store.account!.userId}/$id/$revision/${asset.key}';
  }

  @override
  Future<CloudLibraryLimits> storageLimits() async {
    _check();
    if (store.account!.deployment.region != BackendRegion.china) {
      return CloudLibraryLimits.legacy;
    }
    final capabilities = await client.rpc('pw_library_capabilities');
    _check();
    return CloudLibraryLimits.fromCapabilities(capabilities);
  }

  @override
  Future<List<CloudLibraryRemoteWork>> listWorks() async {
    final limits = await storageLimits();
    _check();
    final rows = await client.rpc('pw_library_list');
    _check();
    if (rows is! List) {
      throw const FormatException('Invalid cloud library response');
    }
    final works = rows
        .map(
          (r) => CloudLibraryRemoteWork.fromJson(
            Map<String, dynamic>.from(r as Map),
          ),
        )
        .toList();
    for (final work in works) {
      if (!work.deleted) limits.requireAssets(work.assets);
    }
    return works;
  }

  @override
  Future<void> reserve(String id, CloudLibraryPayload payload) async {
    final limits = await storageLimits();
    limits.requireAssets(payload.assets, upload: true);
    _check();
    await client.rpc(
      'pw_library_retire_pending',
      params: {'p_work_id': id, 'p_keep_revision': payload.revision},
    );
    _check();
    await cleanupUnused();
    _check();
    await client.rpc(
      'pw_library_reserve',
      params: {
        'p_work_id': id,
        'p_revision': payload.revision,
        'p_record': payload.record,
        'p_assets': payload.assets.map((a) => a.toJson()).toList(),
      },
    );
    _check();
  }

  @override
  Future<void> cleanupUnused() async {
    _check();
    if (store.account!.deployment.region == BackendRegion.china) {
      // The durable service queue owns physical cleanup and its evidence.
      // Clients supply neither object paths nor a completion receipt.
      await client.rpc('pw_library_gc_enqueue', params: const {});
      _check();
      return;
    }
    final paths = await client.rpc('pw_library_gc_candidates');
    _check();
    if (paths is! List) {
      throw const FormatException('Invalid cloud cleanup response');
    }
    final ownerPrefix = '${store.account!.userId}/';
    final validated = <String>[];
    for (final path in paths) {
      if (path is! String || !path.startsWith(ownerPrefix)) {
        throw const FormatException('Invalid cloud cleanup owner');
      }
      final parts = path.split('/');
      if (parts.length < 4 ||
          !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(parts[1]) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(parts[2]) ||
          !parts.every(
            (p) =>
                p.isNotEmpty &&
                p != '.' &&
                p != '..' &&
                RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(p),
          )) {
        throw const FormatException('Invalid cloud cleanup path');
      }
      validated.add(path);
    }
    for (var offset = 0; offset < validated.length; offset += 100) {
      _check();
      await client.storage
          .from(bucket)
          .remove(
            validated.sublist(
              offset,
              (offset + 100).clamp(0, validated.length),
            ),
          );
    }
    _check();
    await client.rpc('pw_library_gc_finish');
    _check();
  }

  @override
  Future<void> upload(
    String id,
    String revision,
    CloudLibraryAsset asset,
  ) async {
    _objectPath(id, revision, asset);
    final limits = await storageLimits();
    limits.requireAsset(asset, upload: true);
    _check();
    final source = asset.localPath;
    if (source == null) throw StateError('Missing protected upload snapshot');
    await store.requireOwnedPath(source);
    _check();
    final file = File(source);
    if (await file.length() != asset.bytes ||
        (await sha256.bind(file.openRead()).first).toString() != asset.sha256) {
      throw StateError('Upload snapshot changed');
    }
    _check();
    final root = await store.accountDocumentsDirectory();
    _check();
    try {
      await _uploadTransport.upload(
        CloudLibraryUploadRequest(
          endpoint: Uri.parse(store.account!.deployment.supabaseUrl),
          accountNamespace: store.account!.namespace,
          owner: store.account!.userId,
          bucket: bucket,
          workId: id,
          revision: revision,
          asset: asset,
          checkpointRoot: Directory('${root.path}/library_resume'),
        ),
      );
    } on ProtocolException catch (error) {
      _check();
      // An interrupted request may already have stored this immutable object.
      if (error.statusCode != 409) rethrow;
      await download(id, revision, asset).drain<void>();
    }
    _check();
  }

  @override
  Future<void> commit(String id, String revision) async {
    _check();
    await client.rpc(
      'pw_library_commit',
      params: {'p_work_id': id, 'p_revision': revision},
    );
    _check();
  }

  @override
  Stream<List<int>> download(
    String id,
    String revision,
    CloudLibraryAsset asset,
  ) async* {
    final path = _objectPath(id, revision, asset);
    HttpClient? transport;
    try {
      final limits = await storageLimits();
      limits.requireAsset(asset);
      _check();
      final signed = await client.storage
          .from(bucket)
          .createSignedUrl(path, 60);
      _check();
      final uri = Uri.tryParse(signed);
      final origin = BackendDeployment.httpsOrigin(
        store.account!.deployment.supabaseUrl,
      );
      final expectedPath = '/storage/v1/object/sign/$bucket/$path';
      if (uri == null ||
          origin == null ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          uri.port != 443 ||
          uri.origin != origin ||
          uri.path != expectedPath ||
          uri.queryParametersAll['token']?.length != 1 ||
          (uri.queryParameters['token']?.trim().isEmpty ?? true)) {
        throw StateError('Invalid cloud object download URL');
      }
      transport = downloadClientFactory?.call() ?? HttpClient();
      transport.connectionTimeout = const Duration(seconds: 30);
      _downloads.add(transport);
      _check();
      final request = await transport
          .getUrl(uri)
          .timeout(const Duration(seconds: 30));
      _check();
      request.followRedirects = false;
      request.headers.removeAll(HttpHeaders.authorizationHeader);
      // This separately owned client has no Supabase authentication headers.
      // Only the validated short-lived signed URL authorizes the byte request.
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      _check();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Cloud object transfer rejected');
      }
      // A yield* forwards source errors directly to subscribers. Iterate so
      // transport failures also pass through the sanitized catch below.
      await for (final chunk in checkedCloudLibraryAssetStream(
        response.timeout(const Duration(seconds: 30)),
        asset,
        check: _check,
      )) {
        yield chunk;
      }
    } catch (_) {
      // Transport errors can retain request URLs. Never put a bearer URL into the
      // library journal or callers' diagnostics.
      throw StateError('Cloud object transfer failed');
    } finally {
      transport?.close(force: true);
      _downloads.remove(transport);
    }
  }

  @override
  Future<void> deleteWork(String id) async {
    _check();
    await client.rpc('pw_library_delete', params: {'p_work_id': id});
    _check();
    if (store.account!.deployment.region == BackendRegion.china) {
      // Retain the durable tombstone even if enqueue fails, so a retry cannot
      // resurrect this work or release quota without verified service cleanup.
      await cleanupUnused();
      return;
    }
    // Bytes are removed through the Storage API, never by deleting SQL rows.
    // A partial cleanup keeps the durable server tombstone and still consumes
    // quota until a later deletion retry completes.
    final prefix = '${store.account!.userId}/$id';
    Future<void> clean(String folder) async {
      _check();
      final entries = await client.storage
          .from(bucket)
          .list(path: folder, searchOptions: const SearchOptions(limit: 100));
      _check();
      if (entries.isEmpty) return;
      final files = <String>[];
      for (final e in entries) {
        if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(e.name) ||
            e.name == '.' ||
            e.name == '..') {
          throw const FormatException('Invalid storage cleanup path');
        }
        if (e.id == null) {
          await clean('$folder/${e.name}');
        } else {
          files.add('$folder/${e.name}');
        }
      }
      _check();
      if (files.isNotEmpty) await client.storage.from(bucket).remove(files);
      if (entries.length == 100) await clean(folder);
    }

    await clean(prefix);
  }
}
