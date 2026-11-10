import '../official_util/worker_storage_query.dart';

const wholeDiskReserveBytes = 1073741824;

/// Known simultaneous cold arrays plus an explicitly unproven suffix floor.
/// Existing input bytes are already occupied on the queried filesystem.
int wholeColdDiskMinimum(int frames) {
  if (frames < 10 || frames > 97) throw ArgumentError.value(frames, 'frames');
  const low = 768 * 576, high = 1536 * 1152;
  return frames *
          (high * 5 +
              29859840 +
              (low + high) * 16 +
              high * 16 +
              high * 5 +
              200 +
              65536) +
      16777216 +
      2 * wholeDiskReserveBytes;
}

const wholeFailureSlotBytes = 16384;

/// Enable only when real feature last-use retirement and strict suffix gates
/// have been integrated. Without that capability, retain the legacy cold gate.
Map<String, int> wholePrefixDiskBudget(
  int frames, {
  required int manifestBytes,
  bool featureRetirementEnabled = false,
}) {
  final cold = wholeColdDiskMinimum(frames);
  if (manifestBytes < 0)
    throw ArgumentError.value(manifestBytes, 'manifestBytes');
  if (!featureRetirementEnabled) {
    return {'required_free_bytes': cold, 'manifest_bytes': manifestBytes};
  }
  final c = _wholeStageBytes(frames);
  final mvs = c['high_gray_and_rgb']! + c['feature_f16']! + c['mvs_f32']!;
  final fusion =
      c['high_gray_and_rgb']! +
      c['mvs_f32']! +
      c['cer_f32']! +
      c['retained_depth_rgb_camera']!;
  final peak = mvs > fusion ? mvs : fusion;
  return {
    'manifest_bytes': manifestBytes,
    'already_occupied_input_bytes': manifestBytes,
    'mvs_live_bytes': mvs,
    'fusion_live_bytes': fusion,
    'peak_live_generated_bytes': peak,
    'failure_slot_bytes': wholeFailureSlotBytes,
    'required_free_bytes':
        peak +
        16777216 +
        frames * 65536 +
        wholeDiskReserveBytes +
        wholeFailureSlotBytes,
  };
}

Map<String, int> _wholeStageBytes(int frames) {
  wholeColdDiskMinimum(frames); // Shared validated frame-count range.
  const low = 768 * 576, high = 1536 * 1152;
  return {
    'high_gray_and_rgb': frames * high * 5,
    'feature_f16': frames * 29859840,
    'mvs_f32': frames * (low + high) * 16,
    'cer_f32': frames * high * 16,
    'retained_depth_rgb_camera': frames * (high * 5 + 200),
  };
}

/// Already occupied files are reporting-only; never subtract or charge twice.
/// For unknown mesh/texture outputs callers must establish a positive byte bound.
Map<String, int> wholeStageDiskBudget(
  int frames,
  String stage, {
  required int existingLiveBytes,
  int? remainingWriteBytes,
  bool failureSlotAllocated = false,
}) {
  if (existingLiveBytes < 0 || stage.isEmpty) {
    throw ArgumentError('Measured live bytes and explicit stage required');
  }
  final known = _wholeStageBytes(frames)[stage];
  if (known != null) {
    if (remainingWriteBytes != null) {
      throw ArgumentError(
        'Known stage requires its complete fixed write bound',
      );
    }
    remainingWriteBytes = known;
  }
  if (remainingWriteBytes == null || remainingWriteBytes <= 0) {
    throw StateError(
      'Unknown suffix requires positive measured remaining-write bound',
    );
  }
  final failure = failureSlotAllocated ? 0 : wholeFailureSlotBytes;
  return {
    'existing_live_bytes': existingLiveBytes,
    'remaining_write_bytes': remainingWriteBytes,
    'failure_slot_bytes': failure,
    'filesystem_reserve': wholeDiskReserveBytes,
    'required_free_bytes':
        remainingWriteBytes + wholeDiskReserveBytes + failure,
  };
}

Map<String, Object?> requireWholeStageDisk(
  String path, {
  required int frames,
  required String stage,
  required int existingLiveBytes,
  int? remainingWriteBytes,
  bool failureSlotAllocated = false,
  int Function(String)? storageQuery,
  int retiredBytes = 0,
  String? retirementEvidence,
}) {
  if (retiredBytes < 0 ||
      (retiredBytes > 0 &&
          (retirementEvidence == null || retirementEvidence.isEmpty))) {
    throw ArgumentError('Actual retired bytes require their receipt source');
  }
  final plan = wholeStageDiskBudget(
    frames,
    stage,
    existingLiveBytes: existingLiveBytes,
    remainingWriteBytes: remainingWriteBytes,
    failureSlotAllocated: failureSlotAllocated,
  );
  final available = (storageQuery ?? readAvailableStorageInWorker)(path);
  requireWholeDiskBytes(available, plan['required_free_bytes']!, stage: stage);
  return {
    ...plan,
    'available_free_bytes': available,
    'required_additional_bytes': plan['required_free_bytes'],
    'remaining_stage': stage,
    'admission_enforced': false,
    'retired_bytes': retiredBytes,
    'retirement_evidence': retirementEvidence,
  };
}

void requireWholeDiskBytes(int available, int required, {String? stage}) {
  if (available < 0 || required <= 0) throw StateError('无法读取可用存储空间');
  // User policy 2026-11-03: generation budgets are observational only.
  // Last-consumer retirement runs normally; actual filesystem write failures
  // retain their original error handling. Never fabricate available bytes.
}

void requireWholeWorkerDisk(String path, {int additionalBytes = 0}) {
  if (additionalBytes < 0)
    throw ArgumentError.value(additionalBytes, 'additionalBytes');
  requireWholeDiskBytes(
    readAvailableStorageInWorker(path),
    wholeDiskReserveBytes + additionalBytes,
  );
}

bool wholeFailureNeedsProcessRestart(Object error) =>
    error.toString().contains('Whole native pending') ||
    error.toString().contains('failed process forbids new producer');

const wholeRestartRequiredMessage = '上次生成异常已停止。请完全退出并重新打开App后重试，原照片和作品会保留';
