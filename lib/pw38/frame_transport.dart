import 'dart:io';
import 'package:crypto/crypto.dart';

const originalRetainedProfile = 'original_numpy_opencv_retained_v2';
const originalRetainedLegacyProfile = 'original_numpy_opencv_retained97_v1';
const wholeRetainedTransportProfile = 'whole_mixed_precision_gpu_fusion_pixel1_v1';
const officialNoiseBankCapacity = 97;
const officialLowNoiseFrameBytes = 552960;
const officialHighNoiseFrameBytes = 2211840;
const officialLowNoiseBankSha256 =
    'be0a6856547538a5a10537e9c64390e8db7e9eac7e0a39ca563b01ff7ce27984';
const officialHighNoiseBankSha256 =
    '77b9df4766b323048b02a8dfecd1fd46d375a5be8c4492d8d8c6aed5c4c1b6b1';
const officialNoiseProducerSha256 =
    'aa09d2db3c79d940d0f741fae4dcd0523bf02d8ff69145cf98d5ed47aff4703f';

bool variableFrameTransport(Map<String, dynamic> request) =>
    request['dense_producer_profile'] == originalRetainedProfile ||
    request['dense_producer_profile'] == wholeRetainedTransportProfile;
int checkedFrameCount(int count) {
  if (count <= 0 || count > officialNoiseBankCapacity) {
    throw StateError(
      'Positive actual frame count within authenticated official noise bank capacity97 required; no frame selection is permitted',
    );
  }
  return count;
}

int frameTransportCount(Map<String, dynamic> request, {int? actualCount}) {
  final profile = request['dense_producer_profile'];
  if (profile != null &&
      profile != originalRetainedProfile &&
      profile != originalRetainedLegacyProfile &&
      profile != wholeRetainedTransportProfile)
    throw StateError('Unsupported explicit dense producer profile');
  final declared = request['ordered_frames'];
  if (variableFrameTransport(request) &&
      actualCount == null &&
      declared is! int)
    throw StateError('V2 requires explicit actual ordered frame count');
  final count = actualCount ?? (declared is int ? declared : 97);
  checkedFrameCount(count);
  if (profile == wholeRetainedTransportProfile && declared != null && declared != count) {
    throw StateError('Whole declared and actual frame count mismatch');
  }
  if (profile == wholeRetainedTransportProfile && count < 10) {
    throw StateError('Whole production transport requires actual10..97 frames');
  }
  if (!variableFrameTransport(request) && count != 97) {
    throw StateError('Legacy transport requires exactly97 frames');
  }
  if (actualCount == null && declared != null && declared != count)
    throw StateError('Actual frame count mismatch');
  return count;
}

/// Adapts an authenticated capacity97 recipe to an actual ordered capture.
/// This is a template-only operation: effective requests must still use the
/// strict [frameTransportCount] mismatch gate. The frozen recipe is not mutated.
int frameTransportTemplateActualCount(
  Map<String, dynamic> frozenRecipe, {
  required int actualCount,
}) {
  if (frozenRecipe['ordered_frames'] != officialNoiseBankCapacity ||
      frameTransportCount(frozenRecipe) != officialNoiseBankCapacity) {
    throw StateError('Frozen capacity97 frame transport template required');
  }
  return frameTransportCount({
    if (frozenRecipe.containsKey('dense_producer_profile'))
      'dense_producer_profile': frozenRecipe['dense_producer_profile'],
    'ordered_frames': actualCount,
  }, actualCount: actualCount);
}

void validateFrameTransportRows(
  Map<String, dynamic> request,
  List<Map<String, dynamic>> rows,
) {
  final count = frameTransportCount(request);
  if (rows.length != count)
    throw StateError('Actual ordered frame count mismatch');
  for (var i = 0; i < count; i++) {
    if (rows[i]['pack_index'] != i || rows[i]['original_index'] != i)
      throw StateError('Actual ordered frame indices changed');
  }
}

int lowNoiseBytes(int count) =>
    checkedFrameCount(count) * officialLowNoiseFrameBytes;
int highNoiseBytes(int count) =>
    checkedFrameCount(count) * officialHighNoiseFrameBytes;

