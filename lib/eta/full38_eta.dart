import 'eta_prior_log.dart';
import 'pipeline_eta.dart';
import 'stage_local_rate_eta.dart';

/// Original38 event adapter with stage-local browser-rate trial ETA.
/// Reconstruction arithmetic, counters and recipe are unchanged.
///
/// The existing native dense call reports session/images/features/infer/fusion.
/// `infer` counts BOTH resolutions and includes the high-pass CER merge; its
/// elapsed time must not be presented as three separately measured stages.
/// The Dart mainline journals downstream stage STARTS with the number of
/// previously completed stages. Native `done` only finishes the dense call.
/// The final GLB stage includes durable record publication before global done.
///
/// Units are actual callback totals. Unknown future totals start from the last
/// successful run, corrected when real photo/counter totals arrive. Numeric
/// full-chain estimates require measured priors for every unfinished stage;
/// sparse/legacy dense logs never stand in for missing downstream durations.
class Full38Eta {
  Full38Eta({
    required this.priors,
    required int startMs,
    this.wholeRoute = false,
    EtaExecutionContext context = EtaExecutionContext.foreground,
  }) {
    // Keep Ninja's historical ruler separate: its unqualified timing records
    // must not contaminate context-qualified browser ETA priors.
    final rulerPriors = EtaPriorLog(priors.file);
    for (final entry in priors.entries.entries) {
      rulerPriors.record(
        entry.key,
        units: entry.value.units,
        ms: entry.value.ms,
      );
    }
    rate = StageLocalRateEta(
      stages: activeStageIds,
      sourceEventClock: wholeRoute,
      priors: priors,
      startMs: startMs,
      context: context,
    );
    for (final id in activeStageIds) {
      rate.setUnits(id, id == 'full38.features' ? 0 : _previousUnits(id));
    }
    rate.enter(activeStageIds.first, startMs);
    pipeline = PipelineEta(
      stages: [
        for (final id in activeStageIds)
          EtaStage(id, id == 'full38.features' ? 0 : _previousUnits(id)),
      ],
      priors: rulerPriors,
      startMs: startMs,
    );
  }

  static const stageIds = [
    'full38.preparing',
    'full38.session',
    'full38.images',
    'full38.features',
    'full38.infer_merge',
    'full38.fusion',
    'full38.tsdf',
    'full38.trim',
    'full38.meshopt',
    'full38.lagrange',
    'full38.texture',
    'full38.avVisibility',
    'full38.avSfmToAbc',
    'full38.avNormal',
    'full38.glb',
  ];
  // Whole-owner production reports these actual phases, not the retired
  // session/images/infer counters. Keep its costs separate from that recipe.
  static const wholeStageIds = [
    'full38.whole_preparing',
    'full38.whole_features',
    'full38.whole_depth_low',
    'full38.whole_depth_high',
    'full38.whole_consistency',
    'full38.whole_fusion',
    'full38.tsdf',
    'full38.trim',
    'full38.meshopt',
    'full38.lagrange',
    'full38.texture',
    'full38.avVisibility',
    'full38.avSfmToAbc',
    'full38.avNormal',
    'full38.glb',
  ];
  final bool wholeRoute;
  List<String> get activeStageIds => wholeRoute ? wholeStageIds : stageIds;
  static bool isWholeCounter(String id) => const {
    'full38.whole_features',
    'full38.whole_depth_low',
    'full38.whole_depth_high',
    'full38.whole_fusion',
  }.contains(id);
  static const downstream = [
    'tsdf',
    'trim',
    'meshopt',
    'lagrange',
    'texture',
    'avVisibility',
    'avSfmToAbc',
    'avNormal',
    'glb',
  ];
  final EtaPriorLog priors;
  late final PipelineEta pipeline;
  late final StageLocalRateEta rate;

  void setExecutionContext(EtaExecutionContext context, int nowMs) =>
      rate.setContext(context, nowMs);

  int _previousUnits(String id) {
    // Non-counter stages represent one measured whole-stage invocation.
    if (!const {
          'full38.images',
          'full38.infer_merge',
          'full38.fusion',
        }.contains(id) &&
        !isWholeCounter(id)) {
      return 1;
    }
    final units =
        priors.entries[StageLocalRateEta.priorKey(id, rate.context)]?.units;
    return units != null && units > 0 ? units : 1;
  }

  void _completeBefore(String id, int nowMs) {
    rate.enter(id, nowMs);
    for (final stage in pipeline.stages) {
      if (stage.id == id) break;
      pipeline.markStageDone(stage.id, nowMs);
    }
  }

  void observe(String phase, int done, int total, int nowMs) {
    if (pipeline.finished) return;
    if (downstream.contains(phase) && total == 13) {
      // Journal events announce the upcoming stage, not its completion.
      _completeBefore('full38.$phase', nowMs);
      return;
    }
    if (phase == 'downstream_native_binding' ||
        (phase == 'done' && total == 1)) {
      _completeBefore('full38.tsdf', nowMs);
      return;
    }
    if (wholeRoute) {
      final id = 'full38.$phase';
      // Preview-only DTO copies and native final validation can repeat an
      // already observed count. They must not move the source clock to poll now.
      if (rate.activeStage == id &&
          done <= rate.done(id) &&
          pipeline.stages.any(
            (stage) => stage.id == id && stage.units == total,
          )) {
        return;
      }
      if (!wholeStageIds.contains(id) ||
          !phase.startsWith('whole_') ||
          total <= 0 ||
          done < 0 ||
          done > total)
        return;
      if (isWholeCounter(id)) {
        // Actual native photo count corrects every unstarted counted phase.
        for (final next in wholeStageIds.where(isWholeCounter)) {
          rate.setUnits(next, total);
          pipeline.setUnits(next, total);
        }
      }
      pipeline.setUnits(id, total);
      _completeBefore(id, nowMs);
      pipeline.markUnits(id, done, nowMs);
      rate.observeUnits(id, done, total, nowMs);
      return;
    }
    final id = switch (phase) {
      'session' => 'full38.session',
      'images' => 'full38.images',
      'features' => 'full38.features',
      'infer' => 'full38.infer_merge',
      'fusion' || 'fuse' => 'full38.fusion',
      _ => null,
    };
    if (id == null || total <= 0 || done < 0 || done > total) return;
    if (phase == 'images') {
      pipeline.setUnits('full38.infer_merge', total * 2);
      rate.setUnits('full38.infer_merge', total * 2);
      pipeline.setUnits('full38.fusion', total);
      rate.setUnits('full38.fusion', total);
    }
    pipeline.setUnits(id, total);
    _completeBefore(id, nowMs);
    pipeline.markUnits(id, done, nowMs);
    rate.observeUnits(id, done, total, nowMs);
  }

  EtaLabel? countdownAt(int nowMs) {
    if (pipeline.finished) return pipeline.countdownAt(nowMs);
    final seconds = rate.secondsAt(nowMs);
    return seconds == null ? null : EtaLabel.countdown(seconds.ceil());
  }

  EtaRulerResult finish(int nowMs) {
    rate.finish(nowMs);
    for (final stage in pipeline.stages) {
      pipeline.markStageDone(stage.id, nowMs);
    }
    return pipeline.finish(nowMs);
  }
}
