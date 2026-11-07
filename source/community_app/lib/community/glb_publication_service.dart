// Private GLB submission using the existing authenticated Supabase client.
// A submission status never substitutes for server publication authorization.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../dense/dense_work_state.dart';
import 'web_publication_service.dart';

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

/// Native source verification stays local; authenticated control requests share
/// the exact same publication protocol as browser submissions.
class _GlbPublicationControlPorts implements PublicationControlPorts {
  final GlbPublicationPorts ports;
  _GlbPublicationControlPorts(this.ports);
  @override
  String? get userId => ports.userId;
  @override
  Uri get apiOrigin => ports.apiOrigin;
  @override
  Future<Map<String, dynamic>> invoke(Map<String, dynamic> body) async {
    try {
      return await ports.invoke(body);
    } on GlbPublicationException catch (e) {
      throw WebPublicationException(
        e.code,
        submissionId: e.submissionId,
        retryable: e.retryable,
      );
    }
  }
}

class GlbPublicationService {
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static const maxSourceBytes = WebPublicationService.maxSourceBytes;
  final GlbPublicationPorts _ports;
  final Duration requestTimeout;
  final WebPublicationService _core;
  GlbPublicationService.forTest(
    this._ports, {
    this.requestTimeout = const Duration(seconds: 30),
  }) : _core = WebPublicationService.forTest(
         _GlbPublicationControlPorts(_ports),
         requestTimeout: requestTimeout,
       );
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

  GlbPublicationStatus _nativeStatus(WebPublicationStatus status) =>
      GlbPublicationStatus(
        submissionId: status.submissionId,
        status: status.status,
        workId: status.workId,
        targetExceeded: status.targetExceeded,
      );

  Future<GlbPublicationStatus> getStatus(String submissionId) async {
    try {
      return _nativeStatus(await _core.getStatus(submissionId));
    } on WebPublicationException catch (e) {
      throw GlbPublicationException(
        e.code,
        submissionId: e.submissionId,
        retryable: e.retryable,
      );
    }
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
    bool submissionReturned = false;
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
      final frozenSnapshot = snapshot;
      final result = await _core.submitPrepared(
        byteLength: size,
        sourceSha256: hash,
        title: title,
        description: description,
        idempotencyKey: idempotencyKey,
        onSubmissionCreated: (id) async {
          submissionId = id;
          try {
            await onSubmissionCreated(id);
          } on GlbPublicationException catch (e) {
            throw WebPublicationException(
              e.code,
              submissionId: e.submissionId,
              retryable: e.retryable,
            );
          }
        },
        onProgress: onProgress,
        upload:
            ({
              required path,
              required token,
              required bucket,
              onBytesSent,
            }) async {
              // The shared core validates bucket/path/token before invoking this.
              // Keep this private disk snapshot until the SDK actually settles;
              // Future.timeout in the core cannot cancel its file transfer.
              uploadInFlight = true;
              try {
                await _ports.upload(
                  path: path,
                  token: token,
                  file: frozenSnapshot,
                );
                if (!submissionReturned) onBytesSent?.call(size, size);
              } on GlbPublicationException catch (e) {
                throw WebPublicationException(
                  e.code,
                  submissionId: e.submissionId,
                  retryable: e.retryable,
                );
              } finally {
                uploadInFlight = false;
                if (submissionReturned) {
                  try {
                    await frozenSnapshot.parent.delete(recursive: true);
                  } catch (_) {}
                }
              }
            },
      );
      return _nativeStatus(result);
    } on WebPublicationException catch (e) {
      throw GlbPublicationException(
        e.code,
        submissionId: e.submissionId,
        retryable: e.retryable,
      );
    } on GlbPublicationException {
      rethrow;
    } catch (_) {
      throw GlbPublicationException(
        'submission_incomplete',
        submissionId: submissionId,
        retryable: true,
      );
    } finally {
      submissionReturned = true;
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
