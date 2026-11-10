import 'dart:io';

import 'package:crypto/crypto.dart';

import 'terminal_glb.dart';

/// A proof of the published model, independent of retired capture inputs.
/// The caller must supply the active account and its persisted record proof.
final class Pw38FinalArtifactCompletionProof {
  Pw38FinalArtifactCompletionProof._({
    required this.accountNamespace,
    required this.recordId,
    required this.publishedGlb,
    required this.sha256Hex,
    required this.bytes,
    required this.terminalValidation,
    required String signature,
  }) : _signature = signature;

  final String accountNamespace, recordId, publishedGlb, sha256Hex;
  final int bytes;
  final Map<String, Object?> terminalValidation;
  final String _signature;

  /// A same-process cache check, not a substitute for cold-start validation.
  bool stillMatches() {
    try {
      final f = File(publishedGlb);
      return FileSystemEntity.typeSync(f.path, followLinks: false) ==
              FileSystemEntityType.file &&
          f.resolveSymbolicLinksSync() == f.path &&
          _statSignature(f.statSync()) == _signature;
    } catch (_) {
      return false;
    }
  }
}

String _statSignature(FileStat stat) =>
    '${stat.type}:${stat.size}:${stat.modified.microsecondsSinceEpoch}:'
    '${stat.changed.microsecondsSinceEpoch}:${stat.mode}';

/// Validate exactly `accountDocuments/scans_official/recordId.glb`.
/// No capture directory, completion marker or reconstruction RESULT is read.
/// Failure throws; a proof is returned only after format, byte count and a
/// streaming digest agree with the persisted record's expected identity.
Future<Pw38FinalArtifactCompletionProof> verifyPw38FinalArtifactCompletion({
  required Directory accountDocuments,
  required String accountNamespace,
  required String recordId,
  required String artifactPath,
  required int expectedBytes,
  required String expectedSha256,
}) async {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(accountNamespace) ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(recordId) ||
      expectedBytes <= 0 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
    throw StateError(
      'Final GLB requires account, record and measured identity',
    );
  }
  final root = accountDocuments.absolute.path;
  if (!root.endsWith('/accounts/v1/$accountNamespace') ||
      await accountDocuments.resolveSymbolicLinks() != root) {
    throw StateError('Final GLB requires canonical active account directory');
  }
  final uri = Uri.tryParse(artifactPath);
  final path = uri != null && uri.scheme == 'file'
      ? uri.toFilePath()
      : artifactPath;
  final expectedPath = '$root/scans_official/$recordId.glb';
  if (path != expectedPath ||
      await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw StateError(
      'Final GLB is outside its account/record or is not a file',
    );
  }
  final file = File(path);
  if (await file.resolveSymbolicLinks() != path) {
    throw StateError('Final GLB cannot use symbolic links');
  }
  final before = await file.stat();
  if (before.size != expectedBytes) {
    throw StateError('Final GLB byte count differs from persisted proof');
  }
  final validation = await validateTerminalGlb(file);
  final digest = (await sha256.bind(file.openRead()).first).toString();
  final after = await file.stat();
  if (digest != expectedSha256 ||
      _statSignature(before) != _statSignature(after) ||
      await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.resolveSymbolicLinks() != path) {
    throw StateError('Final GLB changed or differs from persisted proof');
  }
  return Pw38FinalArtifactCompletionProof._(
    accountNamespace: accountNamespace,
    recordId: recordId,
    publishedGlb: path,
    sha256Hex: digest,
    bytes: expectedBytes,
    terminalValidation: Map.unmodifiable(validation),
    signature: _statSignature(after),
  );
}
