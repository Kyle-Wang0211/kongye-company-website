import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/comments/comment_models.dart';

Map<String, dynamic> row({String status = 'pending', bool public = false}) => {
  'id': 'c1',
  'work_id': 'w1',
  'user_id': 'u1',
  'body': 'hello',
  'author_name': 'Author',
  'created_at': '2026-10-29T01:00:00Z',
  'status': status,
  'is_public': public,
  'attachments': <Object>[],
};
void main() {
  test(
    'hidden content is author-only and sanitized at every construction path',
    () {
      final hidden = CommunityComment.fromJson(
        row(status: 'hidden')
          ..['moderation_case_id'] = 'case1'
          ..['moderation_reason'] = '包含违规内容'
          ..['anchor'] = {
            'position': [1, 2, 3],
          }
          ..['attachments'] = [
            {
              'id': 'a1',
              'url': 'https://example.com/a.jpg',
              'mime_type': 'image/jpeg',
            },
          ],
      );
      expect(hidden.visibleTo('u1'), isTrue);
      expect(hidden.visibleTo('u2'), isFalse);
      expect(hidden.visibleTo(null), isFalse);
      expect(hidden.body, isEmpty);
      expect(hidden.attachments, isEmpty);
      expect(hidden.anchor, isNull);
      expect(hidden.moderationCaseId, 'case1');
      expect(hidden.moderationReason, '包含违规内容');
      final direct = CommunityComment(
        id: 'c',
        workId: 'w',
        userId: 'u',
        body: 'secret',
        authorName: 'a',
        createdAt: DateTime.utc(2026),
        status: CommunityCommentStatus.hidden,
        anchor: CommunityCommentAnchor(position: [0, 0, 0]),
        attachments: [
          const CommunityCommentAttachment(
            id: 'a',
            url: 'https://example.com/a.jpg',
            mimeType: 'image/jpeg',
          ),
        ],
      );
      expect(direct.body, isEmpty);
      expect(direct.anchor, isNull);
      expect(direct.attachments, isEmpty);
      expect(direct.toJson()['body'], isEmpty);
    },
  );
  test(
    'published audit-pending remains public with strictly typed audit flag',
    () {
      final comment = CommunityComment.fromJson(
        row(status: 'published', public: true)..['moderation_pending'] = true,
      );
      expect(comment.published, isTrue);
      expect(comment.visibleTo(null), isTrue);
      expect(comment.moderationPending, isTrue);
      expect(comment.toJson()['is_public'], isTrue);
      expect(comment.toJson()['moderation_pending'], isTrue);
      for (final invalid in ['true', null, 1]) {
        expect(
          () => CommunityComment.fromJson(
            row()..['moderation_pending'] = invalid,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('private moderation states are author only; removed never displays', () {
    for (final status in ['pending', 'review', 'rejected', 'error']) {
      final comment = CommunityComment.fromJson(row(status: status));
      expect(comment.visibleTo('u1'), isTrue);
      expect(comment.visibleTo('u2'), isFalse);
      expect(comment.visibleTo(null), isFalse);
      expect(comment.published, isFalse);
    }
    final removed = CommunityComment.fromJson(row(status: 'removed'));
    expect(removed.visibleTo('u1'), isFalse);
    expect(
      CommunityComment.fromJson(
        row(status: 'published', public: true),
      ).visibleTo(null),
      isTrue,
    );
  });
  test('status/public mismatch and unknown states fail closed', () {
    for (final bad in [
      row(status: 'published'),
      row(public: true),
      row(status: 'approved'),
    ]) {
      expect(() => CommunityComment.fromJson(bad), throwsFormatException);
    }
  });
  test('anchor finite 3-vectors roundtrip and malformed anchors fail', () {
    final anchor = CommunityCommentAnchor(
      position: [1, 2, 3],
      normal: [0, 1, 0],
      cameraPosition: [2, 3, 4],
      cameraTarget: [0, 0, 0],
    );
    expect(CommunityCommentAnchor.fromJson(anchor.toJson()).position, [
      1,
      2,
      3,
    ]);
    for (final position in [
      [1.0, 2.0],
      [double.nan, 0.0, 0.0],
      [double.infinity, 1.0, 0.0],
    ]) {
      expect(
        () => CommunityCommentAnchor(position: position),
        throwsArgumentError,
      );
    }
  });
  test('draft supports image only and enforces exact UTF-16 send capacity', () {
    CommunityCommentDraft draft(
      String text, [
      List<CommunityCommentImageDraft> images = const [],
    ]) => CommunityCommentDraft(
      workId: 'w1',
      assetRevision: 'r1',
      body: text,
      clientRequestId: 'request1',
      images: images,
    );
    final image = CommunityCommentImageDraft(
      bytes: Uint8List.fromList([1, 2]),
      fileName: 'a.jpg',
      mimeType: 'image/jpeg',
    );
    expect(() => draft('', [image]).validate(), returnsNormally);
    expect(() => draft('🙂' * 300).validate(), returnsNormally);
    expect(() => draft('🙂' * 300 + 'a').validate(), throwsArgumentError);
    expect(() => draft('a' * 600).validate(), returnsNormally);
    expect(() => draft('a' * 601).validate(), throwsArgumentError);
    expect(
      () => CommunityComment.fromJson(row()..['body'] = '字' * 2000),
      returnsNormally,
    );
    expect(() => draft(' ').validate(), throwsArgumentError);
    expect(
      () => draft('', List.filled(4, image)).validate(),
      throwsArgumentError,
    );
    final large = CommunityCommentImageDraft(
      bytes: Uint8List(2 * 1024 * 1024 + 1),
      fileName: 'a.jpg',
      mimeType: 'image/jpeg',
    );
    expect(() => draft('', [large]).validate(), throwsArgumentError);
  });
  test(
    'anchors reject orphan cameras, zero normals and excessive coordinates',
    () {
      expect(
        () => CommunityCommentAnchor(
          position: [0, 0, 0],
          cameraPosition: [1, 2, 3],
        ),
        throwsArgumentError,
      );
      expect(
        () => CommunityCommentAnchor(
          position: [0, 0, 0],
          cameraTarget: [1, 2, 3],
        ),
        throwsArgumentError,
      );
      expect(
        () => CommunityCommentAnchor(position: [0, 0, 0], normal: [0, 0, 0]),
        throwsArgumentError,
      );
      expect(
        () => CommunityCommentAnchor(position: [1e12 + 1, 0, 0]),
        throwsArgumentError,
      );
      expect(
        () => CommunityCommentAnchor.fromJson({
          'position': [0, 0, 0],
          'normal': [0, 0, 0],
        }),
        throwsFormatException,
      );
      expect(
        () => CommunityCommentAnchor(
          position: [1e12, -1e12, 0],
          normal: [1, 0, 0],
          cameraPosition: [0, 0, 1],
          cameraTarget: [0, 0, 0],
        ),
        returnsNormally,
      );
    },
  );
}
