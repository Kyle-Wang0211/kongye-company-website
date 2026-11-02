import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../../community/comments/comment_models.dart';
import '../../../l10n/app_localizations.dart';

/// Existing reports UI labels, targeting one comment rather than a work/user.
class CommunityCommentReportSheet extends StatefulWidget {
  const CommunityCommentReportSheet({
    super.key,
    required this.workId,
    required this.commentId,
    required this.revision,
    required this.isCurrent,
    required this.submit,
  });
  final String workId, commentId;
  final ValueListenable<int> revision;
  final bool Function() isCurrent;
  final Future<String> Function(CommunityCommentReportDraft) submit;
  @override
  State<CommunityCommentReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<CommunityCommentReportSheet> {
  final _detail = TextEditingController();
  String? _reason, _requestId, _error;
  String _previousDetail = '';
  bool _busy = false, _invalidated = false;
  int get _detailLimit =>
      CommunityCommentReportDraft.detailLimitForReason(_reason ?? 'other');
  int get _detailCodepoints => _detail.text.runes.length;
  @override
  void initState() {
    super.initState();
    _detail.addListener(_changed);
    widget.revision.addListener(_identityChanged);
  }

  void _changed() {
    if (_previousDetail == _detail.text) return;
    _previousDetail = _detail.text;
    _requestId = null;
    if (mounted) setState(() => _error = null);
  }

  void _identityChanged() {
    if (widget.isCurrent() || _invalidated) return;
    _invalidated = true;
    // The parent may invalidate identity while its own widget tree is building.
    scheduleMicrotask(() {
      if (!mounted) return;
      _detail.clear();
      setState(() {});
      Navigator.of(context).maybePop();
    });
  }

  Future<void> _submit() async {
    if (_busy ||
        _invalidated ||
        !widget.isCurrent() ||
        _reason == null ||
        _detailCodepoints > _detailLimit) {
      return;
    }
    _requestId ??= const Uuid().v4();
    final draft = CommunityCommentReportDraft(
      workId: widget.workId,
      commentId: widget.commentId,
      reason: _reason!,
      detail: _detail.text,
      clientRequestId: _requestId!,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.submit(draft);
      if (!mounted || _invalidated || !widget.isCurrent()) return;
      Navigator.of(context).pop(id);
    } catch (_) {
      if (mounted && !_invalidated && widget.isCurrent()) {
        setState(() => _error = AppL10n.of(context).reportFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    widget.revision.removeListener(_identityChanged);
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final labels = [
      l.reportReasonSpam,
      l.reportReasonHarassment,
      l.reportReasonHateSpeech,
      l.reportReasonSexualContent,
      l.reportReasonViolence,
      l.reportReasonCopyright,
      l.reportReasonMisinformation,
      l.reportReasonOther,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '举报这条评论',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Text(l.reportSheetSubtitle),
              for (
                var i = 0;
                i < CommunityCommentReportDraft.reasons.length;
                i++
              )
                ListTile(
                  dense: true,
                  title: Text(labels[i]),
                  trailing: _reason == CommunityCommentReportDraft.reasons[i]
                      ? const Icon(Icons.check)
                      : null,
                  onTap: _busy || _invalidated
                      ? null
                      : () => setState(() {
                          if (_reason ==
                              CommunityCommentReportDraft.reasons[i]) {
                            return;
                          }
                          _reason = CommunityCommentReportDraft.reasons[i];
                          _requestId = null;
                          _error = null;
                        }),
                ),
              TextField(
                key: const Key('comment-report-detail'),
                controller: _detail,
                enabled: !_busy && !_invalidated,
                maxLength: _detailLimit,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                buildCounter:
                    (
                      context, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => Text(
                      '$_detailCodepoints / $_detailLimit',
                      key: const Key('comment-report-codepoint-counter'),
                    ),
                maxLines: 3,
                decoration: InputDecoration(hintText: l.reportDetailHint),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                key: const Key('comment-report-submit'),
                onPressed:
                    _busy ||
                        _invalidated ||
                        _reason == null ||
                        _detailCodepoints > _detailLimit
                    ? null
                    : _submit,
                child: Text(_busy ? l.reportSubmitting : l.reportSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
