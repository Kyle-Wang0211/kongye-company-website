// Original38 browser-rate trial + real event counters; legacy routes retain Ninja.
// The live display clock is
// separate from the historical first-label ruler; page re-entry cannot reset it.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../../dense/dense_stage_progress.dart';
import '../../dense/pw38_background_execution.dart';
import '../../eta/stage_local_rate_eta.dart';
import '../../eta/upstream/upstream_notices.dart';
import '../../eta/eta_prior_log.dart';
import '../../eta/full38_eta.dart';
import '../../eta/pipeline_eta.dart';
import '../../official_capture/telemetry_writer.dart';
import '../../official_util/device_log.dart';

const String kDenseEtaPriorLogName = 'official_eta_prior_log.json';

class DenseWaitEta with WidgetsBindingObserver {
  DenseWaitEta._()
    : _progress = denseStageProgress,
      _backgroundReports = Pw38BackgroundCoordinator.instance.state,
      _wholeRoute = true,
      _injectedPriors = null,
      _injectedNow = null;

  @visibleForTesting
  DenseWaitEta.forTesting({
    required ValueNotifier<DenseStageProgress?> progress,
    required Future<EtaPriorLog> Function() priorsLoader,
    required int Function() nowMs,
    bool wholeRoute = false,
    ValueListenable<Pw38BackgroundReport?>? backgroundReports,
  }) : _progress = progress,
       _backgroundReports = backgroundReports,
       _wholeRoute = wholeRoute,
       _injectedPriors = priorsLoader,
       _injectedNow = nowMs;

  static final DenseWaitEta instance = DenseWaitEta._();

  /// Whole-job live seconds; null means an unavailable/exhausted prediction.
  /// Full38 never reuses the legacy four-stage history as a complete estimate.
  final ValueNotifier<EtaLabel?> label = ValueNotifier<EtaLabel?>(null);
  final ValueNotifier<DenseStageProgress?> _progress;
  final ValueListenable<Pw38BackgroundReport?>? _backgroundReports;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  EtaExecutionContext _observedContext = EtaExecutionContext.foreground;
  int _contextRevision = 0;
  int? _sourceAnchorMono, _sourceAnchorOwnerMs;
  int? _contextBoundaryAt;
  final bool _wholeRoute;
  final Future<EtaPriorLog> Function()? _injectedPriors;
  final int Function()? _injectedNow;
  final Stopwatch _clock = Stopwatch()..start();
  final int _clockOrigin = DateTime.now().millisecondsSinceEpoch;
  int get _now =>
      _injectedNow?.call() ?? _clockOrigin + _clock.elapsedMilliseconds;
  String? _captureDir;
  DateTime? _startedAt;
  PipelineEta? _eta;
  Full38Eta? _full38;
  EtaPriorLog? _priors;
  bool _attached = false;
  bool _terminal = false;
  int _generation = 0;
  Timer? _ticker;
  Future<EtaPriorLog>? _priorsLoading;

  /// Idempotent across viewer re-entry: ownership belongs to the job, not page.
  void ensureAttached() {
    if (_attached) return;
    _attached = true;
    registerEtaUpstreamLicenses();
    WidgetsBinding.instance.addObserver(this);
    if (_injectedNow == null) {
      _lifecycle =
          WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    }
    _backgroundReports?.addListener(_onContextChanged);
    _progress.addListener(_onProgress);
    _onProgress();
  }

  PipelineEta? get current => _eta;

  EtaExecutionContext get _context {
    if (_lifecycle == AppLifecycleState.resumed ||
        _lifecycle == AppLifecycleState.inactive) {
      return EtaExecutionContext.foreground;
    }
    final report = _backgroundReports?.value;
    if ((_lifecycle == AppLifecycleState.paused ||
            _lifecycle == AppLifecycleState.hidden) &&
        report?.captureDir == _captureDir &&
        report?.granted == true) {
      return EtaExecutionContext.background;
    }
    // A submitted request, missing grant or detached app
    // is not evidence of ongoing compute. No countdown through suspension.
    return EtaExecutionContext.paused;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _onContextChanged();
  }

  void _onContextChanged() {
    final context = _context;
    if (context != _observedContext) {
      _observedContext = context;
      _contextRevision++;
      _contextBoundaryAt = _now;
    }
    _full38?.setExecutionContext(context, _now);
    _refresh();
  }

  Future<EtaPriorLog> _loadPriors() => _priorsLoading ??= () async {
    if (_injectedPriors != null) return _injectedPriors();
    try {
      final docs = await getApplicationDocumentsDirectory();
      final log = EtaPriorLog(File('${docs.path}/$kDenseEtaPriorLogName'));
      await log.load();
      return log;
    } catch (e) {
      DeviceLog.log('DenseWaitEta', 'prior log unavailable: $e');
      return EtaPriorLog(
        File('${Directory.systemTemp.path}/$kDenseEtaPriorLogName'),
      );
    }
  }();

