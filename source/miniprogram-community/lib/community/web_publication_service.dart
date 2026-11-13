// Private GLB submission using the existing authenticated Supabase client.
// A submission status never substitutes for server publication authorization.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'community_cover_processor.dart';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WebPublicationException implements Exception {
  final String code;
  final String? submissionId;
  final bool retryable;
  const WebPublicationException(
    this.code, {
    this.submissionId,
    this.retryable = false,
  });
  @override
  String toString() => 'WebPublicationException($code)';
}

/// Frozen source/selection-bound camera. Public cover pixels are produced by the server.
Map<String, dynamic> validatePublicationInitialView(
  Map<String, dynamic> value, {
  required String sourceSha256,
  required Map<String, dynamic>? selectionBox,
}) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value is num ? value.toDouble() : value;
  }

  bool vector(Object? value) =>
      value is List &&
      value.length == 3 &&
      value.every((v) => v is num && v.isFinite);
  final fov = value['fov_y_degrees'], aspect = value['aspect'];
  if (value.keys.any(
        (key) => !const {
          'schema',
          'source_sha256',
          'selection_box',
          'projection',
          'position',
          'target',
          'up',
          'fov_y_degrees',
          'aspect',
        }.contains(key),
      ) ||
      value['schema'] != 'pw.camera-framing.v1' ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceSha256) ||
      value['source_sha256'] != sourceSha256 ||
      jsonEncode(canonical(value['selection_box'])) !=
          jsonEncode(canonical(selectionBox)) ||
      value['projection'] != 'perspective' ||
      !vector(value['position']) ||
      !vector(value['target']) ||
      !vector(value['up']) ||
      fov is! num ||
      !fov.isFinite ||
      fov < 1 ||
      fov > 120 ||
      aspect is! num ||
      !aspect.isFinite ||
      aspect < 0.1 ||
      aspect > 10) {
    throw const WebPublicationException('invalid_initial_view');
  }
  final position = (value['position'] as List).cast<num>();
  final target = (value['target'] as List).cast<num>();
  final up = (value['up'] as List).cast<num>();
  final d = List.generate(3, (i) => target[i] - position[i]);
  final cross = [
    d[1] * up[2] - d[2] * up[1],
    d[2] * up[0] - d[0] * up[2],
    d[0] * up[1] - d[1] * up[0],
  ];
  final distanceSquared = d.fold<double>(0, (sum, v) => sum + v * v);
  final upLengthSquared = up.fold<double>(0, (sum, v) => sum + v * v);
  if ([...position, ...target].any((v) => v.abs() > 1e9) ||
      distanceSquared < 1e-16 ||
      (upLengthSquared - 1).abs() > 1e-6 ||
      cross.every((v) => v == 0)) {
    throw const WebPublicationException('invalid_initial_view');
  }
  return Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}

class WebPublicationStatus {
  final String submissionId;
  final String status;
  final String? workId;
  final bool targetExceeded;
  const WebPublicationStatus({
    required this.submissionId,
    required this.status,
    this.workId,
    this.targetExceeded = false,
  });
  bool get isTerminal => const {
    'published',
    'unpublished',
    'rejected',
    'not_qualified',
    'failed',
    'cancelled',
  }.contains(status);
}

abstract class WebPublicationPorts {
  String? get userId;
  Uri get apiOrigin;
  Future<Map<String, dynamic>> invoke(Map<String, dynamic> body);
  Future<void> upload({
    required String path,
    required String token,
    required Uint8List bytes,
    String bucket = 'publication-staging',
    void Function(int sent, int total)? onBytesSent,
  });
}

