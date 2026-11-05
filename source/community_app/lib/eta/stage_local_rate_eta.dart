import 'eta_prior_log.dart';
import 'upstream/chromium_rate_estimator.dart';
import 'upstream/firefox_download_speed.dart';

enum EtaExecutionContext { foreground, background, paused }

/// Product composition, NOT a combined algorithm published by either browser.
/// Exact Chromium integer buckets measure only THIS stage and execution context;
/// exact Firefox's 0.1/0.9 speed recurrence smooths those window observations.
/// Actual completed units use 1e6 integer work ticks so sub-unit/second rates
/// survive Chromium's integer output. This conversion is an explicit adapter.
/// No synthetic completion, temperature coefficient, stage ordinal weighting or
/// extrapolation from one heterogeneous stage to another is performed.
class StageLocalRateEta {
  StageLocalRateEta({
    required this.stages,
    required this.priors,
    required int startMs,
    this.sourceEventClock = false,
    EtaExecutionContext context = EtaExecutionContext.foreground,
  }) : _context = context,
       _lastNow = startMs,
       _lastReadNow = startMs;

  static const _ticksPerUnit = 1000000;
  static String priorKey(String stage, EtaExecutionContext context) =>
      'eta38.browser.v1.${context.name}.$stage';
  final List<String> stages;
  final bool sourceEventClock;
  int _lastReadNow;
  final EtaPriorLog priors;
  EtaExecutionContext _context;
  EtaExecutionContext get context => _context;
  String? _active;
  int? _enteredAt;
  EtaExecutionContext? _enteredContext;
  bool _mixedContext = false;
  bool _wholeStageStartKnown = true;
  int _lastNow;
  ChromiumRateEstimator? _window;
  FirefoxEma _ema = FirefoxEma();
  int? _lastSampleAt, _lastIncrementAt;
  bool _awaitingBaseline = true;
  final Map<String, int> _units = {}, _done = {};
  final Set<String> _completed = {};
  final Map<String, ({int units, int ms})> _pendingCosts = {};
  bool _finished = false;
  bool get finished => _finished;
  int get observedCostCount => _pendingCosts.length;

  int _now(int nowMs) {
    if (nowMs > _lastNow) _lastNow = nowMs;
    return _lastNow;
  }

  String? get activeStage => _active;
  int done(String stage) => _done[stage] ?? 0;
  void setUnits(String stage, int units) {
    if (units >= done(stage)) _units[stage] = units;
  }

  void _resetRate(int now) {
    _window = ChromiumRateEstimator(nowMs: now);
    _ema = FirefoxEma();
    _lastSampleAt = null;
    _lastIncrementAt = null;
    _awaitingBaseline = true;
  }

  /// Explicit lost observation boundary, e.g. lifecycle transitions while the
  /// asynchronous history load had not created this estimator yet.
  void invalidateActiveObservation(int nowMs) {
    if (_finished) return;
    _mixedContext = true;
    _wholeStageStartKnown = false;
    _resetRate(_now(nowMs));
  }

  void setContext(EtaExecutionContext context, int nowMs) {
    if (_finished || context == _context) return;
    final now = _now(nowMs);
    if (_active != null) _mixedContext = true;
    _context = context;
    _resetRate(now);
  }

  void enter(String stage, int nowMs) {
    if (_finished || !stages.contains(stage) || stage == _active) return;
    final index = stages.indexOf(stage);
    if (_active != null && index < stages.indexOf(_active!)) return;
    final now = _now(nowMs);
    _closeActive(now);
    for (final preceding in stages.take(index)) {
      _completed.add(preceding);
    }
    _active = stage;
    _enteredAt = now;
    _enteredContext = _context;
    _mixedContext = _context == EtaExecutionContext.paused;
    _wholeStageStartKnown = true;
    _resetRate(now);
  }

  void _closeActive(int now) {
    final id = _active;
    final entered = _enteredAt;
    if (id == null || entered == null) return;
    if (_wholeStageStartKnown &&
        !_mixedContext &&
        _enteredContext != EtaExecutionContext.paused &&
        now > entered &&
        (_units[id] ?? 1) > 0) {
      _pendingCosts[priorKey(id, _enteredContext!)] = (
        units: _units[id] ?? 1,
        ms: now - entered,
      );
    }
    _completed.add(id);
  }

