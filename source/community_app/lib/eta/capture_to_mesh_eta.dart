import 'eta_prior_log.dart';
import 'full38_eta.dart';
import 'pipeline_eta.dart';
import 'stage_local_rate_eta.dart';

/// Product accounting adapter: Finish means final durable textured/normal GLB,
/// never sparse completion. Sparse's browser-rate remainder is one
/// component; every unstarted original38 stage supplies its own compatible cost.
/// This is not a newly claimed upstream predictor or reconstruction algorithm.
class CaptureToMeshEta {
  CaptureToMeshEta({
    required this.priors,
    required int photoCount,
    this.wholeRoute = false,
    EtaExecutionContext context = EtaExecutionContext.foreground,
  }) : _photoCount = photoCount,
       _context = context;

  final EtaPriorLog priors;
  final bool wholeRoute;
  int _photoCount;
  EtaExecutionContext _context;

  void updatePhotoCount(int count) {
    if (count > 0) _photoCount = count;
  }

  void setContext(EtaExecutionContext context) {
    _context = context;
  }

  double? _pendingFull38Seconds() {
    if (_photoCount <= 0 || _context == EtaExecutionContext.paused) return null;
    var totalMs = 0.0;
    for (final id
        in (wholeRoute ? Full38Eta.wholeStageIds : Full38Eta.stageIds)) {
      // Original38's retained-feature path has no extra feature invocation.
      if (id == 'full38.features') continue;
      final units = Full38Eta.isWholeCounter(id)
          ? _photoCount
          : switch (id) {
              'full38.images' || 'full38.fusion' => _photoCount,
              'full38.infer_merge' => _photoCount * 2,
              _ => 1,
            };
      final cost = priors.entries[StageLocalRateEta.priorKey(id, _context)];
      if (cost == null || cost.units <= 0 || cost.ms <= 0) return null;
      totalMs += cost.ms / cost.units * units;
    }
    return totalMs / 1000;
  }

  EtaLabel? duringSparse(EtaLabel? sparseRemaining) {
    final sparseSeconds = sparseRemaining?.remainingSeconds;
    if (sparseSeconds == null || sparseSeconds <= 0) return null;
    final pending = _pendingFull38Seconds();
    if (pending == null || !pending.isFinite || pending <= 0) return null;
    return EtaLabel.countdown((sparseSeconds + pending).ceil());
  }

  /// The production owner emits global done only AFTER GLB bytes verified,
  /// record attachment persisted and completion marker written. Native dense
  /// done or the sparse clock reaching zero cannot satisfy this boundary.
  static EtaLabel? duringFull38(
    EtaLabel? remaining, {
    required bool durablePublished,
  }) {
    final seconds = remaining?.remainingSeconds;
    if (seconds == null || seconds < 0 || (seconds == 0 && !durablePublished)) {
      return null;
    }
    return remaining;
  }
}
