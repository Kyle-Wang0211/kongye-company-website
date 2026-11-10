import 'dart:convert';
import 'dart:typed_data';

/// Standard binary PLY transport only: preserves source order, XYZ and RGB.
/// Geometry parsing and rendering are performed by upstream Three PLYLoader.
Uint8List encodePointCloudPly(Float32List xyz, Uint8List rgb) {
  if (xyz.length % 3 != 0 || rgb.length != xyz.length) {
    throw ArgumentError('Expected matching XYZ triples and RGB bytes');
  }
  final count = xyz.length ~/ 3;
  final header = ascii.encode('ply\nformat binary_little_endian 1.0\n'
      'element vertex $count\nproperty float x\nproperty float y\n'
      'property float z\nproperty uchar red\nproperty uchar green\n'
      'property uchar blue\nend_header\n');
  final bytes = Uint8List(header.length + count * 15)..setAll(0, header);
  final body = ByteData.sublistView(bytes, header.length);
  for (var point = 0; point < count; point++) {
    final source = point * 3, target = point * 15;
    body.setFloat32(target, xyz[source], Endian.little);
    body.setFloat32(target + 4, xyz[source + 1], Endian.little);
    body.setFloat32(target + 8, xyz[source + 2], Endian.little);
    bytes.setRange(header.length + target + 12,
        header.length + target + 15, rgb, source);
  }
  return bytes;
}