  void observeUnits(String stage, int doneUnits, int total, int nowMs) {
    if (_finished || total <= 0 || doneUnits < 0 || doneUnits > total) return;
    final now = _now(nowMs);
    enter(stage, now);
    if (stage != _active) return;
    setUnits(stage, total);
    final before = done(stage);
    if (_awaitingBaseline) {
      if (doneUnits > 0 && now == _enteredAt) _wholeStageStartKnown = false;
      // The first count can include work before the stage/context boundary.
      // Keep its completed work, but never assign that interval to a new rate.
      _done[stage] = doneUnits > before ? doneUnits : before;
      _resetRate(now);
      _awaitingBaseline = false;
      return;
    }
    if (doneUnits <= before) return;
    _done[stage] = doneUnits;
    if (_context == EtaExecutionContext.paused) return;
    var ticks = (doneUnits - before) * _ticksPerUnit;
    while (ticks > 0) {
      final increment = ticks > 0xffffffff ? 0xffffffff : ticks;
      _window!.increment(increment, now);
      ticks -= increment;
    }
    _lastIncrementAt = now;
  }

  /// An actual owner-reported stage boundary, never a guessed progress unit.
  /// Calling this without an observed start cannot publish a whole-stage cost.
  void completeObservedStage(String stage, int nowMs) {
    if (_finished || !stages.contains(stage) || _completed.contains(stage)) {
      return;
    }
    final now = _now(nowMs);
    if (stage != _active) {
      enter(stage, now);
      _wholeStageStartKnown = false;
    }
    if (stage != _active) return;
    _done[stage] = _units[stage] ?? 0;
    _closeActive(now);
    _active = null;
    _enteredAt = null;
  }

  double? _priorSeconds(String id) {
    final cost = priors.entries[priorKey(id, _context)];
    if (cost == null || cost.units <= 0 || cost.ms <= 0) return null;
    final remaining = (_units[id] ?? cost.units) - done(id);
    return cost.ms / cost.units * remaining / 1000;
  }

  double? secondsAt(int nowMs) {
    if (_finished) return 0;
    // Display refreshes must not advance the observed source-event clock:
    // one trace read can deliver earlier boundaries after a ticker fired.
    final now = sourceEventClock
        ? (_lastReadNow = nowMs > _lastReadNow ? nowMs : _lastReadNow)
        : _now(nowMs);
    if (_context == EtaExecutionContext.paused || _active == null) return null;
    var remaining = 0.0;
    for (final id in stages) {
      if (_completed.contains(id) || _units[id] == 0) continue;
      final unitsRemaining = (_units[id] ?? 1) - done(id);
      if (unitsRemaining <= 0) continue;
      double? seconds;
      if (id == _active) {
        final lastWork = _lastIncrementAt;
        if (lastWork != null) {
          // A stopped/stale native counter cannot mean ETA=0 or simulated work.
          if (now - lastWork >= _window!.windowDurationMs) return null;
          final sampleAt = sourceEventClock && _lastNow < now ? _lastNow : now;
          if (_lastSampleAt == null || sampleAt - _lastSampleAt! >= 1000) {
            final rate = _window!.countPerSecond(sampleAt);
            _ema.observeRawSpeed(rate.toDouble());
            _lastSampleAt = sampleAt;
          }
          if (_ema.speed > 0) {
            seconds = unitsRemaining * _ticksPerUnit / _ema.speed;
          }
        } else if (!_mixedContext) {
          final prior = _priorSeconds(id);
          if (prior != null) seconds = prior - (now - _enteredAt!) / 1000;
        }
      } else {
        seconds = _priorSeconds(id);
      }
      if (seconds == null || !seconds.isFinite || seconds <= 0) return null;
      remaining += seconds;
    }
    return remaining > 0 ? remaining : null;
  }

  /// Called only after the owner confirms its complete successful route.
  /// Full38 additionally requires durable GLB publication; sparse segment
  /// success is not the global user-facing completion boundary.
  /// Failed/interrupted runs never publish partially observed timing priors.
  void finish(int nowMs) {
    if (_finished) return;
    _closeActive(_now(nowMs));
    _finished = true;
    for (final entry in _pendingCosts.entries) {
      priors.record(entry.key, units: entry.value.units, ms: entry.value.ms);
    }
  }
}