class _SupabaseWebPublicationPorts implements WebPublicationPorts {
  final SupabaseClient client;
  @override
  final Uri apiOrigin;
  _SupabaseWebPublicationPorts(this.client, this.apiOrigin);
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Future<Map<String, dynamic>> invoke(Map<String, dynamic> body) async {
    final response = await client.functions.invoke(
      'publication-submit',
      body: body,
    );
    final data = response.data;
    if (data is! Map) throw const WebPublicationException('invalid_response');
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<void> upload({
    required String path,
    required String token,
    required Uint8List bytes,
    String bucket = 'publication-staging',
    void Function(int sent, int total)? onBytesSent,
  }) async {
    await client.storage
        .from(bucket)
        .uploadBinaryToSignedUrl(
          path,
          token,
          bytes,
          FileOptions(
            contentType: bucket == 'publication-cover-staging'
                ? 'image/jpeg'
                : path.endsWith('.ply')
                ? 'application/octet-stream'
                : 'model/gltf-binary',
            upsert: false,
          ),
        );
    onBytesSent?.call(bytes.length, bytes.length);
  }
}

class WebPublicationService {
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const maxSourceBytes =
      50000000; // Current fixed26 renderer policy, not a quota override.
  final WebPublicationPorts _ports;
  final String? _owner;
  final Duration requestTimeout;
  WebPublicationService.forTest(
    this._ports, {
    this.requestTimeout = const Duration(seconds: 30),
  }) : _owner = _ports.userId;
  factory WebPublicationService({SupabaseClient? client, Uri? apiOrigin}) {
    final c = client ?? Supabase.instance.client;
    final rest = Uri.parse(c.rest.url);
    final origin = apiOrigin ?? Uri.parse(rest.origin);
    if (origin.scheme != 'https' ||
        origin.origin != rest.origin ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment) {
      throw const WebPublicationException('invalid_api_origin');
    }
    return WebPublicationService.forTest(
      _SupabaseWebPublicationPorts(c, origin),
    );
  }
  void _signedIn(String? expected) {
    if (expected == null ||
        !_uuid.hasMatch(expected) ||
        _ports.userId != expected ||
        _owner != expected) {
      throw const WebPublicationException('signed_out_or_account_changed');
    }
  }

  Future<Map<String, dynamic>> _call(
    Map<String, dynamic> body, {
    String? submissionId,
  }) async {
    try {
      return await _ports.invoke(body).timeout(requestTimeout);
    } on WebPublicationException {
      rethrow;
    } catch (_) {
      throw WebPublicationException(
        'submission_unavailable',
        submissionId: submissionId,
        retryable: true,
      );
    }
  }

  WebPublicationStatus _status(
    Map<String, dynamic> value, {
    String? expectedId,
  }) {
    final id = value['submission_id'];
    final state = value['status'];
    const states = {
      'uploading',
      'queued',
      'rendering',
      'processing',
      'awaiting_review',
      'published',
      'unpublished',
      'rejected',
      'cancelled',
      'failed',
      'not_qualified',
    };
    if (value['ok'] != true ||
        id is! String ||
        !_uuid.hasMatch(id) ||
        (expectedId != null && id != expectedId) ||
        state is! String ||
        !states.contains(state)) {
      throw WebPublicationException(
        'invalid_response',
        submissionId: expectedId,
      );
    }
    final workId = value['work_id'];
    if ((state == 'published' && workId == null) ||
        (workId != null &&
            (state != 'published' ||
                workId is! String ||
                !_uuid.hasMatch(workId)))) {
      throw WebPublicationException('invalid_response', submissionId: id);
    }
    return WebPublicationStatus(
      submissionId: id,
      status: state,
      workId: workId as String?,
      targetExceeded: value['target_exceeded'] == true,
    );
  }

  Future<WebPublicationStatus> getStatus(String submissionId) async {
    final uid = _ports.userId;
    _signedIn(uid);
    if (!_uuid.hasMatch(submissionId)) {
      throw const WebPublicationException('invalid_submission_id');
    }
    final result = await _call({
      'action': 'status',
      'submission_id': submissionId,
    }, submissionId: submissionId);
    _signedIn(uid);
    return _status(result, expectedId: submissionId);
  }

  /// Cancellation is authenticated and server-authoritative. A lost response
  /// keeps the original submission recoverable through status polling.
  Future<WebPublicationStatus> cancel(String submissionId) async {
    final uid = _ports.userId;
    _signedIn(uid);
    if (!_uuid.hasMatch(submissionId)) {
      throw const WebPublicationException('invalid_submission_id');
    }
    final result = await _call({
      'action': 'cancel',
      'submission_id': submissionId,
    }, submissionId: submissionId);
    _signedIn(uid);
    return _status(result, expectedId: submissionId);
  }

