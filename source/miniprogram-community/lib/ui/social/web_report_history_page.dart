import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../community/social_profile_models.dart';
import '../design_system.dart';

/// Only the signed-in owner's report fields belong in this view model.
/// The loader must enforce ownership before returning records.
@immutable
class WebReportSummary {
  const WebReportSummary({
    required this.id,
    required this.targetTitle,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.outcome,
    this.kind,
    this.sourceWorkTitle,
  });

  final String id;
  final String targetTitle;
  final String reason;
  final String status;
  final DateTime createdAt;
  final String? outcome;
  final ReportKind? kind;
  final String? sourceWorkTitle;
}

class WebReportHistoryPage extends StatefulWidget {
  const WebReportHistoryPage({
    super.key,
    required this.loader,
    this.accountId,
    this.onAppeal,
  });

  final String? accountId;
  final Future<List<WebReportSummary>> Function() loader;

  /// Provide only when the backend supports appeals for this owner.
  /// The backend remains responsible for eligibility and authorization.
  final Future<void> Function(String id, String explanation)? onAppeal;

  @override
  State<WebReportHistoryPage> createState() => _WebReportHistoryPageState();
}

class _WebReportHistoryPageState extends State<WebReportHistoryPage> {
  late Future<List<WebReportSummary>> _reports;
  int _ownerGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WebReportHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        (widget.accountId == null && oldWidget.loader != widget.loader)) {
      _ownerGeneration++;
      _load();
    }
  }

  void _load() {
    _reports = Future.sync(widget.loader);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final parent = Theme.of(context);
    final colors = ColorScheme.fromSeed(
      seedColor: Colors.black,
      brightness: parent.brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    );
    return Theme(
      data: parent.copyWith(colorScheme: colors),
      child: Scaffold(
        appBar: AppBar(title: Text(l.reportHistoryTitle)),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: FutureBuilder<List<WebReportSummary>>(
              future: _reports,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Center(
                    child: Semantics(
                      label: l.reportHistoryLoading,
                      child: const CircularProgressIndicator(),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _message(l.reportHistoryLoadFailed, '', retry: true);
                }
                final reports = snapshot.data ?? const <WebReportSummary>[];
                if (reports.isEmpty) {
                  return _message(l.reportHistoryEmpty, '');
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: reports.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(l.reportHistoryNotice),
                      );
                    }
                    final report = reports[index - 1];
                    return Card(
                      key: ValueKey(report.id),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text(
                          report.targetTitle.isEmpty
                              ? _reason(report.reason, l)
                              : report.targetTitle,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${_status(report.status, l)} · ${_date(report.createdAt)}',
                          ),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          SelectableText(_field(l.reportRecordId, report.id)),
                          if (report.kind != null)
                            Text(
                              report.kind == ReportKind.rights
                                  ? l.reportRightsTitle
                                  : l.reportStandardTitle,
                            ),
                          if (report.sourceWorkTitle != null)
                            Text(
                              l.reportHistorySource(report.sourceWorkTitle!),
                            ),
                          const SizedBox(height: 12),
                          SelectableText(
                            _field(
                              l.reportRecordReason,
                              _reason(report.reason, l),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            _field(
                              l.reportRecordOutcome,
                              report.outcome?.trim().isNotEmpty == true
                                  ? report.outcome!
                                  : l.reportOutcomeUnavailable,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (widget.onAppeal != null)
                            ShadButton.outline(
                              onPressed: () => _appeal(report),
                              leading: const Icon(Icons.edit_note),
                              child: Text(l.reportAppealAction),
                            )
                          else
                            Text(l.reportAppealUnavailable),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _field(String label, String value) =>
      Localizations.localeOf(context).languageCode == 'zh'
      ? '$label：$value'
      : '$label: $value';

  Widget _message(String title, String body, {bool retry = false}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
            ],
            if (retry) ...[
              const SizedBox(height: 16),
              ShadButton.outline(
                onPressed: () => setState(_load),
                child: Text(AppL10n.of(context).communityRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _appeal(WebReportSummary report) async {
    final generation = _ownerGeneration;
    final callback = widget.onAppeal;
    if (callback == null) return;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.black,
            brightness: Theme.of(context).brightness,
            dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
          ),
        ),
        child: _AppealDialog(
          onSubmit: (explanation) {
            if (!mounted || generation != _ownerGeneration) {
              throw StateError('Account changed');
            }
            return callback(report.id, explanation);
          },
        ),
      ),
    );
    if (!mounted || generation != _ownerGeneration || submitted != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppL10n.of(context).reportAppealSubmitted)),
    );
    setState(_load);
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}';
  }

  static String _status(String value, AppL10n l) => switch (value) {
    'pending' => l.reportStatusPending,
    'reviewing' || 'in_review' => l.reportStatusInReview,
    'needs_info' => l.reportStatusNeedsInfo,
    'actioned' || 'resolved' => l.reportStatusActioned,
    'dismissed' || 'rejected' => l.reportStatusDismissed,
    'closed' => l.reportStatusClosed,
    _ => l.reportStatusUnknown,
  };

  static String _reason(String value, AppL10n l) =>
      switch (UserReportReason.fromCode(value)) {
        UserReportReason.impersonation => l.reportReasonImpersonation,
        UserReportReason.harassmentThreat => l.reportReasonHarassmentThreat,
        UserReportReason.spamFraud => l.reportReasonSpamFraud,
        UserReportReason.minorSafety => l.reportReasonMinorSafety,
        UserReportReason.sexualContent => l.reportReasonSexualLowQuality,
        UserReportReason.violenceIllegal => l.reportReasonViolenceIllegal,
        UserReportReason.misinformation => l.reportReasonMisleading,
        UserReportReason.privacyIp => l.reportReasonPrivacyIp,
        UserReportReason.other => l.reportReasonOtherUncertain,
        null => value,
      };
}

class _AppealDialog extends StatefulWidget {
  const _AppealDialog({required this.onSubmit});
  final Future<void> Function(String explanation) onSubmit;

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final explanation = _controller.text.trim();
    if (explanation.isEmpty) {
      setState(() => _error = AppL10n.of(context).reportAppealRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(explanation);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppL10n.of(context).reportAppealFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: ShadDialog.alert(
      title: Text(AppL10n.of(context).reportAppealAction),
      actions: [
        ShadButton.ghost(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          enabled: (_busy ? null : () => Navigator.of(context).pop()) != null,
          child: Text(AppL10n.of(context).commonCancel),
        ),
        ShadButton(
          onPressed: _busy ? null : _submit,
          enabled: (_busy ? null : _submit) != null,
          child: Text(
            _busy
                ? AppL10n.of(context).reportAppealSubmitting
                : AppL10n.of(context).reportAppealSubmit,
          ),
        ),
      ],
      closeIcon: const SizedBox.shrink(),
      child: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppL10n.of(context).reportAppealExplanation),
            const SizedBox(height: 8),
            ShadInput(
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
            ),
            const SizedBox(height: 6),
            Text(
              AppL10n.of(context).reportAppealPrivacy,
              style: const TextStyle(
                fontSize: 12,
                color: AetherColors.textSecondary,
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AetherColors.danger)),
          ],
        ),
      ),
    ),
  );
}
