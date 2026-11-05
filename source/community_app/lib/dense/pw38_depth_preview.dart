import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../pw38/request.dart' show hashFile;
import 'pw38_preview_artifact.dart';
import 'pw38_preview_handle_cleanup.dart';

/// Display-only pinhole backprojection from the existing native camera row:
/// K[0:9], world-to-camera R[9:18], t[18:21]. This is the same transport
/// layout documented in continuous_native/src/dense_inputs.h. No reconstruction
/// output is changed. Raw colors encode depth; retained RGB is the original
/// image color, not recovered mesh texture.
/// Reads <=10k depth samples via <=100 sampled scanlines, never a tensor bank.
Future<Pw38PreviewArtifact?> writeWholeDepthPreview({
  required String depthPath,
  required String cameraPath,
  required int frameIndex,
  required int frameCount,
  required int width,
  required int height,
  required String outputPath,
  int budget = 8192,
  bool retained = false,
  String? colorPath,
}) async {
  RandomAccessFile? depth, cameras, colors;
  try {
    if (budget < 1 ||
        budget > 10000 ||
        width < 1 ||
        width > 1536 ||
        height < 1 ||
        height > 1152 ||
        frameCount < 1 ||
        frameCount > 97 ||
        frameIndex < 0 ||
        frameIndex >= frameCount) {
      return null;
    }
    for (final path in [depthPath, cameraPath, ?colorPath]) {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
              FileSystemEntityType.file ||
          File(path).resolveSymbolicLinksSync() != path) {
        return null;
      }
    }
    cameras = File(cameraPath).openSync();
    if (cameras.lengthSync() != (retained ? 200 : frameCount * 144)) {
      return null;
    }
    cameras.setPositionSync(retained ? 0 : frameIndex * 144);
    final cb = ByteData.sublistView(cameras.readSync(retained ? 200 : 144));
    final c = List<double>.filled(36, 0);
    if (retained) {
      // Existing retained K9 then world-to-camera E16, row-major float64.
      for (var i = 0; i < 9; i++) {
        c[i] = cb.getFloat64(i * 8, Endian.little);
      }
      for (var r = 0; r < 3; r++) {
        for (var k = 0; k < 3; k++) {
          c[9 + r * 3 + k] = cb.getFloat64((9 + r * 4 + k) * 8, Endian.little);
        }
        c[18 + r] = cb.getFloat64((9 + r * 4 + 3) * 8, Endian.little);
      }
    } else {
      for (var i = 0; i < 36; i++) {
        c[i] = cb.getFloat32(i * 4, Endian.little);
      }
    }
    if (!c.every((v) => v.isFinite)) return null;
    // Native low K scales exactly 2x for HIGH1536 (same upstream adapter).
    final scale = retained ? 1.0 : width / 768;
    final fx = c[0] * scale,
        fy = c[4] * scale,
        cx = c[2] * scale,
        cy = c[5] * scale;
    if (fx <= 0 ||
        fy <= 0 ||
        c[1] != 0 ||
        c[3] != 0 ||
        c[6] != 0 ||
        c[7] != 0 ||
        c[8] != 1) {
      return null;
    }
    // Reject invalid rotations rather than displaying invalid geometry.
    for (var r = 0; r < 3; r++) {
      for (var s = 0; s < 3; s++) {
        var dot = 0.0;
        for (var k = 0; k < 3; k++) {
          dot += c[9 + r * 3 + k] * c[9 + s * 3 + k];
        }
        if ((dot - (r == s ? 1 : 0)).abs() > 0.001) return null;
      }
    }
    depth = File(depthPath).openSync();
    final sampleBytes = retained ? 2 : 4;
    if (depth.lengthSync() !=
        (retained ? 1 : frameCount) * width * height * sampleBytes) {
      return null;
    }
    if (colorPath != null) {
      colors = File(colorPath).openSync();
      if (colors.lengthSync() != width * height * 3) return null;
    }
    final step = math.sqrt(width * height / budget).ceil().clamp(1, 1536);
    final points = ByteData(budget * 15);
    var n = 0;
    for (var y = 0; y < height && n < budget; y += step) {
      depth.setPositionSync(
        ((retained ? 0 : frameIndex * width * height) + y * width) *
            sampleBytes,
      );
      final line = ByteData.sublistView(depth.readSync(width * sampleBytes));
      if (line.lengthInBytes != width * sampleBytes) return null;
      colors?.setPositionSync(y * width * 3);
      final rgb = colors?.readSync(width * 3);
      if (rgb != null && rgb.length != width * 3) return null;
      for (var x = 0; x < width && n < budget; x += step) {
        final z = retained
            ? line.getUint16(x * 2, Endian.little) / 5000
            : line.getFloat32(x * 4, Endian.little);
        if (!z.isFinite || z <= 0) continue;
        final v = [
          (x - cx) * z / fx - c[18],
          (y - cy) * z / fy - c[19],
          z - c[20],
        ];
        final world = List<double>.generate(
          3,
          (k) => c[9 + k] * v[0] + c[12 + k] * v[1] + c[15 + k] * v[2],
        );
        if (!world.every((v) => v.isFinite && v.abs() < 1e30)) continue;
        for (var k = 0; k < 3; k++) {
          points.setFloat32(n * 15 + k * 4, world[k], Endian.little);
        }
        final color = (255 * z / (1 + z)).round().clamp(0, 255);
        points.setUint8(n * 15 + 12, rgb == null ? color : rgb[x * 3]);
        points.setUint8(n * 15 + 13, rgb == null ? 180 : rgb[x * 3 + 1]);
        points.setUint8(
          n * 15 + 14,
          rgb == null ? 255 - color : rgb[x * 3 + 2],
        );
        n++;
      }
    }
    if (n == 0) return null;
    final file = File(outputPath);
    if (file.existsSync()) {
      return null; // Immutable observations, never overwrite.
    }
    await file.parent.create(recursive: true);
    final header =
        'ply\nformat binary_little_endian 1.0\ncomment display_only depth_frame $frameIndex\nelement vertex $n\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n';
    final out = await file.open(mode: FileMode.writeOnly);
    try {
      await out.writeString(header);
      await out.writeFrom(points.buffer.asUint8List(), 0, n * 15);
      await out.flush();
    } finally {
      await out.close();
    }
    return Pw38PreviewArtifact(
      path: outputPath,
      stage: retained ? 'dense' : 'depth',
      role: 'ply',
      bytes: await file.length(),
      sha256: await hashFile(file),
    );
  } catch (_) {
    return null;
  } finally {
    closePw38PreviewHandles([depth, cameras, colors]);
  }
}