/// Lossless byte transport from the authenticated official per-frame seed bank.
/// No random draw, pose, matrix, image or depth computation occurs here.
Future<Map<String, dynamic>> copyOfficialNoisePrefix({
  required File source,
  required File destination,
  required int count,
  required bool high,
  required String expectedBankSha256,
}) async {
  final n = checkedFrameCount(count);
  final block = high ? officialHighNoiseFrameBytes : officialLowNoiseFrameBytes;
  final expected = high
      ? officialHighNoiseBankSha256
      : officialLowNoiseBankSha256;
  Future<String> hash(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();
  if (await FileSystemEntity.type(source.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await source.resolveSymbolicLinks() != source.path)
    throw StateError('Canonical regular official noise bank required');
  if (expectedBankSha256 != expected ||
      await source.length() != block * officialNoiseBankCapacity ||
      await hash(source) != expected)
    throw StateError('Official noise bank identity mismatch');
  if (await FileSystemEntity.type(destination.path, followLinks: false) !=
      FileSystemEntityType.notFound)
    throw StateError('Fresh request-owned noise prefix required');
  await destination.parent.create(recursive: true);
  final sink = destination.openWrite();
  try {
    await sink.addStream(source.openRead(0, n * block));
    await sink.flush();
  } finally {
    await sink.close();
  }
  final prefixHash = (await sha256.bind(source.openRead(0, n * block)).first)
      .toString();
  if (await destination.length() != n * block ||
      await hash(destination) != prefixHash ||
      await hash(source) != expected)
    throw StateError('Official noise prefix byte identity changed');
  return {
    'path': destination.path,
    'bytes': n * block,
    'sha256': prefixHash,
    'source_bank_sha256': expected,
    'source_bank_frames': officialNoiseBankCapacity,
    'ordered_frames': n,
    'frame_bytes': block,
    'source_offset': 0,
    'seed_base': 0,
    'seed_rule': 'torch.manual_seed(0 + frame_index)',
    'draw_order': 'stage2_then_stage3_randn_like',
    'copy_kind': 'exact_first_N_frame_blocks',
  };
}

void validateNoisePrefixIdentity(Map<String, dynamic> noise, int count) {
  final streams = noise['prefix_streams'];
  if (noise['kind'] != 'official_PyTorch_CPU_E0_seed0_prefix' ||
      noise['ordered_frames'] != count ||
      streams is! Map ||
      noise['source_producer_sha256'] != officialNoiseProducerSha256)
    throw StateError('Source-recorded actual noise prefix required');
  for (final high in [false, true]) {
    final row = streams[high ? 'high' : 'low'];
    if (row is! Map ||
        row['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['sha256'] as String) ||
        row['ordered_frames'] != count ||
        row['source_bank_frames'] != officialNoiseBankCapacity ||
        row['source_bank_sha256'] !=
            (high ? officialHighNoiseBankSha256 : officialLowNoiseBankSha256) ||
        row['frame_bytes'] !=
            (high ? officialHighNoiseFrameBytes : officialLowNoiseFrameBytes) ||
        row['bytes'] != (high ? highNoiseBytes(count) : lowNoiseBytes(count)) ||
        row['sha256'] != noise[high ? 'high_sha256' : 'low_sha256'] ||
        row['source_offset'] != 0 ||
        row['seed_base'] != 0 ||
        row['seed_rule'] != 'torch.manual_seed(0 + frame_index)' ||
        row['draw_order'] != 'stage2_then_stage3_randn_like' ||
        row['copy_kind'] != 'exact_first_N_frame_blocks')
      throw StateError('Official per-frame seed/draw/prefix identity mismatch');
    if (count == officialNoiseBankCapacity &&
        row['sha256'] != row['source_bank_sha256'])
      throw StateError('Full97 bank bytes must remain identical');
  }
}

int cameraTableBytes(int count) => checkedFrameCount(count) * 36 * 4;
int neighborTableBytes(int count) => checkedFrameCount(count) * 9 * 4;
int originalImageTableBytes(int count) =>
    checkedFrameCount(count) * 576 * 768 * 2;
int mergedCerBytes(int count) => checkedFrameCount(count) * 1536 * 1152 * 4;
