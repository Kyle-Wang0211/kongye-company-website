// Private GLB submission using the existing authenticated Supabase client.
// A submission status never substitutes for server publication authorization.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dense/dense_work_state.dart';

class GlbPublicationException implements Exception {
  final String code;
  final String? submissionId;
  final bool retryable;
  const GlbPublicationException(
    this.code, {
    this.submissionId,
    this.retryable = false,
  });
  @override
  String toString() => 'GlbPublicationException($code)';
}

class GlbPublicationStatus {
  final String submissionId;
  final String status;
  final String? workId;
  final bool targetExceeded;
  const GlbPublicationStatus({
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

abstract class GlbPublicationPorts {
  String? get userId;
  Uri get apiOrigin;
  Future<Map<String, dynamic>> invoke(Map<String, dynamic> body);
  Future<void> upload({
    required String path,
    required String token,
    required File file,
  });
  Future<File> verifySource(String recordId, String glbPath);
}

class _SupabaseGlbPublicationPorts implements GlbPublicationPorts {
  final SupabaseClient client;
  @override
  final Uri apiOrigin;
  _SupabaseGlbPublicationPorts(this.client, this.apiOrigin);
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Future<Map<String, dynamic>> invoke(Map<String, dynamic> body) async {
    final response = await client.functions.invoke(
      'publication-submit',
      body: body,
    );
    final data = response.data;
    if (data is! Map) throw const GlbPublicationException('invalid_response');
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<void> upload({
    required String path,
    required String token,
    required File file,
  }) async {
    await client.storage
        .from('publication-staging')
        .uploadToSignedUrl(
          path,
          token,
          file,
          const FileOptions(contentType: 'model/gltf-binary', upsert: false),
          0, // Ambiguous requests are resumed through the same submission, never retried blindly.
        );
  }

  @override
  Future<File> verifySource(String recordId, String glbPath) async {
    final requested = File(glbPath);
    if (await FileSystemEntity.type(glbPath, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const GlbPublicationException('final_glb_not_verified');
    }
    final file = File(await requested.resolveSymbolicLinks());
    final root = file.parent.parent.path;
    final captureDir = '$root/captures_official/$recordId';
    if (file.path != '$root/scans_official/$recordId.glb' ||
        await verifyDenseWorkStateOf(captureDir, recheck: true) !=
            DenseWorkState.done) {
      throw const GlbPublicationException('final_glb_not_verified');
    }
    final verified = verifiedPw38CacheArtifact(captureDir);
    if (verified == null ||
        verified.recordId != recordId ||
        verified.glbPath != file.path) {
      throw const GlbPublicationException('final_glb_not_verified');
    }
    return file;
  }
}

class GlbPublicationService {
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const maxSourceBytes =
      50000000; // Current fixed26 renderer policy, not a quota override.
  final GlbPublicationPorts _ports;
  final Duration requestTimeout;
  GlbPublicationService.forTest(
    this._ports, {
    this.requestTimeout = const Duration(seconds: 30),
  });
  factory GlbPublicationService({SupabaseClient? client, Uri? apiOrigin}) {
    final c = client ?? Supabase.instance.client;
    final rest = Uri.parse(c.rest.url);
    final origin = apiOrigin ?? Uri.parse(rest.origin);
    if (origin.scheme != 'https' ||
        origin.origin != rest.origin ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment) {
      throw const GlbPublicationException('invalid_api_origin');
    }
    return GlbPublicationService.forTest(
      _SupabaseGlbPublicationPorts(c, origin),
    );
  }
  void _signedIn(String? expected) {
    if (expected == null ||
        !_uuid.hasMatch(expected) ||
        _ports.userId != expected) {
      throw const GlbPublicationException('signed_out_or_account_changed');
    }
  }

  Future<Map<String, dynamic>> _call(
    Map<String, dynamic> body, {
    String? submissionId,
  }) async {
    try {
      return await _ports.invoke(body).timeout(requestTimeout);
    } on GlbPublicationException {
      rethrow;
    } catch (_) {
      throw GlbPublicationException(
        'submission_unavailable',
        submissionId: submissionId,
        retryable: true,
      );
    }
  }

  GlbPublicationStatus _status(
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
      throw GlbPublicationException(
        'invalid_response',
        submissionId: expectedId,
      );
    }
    final workId = value['work_id'];
    if (workId != null &&
        (state != 'published' ||
            workId is! String ||
            !_uuid.hasMatch(workId))) {
      throw GlbPublicationException('invalid_response', submissionId: id);
    }
    return GlbPublicationStatus(
      submissionId: id,
      status: state,
      workId: workId as String?,
      targetExceeded: value['target_exceeded'] == true,
    );
  }

  Future<GlbPublicationStatus> getStatus(String submissionId) async {
    final uid = _ports.userId;
    _signedIn(uid);
    if (!_uuid.hasMatch(submissionId))
      throw const GlbPublicationException('invalid_submission_id');
    final result = await _call({
      'action': 'status',
      'submission_id': submissionId,
    }, submissionId: submissionId);
    _signedIn(uid);
    return _status(result, expectedId: submissionId);
  }

  /// The caller persists idempotencyKey before this call and persists the server
  /// submission ID in onSubmissionCreated before upload starts. Never silently
  /// falls back to sparse PLY or creates a new UUID after an ambiguous response.
  Future<GlbPublicationStatus> submit({
    required String recordId,
    required String glbPath,
    required String title,
    String description = '',
    required String idempotencyKey,
    required FutureOr<void> Function(String submissionId) onSubmissionCreated,
    void Function(String phase, double fraction)? onProgress,
  }) async {
    final uid = _ports.userId;
    _signedIn(uid);
    if (recordId.isEmpty ||
        recordId.contains('/') ||
        recordId.contains('\\') ||
        !_uuid.hasMatch(idempotencyKey) ||
        title.trim().isEmpty ||
        title.runes.length > 100 ||
        description.runes.length > 30) {
      throw const GlbPublicationException('invalid_submission');
    }
    File? snapshot;
    String? submissionId;
    bool uploadInFlight = false;
    try {
      onProgress?.call('reading', 0.02);
      final source = await _ports.verifySource(recordId, glbPath);
      final before = await source.stat();
      if (before.type != FileSystemEntityType.file ||
          before.size < 20 ||
          before.size > maxSourceBytes ||
          await FileSystemEntity.type(source.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const GlbPublicationException('invalid_glb_source');
      }
      final dir = await Directory.systemTemp.createTemp('pw-glb-publication-');
      snapshot = File('${dir.path}/source.glb');
      await source.openRead().pipe(snapshot.openWrite());
      final after = await source.stat();
      if (before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed) {
        throw const GlbPublicationException('source_changed');
      }
      final handle = await snapshot.open();
      final header = await handle.read(12);
      await handle.close();
      final size = await snapshot.length();
      if (header.length != 12 ||
          header[0] != 0x67 ||
          header[1] != 0x6c ||
          header[2] != 0x54 ||
          header[3] != 0x46 ||
          ByteData.sublistView(header).getUint32(4, Endian.little) != 2 ||
          ByteData.sublistView(header).getUint32(8, Endian.little) != size ||
          size != before.size) {
        throw const GlbPublicationException('invalid_glb_source');
      }
      final hash = (await sha256.bind(snapshot.openRead()).first).toString();
      _signedIn(uid);
      final initiated = await _call({
        'action': 'initiate',
        'title': title.trim(),
        'description': description.trim(),
        'format': 'glb',
        'byte_length': size,
        'source_sha256': hash,
        'idempotency_key': idempotencyKey,
      });
      final current = _status(initiated);
      submissionId = current.submissionId;
      await onSubmissionCreated(submissionId);
      _signedIn(uid);
      if (current.status != 'uploading') return current;
      final upload = initiated['upload'];
      if (upload is! Map ||
          upload['path'] != '$uid/$submissionId/source.glb' ||
          upload['token'] is! String ||
          (upload['token'] as String).isEmpty ||
          (upload['token'] as String).length > 8192 ||
          upload['signed_url'] is! String) {
        throw GlbPublicationException(
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
              '/storage/v1/object/upload/sign/publication-staging/${upload['path']}' ||
          uri.queryParametersAll.length != 1 ||
          uri.queryParametersAll['token']?.length != 1 ||
          uri.queryParameters['token'] != upload['token']) {
        throw GlbPublicationException(
          'invalid_upload_contract',
          submissionId: submissionId,
        );
      }
      onProgress?.call('uploading', 0.2);
      uploadInFlight = true;
      bool transferTimedOut = false;
      final frozenSnapshot = snapshot;
      final transfer = _ports.upload(
        path: upload['path'] as String,
        token: upload['token'] as String,
        file: snapshot,
      );
      // Future.timeout does not cancel an SDK transfer. Clean only our private
      // snapshot after that transfer really settles, even if the caller timed out.
      unawaited(
        transfer.then<void>(
          (_) async {
            if (transferTimedOut) {
              try {
                await frozenSnapshot.parent.delete(recursive: true);
              } catch (_) {}
            }
          },
          onError: (Object _) async {
            if (transferTimedOut) {
              try {
                await frozenSnapshot.parent.delete(recursive: true);
              } catch (_) {}
            }
          },
        ),
      );
      try {
        await transfer.timeout(
          requestTimeout,
          onTimeout: () {
            transferTimedOut = true;
            throw GlbPublicationException(
              'upload_outcome_unknown',
              submissionId: submissionId,
              retryable: true,
            );
          },
        );
        uploadInFlight = false;
      } on StorageException catch (e) {
        uploadInFlight = false;
        // The server hashes the stored object before processing. A previous
        // successful write with lost response can legitimately return409.
        if (e.statusCode != '409') rethrow;
      } catch (_) {
        uploadInFlight = transferTimedOut;
        rethrow;
      }
      _signedIn(uid);
      onProgress?.call('sealing', 0.9);
      final sealed = _status(
        await _call({
          'action': 'seal',
          'submission_id': submissionId,
        }, submissionId: submissionId),
        expectedId: submissionId,
      );
      if (sealed.status == 'uploading')
        throw GlbPublicationException(
          'invalid_response',
          submissionId: submissionId,
        );
      onProgress?.call('submitted', 1);
      return sealed;
    } on GlbPublicationException {
      rethrow;
    } catch (_) {
      throw GlbPublicationException(
        'submission_incomplete',
        submissionId: submissionId,
        retryable: true,
      );
    } finally {
      // A timed-out SDK transfer may still hold the private snapshot open.
      // Do not remove it while the request outcome is ambiguous; never delete source.
      if (snapshot != null && !uploadInFlight) {
        try {
          await snapshot.parent.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
