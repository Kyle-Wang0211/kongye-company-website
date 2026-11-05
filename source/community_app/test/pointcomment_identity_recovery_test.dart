import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/comments/comment_repository.dart';
import 'community_comments_panel_test.dart' show FakeComments, mount;

void main() {
  testWidgets('verified model hash restores authenticated typing and sending', (
    tester,
  ) async {
    final hash = 'a' * 64;
    final repo = FakeComments()..assetSha256 = hash;
    await mount(tester, repo, requireAssetBinding: true);
    expect(find.textContaining('模型身份校验中'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byKey(const Key('comment-input'))).enabled,
      isFalse,
    );
    await mount(
      tester,
      repo,
      requireAssetBinding: true,
      expectedAssetSha256: hash,
    );
    expect(find.textContaining('模型身份校验中'), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const Key('comment-input'))).enabled,
      isTrue,
    );
    await tester.enterText(find.byKey(const Key('comment-input')), '验证后发送');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(repo.sent.single.body, '验证后发送');
    expect(repo.sent.single.assetRevision, 'revision');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('successful reload clears stale identity error', (tester) async {
    final repo = FakeComments()
      ..submitError = const CommunityCommentException('identity_changed');
    await mount(tester, repo);
    await tester.enterText(find.byKey(const Key('comment-input')), 'draft');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(find.text('账号或服务区域已变化，请重新打开评论'), findsWidgets);
    repo.submitError = null;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('账号或服务区域已变化，请重新打开评论'), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const Key('comment-input'))).enabled,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('successful refresh retains current failed draft error', (
    tester,
  ) async {
    final repo = FakeComments()..failSubmit = true;
    await mount(tester, repo);
    await tester.enterText(find.byKey(const Key('comment-input')), '保留草稿');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(find.text('发送失败，草稿已保留，请重试'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新评论'));
    await tester.pumpAndSettle();
    expect(find.text('发送失败，草稿已保留，请重试'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('comment-input')))
          .controller!
          .text,
      '保留草稿',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
