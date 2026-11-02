import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/comments/community_comments_panel.dart';
import 'package:pocketworld_flutter/community/comments/comment_models.dart';
import 'package:pocketworld_flutter/community/comments/comment_repository.dart';
import 'community_comments_panel_test.dart' show FakeComments, comment;

class _PagedComments extends FakeComments
    implements CommunityCommentFeedRepository {
  @override
  Future<CommunityCommentPage> fetchSection(
    String workId, {
    required CommunityCommentSection section,
    String? cursor,
  }) async => CommunityCommentPage(
    assetRevision: 'r1',
    assetSha256: 'a' * 64,
    comments: rows,
    publicCount: 1,
    canComment: false,
  );
}

void main() {
  testWidgets(
    'paged comments wait for proven model identity and never bypass the hash gate',
    (tester) async {
      final repo = _PagedComments()..rows = [comment('public', user: 'other')];
      Future<void> mount(String? hash) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Scaffold(
              body: CommunityCommentsPanel(
                workId: 'work',
                repository: repo,
                currentUserId: null,
                refreshInterval: null,
                requireAssetBinding: true,
                expectedAssetSha256: hash,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount(null);
      expect(find.text('模型身份校验中，请稍后重试'), findsWidgets);
      expect(find.text('模型版本已更新，请重新打开评论'), findsNothing);
      expect(find.text('body-public'), findsNothing);
      await mount('a' * 64);
      expect(find.text('body-public'), findsWidgets);
      expect(find.text('模型身份校验中，请稍后重试'), findsNothing);
      await mount('b' * 64);
      expect(find.text('body-public'), findsNothing);
      expect(find.text('模型版本已更新，请重新打开评论'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'anonymous can read public comments but composer writes require login',
    (tester) async {
      var logins = 0;
      final repo = FakeComments()
        ..rows = [comment('public', user: 'other')]
        ..publicCount = 1;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: Scaffold(
            body: CommunityCommentsPanel(
              workId: 'work',
              repository: repo,
              currentUserId: null,
              refreshInterval: null,
              onSignIn: () => logins++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('body-public'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('comment-input')))
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('登录后发表评论').first);
      await tester.pump();
      expect(logins, 1);
      expect(repo.sent, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
