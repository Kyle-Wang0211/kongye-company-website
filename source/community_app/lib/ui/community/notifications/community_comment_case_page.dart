import 'dart:math';

import 'package:flutter/material.dart';

import '../../../community/comments/comment_moderation_models.dart';
import '../../../community/comments/comment_moderation_repository.dart';
import '../../design_system.dart';
import 'moderation_ui_support.dart';

class CommunityCommentCasePage extends StatefulWidget {
  const CommunityCommentCasePage({
    super.key,
    required this.caseId,
    required this.repository,
    required this.currentUserId,
    this.identityKey,
    this.refreshInterval = const Duration(seconds: 30),
  });
  final String caseId;
  final CommunityCommentModerationRepository repository;
  final String? currentUserId;
  final String? identityKey;
  final Duration? refreshInterval;

  @override
  State<CommunityCommentCasePage> createState() =>
      _CommunityCommentCasePageState();
}

class _CommunityCommentCasePageState extends State<CommunityCommentCasePage>
    with
        WidgetsBindingObserver,
        ActiveModerationRefresh<CommunityCommentCasePage> {
  final _statement = TextEditingController();
  CommunityCommentModerationCase? _case;
  String? _error;
  String? _requestId;
  String _lastStatement = '';
  int _generation = 0;
  int _fetchSequence = 0;
  bool _loading = false;
  bool _submitting = false;
  bool get _signedIn => widget.currentUserId?.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    _statement.addListener(_statementChanged);
    startModerationRefresh(widget.refreshInterval);
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunityCommentCasePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caseId != widget.caseId ||
        oldWidget.repository != widget.repository ||
        oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.identityKey != widget.identityKey) {
      _generation++;
      _fetchSequence++;
      _case = null;
      _error = null;
      _loading = false;
      _submitting = false;
      _statement.clear();
      _requestId = null;
      _load();
    }
    if (oldWidget.refreshInterval != widget.refreshInterval) {
      stopModerationRefresh();
      startModerationRefresh(widget.refreshInterval);
    }
  }

  @override
  void refreshModeration() => _load();

  void _statementChanged() {
    if (_lastStatement != _statement.text) {
      _lastStatement = _statement.text;
      _requestId = null;
      if (mounted) setState(() {});
    }
  }

  bool _owns(CommunityCommentModerationCase value) =>
      value.id == widget.caseId && value.ownerId == widget.currentUserId;

  Future<void> _load() async {
    if (!_signedIn || _loading || _submitting) return;
    final generation = _generation;
    final sequence = ++_fetchSequence;
    setState(() {
      _loading = true;
    });
    try {
      final detail = await widget.repository.fetchCase(widget.caseId);
      if (!mounted || generation != _generation || sequence != _fetchSequence) {
        return;
      }
      if (!_owns(detail)) throw const FormatException('Case identity mismatch');
      setState(() {
        _case = detail;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation || sequence != _fetchSequence) {
        return;
      }
      setState(() {
        _case = null;
        _error = moderationError(error);
        if (moderationIdentityChanged(error)) {
          _statement.clear();
          _requestId = null;
        }
      });
    } finally {
      if (mounted && generation == _generation && sequence == _fetchSequence) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  bool get _canAppeal =>
      _case != null &&
      _case!.canAppeal &&
      _case!.isHidden &&
      _case!.appealStatus == CommunityCommentAppealStatus.none;
  bool get _validStatement =>
      _statement.text.trim().isNotEmpty && _statement.text.length <= 1000;

  Future<void> _submit() async {
    if (!_canAppeal || !_validStatement || _submitting || !_signedIn) return;
    final generation = _generation;
    final statement = _statement.text;
    // Selection and composing-range updates do not replace the request identity.
    _requestId ??=
        'appeal-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final requestId = _requestId!;
    ++_fetchSequence;
    setState(() {
      _submitting = true;
      _loading = false;
      _error = null;
    });
    try {
      final detail = await widget.repository.submitAppeal(
        caseId: widget.caseId,
        statement: statement,
        clientRequestId: requestId,
      );
      if (!mounted || generation != _generation) return;
      if (!_owns(detail) ||
          detail.appealStatus == CommunityCommentAppealStatus.none) {
        throw const FormatException('Unacknowledged appeal');
      }
      setState(() {
        _case = detail;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = moderationError(error);
        if (moderationIdentityChanged(error)) {
          _case = null;
          _statement.clear();
          _requestId = null;
        }
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    stopModerationRefresh();
    _statement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _case;
    return Scaffold(
      backgroundColor: AetherColors.bgCanvas,
      appBar: AppBar(
        title: const Text('评论处理详情'),
        backgroundColor: AetherColors.bgCanvas,
        foregroundColor: AetherColors.textPrimary,
        actions: [
          IconButton(
            tooltip: '刷新处理结果',
            onPressed: _loading || _submitting ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !_signedIn
          ? const ModerationMessage(message: '请登录后查看审核通知')
          : detail == null
          ? _error != null
                ? ModerationMessage(message: _error!, retry: _load)
                : const Center(
                    child: CircularProgressIndicator(
                      color: AetherColors.primary,
                    ),
                  )
          : RefreshIndicator(
              color: AetherColors.primary,
              onRefresh: _load,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AetherSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      detail.isHidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 36,
                      color: AetherColors.primary,
                    ),
                    const SizedBox(height: AetherSpacing.lg),
                    Text(
                      detail.isHidden ? '评论已隐藏' : '评论已恢复',
                      style: AetherTextStyles.h1,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AetherSpacing.sm),
                    Text(
                      detail.isHidden ? '这条评论目前对其他人不可见。' : '服务端确认这条评论已恢复可见。',
                      style: AetherTextStyles.bodySm,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AetherSpacing.xxl),
                    const Text('处理原因', style: AetherTextStyles.h3),
                    const SizedBox(height: AetherSpacing.sm),
                    Text(detail.reasonText, style: AetherTextStyles.body),
                    const SizedBox(height: AetherSpacing.lg),
                    Text(
                      '处理时间：${moderationDate(detail.decidedAt)}',
                      style: AetherTextStyles.bodySm,
                    ),
                    const Divider(
                      height: AetherSpacing.xxl,
                      color: AetherColors.border,
                    ),
                    const Text('关联内容', style: AetherTextStyles.h3),
                    const SizedBox(height: AetherSpacing.sm),
                    Text(
                      detail.workTitle ?? '该评论所属作品',
                      style: AetherTextStyles.bodySm,
                    ),
                    const SizedBox(height: AetherSpacing.xs),
                    Text(
                      detail.commentPreview ?? '该条评论目前已隐藏，可在此查看处理结果并提出申诉。',
                      style: AetherTextStyles.bodySm,
                    ),
                    const SizedBox(height: AetherSpacing.xl),
                    ..._appealResult(detail),
                    if (_canAppeal) ...[
                      const Text('申请复核', style: AetherTextStyles.h3),
                      const SizedBox(height: AetherSpacing.sm),
                      const Text(
                        '请说明需要复核的原因。申诉处理期间，评论保持隐藏。',
                        style: AetherTextStyles.bodySm,
                      ),
                      const SizedBox(height: AetherSpacing.md),
                      TextField(
                        key: const Key('appeal-statement'),
                        controller: _statement,
                        enabled: !_submitting,
                        minLines: 4,
                        maxLines: 8,
                        maxLength: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: '申诉说明',
                          hintText: '补充上下文或说明你认为需要复核的地方',
                          counterText: '${_statement.text.length}/1000',
                          errorText: _statement.text.length > 1000
                              ? '申诉说明不能超过 1000 字符'
                              : null,
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AetherRadii.sm),
                          ),
                        ),
                      ),
                      const SizedBox(height: AetherSpacing.lg),
                      FilledButton(
                        key: const Key('appeal-submit'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AetherColors.primary,
                          foregroundColor: AetherColors.bgCanvas,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: !_submitting && _validStatement
                            ? _submit
                            : null,
                        child: Text(_submitting ? '正在提交…' : '提交申诉'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AetherSpacing.md),
                      Text(
                        _error!,
                        style: AetherTextStyles.bodySm,
                        semanticsLabel: _error,
                      ),
                    ],
                    const SizedBox(height: AetherSpacing.lg),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _appealResult(CommunityCommentModerationCase detail) {
    final title = switch (detail.appealStatus) {
      CommunityCommentAppealStatus.none => null,
      CommunityCommentAppealStatus.submitted => '申诉已提交',
      CommunityCommentAppealStatus.approved => '申诉已通过',
      CommunityCommentAppealStatus.rejected => '申诉未通过',
    };
    if (title == null) return [];
    return [
      Text(title, style: AetherTextStyles.h3),
      const SizedBox(height: AetherSpacing.sm),
      Text(
        detail.appealStatus == CommunityCommentAppealStatus.submitted
            ? '请等待复核结果。处理期间评论保持隐藏，无需重复提交。'
            : detail.appealResult ?? '处理结果以当前评论状态为准。',
        style: AetherTextStyles.body,
      ),
      const SizedBox(height: AetherSpacing.xl),
    ];
  }
}
