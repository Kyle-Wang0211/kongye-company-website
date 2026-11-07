import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';

enum CommunityCommentStatus {
  pending,
  review,
  published,
  hidden,
  rejected,
  error,
  removed,
}

/// Existing reports reason codes; server owns normalization and review policy.
class CommunityCommentReportDraft {
  CommunityCommentReportDraft({
    required this.workId,
    required this.commentId,
    required this.reason,
    required this.clientRequestId,
    this.detail = '',
  });
  static const reasons = [
    'spam',
    'harassment',
    'hate_speech',
    'sexual_content',
    'violence',
    'copyright',
    'misinformation',
    'other',
  ];
  final String workId, commentId, reason, detail, clientRequestId;
  // Existing normalize_report_reason maps copyright to privacy_ip/rights;
  // enforce_report_detail_limit uses PostgreSQL char_length, i.e. codepoints.
  static int detailLimitForReason(String reason) =>
      reason == 'copyright' ? 500 : 50;
  int get maxDetailCodepoints => detailLimitForReason(reason);
  Map<String, dynamic> toJson() {
    if (workId.trim().isEmpty ||
        commentId.trim().isEmpty ||
        !reasons.contains(reason) ||
        detail.runes.length > maxDetailCodepoints ||
        detail.contains('\u0000') ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(clientRequestId)) {
      throw ArgumentError('Invalid comment report draft');
    }
    return {
      'work_id': workId,
      'comment_id': commentId,
      'reason': reason,
      if (detail.trim().isNotEmpty) 'detail': detail.trim(),
      'client_request_id': clientRequestId,
    };
  }
}

class CommunityCommentAnchor {
  CommunityCommentAnchor({
    required List<double> position,
    List<double>? normal,
    List<double>? cameraPosition,
    List<double>? cameraTarget,
  }) : position = _vector(position),
       normal = normal == null ? null : _vector(normal),
       cameraPosition = cameraPosition == null ? null : _vector(cameraPosition),
       cameraTarget = cameraTarget == null ? null : _vector(cameraTarget) {
    if ((cameraPosition == null) != (cameraTarget == null)) {
      throw ArgumentError(
        'Camera position and target must be supplied together',
      );
    }
    if (normal != null && normal.every((value) => value == 0)) {
      throw ArgumentError('Normal must be nonzero');
    }
  }

  final List<double> position;
  final List<double>? normal;
  final List<double>? cameraPosition;
  final List<double>? cameraTarget;
  static List<double> _vector(List<double> value) {
    if (value.length != 3 || value.any((v) => !v.isFinite || v.abs() > 1e12)) {
      throw ArgumentError('Anchor requires a finite three-component vector');
    }
    return List.unmodifiable(value);
  }

  factory CommunityCommentAnchor.fromJson(Map<String, dynamic> json) {
    List<double>? vector(String key, {bool required = false}) {
      final value = json[key];
      if (value == null && !required) return null;
      if (value is! List ||
          value.length != 3 ||
          value.any((v) => v is! num || !v.isFinite)) {
        throw const FormatException('Invalid comment anchor');
      }
      return value.map((v) => (v as num).toDouble()).toList();
    }

    try {
      return CommunityCommentAnchor(
        position: vector('position', required: true)!,
        normal: vector('normal'),
        cameraPosition: vector('camera_position'),
        cameraTarget: vector('camera_target'),
      );
    } on ArgumentError {
      throw const FormatException('Invalid comment anchor');
    }
  }
  Map<String, dynamic> toJson() => {
    'position': position,
    if (normal != null) 'normal': normal,
    if (cameraPosition != null) 'camera_position': cameraPosition,
    if (cameraTarget != null) 'camera_target': cameraTarget,
  };
}

