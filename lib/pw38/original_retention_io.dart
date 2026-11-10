import 'dart:convert';
import 'dart:io';
import 'production_original_fixture_binding.dart'
    show OriginalFixtureExecutionProof;

import 'frame_transport.dart';
export 'frame_transport.dart' show originalRetainedProfile;

const originalRetained97Profile = 'original_numpy_opencv_retained97_v1';
/// Retained D16/camera/color/order layout only, not an algorithm parity claim.
/// The whole GPU producer shares this layout but remains a distinct profile.
bool usesOriginalRetained97(Map<String, dynamic> request) {
  if (!request.containsKey('dense_producer_profile')) return false;
  if ((request['dense_producer_profile'] == originalRetained97Profile || request['dense_producer_profile'] == originalRetainedProfile || request['dense_producer_profile'] == wholeRetainedTransportProfile))
    return true;
  throw StateError('Unsupported explicit dense producer profile');
}

/// Only the actual in-worker whole producer execution can create this capability.
/// Callers must also await proof revalidation at each preparation/execution gate.
/// No JSON label or receipt hash can construct a proof or authorize a capture.
void requireProductionDenseProvenance(
  Map<String, dynamic> request, {
  OriginalFixtureExecutionProof? proof,
}) {
  if (usesOriginalRetained97(request) && proof == null) {
    throw StateError(
      'STOPPED: original production camera/neighbor source identity and numerical proof not established; dedicated frozen-table entry required',
    );
  }
}

/// Retained producer transport only; no camera, depth or pixel arithmetic.
Future<int> readOriginalRetained97({
  required String directory,
  String profile = originalRetained97Profile,
  required List<String> frameBits,
  required Future<File> Function(String) regularFile,
  required Future<void> Function(String) verifyProduced,
  required Map<int, Map<String, String>> retained,
}) async {
  final count = frameTransportCount({'dense_producer_profile': profile}, actualCount: frameBits.length);
  if (frameBits.length != count)
    throw StateError('Original cache requires97 frame identities');
  final orderPath = '$directory/order.json';
  await verifyProduced(orderPath);
  final order =
      jsonDecode(await (await regularFile(orderPath)).readAsString()) as Map;
  final indices = order['order'];
  final kept = order['kept_total'];
  if (order.length != 2 ||
      indices is! List ||
      indices.length != count ||
      kept is! int ||
      kept <= 0 ||
      kept > count * 1536 * 1152) {
    throw StateError('Original cache order/kept_total mismatch');
  }
  for (var i = 0; i < count; i++) {
    if (indices[i] is! int || indices[i] != i)
      throw StateError('Original ascending97 order mismatch');
  }
  final observed = <int, Map<String, String>>{};
  for (var i = 0; i < count; i++) {
    final stem = i.toString().padLeft(8, '0');
    final metaPath = '$directory/$stem.json';
    await verifyProduced(metaPath);
    final meta =
        jsonDecode(await (await regularFile(metaPath)).readAsString()) as Map;
    if (meta['schema'] != 1 ||
        meta['pack_index'] != i ||
        meta['original_index'] != i ||
        meta['frame_id_f64_bits'] != frameBits[i] ||
        meta['width'] != 1536 ||
        meta['height'] != 1152 ||
        meta['depth_scale'] != 5000 ||
        meta['d16'] != '$stem.d16' ||
        meta['d16_bytes'] != 3538944 ||
        meta['camera'] != '$stem.camera.f64le' ||
        meta['camera_bytes'] != 200 ||
        meta['camera_layout'] != 'K9_then_E16_row_major_f64le') {
      throw StateError('Actual original tuple identity/shape mismatch: $i');
    }
    for (final part in [
      ('$stem.d16', 3538944),
      ('$stem.camera.f64le', 200),
      ('$stem.col.u8', 5308416),
    ]) {
      final path = '$directory/${part.$1}';
      await verifyProduced(path);
      if (await (await regularFile(path)).length() != part.$2) {
        throw StateError(
          'Actual original retained payload size mismatch: $path',
        );
      }
    }
    observed[i] = {
      'd16': '$directory/$stem.d16',
      'camera_f64': '$directory/$stem.camera.f64le',
    };
  }
  retained
    ..clear()
    ..addAll(observed);
  return kept;
}
