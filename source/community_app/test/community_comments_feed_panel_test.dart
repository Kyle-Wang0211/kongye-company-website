import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/comments/comment_models.dart';
import 'package:pocketworld_flutter/community/comments/comment_repository.dart';
import 'community_comments_panel_test.dart' as fixture;

class PagedComments extends fixture.FakeComments
    implements CommunityCommentFeedRepository {
  final calls = <(CommunityCommentSection, String?)>[];
  final pending = <CommunityCommentSection, Completer<CommunityCommentPage>>{};
  bool failHot = false;
  List<CommunityComment> contextRows = [];
  final firstPages = <CommunityCommentSection, List<CommunityComment>>{};
  @override
  Future<CommunityCommentPage> fetchSection(
    String id, {
    required CommunityCommentSection section,
    String? cursor,
  }) async {
    calls.add((section, cursor));
    if (pending[section] != null) return pending[section]!.future;
    if (section == CommunityCommentSection.hot && failHot) {
      throw Exception('offline');
    }
    final prefix = section.name;
    return CommunityCommentPage(
      assetRevision: 'revision',
      canComment: true,
      publicCount: 45,
      contextComments: contextRows,
      comments: cursor == null
          ? firstPages[section] ??
                List.generate(20, (i) => fixture.comment('$prefix-$i'))
          : [fixture.comment('$prefix-19'), fixture.comment('$prefix-20')],
      nextCursor: cursor == null ? '$prefix-next' : null,
    );
  }
}

