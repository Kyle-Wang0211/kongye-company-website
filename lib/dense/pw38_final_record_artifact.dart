import 'dart:io';

import '../me/scan_record_store.dart';
import '../pw38/final_artifact_completion.dart';
import '../ui/scan_record.dart';

bool hasPw38FinalRecordProof(ScanRecord record) =>
    record.finalGlbSha256 != null || record.finalGlbBytes != null;

String? _recordFilePath(String? reference) {
  if (reference == null) return null;
  final uri = Uri.tryParse(reference);
  if (uri != null && uri.hasScheme && uri.scheme != 'file') return null;
  return uri?.scheme == 'file' ? uri!.toFilePath() : reference;
}

// Resolve only trusted platform aliases here. Business paths and symlinks are
// checked by the originating store before the full verification below.
String _platformAlias(String path) {
  if (Platform.isMacOS || Platform.isIOS) {
    if (path.startsWith('/var/')) return '/private$path';
    if (path.startsWith('/tmp/')) return '/private$path';
  }
  return path;
}

bool pw38FinalRecordProofMatches(
  ScanRecord record,
  Pw38FinalArtifactCompletionProof proof,
) =>
    record.accountNamespace == proof.accountNamespace &&
    record.id == proof.recordId &&
    record.finalGlbSha256 == proof.sha256Hex &&
    record.finalGlbBytes == proof.bytes &&
    _recordFilePath(record.artifactPath) != null &&
    _platformAlias(_recordFilePath(record.artifactPath)!) ==
        proof.publishedGlb &&
    proof.stillMatches();

/// Verify a completed record without depending on retired reconstruction data.
Future<Pw38FinalArtifactCompletionProof> verifyPw38FinalRecordArtifact(
  ScanRecordStore store,
  ScanRecord record,
) async {
  await store.ensureLoaded();
  final namespace = store.account?.namespace;
  if (!store.isActive ||
      namespace == null ||
      namespace != record.accountNamespace ||
      record.artifactPath == null ||
      record.finalGlbSha256 == null ||
      record.finalGlbBytes == null) {
    throw StateError('Completed model has no active persisted identity');
  }
  final root = await store.accountDocumentsDirectory();
  final path = _recordFilePath(record.artifactPath);
  if (path == null) throw StateError('Completed model requires a local file');
  // Reject business symlinks before resolving /var's trusted system alias.
  await store.requireOwnedPath(path);
  final proof = await verifyPw38FinalArtifactCompletion(
    accountDocuments: Directory(await root.resolveSymbolicLinks()),
    accountNamespace: namespace,
    recordId: record.id,
    artifactPath: await File(path).resolveSymbolicLinks(),
    expectedBytes: record.finalGlbBytes!,
    expectedSha256: record.finalGlbSha256!,
  );
  final current = store.byId(record.id);
  if (!store.isActive ||
      store.account?.namespace != namespace ||
      current == null ||
      !pw38FinalRecordProofMatches(current, proof)) {
    throw StateError('Completed model changed during verification');
  }
  return proof;
}
