import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../design_system.dart';
import '../legal/legal_doc_page.dart';
import '../legal/platform_rules_page.dart';

@immutable
class WebBlockedUser {
  const WebBlockedUser({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

/// A submitted request is pending. It never implies completed account erasure.
enum WebDeletionRequestStatus { pending }

/// Repository callbacks must complete only after the server accepts the action.
/// This page does not clear credentials, delete local data, or sign the user out.
class WebAccountPrivacyPage extends StatefulWidget {
  const WebAccountPrivacyPage({
    super.key,
    this.accountLabel,
    this.accountId,
    this.onOpenPrivacyPolicy,
    this.onOpenUserAgreement,
    this.onOpenPlatformRules,
    this.loadBlockedUsers,
    this.onUnblock,
    this.onRequestDeletion,
  });

  final String? accountId;
  final String? accountLabel;
  final VoidCallback? onOpenPrivacyPolicy;
  final VoidCallback? onOpenUserAgreement;
  final VoidCallback? onOpenPlatformRules;
  final Future<List<WebBlockedUser>> Function()? loadBlockedUsers;
  final Future<void> Function(String userId)? onUnblock;
  final Future<WebDeletionRequestStatus> Function()? onRequestDeletion;

  @override
  State<WebAccountPrivacyPage> createState() => _WebAccountPrivacyPageState();
}

class _WebAccountPrivacyPageState extends State<WebAccountPrivacyPage> {
  List<WebBlockedUser> _blocked = const [];
  bool _loading = false;
  bool _loadFailed = false;
  bool _deleting = false;
  bool _deletionFailed = false;
  WebDeletionRequestStatus? _deletionStatus;
  final Set<String> _unblocking = {};
  final Set<String> _unblockFailed = {};
  int _loadGeneration = 0;
  int _accountGeneration = 0;
  bool _confirmingDeletion = false;

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    _loadBlocked();
  }

  @override
  void didUpdateWidget(WebAccountPrivacyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.accountId != widget.accountId ||
        (widget.accountId == null &&
            (oldWidget.accountLabel != widget.accountLabel ||
                oldWidget.onRequestDeletion != widget.onRequestDeletion ||
                oldWidget.onUnblock != widget.onUnblock));
    if (changed) {
      _accountGeneration++;
      _deleting = false;
      _confirmingDeletion = false;
      _deletionStatus = null;
      _deletionFailed = false;
      _unblocking.clear();
    }
    if (changed || oldWidget.loadBlockedUsers != widget.loadBlockedUsers) {
      _loadBlocked();
    }
  }

  Future<void> _loadBlocked() async {
    final loader = widget.loadBlockedUsers;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = loader != null;
      _loadFailed = false;
      _blocked = const [];
      _unblockFailed.clear();
    });
    if (loader == null) return;
    try {
      final users = await loader();
      if (!mounted || generation != _loadGeneration) return;
      final ids = <String>{};
      setState(() {
        _blocked = users.where((user) => ids.add(user.id)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _unblock(WebBlockedUser user) async {
    final identity = _accountGeneration;
    final action = widget.onUnblock;
    if (action == null || _unblocking.contains(user.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: _theme(context),
        child: ShadDialog.alert(
          title: Text(_text('解除屏蔽？', 'Unblock user?')),
          actions: [
            ShadButton.ghost(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_text('取消', 'Cancel')),
            ),
            ShadButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_text('确认解除屏蔽', 'Confirm unblock')),
            ),
          ],
          closeIcon: const SizedBox.shrink(),
          child: Text(user.displayName),
        ),
      ),
    );
    if (!mounted ||
        identity != _accountGeneration ||
        confirmed != true ||
        _unblocking.contains(user.id)) {
      return;
    }
    final generation = _loadGeneration;
    setState(() {
      _unblocking.add(user.id);
      _unblockFailed.remove(user.id);
    });
    try {
      await action(user.id);
      if (!mounted || identity != _accountGeneration) return;
      setState(() {
        _unblocking.remove(user.id);
        if (generation == _loadGeneration) {
          _blocked = _blocked.where((item) => item.id != user.id).toList();
        }
      });
    } catch (_) {
      if (!mounted || identity != _accountGeneration) return;
      setState(() {
        _unblocking.remove(user.id);
        if (generation == _loadGeneration) _unblockFailed.add(user.id);
      });
    }
  }

  Future<void> _requestDeletion() async {
    final identity = _accountGeneration;
    final action = widget.onRequestDeletion;
    if (action == null ||
        _deleting ||
        _confirmingDeletion ||
        _deletionStatus != null) {
      return;
    }
    setState(() => _confirmingDeletion = true);
    bool acknowledged = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: _theme(context),
        child: StatefulBuilder(
          builder: (context, updateDialog) => ShadDialog.alert(
            title: Text(_text('申请注销账号', 'Request account deletion')),
            actions: [
              ShadButton.ghost(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_text('取消', 'Cancel')),
              ),
              ShadButton(
                onPressed: acknowledged
                    ? () => Navigator.pop(context, true)
                    : null,
                enabled:
                    (acknowledged
                        ? () => Navigator.pop(context, true)
                        : null) !=
                    null,
                child: Text(_text('提交申请', 'Submit request')),
              ),
            ],
            closeIcon: const SizedBox.shrink(),
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _text(
                      '提交后将由服务处理注销申请。提交申请不代表账号或数据已删除。具体处理方式请查看隐私政策。',
                      'The service will process your request. Submitting does not mean your account or data has been deleted. See the privacy policy for details.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ShadCheckbox(
                    value: acknowledged,
                    onChanged: (value) =>
                        updateDialog(() => acknowledged = value),
                    label: Text(
                      _text(
                        '我确认申请注销当前账号',
                        'I confirm this request for my current account',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || identity != _accountGeneration) return;
    setState(() => _confirmingDeletion = false);
    if (confirmed != true || _deleting || _deletionStatus != null) {
      return;
    }
    setState(() {
      _deleting = true;
      _deletionFailed = false;
    });
    try {
      final status = await action();
      if (!mounted || identity != _accountGeneration) return;
      setState(() {
        _deletionStatus = status;
        _deleting = false;
      });
    } catch (_) {
      if (!mounted || identity != _accountGeneration) return;
      setState(() {
        _deleting = false;
        _deletionFailed = true;
      });
    }
  }

  ThemeData _theme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: AetherColors.primary,
            dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
          ).copyWith(
            primary: AetherColors.primary,
            onPrimary: Colors.white,
            primaryContainer: AetherColors.bgElevated,
            onPrimaryContainer: AetherColors.primary,
            secondary: AetherColors.primarySoft,
            secondaryContainer: AetherColors.bgElevated,
            onSecondaryContainer: AetherColors.primary,
            error: AetherColors.danger,
            surface: AetherColors.bgCanvas,
            surfaceTint: AetherColors.primary,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme(context),
      child: Scaffold(
        backgroundColor: AetherColors.bg,
        appBar: AppBar(
          backgroundColor: AetherColors.bgCanvas,
          foregroundColor: AetherColors.primary,
          title: Text(_text('账号与隐私', 'Account & privacy')),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _text('管理您的账号', 'Your account'),
                      style: AetherTextStyles.h1,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.accountLabel ??
                          _text('账号信息未提供', 'Account details unavailable'),
                      style: AetherTextStyles.bodySm,
                    ),
                    const SizedBox(height: 24),
                    _section(_text('政策与约定', 'Policies'), [
                      _policyLink(
                        _text('隐私政策', 'Privacy policy'),
                        widget.onOpenPrivacyPolicy ??
                            () => PrivacyPolicyPage.open(context),
                      ),
                      _policyLink(
                        _text('用户协议', 'User agreement'),
                        widget.onOpenUserAgreement ??
                            () => UserAgreementPage.open(context),
                      ),
                      _policyLink(
                        _text('平台公约', 'Community rules'),
                        widget.onOpenPlatformRules ??
                            () => PlatformRulesPage.open(context),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    _section(_text('已屏蔽用户', 'Blocked users'), [
                      if (_loading)
                        const LinearProgressIndicator()
                      else if (widget.loadBlockedUsers == null)
                        Text(
                          _text(
                            '屏蔽名单服务暂不可用。',
                            'Blocked users service is unavailable.',
                          ),
                        )
                      else if (_loadFailed) ...[
                        _error(
                          _text('无法加载屏蔽名单。', 'Could not load blocked users.'),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ShadButton.ghost(
                            onPressed: _loadBlocked,
                            child: Text(_text('重试', 'Retry')),
                          ),
                        ),
                      ] else if (_blocked.isEmpty)
                        Text(_text('暂无已屏蔽用户', 'No blocked users'))
                      else ...[
                        for (final user in _blocked)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        user.displayName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ShadButton.outline(
                                      key: ValueKey('unblock-${user.id}'),
                                      onPressed:
                                          widget.onUnblock == null ||
                                              _unblocking.contains(user.id)
                                          ? null
                                          : () => _unblock(user),
                                      enabled:
                                          (widget.onUnblock == null ||
                                                  _unblocking.contains(user.id)
                                              ? null
                                              : () => _unblock(user)) !=
                                          null,
                                      child: Text(
                                        _unblocking.contains(user.id)
                                            ? _text('处理中…', 'Working…')
                                            : _text('解除屏蔽', 'Unblock'),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_unblockFailed.contains(user.id))
                                  _error(
                                    _text(
                                      '解除屏蔽未成功，请重试。',
                                      'Could not unblock user. Please retry.',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (widget.onUnblock == null)
                          Text(
                            _text('解除屏蔽服务暂不可用。', 'Unblocking is unavailable.'),
                          ),
                      ],
                    ]),
                    const SizedBox(height: 20),
                    _section(_text('账号注销', 'Account deletion'), [
                      Text(
                        _text(
                          '在此提交注销申请，并查看申请状态。',
                          'Submit an account deletion request and view its status.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (widget.onRequestDeletion == null)
                        Text(
                          _text(
                            '注销申请服务暂不可用，请查看隐私政策中的联系方式。',
                            'Deletion requests are unavailable. See the privacy policy for contact details.',
                          ),
                        )
                      else if (_deletionStatus ==
                          WebDeletionRequestStatus.pending)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _text(
                              '申请已提交，等待处理；尚未确认删除。',
                              'Request submitted, awaiting processing. Deletion is not confirmed.',
                            ),
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ShadButton.outline(
                            onPressed: _deleting || _confirmingDeletion
                                ? null
                                : _requestDeletion,
                            enabled:
                                (_deleting || _confirmingDeletion
                                    ? null
                                    : _requestDeletion) !=
                                null,
                            child: Text(
                              _deleting
                                  ? _text('正在提交…', 'Submitting…')
                                  : _text('申请注销账号', 'Request account deletion'),
                            ),
                          ),
                        ),
                      if (_deletionFailed)
                        _error(
                          _text(
                            '申请未能确认提交，请稍后重试。',
                            'Submission could not be confirmed. Please retry later.',
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: AetherColors.bgCanvas,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AetherColors.border),
      borderRadius: BorderRadius.circular(AetherRadii.md),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AetherTextStyles.h2),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget _policyLink(String label, VoidCallback open) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: const Icon(Icons.chevron_right),
    onTap: open,
  );

  Widget _error(String message) => Semantics(
    liveRegion: true,
    child: Text(message, style: const TextStyle(color: AetherColors.danger)),
  );
}
