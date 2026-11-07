import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'capture_artifact_retirement.dart';

/// Durable account/publication authorization. Legacy file lists remain readable.
/// Persisted paths are account-relative,
/// so sandbox relocation cannot change which capture/GLB identity is authorized.
final class PendingCaptureRetirementToken {
  const PendingCaptureRetirementToken({
    required this.accountNamespace,
    required this.recordId,
    required this.captureRelative,
    required this.publishedGlbRelative,
    required this.finalGlbSha256,
    required this.finalGlbBytes,
    required this.manifest,
    required this.identitySha256,
  });
  final String accountNamespace,
      recordId,
      captureRelative,
      publishedGlbRelative;
  final String finalGlbSha256, identitySha256;
  final int finalGlbBytes;
  final List<CaptureRetirementEntry> manifest;
}

/// The caller serializes this store per account/record, closes new readers, and
/// supplies active-account + durable GLB format/proof validation callbacks.
/// No token means no deletion; successful deletion retains the token until the
/// caller commits the account record, then calls finish.
final class PendingCaptureRetirementStore {
  PendingCaptureRetirementStore({
    required this.accountRoot,
    required this.accountNamespace,
    required this.recordId,
    Future<void> Function(File, String)? persistForTesting,
  }) : _persistForTesting = persistForTesting;

  final Directory accountRoot;
  final String accountNamespace, recordId;
  final Future<void> Function(File, String)? _persistForTesting;
  static final _id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
  static final _hashPattern = RegExp(r'^[0-9a-f]{64}$');
  File get _file =>
      File('${accountRoot.path}/.pw_capture_retirement/$recordId.json');

  Future<void> _requireAccount() async {
    if (!_id.hasMatch(accountNamespace) ||
        !_id.hasMatch(recordId) ||
        accountRoot.path != accountRoot.absolute.path ||
        await accountRoot.resolveSymbolicLinks() != accountRoot.path ||
        accountRoot.uri.pathSegments.where((s) => s.isNotEmpty).last !=
            accountNamespace ||
        accountRoot.parent.uri.pathSegments.where((s) => s.isNotEmpty).last !=
            'v1' ||
        accountRoot.parent.parent.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last !=
            'accounts') {
      throw StateError('Pending capture retirement account mismatch');
    }
    final parent = _file.parent;
    final kind = await FileSystemEntity.type(parent.path, followLinks: false);
    if (kind != FileSystemEntityType.notFound &&
        (kind != FileSystemEntityType.directory ||
            await parent.resolveSymbolicLinks() != parent.path)) {
      throw StateError('Noncanonical pending capture directory');
    }
  }

  static void _requireLeaf(String p) {
    if (p.isEmpty ||
        p.startsWith('/') ||
        p.contains('\\') ||
        p.contains('\u0000') ||
        p.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw StateError('Invalid pending capture manifest path');
    }
  }

  Directory captureRootFor(PendingCaptureRetirementToken token) =>
      Directory('${accountRoot.path}/${token.captureRelative}');
  File publishedGlbFor(PendingCaptureRetirementToken token) =>
      File('${accountRoot.path}/${token.publishedGlbRelative}');