class CommunityCommentImageDraft {
  CommunityCommentImageDraft({
    required Uint8List bytes,
    required this.fileName,
    required this.mimeType,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  static const maxBytes = 2 * 1024 * 1024;
  static const allowedMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};
  void validate() {
    if (bytes.isEmpty ||
        bytes.length > maxBytes ||
        !allowedMimeTypes.contains(mimeType) ||
        fileName.trim().isEmpty ||
        fileName.length > 255 ||
        fileName.contains(RegExp(r'[\x00-\x1f/\\]'))) {
      throw ArgumentError('Invalid comment image');
    }
  }

  Map<String, dynamic> toJson() => {
    'base64': base64Encode(bytes),
    'name': fileName,
    'mime_type': mimeType,
  };
}

class CommunityCommentAttachment {
  const CommunityCommentAttachment({
    required this.id,
    required this.url,
    required this.mimeType,
    this.fileName,
  });
  final String id;
  final String url;
  final String mimeType;
  final String? fileName;
  factory CommunityCommentAttachment.fromJson(Map<String, dynamic> json) {
    final url = _string(json, 'url');
    final uri = Uri.tryParse(url);
    final mimeType = _string(json, 'mime_type');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !CommunityCommentImageDraft.allowedMimeTypes.contains(mimeType)) {
      throw const FormatException('Invalid comment attachment');
    }
    return CommunityCommentAttachment(
      id: _string(json, 'id'),
      url: url,
      mimeType: mimeType,
      fileName: _optionalString(json, 'file_name'),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'mime_type': mimeType,
    if (fileName != null) 'file_name': fileName,
  };
}

class CommunityComment {
  CommunityComment({
    required this.id,
    required this.workId,
    required this.userId,
    required String body,
    required this.authorName,
    required this.createdAt,
    required this.status,
    List<CommunityCommentAttachment> attachments = const [],
    CommunityCommentAnchor? anchor,
    this.parentId,
    this.authorAvatarUrl,
    this.likesCount = 0,
    this.likedByMe = false,
    this.reasonCode,
    this.moderationCaseId,
    this.moderationReason,
    this.moderationPending = false,
  }) : body =
           status == CommunityCommentStatus.hidden ||
               status == CommunityCommentStatus.removed
           ? ''
           : body,
       anchor =
           status == CommunityCommentStatus.hidden ||
               status == CommunityCommentStatus.removed
           ? null
           : anchor,
       attachments = List.unmodifiable(
         status == CommunityCommentStatus.hidden ||
                 status == CommunityCommentStatus.removed
             ? <CommunityCommentAttachment>[]
             : attachments,
       );
  final String id;
  final String workId;
  final String userId;
  final String body;
  final String authorName;
  final DateTime createdAt;
  final CommunityCommentStatus status;
  final List<CommunityCommentAttachment> attachments;
  final CommunityCommentAnchor? anchor;
  final String? parentId;
  final String? authorAvatarUrl;
  final int likesCount;
  final bool likedByMe;
  final String? reasonCode;
  final String? moderationCaseId;
  final String? moderationReason;
  final bool moderationPending;
  bool get published => status == CommunityCommentStatus.published;
  bool visibleTo(String? currentUserId) =>
      status != CommunityCommentStatus.removed &&
      (published || currentUserId != null && currentUserId == userId);

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'];
    final matches = CommunityCommentStatus.values.where(
      (s) => s.name == rawStatus,
    );
    if (matches.isEmpty) throw const FormatException('Invalid comment status');
    final status = matches.single;
    if (json['is_public'] is! bool ||
        json['is_public'] != (status == CommunityCommentStatus.published)) {
      throw const FormatException('Invalid comment visibility');
    }
    final dateString = _string(json, 'created_at');
    final createdAt = DateTime.tryParse(dateString);
    if (createdAt == null ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(dateString)) {
      throw const FormatException('Invalid comment timestamp');
    }
    final rawAttachments = json['attachments'];
    if (rawAttachments is! List || rawAttachments.length > 3) {
      throw const FormatException('Invalid comment attachments');
    }
    final anchor = json['anchor'];
    if (anchor != null && anchor is! Map<String, dynamic>) {
      throw const FormatException('Invalid comment anchor');
    }
    final body = _string(json, 'body', allowEmpty: true);
    if (body.characters.length > 2000) {
      throw const FormatException('Invalid comment body');
    }
    final avatar = _optionalString(json, 'author_avatar_url');
    if (avatar != null) {
      final uri = Uri.tryParse(avatar);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('Invalid author avatar');
      }
    }
    return CommunityComment(
      id: _string(json, 'id'),
      workId: _string(json, 'work_id'),
      userId: _string(json, 'user_id'),
      body: status == CommunityCommentStatus.removed ? '' : body,
      authorName: _string(json, 'author_name'),
      createdAt: createdAt.toUtc(),
      status: status,
      attachments: rawAttachments.map((v) {
        if (v is! Map<String, dynamic>) {
          throw const FormatException('Invalid attachment');
        }
        return CommunityCommentAttachment.fromJson(v);
      }).toList(),
      anchor: status == CommunityCommentStatus.removed || anchor == null
          ? null
          : CommunityCommentAnchor.fromJson(anchor as Map<String, dynamic>),
      parentId: _optionalString(json, 'parent_id'),
      authorAvatarUrl: avatar,
      likesCount: _count(json['likes_count'] ?? 0),
      likedByMe: _bool(json['liked_by_me'] ?? false),
      reasonCode: _optionalString(json, 'reason_code'),
      moderationCaseId: _optionalString(json, 'moderation_case_id'),
      moderationReason: _optionalString(json, 'moderation_reason'),
      moderationPending: _bool(
        json.containsKey('moderation_pending')
            ? json['moderation_pending']
            : false,
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'work_id': workId,
    'user_id': userId,
    'body': body,
    'author_name': authorName,
    'created_at': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    'is_public': published,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    if (anchor != null) 'anchor': anchor!.toJson(),
    if (parentId != null) 'parent_id': parentId,
    if (authorAvatarUrl != null) 'author_avatar_url': authorAvatarUrl,
    'likes_count': likesCount,
    'liked_by_me': likedByMe,
    if (reasonCode != null) 'reason_code': reasonCode,
    if (moderationCaseId != null) 'moderation_case_id': moderationCaseId,
    if (moderationReason != null) 'moderation_reason': moderationReason,
    'moderation_pending': moderationPending,
  };
}

// Ranked is a legacy client spelling. The gateway maps it to the supported
// hot section, whose cursor orders likes, newest creation time, then ID.
enum CommunityCommentSection { hot, latest, ranked }

int compareCommunityComments(CommunityComment a, CommunityComment b) {
  final likes = b.likesCount.compareTo(a.likesCount);
  if (likes != 0) return likes;
  final created = b.createdAt.compareTo(a.createdAt);
  return created != 0 ? created : b.id.compareTo(a.id);
}

/// Product default; keep the gateway and SQL page-size constants in sync.
const communityCommentPageSize = 20;

class CommunityCommentPage {
  CommunityCommentPage({
    required this.assetRevision,
    required List<CommunityComment> comments,
    this.canComment = false,
    this.publicCount = 0,
    this.assetSha256,
    this.nextCursor,
    List<CommunityComment> contextComments = const [],
  }) : comments = List.unmodifiable(comments),
       contextComments = List.unmodifiable(contextComments);
  final String assetRevision;
  final String? nextCursor;
  final List<CommunityComment> contextComments;
  final String? assetSha256;
  final List<CommunityComment> comments;
  final bool canComment;
  final int publicCount;
}

class CommunityCommentDraft {
  CommunityCommentDraft({
    required this.workId,
    required this.assetRevision,
    required this.body,
    required this.clientRequestId,
    this.anchor,
    this.parentId,
    List<CommunityCommentImageDraft> images = const [],
  }) : images = List.unmodifiable(images);
  final String workId;
  final String assetRevision;
  final String body;
  final String clientRequestId;
  final CommunityCommentAnchor? anchor;
  final String? parentId;
  final List<CommunityCommentImageDraft> images;

