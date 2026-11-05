import 'package:flutter/material.dart';
import 'package:pocketworld_flutter/community/comments/comment_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/comments/community_comments_panel.dart';
import 'community_comments_panel_test.dart' show FakeComments, comment;

void main() {
  testWidgets(
    'real work owner comments and replies get author badge by user ID',
    (tester) async {
      final repo = FakeComments()
        ..rows = [
          comment('parent', user: 'reader'),
          comment('author-root', user: 'author'),
          comment('author-reply', user: 'author', parentId: 'parent'),
          comment('reader-reply', user: 'reader', parentId: 'parent'),
          CommunityComment(
            id: 'impostor',
            workId: 'work',
            userId: 'impostor',
            body: 'same name',
            authorName: '用户author-root',
            createdAt: DateTime.utc(2026),
            status: CommunityCommentStatus.published,
          ),
        ];
      tester.view.physicalSize = const Size(800, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: Scaffold(
            body: CommunityCommentsPanel(
              workId: 'work',
              workAuthorId: 'author',
              repository: repo,
              currentUserId: null,
              refreshInterval: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('作者'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('author-reply-author-reply')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('author-reply-author-root')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('author-reply-reader-reply')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('author-reply-impostor')), findsNothing);
      expect(find.text('回复 用户parent'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('logged-in author reply sends the existing parentId relation', (
    tester,
  ) async {
    final repo = FakeComments()
      ..rows = [comment('reader-comment', user: 'reader')];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: CommunityCommentsPanel(
            workId: 'work',
            workAuthorId: 'author',
            repository: repo,
            currentUserId: 'author',
            refreshInterval: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('回复'));
    await tester.pump();
    expect(find.text('回复 用户reader-comment'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-input')), '感谢你的评论');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(repo.sent.single.parentId, 'reader-comment');
    expect(repo.sent.single.body, '感谢你的评论');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
