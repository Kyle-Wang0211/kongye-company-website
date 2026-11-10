// dense_stage_progress.dart — the one observable the UI needs from the dense stage: which capture is being
// processed, what phase it is in, when it started, and where the PLY landed when it finished.
import 'package:flutter/foundation.dart';

import 'dense_live_cloud.dart';
import 'pw38_preview_artifact.dart';

/// Actual native M0 event clock pair, propagated with one progress observation.
final class DenseProgressSourceTime {
  const DenseProgressSourceTime(this.monoNs, this.wallNs);
  final int monoNs, wallNs;
}

enum DenseStageState { running, done, failed }

final class DenseStageProgress {
  const DenseStageProgress({
    required this.captureDir,
    required this.state,
    this.phase = '',
    this.done = 0,
    this.total = 0,
    this.outPly,
    this.message,
    this.points = 0,
    this.startedAt,
    this.finishedAt,
    this.live,
    this.preview,
    this.sourceTime,
  });
  final String captureDir;
  final DenseStageState state;
  final String phase;
  final DenseProgressSourceTime? sourceTime;
  final int done, total;
  final String? outPly;

  /// Short, user-facing (≤ ~90 chars). The full error goes to the device log, never to the screen.
  final String? message;
  final int points;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// The display copy growing chunk by chunk while the job runs (PWDense v2). Null on a v1 framework, before the
  /// first chunk, and on the terminal states — once the PLY is on disk the viewer reads that instead.
  final DenseLiveCloud? live;
  final Pw38PreviewArtifact? preview;

  DenseStageProgress copyWith({
    DenseStageState? state,
    String? phase,
    int? done,
    int? total,
    String? outPly,
    String? message,
    int? points,
    DateTime? startedAt,
    DateTime? finishedAt,
    DenseLiveCloud? live,
    Pw38PreviewArtifact? preview,
    DenseProgressSourceTime? sourceTime,
  }) => DenseStageProgress(
    captureDir: captureDir,
    state: state ?? this.state,
    phase: phase ?? this.phase,
    done: done ?? this.done,
    total: total ?? this.total,
    outPly: outPly ?? this.outPly,
    message: message ?? this.message,
    points: points ?? this.points,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    live: live ?? this.live,
    preview: preview ?? this.preview,
    sourceTime: sourceTime,
  );

  /// Seven user steps observe the existing thirteen-stage pipeline. Native
  /// frame counters remain separate from the stage-completion journal.
  String get label {
    final frames = total > 0 ? ' · 已处理 $done/$total 张' : '';
    switch (phase) {
      case 'input_preparation':
      case 'dense_native_binding':
      case 'original_python_runtime_binding':
      case 'preparing':
      case 'session':
        return '1/7 整理照片';
      case 'pw_full38_dense_run':
      case 'pw38_production_whole_run_v1':
        return '2/7 准备图像特征';
      case 'whole_features':
        return '2/7 准备图像特征$frames';
      case 'whole_depth_low':
        return '3/7 估算深度 · 初步$frames';
      case 'whole_depth_high':
        return '3/7 估算深度 · 精细$frames';
      case 'mvs768':
      case 'mvs1536':
        return '3/7 估算深度';
      case 'whole_consistency':
      case 'cer':
        return '4/7 筛选与融合 · 筛选深度';
      case 'whole_fusion':
        return '4/7 筛选与融合$frames';
      case 'fusionPly':
        return '4/7 筛选与融合';
      case 'downstream_native_binding':
      case 'tsdf':
      case 'trim':
      case 'meshopt':
      case 'lagrange':
        return '5/7 生成并整理模型';
      case 'texture':
      case 'avVisibility':
      case 'avSfmToAbc':
      case 'avNormal':
        return '6/7 添加颜色与表面细节';
      case 'terminal_glb_format_validation':
      case 'glb':
        return '7/7 保存模型';
      case 'done':
        return '7/7 模型已保存';
      case 'preparation_failed':
      case 'failed':
        return '处理暂时中断，本地素材已保留';
      case 'images':
        return '整理照片$frames';
      case 'infer':
        return '估算深度$frames';
      case 'fuse':
        return '筛选与融合$frames';
      default:
        return '正在处理模型';
    }
  }

  /// 0..1 over the whole job: the phases are weighted by their measured cost on the phone (session ≈ 6 s,
  /// images ≈ 0.07 s each, inference ≈ 2 s each, fusion ≈ 0.15 s per frame) — inference dominates.
  double? get fraction {
    if (state == DenseStageState.done) return 1;
    if (total <= 0) return null;
    final double start, end;
    switch (phase) {
      case 'session':
        start = 0.0;
        end = 0.02;
      case 'images':
        start = 0.02;
        end = 0.05;
      case 'infer':
        start = 0.05;
        end = 0.95;
      case 'fuse':
        start = 0.95;
        end = 1.0;
      default:
        return null;
    }
    // exact at both ends (done=0 -> start, done=total -> end), so phase boundaries never overlap
    return (start * (total - done) + end * done) / total;
  }

  Duration elapsed([DateTime? now]) {
    final s = startedAt;
    if (s == null) return Duration.zero;
    return (finishedAt ?? now ?? DateTime.now()).difference(s);
  }

  /// First line of an exception text, capped, for the screen.
  static String shorten(Object error, {int max = 90}) {
    var s = error.toString().split('\n').first.trim();
    final arrow = s.indexOf(' <- ');
    if (arrow > 0) s = s.substring(0, arrow);
    return s.length > max ? '${s.substring(0, max)}…' : s;
  }
}

String formatDenseDuration(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '$s 秒';
  final m = s ~/ 60, r = s % 60;
  if (m < 60) return '$m 分 $r 秒';
  return '${m ~/ 60} 小时 ${m % 60} 分';
}

/// Global, one job at a time (the stage is minutes long and memory-bound; two at once would jetsam).
final ValueNotifier<DenseStageProgress?> denseStageProgress =
    ValueNotifier<DenseStageProgress?>(null);