  void _onProgress() {
    final p = _progress.value;
    if (p == null) {
      _ticker?.cancel();
      _generation++;
      _captureDir = null;
      _eta = null;
      _full38 = null;
      label.value = null;
      return;
    }
    if (p.captureDir != _captureDir ||
        p.startedAt != _startedAt ||
        (_terminal && p.state == DenseStageState.running)) {
      _ticker?.cancel();
      _generation++;
      _sourceAnchorMono = null;
      _sourceAnchorOwnerMs = null;
      _contextBoundaryAt = null;
      _captureDir = p.captureDir;
      _startedAt = p.startedAt;
      _observedContext = _context;
      _eta = null;
      _full38 = null;
      _terminal = false;
      label.value = null;
      _priorsLoading = null;
      if (p.state == DenseStageState.running) unawaited(_plan(p, _generation));
    }
    final eta = _eta;
    if (eta == null) return;
    final now = _now;
    switch (p.state) {
      case DenseStageState.running:
        final full = _full38;
        if (full != null) {
          final source = p.sourceTime;
          var eventMs = now;
          if (source != null) {
            _sourceAnchorMono ??= source.monoNs;
            _sourceAnchorOwnerMs ??=
                source.wallNs ~/ 1000000 +
                now -
                (_injectedNow != null
                    ? now
                    : DateTime.now().millisecondsSinceEpoch);
            eventMs =
                _sourceAnchorOwnerMs! +
                (source.monoNs - _sourceAnchorMono!) ~/ 1000000;
          }
          final crossesContext =
              source != null &&
              _contextBoundaryAt != null &&
              eventMs < _contextBoundaryAt!;
          final repeatedWholeCount =
              full.rate.activeStage == 'full38.${p.phase}' &&
              p.done <= full.rate.done('full38.${p.phase}');
          final missingClock =
              source == null &&
              p.phase.startsWith('whole_') &&
              !repeatedWholeCount;
          final timingUnknown = crossesContext || missingClock || eventMs > now;
          if (timingUnknown) full.rate.invalidateActiveObservation(now);
          full.observe(p.phase, p.done, p.total, timingUnknown ? now : eventMs);
          if (timingUnknown) full.rate.invalidateActiveObservation(now);
        } else {
          final id = _legacyStageId(p.phase);
          if (id != null && p.total > 0) {
            eta.setUnits(id, p.total);
            for (final stage in eta.stages) {
              if (stage.id == id) break;
              eta.markStageDone(stage.id, now);
            }
            eta.markUnits(id, p.done, now);
          }
        }
        _refresh();
      case DenseStageState.done:
      case DenseStageState.failed:
        _finish(ok: p.state == DenseStageState.done);
    }
  }

  static String? _legacyStageId(String phase) => switch (phase) {
    'session' => 'dense.session',
    'images' => 'dense.images',
    'infer' => 'dense.infer',
    'fuse' => 'dense.fuse',
    _ => null,
  };

  Future<void> _plan(DenseStageProgress p, int generation) async {
    final startMs = p.startedAt?.millisecondsSinceEpoch ?? _now;
    final initialContext = _context;
    final initialContextRevision = _contextRevision;
    final priors = await _loadPriors();
    if (generation != _generation || _eta != null) return;
    _priors = priors;
    // Production full38 always publishes `preparing` BEFORE asynchronous input
    // gathering. Its complete plan must exist before the first native callback.
    final full38 =
        p.phase == 'preparing' ||
        p.phase == 'input_preparation' ||
        p.phase == 'pw_full38_dense_run' ||
        p.phase == 'pw38_production_whole_run_v1' ||
        p.phase.startsWith('whole_') ||
        Full38Eta.downstream.contains(p.phase);
    if (full38) {
      _full38 = Full38Eta(
        priors: priors,
        wholeRoute: _wholeRoute,
        startMs: startMs,
        context: initialContext,
      );
      if (initialContextRevision != _contextRevision) {
        // Loading storage must not erase lifecycle transitions, including a
        // round trip back to the original context. No same-context timing is
        // knowable across this unobserved interval.
        _full38!.rate.invalidateActiveObservation(_now);
      }
      _full38!.setExecutionContext(_context, _now);
      _eta = _full38!.pipeline;
    } else {
      _eta = PipelineEta(
        stages: const [
          EtaStage('dense.session', 1),
          EtaStage('dense.images', 1),
          EtaStage('dense.infer', 1),
          EtaStage('dense.fuse', 1),
        ],
        priors: priors,
        startMs: startMs,
      );
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    _onProgress();
  }

  void _refresh() {
    final eta = _eta;
    if (eta == null || _terminal) return;
    if (_context == EtaExecutionContext.paused) {
      label.value = null;
      return;
    }
    label.value =
        _full38?.countdownAt(_now) ??
        (_full38 == null ? eta.countdownAt(_now) : null);
  }

  void _finish({required bool ok}) {
    final eta = _eta;
    if (eta == null || _terminal) return;
    _terminal = true;
    _ticker?.cancel();
    if (!ok) {
      // Failed/interrupted execution is not a completed timing prior.
      label.value = null;
      return;
    }
    final now = _now;
    final EtaRulerResult r;
    if (_full38 != null) {
      r = _full38!.finish(now);
    } else {
      for (final stage in eta.stages) {
        eta.markStageDone(stage.id, now);
      }
      r = eta.finish(now);
    }
    label.value = eta.countdownAt(now);
    if (_injectedNow == null) {
      TelemetryWriter.instance.event('eta_ruler', {
        ...r.toTelemetry(),
        'job': _full38 == null ? 'dense' : 'full38',
        'ok': true,
      });
      DeviceLog.log('DenseWaitEta', 'completed timing log: ${r.toTelemetry()}');
      unawaited(
        _priors?.save().catchError((Object e) {
          DeviceLog.log('DenseWaitEta', 'prior log save failed: $e');
        }),
      );
    }
  }

  @visibleForTesting
  void disposeForTesting() {
    _ticker?.cancel();
    _generation++;
    _progress.removeListener(_onProgress);
    _backgroundReports?.removeListener(_onContextChanged);
    if (_attached) WidgetsBinding.instance.removeObserver(this);
    label.dispose();
  }
}
