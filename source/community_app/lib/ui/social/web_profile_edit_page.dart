import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system.dart';
import '../community/community_navigation_frame.dart';

class WebProfileDraft {
  final String displayName;
  final String bio;

  const WebProfileDraft({required this.displayName, required this.bio});
}

enum WebProfileSaveResult {
  approved,
  pendingReview,
  retrying,
  review,
  rejected,
  superseded,
  unknown,
}

class WebProfileSaveFailure implements Exception {
  const WebProfileSaveFailure(this.message);
  final String message;
}

/// Saves through the supplied repository callback; never assumes approval.
class WebProfileEditPage extends StatefulWidget {
  final WebProfileDraft initialProfile;
  final Future<WebProfileSaveResult> Function(WebProfileDraft) save;
  final String? avatarSeed;
  final Widget? avatar;
  final bool approvalFromProjection;
  final String? statusError;
  final WebProfileSaveResult? observedResult;
  final bool submissionBlocked;
  final VoidCallback? onRefresh;

  const WebProfileEditPage({
    super.key,
    required this.initialProfile,
    required this.save,
    this.avatarSeed,
    this.avatar,
    this.approvalFromProjection = false,
    this.statusError,
    this.observedResult,
    this.submissionBlocked = false,
    this.onRefresh,
  });

  @override
  State<WebProfileEditPage> createState() => _WebProfileEditPageState();
}

