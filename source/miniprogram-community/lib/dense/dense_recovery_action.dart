import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../official_capture/dense_stage.dart';
import '../official_capture/selection_box.dart';
import '../ui/official_capture/sfm_preview_overlay.dart';
import 'dense_stage_progress.dart';
import 'dense_work_state.dart' show kDenseStartedMarkerName;

/// Reconstructs the authorized request from one original marker read. Display
/// budgets and any subsequently edited selection file are not recovery inputs.
Future<DenseStageRequest> originalDenseRecoveryRequest({
  required String captureDir,
  required String sparsePlyPath,
  String? recordId,
}) async {
  final path = '$captureDir/$kDenseStartedMarkerName';
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError('缺少原始稠密任务记录，不能重新选择处理输入');
  }
  final marker = jsonDecode(await File(path).readAsString());
  if (marker is! Map ||
      marker['schema'] != 'pw_dense_started/1' ||
      marker['sparse_points'] is! int ||
      marker['sparse_points'] <= 0 ||
      !marker.containsKey('selection')) {
    throw StateError('原始稠密任务记录不完整，不能使用当前显示点数替代');
  }
  final selection = SelectionBox.fromJson(marker['selection']);
  if (marker['selection'] != null && selection == null) {
    throw StateError('原始稠密任务选区无效，不能重新选择');
  }
  return DenseStageRequest(
    captureDir: captureDir,
    sparsePlyPath: sparsePlyPath,
    pointCount: marker['sparse_points'] as int,
    selection: selection,
    recordId: recordId,
  );
}

/// Offers only the recovery operation the installed launcher has verified.
/// It never falls back to start(), and never reopens the sparse editor.
class DenseRecoveryAction extends StatefulWidget {
  const DenseRecoveryAction({
    super.key,
    required this.captureDir,
    required this.buildRequest,
  });

  final String captureDir;
  final Future<DenseStageRequest> Function() buildRequest;

  @override
  State<DenseRecoveryAction> createState() => _DenseRecoveryActionState();
}

class _DenseRecoveryActionState extends State<DenseRecoveryAction> {
  DenseStageRecoveryPlan? _plan;
  DenseStageRequest? _request;
  DenseStageRecoveryLauncher? _launcher;
  DenseStageLauncher? _installedLauncher;
  String? _failure;
  bool _checking = true;
  bool _submitting = false;
  bool _accepted = false;
  int _generation = 0;
  String? _progressKey;

  @override
  void initState() {
    super.initState();
    _progressKey = _stateKey();
    denseStageProgress.addListener(_onProgress);
    unawaited(_inspect());
  }

  @override
  void didUpdateWidget(covariant DenseRecoveryAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.captureDir != widget.captureDir ||
        !identical(_installedLauncher, denseStageLauncher)) {
      unawaited(_inspect());
    }
  }

  @override
  void dispose() {
    _generation++;
    denseStageProgress.removeListener(_onProgress);
    super.dispose();
  }

  String? _stateKey() {
    final p = denseStageProgress.value;
    return p == null ? null : '${p.captureDir}:${p.state}';
  }

  void _onProgress() {
    final next = _stateKey();
    if (!mounted || next == _progressKey) return;
    _progressKey = next;
    final progress = denseStageProgress.value;
    if (progress?.captureDir == widget.captureDir &&
        progress?.state == DenseStageState.failed) {
      _accepted = false;
    }
    if (!_submitting && !_accepted) unawaited(_inspect());
    setState(() {});
  }

  Future<void> _inspect() async {
    final generation = ++_generation;
    final launcher = denseStageLauncher;
    _installedLauncher = launcher;
    _checking = true;
    _submitting = false;
    _accepted = false;
    _failure = null;
    _plan = null;
    _request = null;
    _launcher = launcher is DenseStageRecoveryLauncher ? launcher : null;
    if (mounted) setState(() {});
    try {
      if (launcher is! DenseStageRecoveryLauncher) {
        _failure = '本机暂不支持恢复处理';
        return;
      }
      final request = await widget.buildRequest();
      if (!mounted || generation != _generation) return;
      if (request.captureDir != widget.captureDir) {
        throw StateError('处理数据与当前作品不一致');
      }
      final plan = await launcher.inspectRecovery(request);
      if (!mounted || generation != _generation) return;
      _request = request;
      _plan = plan;
    } catch (error) {
      if (mounted && generation == _generation) {
        _failure = DenseStageProgress.shorten(error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _recover() async {
    if (!identical(_installedLauncher, denseStageLauncher)) {
      await _inspect();
      return;
    }
    final request = _request;
    final launcher = _launcher;
    if (_submitting ||
        _accepted ||
        _checking ||
        request == null ||
        launcher == null ||
        _plan?.canRecover != true ||
        _plan?.action != DenseStageRecoveryAction.restartDense ||
        denseStageProgress.value?.state == DenseStageState.running) {
      return;
    }
    final generation = _generation;
    setState(() {
      _submitting = true;
      _failure = null;
    });
    try {
      final result = await launcher.recover(request);
      if (!mounted || generation != _generation) return;
      setState(() {
        _accepted = result.status == DenseStageStatus.started;
        _failure = _accepted ? null : result.message ?? '处理未能启动，请稍后重试';
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _failure = DenseStageProgress.shorten(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = denseStageProgress.value;
    final running = progress?.state == DenseStageState.running;
    final available =
        _plan?.canRecover == true &&
        _plan?.action == DenseStageRecoveryAction.restartDense;
    final enabled =
        available && !_checking && !_submitting && !_accepted && !running;
    final label = _checking
        ? '正在检查处理数据…'
        : _submitting
        ? '正在启动稠密处理…'
        : running && progress?.captureDir != widget.captureDir
        ? '其他作品正在处理中…'
        : _accepted || running
        ? '稠密处理中…'
        : _plan?.status == DenseStageRecoveryStatus.completed
        ? '处理已完成'
        : '从稠密阶段起点重新开始';
    final planMessage = _plan?.message;
    final failure =
        _failure ??
        (progress?.captureDir == widget.captureDir &&
                progress?.state == DenseStageState.failed
            ? progress?.message
            : null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SfmBottomActionButton(
          key: const ValueKey('dense-recovery-action'),
          label: label,
          onTap: enabled ? () => unawaited(_recover()) : null,
        ),
        const SizedBox(height: 6),
        Text(
          available ? '选区已锁定，核对后复用本地输入' : '选区已锁定，不能返回编辑',
          key: const ValueKey('dense-recovery-locked-selection'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        if (planMessage != null && planMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            planMessage,
            key: const ValueKey('dense-recovery-plan'),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
        if (failure != null && failure.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            failure,
            key: const ValueKey('dense-recovery-error'),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
