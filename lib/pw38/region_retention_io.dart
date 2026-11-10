import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'frame_transport.dart';
import 'reconstruction_artifact_gate.dart';
import 'reconstruction_region.dart';

/// Pins returned by pw38_selected_fusion.source_codes(), including exact spans.
const regionSelectedSourceIdentity = <String, Object>{
  'filter_full_sha256':
      'c46efb40f15297c62ee8932cce8197bd7f360737c338e6de2d42c9bab52379cb',
  'fusion_full_sha256':
      '779a5cc40a9b1c20ec7367ca4f73e4f3085bbee6cac062ab8640064d1182b8a4',
  'projection_sha256':
      '0819a37f14e822bd3369f762e3631c7a1e9ad4ed544722a7f4b8cac430c4bb01',
  'projection_lines': [216, 217, 218, 220, 223, 224, 225, 226, 227],
  'assembly_sha256':
      '2ef863cce1df72641fdb389aa90aab2109ec8cb67497fd2caa0cb519ff2094aa',
  'assembly_lines': [230, 232, 233],
  'original_driver_sha256':
      '651d65d4a31c84dd7630e0d7f4886a08384650cdef1f65788b9f28b18fa86078',
};

const _pixels = 1536 * 1152;
const _pointColorOrder =
    'callback-selected f4 rows match color[selection_mask!=0] in C-row-major pixel order';

List<ReconstructionOutput> regionRetentionOutputs(
  ReconstructionRegion region,
  int count,
) {
  checkedFrameCount(count);
  final directory = region.selectedDepthDir;
  return [
    ReconstructionOutput(
      '$directory/selection_manifest.json',
      'region_manifest',
    ),
    for (var i = 0; i < count; i++) ...[
      ReconstructionOutput(
        '$directory/${_stem(i)}.d16',
        'region_d16',
        shapeBytes: _pixels * 2,
      ),
      ReconstructionOutput(
        '$directory/${_stem(i)}.camera.f64le',
        'region_camera',
        shapeBytes: 200,
      ),
      ReconstructionOutput(
        '$directory/${_stem(i)}.col.u8',
        'region_color',
        shapeBytes: _pixels * 3,
      ),
      ReconstructionOutput(
        '$directory/${_stem(i)}.selection.u8',
        'region_mask',
        shapeBytes: _pixels,
      ),
      ReconstructionOutput('$directory/${_stem(i)}.json', 'region_metadata'),
    ],
  ];
}

final class RegionRetentionResult {
  RegionRetentionResult._(
    Map<int, Map<String, String>> paths,
    this.selectedKeptTotal,
  ) : retained = Map.unmodifiable(
        paths.map(
          (key, value) =>
              MapEntry(key, Map<String, String>.unmodifiable(value)),
        ),
      );
  final Map<int, Map<String, String>> retained;
  final int selectedKeptTotal;
}