class _WebProfileEditPageState extends State<WebProfileEditPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _bio;
  late WebProfileDraft _approved;
  late WebProfileDraft _saved;
  bool _saving = false;
  bool _allowPop = false;
  WebProfileSaveResult? _result;
  String? _error;
  CommunityNavigationController? _navigation;
  Future<bool>? _discardPending;

  @override
  void initState() {
    super.initState();
    _approved = _saved = widget.initialProfile;
    _result = widget.observedResult;
    _name = TextEditingController(text: _saved.displayName)
      ..addListener(_changed);
    _bio = TextEditingController(text: _saved.bio)..addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = CommunityNavigationScope.maybeOf(context)?.controller;
    if (identical(_navigation, navigation)) return;
    _navigation?.unregisterExitGuard(this);
    _navigation = navigation;
    _navigation?.registerExitGuard(this, _confirmDiscard);
  }

  @override
  void didUpdateWidget(WebProfileEditPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Published projection is refreshed independently of the in-progress draft.
    if (widget.approvalFromProjection ||
        oldWidget.initialProfile.displayName !=
            widget.initialProfile.displayName ||
        oldWidget.initialProfile.bio != widget.initialProfile.bio) {
      _approved = widget.initialProfile;
    }
    if (widget.observedResult != oldWidget.observedResult) {
      _result = widget.observedResult;
    }
  }

  void _changed() => setState(() {});

  WebProfileDraft get _draft =>
      WebProfileDraft(displayName: _name.text.trim(), bio: _bio.text.trim());

  bool get _dirty =>
      _draft.displayName != _saved.displayName || _draft.bio != _saved.bio;

  @override
  void dispose() {
    _navigation?.unregisterExitGuard(this);
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() {
    if (!mounted || _saving) return Future.value(false);
    if (!_dirty) return Future.value(true);
    // Sidebar actions and route Back share one outstanding confirmation.
    return _discardPending ??= _showDiscardConfirmation().whenComplete(() {
      _discardPending = null;
    });
  }

  Future<bool> _showDiscardConfirmation() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: _theme(context),
        child: AlertDialog(
          title: const Text('放弃未保存的修改？'),
          content: const Text('离开后，本次未保存的昵称和简介将丢失。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      ),
    );
    return mounted && discard == true;
  }

  Future<void> _exit() async {
    if (!await _confirmDiscard() || !mounted) return;
    setState(() => _allowPop = true);
    // PopScope must rebuild its route permission before the programmatic pop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _save() async {
    if (_saving ||
        widget.submissionBlocked ||
        !_dirty ||
        !_form.currentState!.validate()) {
      return;
    }
    final submitted = _draft;
    setState(() {
      _saving = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.save(submitted);
      if (!mounted) return;
      setState(() {
        if (result != WebProfileSaveResult.rejected &&
            result != WebProfileSaveResult.superseded &&
            result != WebProfileSaveResult.unknown) {
          _saved = submitted;
        }
        if (result == WebProfileSaveResult.approved &&
            !widget.approvalFromProjection) {
          _approved = submitted;
        }
        _result = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is WebProfileSaveFailure
            ? error.message
            : '保存失败，修改尚未保存。请重试。',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _fieldDecoration(
    String label,
    TextEditingController controller,
    int maxLength, {
    String? hintText,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      hintText: hintText,
      filled: true,
      fillColor: AetherColors.bgElevated,
      contentPadding: const EdgeInsets.all(16),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AetherColors.primary),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: AetherColors.danger),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: const BorderSide(color: AetherColors.danger),
      ),
      helperText: '最多 $maxLength 个字符',
      counterText: '${controller.text.characters.length}/$maxLength',
    );
  }

  ThemeData _theme(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ColorScheme.fromSeed(
      seedColor: AetherColors.primary,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      primary: AetherColors.primary,
      onPrimary: Colors.white,
      secondary: AetherColors.primarySoft,
      surface: AetherColors.bgCanvas,
      error: AetherColors.danger,
    );
    return theme.copyWith(colorScheme: colors);
  }

  @override
  Widget build(BuildContext context) {
    final seed = (widget.avatarSeed ?? _approved.displayName).trim();
    return Theme(
      data: _theme(context),
      child: PopScope(
        canPop: _allowPop || (!_dirty && !_saving),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exit();
        },
        child: Scaffold(
          backgroundColor: AetherColors.bg,
          appBar: AppBar(
            backgroundColor: AetherColors.bgCanvas,
            foregroundColor: AetherColors.textPrimary,
            leading: IconButton(
              tooltip: '返回',
              onPressed: _saving ? null : _exit,
              icon: const Icon(Icons.arrow_back),
            ),
            title: const Text('编辑个人资料'),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AetherSpacing.xl),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Semantics(
                            label: '系统生成头像，不支持上传',
                            image: true,
                            child: ExcludeSemantics(
                              child:
                                  widget.avatar ??
                                  CircleAvatar(
                                    radius: 36,
                                    backgroundColor: AetherColors.bgElevated,
                                    foregroundColor: AetherColors.textPrimary,
                                    child: Text(
                                      seed.isEmpty
                                          ? '·'
                                          : seed.characters.first,
                                      style: const TextStyle(fontSize: 28),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AetherSpacing.sm),
                        const Text(
                          '头像由系统生成',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AetherColors.textSecondary),
                        ),
                        const SizedBox(height: AetherSpacing.xxl),
                        const Text('当前公开资料'),
                        const SizedBox(height: AetherSpacing.sm),
                        Text(
                          _approved.displayName,
                          key: const Key('approved-name'),
                        ),
                        Text(
                          _approved.bio.isEmpty ? '暂无简介' : _approved.bio,
                          key: const Key('approved-bio'),
                        ),
                        const SizedBox(height: AetherSpacing.xl),
                        TextFormField(
                          key: const Key('profile-name'),
                          controller: _name,
                          enabled: !_saving,
                          maxLength: 20,
                          maxLengthEnforcement:
                              MaxLengthEnforcement.truncateAfterCompositionEnds,
                          decoration: _fieldDecoration('昵称', _name, 20),
                          textInputAction: TextInputAction.next,
                          validator: (value) => (value?.trim().isEmpty ?? true)
                              ? '请输入昵称'
                              : value!.trim().characters.length > 20
                              ? '昵称最多 20 个字符'
                              : null,
                        ),
                        const SizedBox(height: AetherSpacing.lg),
                        TextFormField(
                          key: const Key('profile-bio'),
                          controller: _bio,
                          enabled: !_saving,
                          minLines: 5,
                          maxLines: 5,
                          maxLength: 160,
                          maxLengthEnforcement:
                              MaxLengthEnforcement.truncateAfterCompositionEnds,
                          decoration: _fieldDecoration(
                            '个人简介',
                            _bio,
                            160,
                            hintText: '介绍一下你自己',
                          ),
                          validator: (value) =>
                              (value?.characters.length ?? 0) > 160
                              ? '个人简介最多 160 个字符'
                              : null,
                        ),
                        const SizedBox(height: AetherSpacing.lg),
                        if (_result != null)
                          Semantics(
                            liveRegion: true,
                            child: Text(switch (_result!) {
                              WebProfileSaveResult.pendingReview =>
                                '修改已提交，等待内容审核。',
                              WebProfileSaveResult.retrying =>
                                '审核服务暂时繁忙，系统将自动重试。',
                              WebProfileSaveResult.review =>
                                '内容待进一步审核，请稍后查看结果。',
                              WebProfileSaveResult.rejected =>
                                '修改未通过审核，请调整内容后重新提交。',
                              WebProfileSaveResult.superseded =>
                                '本次修改已被更新的提交替代。',
                              WebProfileSaveResult.unknown =>
                                '提交结果待确认，请刷新状态后再继续。',
                              WebProfileSaveResult.approved => '个人资料已更新',
                            }),
                          ),
                        if (widget.onRefresh != null)
                          TextButton(
                            onPressed: _saving ? null : widget.onRefresh,
                            child: const Text('刷新审核状态'),
                          ),
                        if (widget.statusError != null)
                          Semantics(
                            liveRegion: true,
                            child: Text(widget.statusError!),
                          ),
                        if (_error != null)
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AetherColors.danger,
                              ),
                            ),
                          ),
                        const SizedBox(height: AetherSpacing.lg),
                        FilledButton(
                          onPressed:
                              _saving || widget.submissionBlocked || !_dirty
                              ? null
                              : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AetherColors.textSecondary,
                                    semanticsLabel: '正在保存',
                                  ),
                                )
                              : const Text('保存修改'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