CommunityComment ranked(String id, int likes, int day) => CommunityComment(
  id: id,
  workId: 'work',
  userId: 'me',
  body: 'body-$id',
  authorName: id,
  createdAt: DateTime.utc(2026, 11, day),
  status: CommunityCommentStatus.published,
  likesCount: likes,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final language in ['zh', 'en']) {
    testWidgets('ranked feed has no old tabs in $language', (tester) async {
      final repo = PagedComments();
      await fixture.mount(tester, repo, locale: Locale(language));
      expect(
        find.byType(SegmentedButton<CommunityCommentSection>),
        findsNothing,
      );
      for (final oldLabel in ['热评', '最新', 'Top comments', 'Latest']) {
        expect(find.text(oldLabel), findsNothing);
      }
      expect(repo.calls, [(CommunityCommentSection.hot, null)]);
    });
  }

  testWidgets(
    'single list orders likes descending then newest then stable ID',
    (tester) async {
      final repo = PagedComments()
        ..firstPages[CommunityCommentSection.hot] = [
          ranked('old-popular', 10, 1),
          ranked('new-zero', 0, 5),
          ranked('old-tie', 2, 1),
          ranked('a', 2, 3),
          ranked('z', 2, 3),
        ];
      await fixture.mount(tester, repo);
      expect(
        find.byType(SegmentedButton<CommunityCommentSection>),
        findsNothing,
      );
      expect(find.text('热评'), findsNothing);
      expect(find.text('最新'), findsNothing);
      expect(repo.calls, [(CommunityCommentSection.hot, null)]);
      final order = ['old-popular', 'z', 'a', 'old-tie', 'new-zero'];
      for (var i = 1; i < order.length; i++) {
        expect(
          tester.getTopLeft(find.text('body-${order[i - 1]}')).dy,
          lessThan(tester.getTopLeft(find.text('body-${order[i]}')).dy),
        );
      }
      expect(find.text('body-new-zero'), findsOneWidget);
    },
  );

  testWidgets(
    'single ranked list retains cursor and deduplicates overlapping pages',
    (tester) async {
      final repo = PagedComments();
      await fixture.mount(tester, repo);
      await tester.ensureVisible(
        find.byKey(const ValueKey('comment-more-hot')),
      );
      await tester.tap(find.byKey(const ValueKey('comment-more-hot')));
      await tester.pumpAndSettle();
      expect(repo.calls, [
        (CommunityCommentSection.hot, null),
        (CommunityCommentSection.hot, 'hot-next'),
      ]);
      expect(find.text('body-hot-19'), findsOneWidget);
      expect(find.text('body-hot-20'), findsOneWidget);
      expect(find.byKey(const ValueKey('comment-more-hot')), findsNothing);
      expect(repo.fetches, 0);
    },
  );

  testWidgets('single feed preserves reply point draft and parent context', (
    tester,
  ) async {
    final anchor = CommunityCommentAnchor(position: [1, 2, 3]);
    final repo = PagedComments()
      ..contextRows = [fixture.comment('context')]
      ..firstPages[CommunityCommentSection.hot] = [
        fixture.comment('parent', anchor: anchor),
        fixture.comment('reply', parentId: 'context'),
      ];
    CommunityComment? selected;
    await fixture.mount(
      tester,
      repo,
      anchor: anchor,
      selected: (c) => selected = c,
    );
    expect(find.text('回复 用户context'), findsOneWidget);
    expect(find.text('body-context'), findsNothing);
    await tester.tap(find.text('查看模型点位'));
    expect(selected?.id, 'parent');
    await tester.tap(find.text('回复').last);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('comment-input')),
      'reply draft',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(repo.sent.single.parentId, 'parent');
    expect(repo.sent.single.anchor, same(anchor));
  });

  testWidgets('anonymous ranked reads retain sign-in action', (tester) async {
    final repo = PagedComments();
    var signIns = 0;
    await fixture.mount(
      tester,
      repo,
      user: null,
      locale: const Locale('en'),
      signIn: () => signIns++,
    );
    expect(find.text('body-hot-0'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('comment-input'))).enabled,
      isFalse,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Sign in to comment'));
    expect(signIns, 1);
    expect(repo.sent, isEmpty);
  });

  testWidgets('ranked list fits narrow keyboard layout with point and reply', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    await fixture.mount(
      tester,
      PagedComments(),
      locale: const Locale('en'),
      anchor: CommunityCommentAnchor(position: [0, 0, 0]),
    );
    await tester.tap(find.text('Reply').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SegmentedButton<CommunityCommentSection>), findsNothing);
  });

  testWidgets('failed ranked feed retries same endpoint', (tester) async {
    final repo = PagedComments()..failHot = true;
    await fixture.mount(tester, repo);
    expect(find.byKey(const ValueKey('comment-more-hot')), findsOneWidget);
    repo.failHot = false;
    await tester.tap(find.byKey(const ValueKey('comment-more-hot')));
    await tester.pumpAndSettle();
    expect(find.text('body-hot-0'), findsOneWidget);
    expect(repo.calls, [
      (CommunityCommentSection.hot, null),
      (CommunityCommentSection.hot, null),
    ]);
  });

  testWidgets('ranked timeout retries and ignores stale response', (
    tester,
  ) async {
    final pending = Completer<CommunityCommentPage>();
    final repo = PagedComments()
      ..pending[CommunityCommentSection.hot] = pending;
    await fixture.mount(tester, repo);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    repo.pending.clear();
    await tester.tap(find.byKey(const ValueKey('comment-more-hot')));
    await tester.pumpAndSettle();
    expect(find.text('body-hot-0'), findsOneWidget);
    pending.complete(
      CommunityCommentPage(
        assetRevision: 'stale',
        comments: [fixture.comment('stale')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('body-stale'), findsNothing);
  });

  testWidgets(
    'new confirmed comment enters single list at its ranked position',
    (tester) async {
      final repo = PagedComments()
        ..firstPages[CommunityCommentSection.hot] = [ranked('popular', 10, 1)]
        ..submitResult = ranked('new', 0, 5);
      await fixture.mount(tester, repo);
      await tester.enterText(find.byKey(const Key('comment-input')), '新评论');
      await tester.pump();
      await tester.tap(find.byKey(const Key('comment-send')));
      await tester.pumpAndSettle();
      expect(find.text('body-new'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('body-popular')).dy,
        lessThan(tester.getTopLeft(find.text('body-new')).dy),
      );
      expect(find.byKey(const ValueKey('comment-section-hot')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('comment-section-latest')),
        findsNothing,
      );
      expect(repo.sent.single.body, '新评论');
    },
  );

  testWidgets('account switch rejects stale ranked private page', (
    tester,
  ) async {
    final pending = Completer<CommunityCommentPage>();
    final repo = PagedComments()
      ..pending[CommunityCommentSection.hot] = pending;
    await fixture.mount(tester, repo);
    repo.pending.clear();
    await fixture.mount(tester, repo, user: 'other');
    pending.complete(
      CommunityCommentPage(
        assetRevision: 'revision',
        comments: [
          fixture.comment('private', status: CommunityCommentStatus.pending),
        ],
        canComment: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('body-private'), findsNothing);
    expect(
      repo.calls.every((c) => c.$1 == CommunityCommentSection.hot),
      isTrue,
    );
  });
}