/// Verifies byte transport after the original retained cache has passed its gate.
/// Classifying the box remains the producer's responsibility; this gate never
/// reprojects pixels or recomputes any official numerical operation.
Future<RegionRetentionResult> verifyRegionRetention({
  required ReconstructionRegion region,
  required String originalDirectory,
  required List<String> frameBits,
  required int originalKeptTotal,
  required Future<File> Function(String) regularFile,
  required Future<void> Function(String) verifyProduced,
}) async {
  final count = checkedFrameCount(frameBits.length);
  final selected = region.selectedDepthDir;
  if (originalDirectory.isEmpty ||
      originalDirectory.startsWith('/') ||
      originalDirectory.contains('\\') ||
      originalDirectory
          .split('/')
          .any((p) => p.isEmpty || p == '.' || p == '..') ||
      selected == originalDirectory ||
      selected.startsWith('$originalDirectory/') ||
      originalDirectory.startsWith('$selected/') ||
      originalKeptTotal <= 0 ||
      originalKeptTotal > count * _pixels ||
      frameBits.any((b) => !RegExp(r'^[0-9a-f]{16}$').hasMatch(b))) {
    throw StateError('Invalid selected/original retention roots or identities');
  }
  Future<File> produced(String path) async {
    await verifyProduced(path);
    return regularFile(path);
  }

  Future<Map<String, dynamic>> read(String path) async {
    final value = jsonDecode(await (await produced(path)).readAsString());
    if (value is! Map<String, dynamic>) {
      throw StateError('Retained metadata object required: $path');
    }
    return value;
  }

  final manifest = await read('$selected/selection_manifest.json');
  final order = await read('$originalDirectory/order.json');
  final identityOrder = List.generate(count, (i) => i);
  if (order.length != 2 ||
      !_same(order['order'], identityOrder) ||
      order['kept_total'] != originalKeptTotal) {
    throw StateError('Original retained order/total changed');
  }
  final rows = manifest['frames'];
  if (manifest['schema'] != 'pw38_selected_retained/1' ||
      manifest['profile'] != 'original38_selected_transport_v1' ||
      manifest['plan_sha256'] != region.planSha256 ||
      manifest['image_profile'] != 'original_jpeg' ||
      manifest['pixel_order'] !=
          'C-row-major original final-valid boolean indexing' ||
      !_same(manifest['order'], identityOrder) ||
      !_same(manifest['original_indices'], identityOrder) ||
      !_same(manifest['frame_id_f64_bits'], frameBits) ||
      !_same(manifest['source_identity'], regionSelectedSourceIdentity) ||
      !_same(manifest['runtime'], {
        'python': [3, 10, 21],
        'numpy': '1.26.4',
        'opencv': '4.11.0',
        'pillow': '12.3.0',
      }) ||
      manifest['kept_total'] != originalKeptTotal ||
      manifest['original_kept_total'] != originalKeptTotal ||
      !_count(manifest['selected_kept_total'], originalKeptTotal) ||
      rows is! List ||
      rows.length != count) {
    throw StateError('Selected manifest identity/runtime/order/total mismatch');
  }
  _inputIdentity(manifest['input_identity'], frameBits);
  final retained = <int, Map<String, String>>{};
  var selectedTotal = 0, originalTotal = 0;
  for (var i = 0; i < count; i++) {
    final stem = _stem(i);
    final row = await read('$selected/$stem.json');
    if (!_same(rows[i], row) ||
        row['schema'] != 'pw38_selected_retained_frame/1' ||
        row['pack_index'] is! int ||
        row['original_index'] is! int ||
        row['pack_index'] != i ||
        row['original_index'] != i ||
        row['frame_id_f64_bits'] != frameBits[i] ||
        row['plan_sha256'] != region.planSha256 ||
        row['width'] != 1536 ||
        row['height'] != 1152 ||
        row['depth_scale'] != 5000 ||
        row['camera_layout'] != 'K9_then_E16_row_major_f64le' ||
        row['point_color_order'] != _pointColorOrder ||
        row['d16'] != '$stem.d16' ||
        row['color'] != '$stem.col.u8' ||
        row['camera'] != '$stem.camera.f64le' ||
        row['mask'] != '$stem.selection.u8' ||
        row['d16_bytes'] != _pixels * 2 ||
        row['color_bytes'] != _pixels * 3 ||
        row['camera_bytes'] != 200 ||
        row['mask_bytes'] != _pixels ||
        !_count(row['original_final_valid_count'], _pixels) ||
        !_count(
          row['selected_kept_count'],
          row['original_final_valid_count'] as int,
        )) {
      throw StateError('Selected retained tuple identity/shape mismatch: $i');
    }
    for (final field in [
      'original_d16_sha256',
      'selected_d16_sha256',
      'color_sha256',
      'camera_sha256',
      'mask_sha256',
    ]) {
      if (!_isHash(row[field])) {
        throw StateError('Selected retained hash missing: $field');
      }
    }
    final originalDepth = await produced('$originalDirectory/$stem.d16');
    final selectedDepth = await produced('$selected/$stem.d16');
    final mask = await produced('$selected/$stem.selection.u8');
    if (manifest['original_retained'] != originalDepth.parent.path ||
        row['original_retained_d16'] != originalDepth.path) {
      throw StateError('Selected retained original root binding changed');
    }
    final selectedRoot = selectedDepth.parent.path;
    final originalRoot = originalDepth.parent.path;
    if (selectedRoot == originalRoot ||
        selectedRoot.startsWith('$originalRoot/') ||
        originalRoot.startsWith('$selectedRoot/')) {
      throw StateError(
        'Selected retained roots must be separate nonnested directories',
      );
    }
    for (final entry in [
      (originalDepth, _pixels * 2, 'original_d16_sha256'),
      (selectedDepth, _pixels * 2, 'selected_d16_sha256'),
      (mask, _pixels, 'mask_sha256'),
    ]) {
      await _identity(entry.$1, entry.$2, row[entry.$3] as String);
    }
    for (final part in [
      ('$stem.camera.f64le', 200, 'camera_sha256'),
      ('$stem.col.u8', _pixels * 3, 'color_sha256'),
    ]) {
      final source = await produced('$originalDirectory/${part.$1}');
      final destination = await produced('$selected/${part.$1}');
      await _identity(source, part.$2, row[part.$3] as String);
      await _identity(destination, part.$2, row[part.$3] as String);
    }
    final kept = await _verifyMask(originalDepth, selectedDepth, mask);
    if (kept != row['selected_kept_count']) {
      throw StateError('Selected mask count mismatch: $i');
    }
    selectedTotal += kept;
    originalTotal += row['original_final_valid_count'] as int;
    retained[i] = {
      'd16': '$selected/$stem.d16',
      'camera_f64': '$selected/$stem.camera.f64le',
    };
  }
  if (selectedTotal != manifest['selected_kept_total'] ||
      originalTotal != originalKeptTotal) {
    throw StateError('Selected/original retained aggregate totals mismatch');
  }
  return RegionRetentionResult._(retained, selectedTotal);
}