  /// The caller persists idempotencyKey before this call and persists the server
  /// submission ID in onSubmissionCreated before upload starts. Never silently
  /// falls back to sparse PLY or creates a new UUID after an ambiguous response.
  Future<WebPublicationStatus> submit({
    required Uint8List bytes,
    String format = 'glb',
    required String title,
    String description = '',
    required String idempotencyKey,
    Map<String, dynamic>? selectionBox,
    Uint8List? coverJpeg,
    String? expectedSourceSha256,
    Map<String, dynamic>? initialView,
    required FutureOr<void> Function(String submissionId) onSubmissionCreated,
    void Function(String phase, double fraction)? onProgress,
  }) async {
    final uid = _ports.userId;
    _signedIn(uid);
    if (!_uuid.hasMatch(idempotencyKey) ||
        title.trim().isEmpty ||
        title.runes.length > 100 ||
        description.runes.length > 30) {
      throw const WebPublicationException('invalid_submission');
    }
    final snapshot = Uint8List.fromList(bytes).asUnmodifiableView();
    String? submissionId;
    try {
      onProgress?.call('reading', 0);
      final size = snapshot.length;
      if (!const {'glb', 'ply'}.contains(format) ||
          size < 20 ||
          size > maxSourceBytes) {
        throw const WebPublicationException('invalid_glb_source');
      }
      final header = snapshot.sublist(0, 12);
      if (format == 'glb' &&
          (header.length != 12 ||
              header[0] != 0x67 ||
              header[1] != 0x6c ||
              header[2] != 0x54 ||
              header[3] != 0x46 ||
              ByteData.sublistView(header).getUint32(4, Endian.little) != 2 ||
              ByteData.sublistView(header).getUint32(8, Endian.little) !=
                  size)) {
        throw const WebPublicationException('invalid_glb_source');
      }
      if (format == 'ply' &&
          !utf8
              .decode(snapshot.sublist(0, 5), allowMalformed: true)
              .replaceAll('\r', '')
              .startsWith('ply\n')) {
        throw const WebPublicationException('invalid_model_source');
      }
      final hash = sha256.convert(snapshot).toString();
      if (expectedSourceSha256 != null && hash != expectedSourceSha256) {
        throw const WebPublicationException('source_changed');
      }
      Uint8List? preparedCover;
      Map<String, dynamic>? userCover;
      if (coverJpeg != null) {
        final coverBytes = await compute(prepareCommunityCover, coverJpeg);
        preparedCover = coverBytes;
        final codec = await ui.instantiateImageCodec(coverBytes);
        try {
          final image = (await codec.getNextFrame()).image;
          try {
            userCover = {
              'sha256': sha256.convert(coverBytes).toString(),
              'byte_length': coverBytes.lengthInBytes,
              'width': image.width,
              'height': image.height,
              'content_type': 'image/jpeg',
            };
          } finally {
            image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
      if (format == 'glb' && coverJpeg == null)
        throw const WebPublicationException('missing_user_cover');
      final frozenView = initialView == null
          ? null
          : validatePublicationInitialView(
              initialView,
              sourceSha256: hash,
              selectionBox: selectionBox,
            );
      _signedIn(uid);
      final initiated = await _call({
        'action': 'initiate',
        'title': title.trim(),
        'description': description.trim(),
        'format': format,
        'byte_length': size,
        'source_sha256': hash,
        'idempotency_key': idempotencyKey,
        'selection_box': ?selectionBox,
        'initial_view': ?frozenView,
        'user_cover': ?userCover,
      });
      _signedIn(uid);
      final current = _status(initiated);
      submissionId = current.submissionId;
      await onSubmissionCreated(submissionId);
      _signedIn(uid);
      if (current.status != 'uploading') return current;
      final upload = initiated['upload'];
      final bucket = upload is Map
          ? (upload['bucket'] ?? 'publication-staging')
          : null;
      final expectedBucket = selectionBox == null
          ? 'publication-staging'
          : 'publication-selection-staging';
      if (upload is! Map ||
          bucket != expectedBucket ||
          upload['path'] != '$uid/$submissionId/source.$format' ||
          upload['token'] is! String ||
          (upload['token'] as String).isEmpty ||
          (upload['token'] as String).length > 8192 ||
          upload['signed_url'] is! String) {
        throw WebPublicationException(
          'invalid_upload_contract',
          submissionId: submissionId,
        );
      }
      final uri = Uri.tryParse(upload['signed_url'] as String);
      final api = _ports.apiOrigin;
      if (uri == null ||
          api.scheme != 'https' ||
          api.userInfo.isNotEmpty ||
          uri.scheme != 'https' ||
          uri.origin != api.origin ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          uri.path !=
              '/storage/v1/object/upload/sign/$bucket/${upload['path']}' ||
          uri.queryParametersAll.length != 1 ||
          uri.queryParametersAll['token']?.length != 1 ||
          uri.queryParameters['token'] != upload['token']) {
        throw WebPublicationException(
          'invalid_upload_contract',
          submissionId: submissionId,
        );
      }
      final coverUpload = initiated['cover_upload'];
      if (preparedCover != null) {
        if (_ports is! WebPublicationPorts ||
            coverUpload is! Map ||
            coverUpload['bucket'] != 'publication-cover-staging' ||
            coverUpload['path'] != '$uid/$submissionId/cover.jpg' ||
            coverUpload['token'] is! String ||
            (coverUpload['token'] as String).isEmpty ||
            coverUpload['signed_url'] is! String ||
            coverUpload['sha256'] != userCover!['sha256'] ||
            coverUpload['byte_length'] != preparedCover.lengthInBytes) {
          throw WebPublicationException(
            'invalid_cover_upload_contract',
            submissionId: submissionId,
          );
        }
        final coverUri = Uri.tryParse(coverUpload['signed_url'] as String);
        if (coverUri == null ||
            coverUri.scheme != 'https' ||
            coverUri.origin != api.origin ||
            coverUri.userInfo.isNotEmpty ||
            coverUri.hasFragment ||
            coverUri.path !=
                '/storage/v1/object/upload/sign/publication-cover-staging/${coverUpload['path']}' ||
            coverUri.queryParametersAll.length != 1 ||
            coverUri.queryParametersAll['token']?.length != 1 ||
            coverUri.queryParameters['token'] != coverUpload['token']) {
          throw WebPublicationException(
            'invalid_cover_upload_contract',
            submissionId: submissionId,
          );
        }
      }
      onProgress?.call('uploading', 0);
      final transfer = _ports.upload(
        path: upload['path'] as String,
        token: upload['token'] as String,
        bytes: snapshot,
        bucket: bucket as String,
        onBytesSent: (sent, total) =>
            onProgress?.call('uploading', sent / total),
      );
      try {
        await transfer.timeout(
          requestTimeout,
          onTimeout: () {
            throw WebPublicationException(
              'upload_outcome_unknown',
              submissionId: submissionId,
              retryable: true,
            );
          },
        );
      } on StorageException catch (e) {
        // The server hashes the stored object before processing. A previous
        // successful write with lost response can legitimately return409.
        if (e.statusCode != '409') rethrow;
      } catch (_) {
        rethrow;
      }
      _signedIn(uid);
      if (preparedCover != null) {
        onProgress?.call('uploading_cover', 0.95);
        try {
          await (_ports as WebPublicationPorts)
              .upload(
                path: (coverUpload as Map)['path'] as String,
                token: coverUpload['token'] as String,
                bytes: preparedCover,
                bucket: 'publication-cover-staging',
              )
              .timeout(requestTimeout);
        } on StorageException catch (e) {
          if (e.statusCode != '409') rethrow;
        }
        _signedIn(uid);
      }
      onProgress?.call('sealing', 1);
      final sealed = _status(
        await _call({
          'action': 'seal',
          'submission_id': submissionId,
        }, submissionId: submissionId),
        expectedId: submissionId,
      );
      _signedIn(uid);
      if (sealed.status == 'uploading') {
        throw WebPublicationException(
          'invalid_response',
          submissionId: submissionId,
        );
      }
      onProgress?.call('submitted', 1);
      return sealed;
    } on WebPublicationException {
      rethrow;
    } catch (_) {
      throw WebPublicationException(
        'submission_incomplete',
        submissionId: submissionId,
        retryable: true,
      );
    }
  }
}
