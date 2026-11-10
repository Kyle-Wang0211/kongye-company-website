import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';

import 'publication_source.dart';

/// An identity, not an in-memory copy. Native callers retain their protected
/// snapshot; browser callers retain the selected File/Blob until upload settles.
class PublicationFileSource {
  const PublicationFileSource({
    required this.file,
    required this.format,
    required this.byteLength,
    required this.sha256,
  });

  static const rangeBytes = 6 * 1024 * 1024;
  final XFile file;
  final PublicationSourceFormat format;
  final int byteLength;
  final String sha256;

  /// Explicit ranges matter on web: an unbounded XFile.openRead() can cause
  /// cross_file to materialize the entire Blob before emitting its stream.
  static Future<PublicationFileSource> inspect(
    XFile file, {
    required void Function() check,
    void Function(int read, int total)? onProgress,
  }) async {
    check();
    final format = PublicationSourceFormat.fromFileName(file.name);
    final length = await file.length();
    check();
    if (format == null || length < 20 || length > 9007199254740991) {
      throw const FormatException('Invalid publication file');
    }
    final header = await _readRange(file, 0, 12, check);
    if (format == PublicationSourceFormat.glb) {
      final view = ByteData.sublistView(header);
      if (view.getUint32(0, Endian.little) != 0x46546c67 ||
          view.getUint32(4, Endian.little) != 2 ||
          view.getUint32(8, Endian.little) != length) {
        throw const FormatException('Invalid GLB container');
      }
    } else if (header[0] != 0x70 ||
        header[1] != 0x6c ||
        header[2] != 0x79 ||
        (header[3] != 0x0a && header[3] != 0x0d)) {
      throw const FormatException('Invalid PLY signature');
    }
    final digest = _DigestSink();
    final hash = sha256Converter.startChunkedConversion(digest);
    try {
      for (var offset = 0; offset < length; offset += rangeBytes) {
        check();
        final end = math.min(length, offset + rangeBytes);
        final chunk = await _readRange(file, offset, end, check);
        hash.add(chunk);
        check();
        onProgress?.call(end, length);
      }
    } finally {
      hash.close();
    }
    if (await file.length() != length) {
      throw StateError('Publication source changed');
    }
    check();
    return PublicationFileSource(
      file: file,
      format: format,
      byteLength: length,
      sha256: digest.value!.toString(),
    );
  }

  /// An optional small preview is separate from admission to file transfer.
  Future<Uint8List?> previewBytes({required int memoryBudget}) async {
    if (byteLength > memoryBudget) return null;
    return _readRange(file, 0, byteLength, () {});
  }
}

// Avoid confusion with the instance's textual sha256 identity.
final sha256Converter = sha256;

Future<Uint8List> _readRange(
  XFile file,
  int start,
  int end,
  void Function() check,
) async {
  final bytes = BytesBuilder(copy: false);
  await for (final part in file.openRead(start, end)) {
    check();
    if (bytes.length + part.length > end - start) {
      throw StateError('Publication source range changed');
    }
    bytes.add(part);
  }
  check();
  if (bytes.length != end - start) {
    throw StateError('Publication source range changed');
  }
  return bytes.takeBytes();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
