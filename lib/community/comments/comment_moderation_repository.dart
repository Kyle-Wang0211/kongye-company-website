import 'comment_moderation_models.dart';

export 'comment_repository.dart'
    show SupabaseCommunityCommentModerationRepository;

abstract class CommunityCommentModerationRepository {
  Future<List<CommunityCommentNotice>> fetchNotices();
  Future<void> markRead(String noticeId);
  Future<CommunityCommentModerationCase> fetchCase(String caseId);
  Future<CommunityCommentModerationCase> submitAppeal({
    required String caseId,
    required String statement,
    required String clientRequestId,
  });
}
