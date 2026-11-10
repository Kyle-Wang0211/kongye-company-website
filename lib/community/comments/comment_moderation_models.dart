enum CommunityCommentNoticeKind { hidden, restored, appealRejected }

enum CommunityCommentAppealStatus { none, submitted, approved, rejected }

/// A notification is a navigation hint; fetch the server-owned case for facts.
class CommunityCommentNotice {
  const CommunityCommentNotice({
    required this.id,
    required this.recipientId,
    required this.caseId,
    required this.commentId,
    required this.workId,
    required this.reasonText,
    required this.kind,
    required this.createdAt,
    this.readAt,
    this.workTitle,
    this.commentPreview,
  });
  final String id;
  final String recipientId;
  final String caseId;
  final String commentId;
  final String workId;
  final String reasonText;
  final CommunityCommentNoticeKind kind;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? workTitle;
  final String? commentPreview;

  static bool isCommentSubtype(Object? value) => const {
    'comment_hidden',
    'comment_restored',
    'comment_appeal_rejected',
  }.contains(value);

  factory CommunityCommentNotice.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    if (json['type'] != 'system_announcement' ||
        json['target_type'] != 'comment' ||
        payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid comment notice');
    }
    final kind = switch (payload['subtype']) {
      'comment_hidden' => CommunityCommentNoticeKind.hidden,
      'comment_restored' => CommunityCommentNoticeKind.restored,
      'comment_appeal_rejected' => CommunityCommentNoticeKind.appealRejected,
      _ => throw const FormatException('Invalid comment notice subtype'),
    };
    final commentId = _text(payload, 'comment_id');
    if (_text(json, 'target_id') != commentId) {
      throw const FormatException('Invalid comment notice target');
    }
    return CommunityCommentNotice(
      id: _text(json, 'id'),
      recipientId: _text(json, 'recipient_id'),
      caseId: _text(payload, 'case_id'),
      commentId: commentId,
      workId: _text(payload, 'work_id'),
      reasonText: _text(payload, 'reason_text'),
      kind: kind,
      createdAt: _timestamp(json, 'created_at'),
      readAt: json['read_at'] == null ? null : _timestamp(json, 'read_at'),
      workTitle: _optionalText(payload, 'work_title'),
      commentPreview: _optionalText(payload, 'comment_preview'),
    );
  }
}

class CommunityCommentModerationCase {
  const CommunityCommentModerationCase({
    required this.id,
    required this.ownerId,
    required this.commentId,
    required this.workId,
    required this.contentRevision,
    required this.reasonText,
    required this.decidedAt,
    required this.isHidden,
    required this.appealStatus,
    required this.canAppeal,
    this.appealResult,
    this.workTitle,
    this.commentPreview,
  });
  final String id;
  final String ownerId;
  final String commentId;
  final String workId;
  final String contentRevision;
  final String reasonText;
  final DateTime decidedAt;
  final bool isHidden;
  final CommunityCommentAppealStatus appealStatus;
  final bool canAppeal;
  final String? appealResult;
  final String? workTitle;
  final String? commentPreview;

  factory CommunityCommentModerationCase.fromJson(Map<String, dynamic> json) {
    final appealStatus = switch (json['appeal_status']) {
      'none' => CommunityCommentAppealStatus.none,
      'submitted' => CommunityCommentAppealStatus.submitted,
      'approved' => CommunityCommentAppealStatus.approved,
      'rejected' => CommunityCommentAppealStatus.rejected,
      _ => throw const FormatException('Invalid comment appeal status'),
    };
    final hidden = json['is_hidden'];
    final canAppeal = json['can_appeal'];
    if (hidden is! bool ||
        canAppeal is! bool ||
        hidden != (appealStatus != CommunityCommentAppealStatus.approved) ||
        (canAppeal &&
            (appealStatus == CommunityCommentAppealStatus.submitted ||
                appealStatus == CommunityCommentAppealStatus.approved))) {
      throw const FormatException('Invalid comment case state');
    }
    return CommunityCommentModerationCase(
      id: _text(json, 'id'),
      ownerId: _text(json, 'owner_id'),
      commentId: _text(json, 'comment_id'),
      workId: _text(json, 'work_id'),
      contentRevision: _text(json, 'content_revision'),
      reasonText: _text(json, 'reason_text'),
      decidedAt: _timestamp(json, 'decided_at'),
      isHidden: hidden,
      appealStatus: appealStatus,
      canAppeal: canAppeal,
      appealResult: _optionalText(json, 'appeal_result'),
      workTitle: _optionalText(json, 'work_title'),
      commentPreview: _optionalText(json, 'comment_preview'),
    );
  }
}

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid moderation field');
  }
  return value;
}

String? _optionalText(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _text(json, key);

DateTime _timestamp(Map<String, dynamic> json, String key) {
  final value = _text(json, key);
  final pattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$',
  );
  final match = pattern.firstMatch(value);
  final parsed = DateTime.tryParse(value);
  if (match == null || parsed == null) {
    throw const FormatException('Invalid moderation timestamp');
  }
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
  final normalized = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  final zone = match[7]!;
  if (normalized.year != parts[0] ||
      normalized.month != parts[1] ||
      normalized.day != parts[2] ||
      normalized.hour != parts[3] ||
      normalized.minute != parts[4] ||
      normalized.second != parts[5] ||
      (zone != 'Z' &&
          (int.parse(zone.substring(1, 3)) > 23 ||
              int.parse(zone.substring(4, 6)) > 59))) {
    throw const FormatException('Invalid moderation timestamp');
  }
  return parsed.toUtc();
}