String _stem(int index) => index.toString().padLeft(8, '0');
bool _count(Object? value, int maximum) =>
    value is int && value >= 0 && value <= maximum;
bool _isHash(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
bool _same(Object? a, Object? b) {
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => _same(a[i], b[i])).every((v) => v);
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
  }
  if (a is num && b is num && (a is int) != (b is int)) return false;
  return a == b;
}

void _inputIdentity(Object? value, List<String> frameBits) {
  if (value is! Map ||
      value.length != 4 ||
      value['banks'] is! List ||
      !_isHash(value['cameras_sha256']) ||
      !_isHash(value['frame_ids_sha256']) ||
      !_isHash(value['original_indices_sha256'])) {
    throw StateError('Selected input identity malformed');
  }
  final banks = value['banks'] as List;
  const kinds = ['depth', 'conf0', 'conf1', 'conf2'];
  if (banks.length != 4) throw StateError('Selected input banks missing');
  for (var i = 0; i < 4; i++) {
    final row = banks[i];
    if (row is! Map ||
        row.length != 3 ||
        row['kind'] != kinds[i] ||
        row['bytes'] != frameBits.length * _pixels * 4 ||
        !_isHash(row['sha256'])) {
      throw StateError('Selected input bank identity malformed');
    }
  }
  final ids = BytesBuilder(copy: false);
  final indices = ByteData(frameBits.length * 4);
  for (var i = 0; i < frameBits.length; i++) {
    final bits = frameBits[i];
    ids.add([
      for (var j = 14; j >= 0; j -= 2)
        int.parse(bits.substring(j, j + 2), radix: 16),
    ]);
    indices.setUint32(i * 4, i, Endian.little);
  }
  if (sha256.convert(ids.takeBytes()).toString() != value['frame_ids_sha256'] ||
      sha256.convert(indices.buffer.asUint8List()).toString() !=
          value['original_indices_sha256']) {
    throw StateError('Selected input frame/index byte identity mismatch');
  }
}

Future<void> _identity(File file, int bytes, String expectedHash) async {
  if (await file.length() != bytes ||
      (await sha256.bind(file.openRead()).first).toString() != expectedHash) {
    throw StateError('Selected retained byte identity mismatch: ${file.path}');
  }
}

Future<int> _verifyMask(File original, File selected, File mask) async {
  final handles = <RandomAccessFile>[];
  try {
    for (final file in [original, selected, mask]) {
      handles.add(await file.open());
    }
    var kept = 0;
    for (var offset = 0; offset < _pixels; offset += 32768) {
      final pixels = (_pixels - offset).clamp(0, 32768);
      final source = await handles[0].read(pixels * 2);
      final destination = await handles[1].read(pixels * 2);
      final flags = await handles[2].read(pixels);
      if (source.length != pixels * 2 ||
          destination.length != pixels * 2 ||
          flags.length != pixels) {
        throw StateError(
          'Selected retained depth/mask truncated during comparison',
        );
      }
      for (var i = 0; i < pixels; i++) {
        if (flags[i] != 0 && flags[i] != 1) {
          throw StateError('Selected mask contains nonboolean byte');
        }
        final start = i * 2;
        if (flags[i] == 1) {
          kept++;
          if (source[start] != destination[start] ||
              source[start + 1] != destination[start + 1]) {
            throw StateError('Included depth was changed or requantized');
          }
        } else if (destination[start] != 0 || destination[start + 1] != 0) {
          throw StateError('Excluded depth must be zero');
        }
      }
    }
    for (final handle in handles) {
      if ((await handle.read(1)).isNotEmpty) {
        throw StateError('Selected retained depth/mask grew during comparison');
      }
    }
    return kept;
  } finally {
    for (final handle in handles) {
      await handle.close();
    }
  }
}