  /// The preserved server provider accepts at most 600 UTF-16 code units.
  /// Unlike read-side legacy compatibility, sending counts composite emoji in full.
  static const maxTextCodeUnits = 600;
  static int textCodeUnits(String text) => text.length;
  static bool allowsText(String text) =>
      textCodeUnits(text) <= maxTextCodeUnits;
  void validate() {
    if (workId.trim().isEmpty ||
        assetRevision.trim().isEmpty ||
        clientRequestId.trim().isEmpty ||
        (parentId != null && parentId!.trim().isEmpty) ||
        !allowsText(body) ||
        images.length > 3 ||
        (body.trim().isEmpty && images.isEmpty)) {
      throw ArgumentError('Invalid comment draft');
    }
    for (final image in images) {
      image.validate();
    }
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      'work_id': workId,
      'asset_revision': assetRevision,
      'client_request_id': clientRequestId,
      'body': body,
      if (parentId != null) 'parent_id': parentId,
      if (anchor != null) 'anchor': anchor!.toJson(),
      'images': images.map((i) => i.toJson()).toList(),
    };
  }
}

String _string(
  Map<String, dynamic> json,
  String key, {
  bool allowEmpty = false,
}) {
  final value = json[key];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw const FormatException('Invalid comment field');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _string(json, key);
int _count(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Invalid comment count');
  }
  return value;
}

bool _bool(Object? value) {
  if (value is! bool) throw const FormatException('Invalid comment flag');
  return value;
}
