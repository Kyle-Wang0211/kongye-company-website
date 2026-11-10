import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'pw38_preview_artifact.dart';
import 'pw38_generated_consumer_leases.dart';

/// Display-only vertices of a completed original38 mesh. Faces and retained
/// reconstruction bytes are never rewritten. Texture appears with the GLB.
final class Pw38GeometryPreview {
  const Pw38GeometryPreview(this.xyz, this.rgb, this.sourceCount);
  final Float32List xyz;
  final Uint8List rgb;
  final int sourceCount;
}

Future<Pw38GeometryPreview?> loadPw38GeometryPreview(
  Pw38PreviewArtifact artifact,
) async {
  if (artifact.role != 'ply') return null;
  final read = Pw38GeneratedConsumerLeases.instance.acquire(
    artifact.path,
    'geometry-decode:${artifact.identity}',
  );
  try {
    return await compute(_load, artifact.path);
  } finally {
    read?.release();
  }
}

Pw38GeometryPreview? _load(String path) => readPw38GeometryPreview(path);

/// Bounded binary PLY IO for the pinned original producers' mesh outputs.
/// Samples file-order vertices only for display, using at most 100k vertices
/// and a 64KiB read buffer; unsupported formats retain the previous preview.
@visibleForTesting
Pw38GeometryPreview? readPw38GeometryPreview(
  String path, {
  int budget = 100000,
}) {
  RandomAccessFile? file;
  try {
    if (budget < 1 || budget > 1000000) return null;
    file = File(path).openSync();
    final length = file.lengthSync();
    final head = file.readSync(math.min(length, 65536));
    final text = String.fromCharCodes(head);
    final end = RegExp(r'end_header\r?\n').firstMatch(text);
    if (end == null) return null;
    final lines = text.substring(0, end.start).split(RegExp(r'\r?\n'));
    if (lines.first != 'ply' ||
        !lines.contains('format binary_little_endian 1.0')) {
      return null;
    }
    var count = 0, stride = 0;
    var vertex = false, firstElement = true;
    final properties = <String, (String, int)>{};
    const sizes = {
      'char': 1,
      'int8': 1,
      'uchar': 1,
      'uint8': 1,
      'short': 2,
      'int16': 2,
      'ushort': 2,
      'uint16': 2,
      'int': 4,
      'int32': 4,
      'uint': 4,
      'uint32': 4,
      'float': 4,
      'float32': 4,
      'double': 8,
      'float64': 8,
    };
    for (final line in lines.skip(2)) {
      final p = line.trim().split(RegExp(r'\s+'));
      if (p.first == 'element') {
        if (p.length != 3) return null;
        vertex = p[1] == 'vertex';
        if (vertex) {
          if (!firstElement || count != 0) return null;
          count = int.parse(p[2]);
        }
        firstElement = false;
      } else if (vertex && p.first == 'property') {
        if (p.length != 3 ||
            !sizes.containsKey(p[1]) ||
            properties.containsKey(p[2])) {
          return null;
        }
        properties[p[2]] = (p[1], stride);
        stride += sizes[p[1]]!;
      }
    }
    if (count <= 0 ||
        stride <= 0 ||
        stride > 1024 ||
        end.end + count * stride > length ||
        !['x', 'y', 'z'].every(
          (k) => const {
            'float',
            'float32',
            'double',
            'float64',
          }.contains(properties[k]?.$1),
        )) {
      return null;
    }
    final step = (count / budget).ceil();
    final capacity = (count / step).ceil();
    final xyz = Float32List(capacity * 3), rgb = Uint8List(capacity * 3);
    file.setPositionSync(end.end);
    var output = 0, index = 0;
    final rows = math.max(1, 65536 ~/ stride);
    while (index < count) {
      final n = math.min(rows, count - index);
      final bytes = file.readSync(n * stride);
      if (bytes.length != n * stride) return null;
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i < n; i++) {
        if ((index + i) % step != 0) continue;
        final values = <double>[];
        for (final k in ['x', 'y', 'z']) {
          final p = properties[k]!;
          values.add(
            p.$1 == 'double' || p.$1 == 'float64'
                ? data.getFloat64(i * stride + p.$2, Endian.little)
                : data.getFloat32(i * stride + p.$2, Endian.little),
          );
        }
        if (!values.every((v) => v.isFinite)) continue;
        for (var c = 0; c < 3; c++) {
          xyz[output * 3 + c] = values[c];
          final p = properties[['red', 'green', 'blue'][c]];
          rgb[output * 3 +
              c] = p != null && const {'uchar', 'uint8'}.contains(p.$1)
              ? bytes[i * stride + p.$2]
              : 190;
        }
        output++;
      }
      index += n;
    }
    if (output == 0) return null;
    return Pw38GeometryPreview(
      Float32List.sublistView(xyz, 0, output * 3),
      Uint8List.sublistView(rgb, 0, output * 3),
      count,
    );
  } catch (_) {
    return null;
  } finally {
    file?.closeSync();
  }
}