  Future<void> _requirePublication(PendingCaptureRetirementToken token) async {
    await _requireAccount();
    final file = publishedGlbFor(token);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.resolveSymbolicLinks() != file.path ||
        await file.length() != token.finalGlbBytes ||
        (await sha256.bind(file.openRead()).first).toString() !=
            token.finalGlbSha256) {
      throw StateError('Pending capture final GLB changed');
    }
    // An absent root remains a valid pending Store-finalization state, but its
    // existing parent must still be canonical and account-owned.
    final capture = captureRootFor(token);
    if (await capture.parent.resolveSymbolicLinks() != capture.parent.path) {
      throw StateError('Pending capture parent changed');
    }
    final kind = await FileSystemEntity.type(capture.path, followLinks: false);
    if (kind != FileSystemEntityType.notFound &&
        (kind != FileSystemEntityType.directory ||
            await capture.resolveSymbolicLinks() != capture.path)) {
      throw StateError('Pending capture root changed');
    }
  }

  PendingCaptureRetirementToken _decode(String text) {
    final envelope = jsonDecode(text);
    if (envelope is! Map<String, dynamic> ||
        envelope['schema'] != 'PW38_PENDING_CAPTURE_RETIREMENT_V1' ||
        envelope['payload'] is! Map<String, dynamic>) {
      throw StateError('Invalid pending capture token schema');
    }
    final p = envelope['payload'] as Map<String, dynamic>;
    final digest = sha256.convert(utf8.encode(jsonEncode(p))).toString();
    if (envelope['identity_sha256'] != digest ||
        p['account_namespace'] != accountNamespace ||
        p['record_id'] != recordId) {
      throw StateError('Pending capture identity mismatch');
    }
    final capture = p['capture_relative'];
    final glb = p['published_glb_relative'];
    if (capture is! String ||
        glb is! String ||
        capture.split('/').length != 2 ||
        capture != 'captures_official/$recordId' ||
        !_id.hasMatch(capture.split('/').last) ||
        glb != 'scans_official/$recordId.glb' ||
        p['final_glb_bytes'] is! int ||
        (p['final_glb_bytes'] as int) < 12 ||
        p['final_glb_sha256'] is! String ||
        !_hashPattern.hasMatch(p['final_glb_sha256'] as String) ||
        p['manifest'] is! List) {
      throw StateError('Invalid pending capture paths/proof');
    }
    final entries = <CaptureRetirementEntry>[];
    final names = <String>{};
    for (final row in p['manifest'] as List) {
      if (row is! Map<String, dynamic> ||
          row['path'] is! String ||
          row['bytes'] is! int ||
          (row['bytes'] as int) < 0 ||
          row['sha256'] is! String ||
          !_hashPattern.hasMatch(row['sha256'] as String) ||
          !names.add(row['path'] as String)) {
        throw StateError('Invalid pending capture manifest identity');
      }
      final metadata = [
        row['modified_micros'],
        row['changed_micros'],
        row['mode'],
      ];
      if (metadata.any((v) => v != null) &&
          metadata.any((v) => v is! int || v < 0)) {
        throw StateError('Invalid pending capture native metadata');
      }
      _requireLeaf(row['path'] as String);
      entries.add(
        CaptureRetirementEntry(
          relativePath: row['path'] as String,
          bytes: row['bytes'] as int,
          sha256: row['sha256'] as String,
          modifiedMicros: row['modified_micros'] as int?,
          changedMicros: row['changed_micros'] as int?,
          mode: row['mode'] as int?,
        ),
      );
    }
    return PendingCaptureRetirementToken(
      accountNamespace: accountNamespace,
      recordId: recordId,
      captureRelative: capture,
      publishedGlbRelative: glb,
      finalGlbSha256: p['final_glb_sha256'] as String,
      finalGlbBytes: p['final_glb_bytes'] as int,
      manifest: List.unmodifiable(entries),
      identitySha256: digest,
    );
  }

  Future<PendingCaptureRetirementToken?> load({
    required Future<void> Function() requirePublicationAndConsumersDrained,
  }) async {
    await requirePublicationAndConsumersDrained();
    await _requireAccount();
    final token = await _readToken();
    if (token != null) await _requirePublication(token);
    return token;
  }

  Future<PendingCaptureRetirementToken?> _readToken() async {
    await _requireAccount();
    final kind = await FileSystemEntity.type(_file.path, followLinks: false);
    if (kind == FileSystemEntityType.notFound) return null;
    if (kind != FileSystemEntityType.file ||
        await _file.resolveSymbolicLinks() != _file.path ||
        await _file.length() > 8 * 1024 * 1024) {
      throw StateError('Invalid pending token file');
    }
    final token = _decode(await _file.readAsString());
    return token;
  }

  Future<PendingCaptureRetirementToken> prepare({
    required Directory captureRoot,
    required File publishedGlb,
    required String expectedGlbSha256,
    required int expectedGlbBytes,
    required Future<void> Function() requirePublicationAndConsumersDrained,
  }) async {
    final existing = await load(
      requirePublicationAndConsumersDrained:
          requirePublicationAndConsumersDrained,
    );
    if (existing != null) {
      if (captureRoot.path != captureRootFor(existing).path ||
          publishedGlb.path != publishedGlbFor(existing).path ||
          expectedGlbSha256 != existing.finalGlbSha256 ||
          expectedGlbBytes != existing.finalGlbBytes) {
        throw StateError(
          'Existing pending capture belongs to a different publication',
        );
      }
      return existing; // Same durable authorization, including partial deletion.
    }
    await _requireAccount();
    final prefix = '${accountRoot.path}/captures_official/';
    if (!captureRoot.path.startsWith(prefix) ||
        !_id.hasMatch(captureRoot.path.substring(prefix.length)) ||
        await FileSystemEntity.type(captureRoot.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        publishedGlb.path !=
            '${accountRoot.path}/scans_official/$recordId.glb' ||
        !_hashPattern.hasMatch(expectedGlbSha256) ||
        expectedGlbBytes < 12) {
      throw StateError('Pending capture preparation paths/proof mismatch');
    }
    // Authorization covers the whole record-owned capture, including late
    // ordinary files. Do not hash temporary raw payloads again for deletion.
    final manifest = const <CaptureRetirementEntry>[];
    final payload = <String, Object?>{
      'account_namespace': accountNamespace,
      'record_id': recordId,
      'capture_relative': captureRoot.path.substring(
        accountRoot.path.length + 1,
      ),
      'published_glb_relative': 'scans_official/$recordId.glb',
      'final_glb_sha256': expectedGlbSha256,
      'final_glb_bytes': expectedGlbBytes,
      'manifest': manifest
          .map(
            (e) => {
              'path': e.relativePath,
              'bytes': e.bytes,
              'sha256': e.sha256,
              if (e.modifiedMicros != null) 'modified_micros': e.modifiedMicros,
              if (e.changedMicros != null) 'changed_micros': e.changedMicros,
              if (e.mode != null) 'mode': e.mode,
            },
          )
          .toList(),
    };
    final digest = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    final text = jsonEncode({
      'schema': 'PW38_PENDING_CAPTURE_RETIREMENT_V1',
      'payload': payload,
      'identity_sha256': digest,
    });
    if (utf8.encode(text).length > 8 * 1024 * 1024) {
      throw StateError('Pending token metadata too large');
    }
    final token = _decode(text);
    await _requirePublication(token);
    await _file.parent.create();
    await _requireAccount();
    if (_persistForTesting case final persist?) {
      await persist(_file, text);
    } else {
      final staging = File(
        '${_file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
      );
      await staging.create(exclusive: true);
      await staging.writeAsString(text, flush: true);
      if (await staging.readAsString() != text) {
        throw StateError('Pending token staging readback mismatch');
      }
      await requirePublicationAndConsumersDrained();
      await _requireAccount();
      if (await FileSystemEntity.type(_file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Pending token concurrently created');
      }
      await staging.rename(_file.path);
    }
    final persisted = await load(
      requirePublicationAndConsumersDrained:
          requirePublicationAndConsumersDrained,
    );
    if (persisted == null || persisted.identitySha256 != digest) {
      throw StateError('Pending token durable readback mismatch');
    }
    return persisted;
  }

  Future<CaptureRetirementResult?> resume({
    required Future<void> Function() requirePublicationAndConsumersDrained,
  }) async {
    final token = await load(
      requirePublicationAndConsumersDrained:
          requirePublicationAndConsumersDrained,
    );
    if (token == null) return null;
    final helper = CaptureArtifactRetirement(
      ownedCaptureRoot: captureRootFor(token),
      publishedGlb: publishedGlbFor(token),
      expectedGlbSha256: token.finalGlbSha256,
      expectedGlbBytes: token.finalGlbBytes,
      manifest: token.manifest,
    );
    return helper.retire(
      requirePublicationAndConsumersDrained: () async {
        await requirePublicationAndConsumersDrained();
        final current = await _readToken();
        if (current?.identitySha256 != token.identitySha256) {
          throw StateError('Pending token changed during retirement');
        }
      },
    );
  }

  /// Only after the Store has durably committed its final-GLB completion state.
  Future<void> finish({
    required Future<void> Function() requireStoreCommittedAndConsumersDrained,
  }) async {
    final token = await load(
      requirePublicationAndConsumersDrained:
          requireStoreCommittedAndConsumersDrained,
    );
    if (token == null) return;
    if (await FileSystemEntity.type(
          captureRootFor(token).path,
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      throw StateError('Capture retirement still pending');
    }
    final current = await load(
      requirePublicationAndConsumersDrained:
          requireStoreCommittedAndConsumersDrained,
    );
    if (current?.identitySha256 != token.identitySha256) {
      throw StateError('Pending token changed before finish');
    }
    await _file.delete();
    if (await _file.exists()) throw StateError('Pending token removal failed');
    if (await _file.parent.list(followLinks: false).isEmpty) {
      await _file.parent.delete();
    }
  }
}
