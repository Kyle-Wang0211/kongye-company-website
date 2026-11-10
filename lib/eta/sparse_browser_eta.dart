import 'eta_prior_log.dart';
import 'pipeline_eta.dart' show EtaLabel, EtaStage;
import 'stage_local_rate_eta.dart';

/// Sparse event/plan adapter for the SAME source-pinned browser rate engine used
/// by Full38. No Ninja prediction, stage-ordinal fraction or new numeric kernel.
class SparseBrowserEta {
  SparseBrowserEta({
    required List<EtaStage> stages,
    required EtaPriorLog priors,
    required this.startMs,
    EtaExecutionContext context = EtaExecutionContext.foreground,
  }) : _stages = List.of(stages),
       _lastNow = startMs,
       rate = StageLocalRateEta(
         stages: stages.map((s) => s.id).toList(),
         priors: priors,
         startMs: startMs,
         context: context,
       ) {
    for (final stage in _stages) {
      rate.setUnits(stage.id, stage.units);
    }
    _advance(startMs);
  }

  final List<EtaStage> _stages;
  final StageLocalRateEta rate;
  final int startMs;
  int _lastNow;
  int _activeIndex = -1;
  final Set<String> _completed = {};
  bool _finished = false, _success = false;
  bool get finished => _finished;
  List<EtaStage> get stages => List.unmodifiable(_stages);
  int unitsDone(String id) => rate.done(id);

  int _now(int nowMs) {
    if (nowMs > _lastNow) _lastNow = nowMs;
    return _lastNow;
  }

  void setExecutionContext(EtaExecutionContext context, int nowMs) =>
      rate.setContext(context, _now(nowMs));
  void invalidateActiveObservation(int nowMs) =>
      rate.invalidateActiveObservation(_now(nowMs));

  void setUnits(String id, int units) {
    if (_finished || units < 0 || _completed.contains(id)) return;
    final index = _stages.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final old = _stages[index].units;
    final done = rate.done(id);
    if (units < done || (done > 0 && units < old)) return;
    _stages[index] = EtaStage(id, units);
    rate.setUnits(id, units);
  }

  void _activate(int index, int now) {
    if (index < _activeIndex) return;
    _activeIndex = index;
    rate.enter(_stages[index].id, now);
  }

  void _advance(int now) {
    for (var i = _activeIndex + 1; i < _stages.length; i++) {
      if (_stages[i].units <= 0 || _completed.contains(_stages[i].id)) continue;
      _activate(i, now);
      // A known phase boundary establishes count0 without inventing completed
      // work; subsequent actual deltas are timed in this stage/context only.
      rate.observeUnits(_stages[i].id, 0, _stages[i].units, now);
      return;
    }
  }

  void markUnits(String id, int doneUnits, int nowMs) {
    if (_finished || _completed.contains(id)) return;
    final index = _stages.indexWhere((s) => s.id == id);
    if (index < 0 || index < _activeIndex || _stages[index].units <= 0) return;
    final now = _now(nowMs);
    _activate(index, now);
    rate.observeUnits(id, doneUnits, _stages[index].units, now);
    // All queued drain frames fed is an actual phase boundary. BA iterations
    // instead report a provisional discovered total; only Refined ends BA.
    if (id == 'sparse.drain' && rate.done(id) == _stages[index].units) {
      markStageDone(id, now);
    }
  }

  void markStageDone(String id, int nowMs) {
    if (_finished || _completed.contains(id)) return;
    final index = _stages.indexWhere((s) => s.id == id);
    if (index < 0 || index < _activeIndex) return;
    final now = _now(nowMs);
    _activate(index, now);
    rate.completeObservedStage(id, now);
    _completed.add(id);
    _advance(now);
  }

  EtaLabel? countdownAt(int nowMs) {
    if (_finished) return _success ? EtaLabel.countdown(0) : null;
    final seconds = rate.secondsAt(_now(nowMs));
    return seconds == null ? null : EtaLabel.countdown(seconds.ceil());
  }

  SparseBrowserEtaResult finish(int nowMs, {required bool success}) {
    final now = _now(nowMs);
    if (!_finished) {
      _finished = true;
      _success = success;
      final complete = _stages
          .where((s) => s.units > 0)
          .every((s) => _completed.contains(s.id));
      // Preserve failed/interrupted observations in telemetry, never priors.
      if (success && complete) rate.finish(now);
    }
    return SparseBrowserEtaResult(
      success: _success,
      timingRecorded: _success && rate.finished && rate.observedCostCount > 0,
      totalSec: (now - startMs) / 1000,
      observedStages: _completed.length,
    );
  }
}

class SparseBrowserEtaResult {
  const SparseBrowserEtaResult({
    required this.success,
    required this.timingRecorded,
    required this.totalSec,
    required this.observedStages,
  });
  final bool success, timingRecorded;
  final double totalSec;
  final int observedStages;
  Map<String, Object?> toTelemetry() => {
    'estimator': 'chromium_window_firefox_ema.v1',
    'scope': 'sparse_segment_not_final_mesh',
    'ok': success,
    'timing_recorded': timingRecorded,
    'observed_complete_stages': observedStages,
    'total_s': totalSec,
  };
}
