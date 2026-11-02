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

void main() {
  testWidgets(
    'overlapping sort results render one feed and keep server order',
    (tester) async {
      final repo = PagedComments()
        ..firstPages[CommunityCommentSection.hot] = [
          fixture.comment('a'),
          fixture.comment('b'),
          fixture.comment('c'),
        ]
        ..firstPages[CommunityCommentSection.latest] = [
          fixture.comment('c'),
          fixture.comment('b'),
          fixture.comment('a'),
        ];
      final visible = <List<CommunityComment>>[];
      await fixture.mount(tester, repo, visible: visible.add);
      expect(
        find.byType(SegmentedButton<CommunityCommentSection>),
        findsOneWidget,
      );
      expect(find.text('body-a'), findsOneWidget);
      expect(find.text('body-b'), findsOneWidget);
      expect(find.text('body-c'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('body-a')).dy,
        lessThan(tester.getTopLeft(find.text('body-c')).dy),
      );
      expect(visible.last.map((c) => c.id).toSet(), {'a', 'b', 'c'});
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      expect(find.text('body-a'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('body-c')).dy,
        lessThan(tester.getTopLeft(find.text('body-a')).dy),
      );
      await tester.tap(find.text('热评'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('body-a')).dy,
        lessThan(tester.getTopLeft(find.text('body-c')).dy),
      );
      expect(repo.calls, hasLength(2));
    },
  );

  testWidgets(
    'sort changes retain independent cursors and deduplicate page overlaps',
    (tester) async {
      final repo = PagedComments();
      await fixture.mount(tester, repo);
      await tester.ensureVisible(
        find.byKey(const ValueKey('comment-more-hot')),
      );
      await tester.tap(find.byKey(const ValueKey('comment-more-hot')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, (CommunityCommentSection.hot, 'hot-next'));
      expect(find.text('body-hot-19'), findsOneWidget);
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      expect(find.text('body-hot-19'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('comment-more-latest')),
      );
      await tester.tap(find.byKey(const ValueKey('comment-more-latest')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, (CommunityCommentSection.latest, 'latest-next'));
      expect(find.text('body-latest-19'), findsOneWidget);
      await tester.tap(find.text('热评'));
      await tester.pumpAndSettle();
      expect(find.text('body-hot-20'), findsOneWidget);
      expect(find.byKey(const ValueKey('comment-more-hot')), findsNothing);
      expect(repo.calls, hasLength(4));
    },
  );

  testWidgets(
    'sort switching preserves reply anchor and deduplicated pin callback',
    (tester) async {
      final anchor = CommunityCommentAnchor(position: [1, 2, 3]);
      final parent = fixture.comment('parent', anchor: anchor);
      final repo = PagedComments()
        ..firstPages[CommunityCommentSection.hot] = [parent]
        ..firstPages[CommunityCommentSection.latest] = [parent];
      CommunityComment? selected;
      final visible = <List<CommunityComment>>[];
      await fixture.mount(
        tester,
        repo,
        anchor: anchor,
        visible: visible.add,
        selected: (value) => selected = value,
      );
      await tester.tap(find.text('查看模型点位'));
      expect(selected?.id, 'parent');
      await tester.tap(find.text('回复'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('comment-input')),
        'reply draft',
      );
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      expect(find.text('回复 用户parent'), findsOneWidget);
      expect(find.text('reply draft'), findsOneWidget);
      expect(visible.last.map((c) => c.id), ['parent']);
      await tester.tap(find.byKey(const Key('comment-send')));
      await tester.pumpAndSettle();
      expect(repo.sent.single.parentId, 'parent');
      expect(repo.sent.single.anchor, same(anchor));
    },
  );

  testWidgets(
    'anonymous sort selection keeps public reads and a real sign-in action',
    (tester) async {
      final repo = PagedComments();
      var signIns = 0;
      await fixture.mount(
        tester,
        repo,
        user: null,
        locale: const Locale('en'),
        signIn: () => signIns++,
      );
      await tester.tap(find.text('Latest'));
      await tester.pumpAndSettle();
      expect(find.text('body-latest-0'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('comment-input')))
            .enabled,
        isFalse,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Sign in to comment'));
      expect(signIns, 1);
      expect(repo.sent, isEmpty);
    },
  );

  testWidgets('parent context stays available across sort switches', (
    tester,
  ) async {
    final repo = PagedComments()
      ..contextRows = [fixture.comment('parent')]
      ..firstPages[CommunityCommentSection.hot] = [
        fixture.comment('reply', parentId: 'parent'),
      ]
      ..firstPages[CommunityCommentSection.latest] = [
        fixture.comment('reply', parentId: 'parent'),
      ];
    await fixture.mount(tester, repo);
    expect(find.text('回复 用户parent'), findsOneWidget);
    await tester.tap(find.text('最新'));
    await tester.pumpAndSettle();
    expect(find.text('回复 用户parent'), findsOneWidget);
    expect(find.text('body-parent'), findsNothing);
  });

  testWidgets(
    'paged English selector fits 320 pixels with keyboard and reply anchor',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });
      final repo = PagedComments();
      await fixture.mount(
        tester,
        repo,
        locale: const Locale('en'),
        anchor: CommunityCommentAnchor(position: [0, 0, 0]),
      );
      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Latest'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byType(SegmentedButton<CommunityCommentSection>),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'hot and latest load independently with explicit more, no legacy 200 fetch',
    (tester) async {
      final repo = PagedComments();
      await fixture.mount(tester, repo);
      expect(repo.fetches, 0);
      expect(
        repo.calls,
        containsAll([
          (CommunityCommentSection.hot, null),
          (CommunityCommentSection.latest, null),
        ]),
      );
      expect(find.text('热评'), findsOneWidget);
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      expect(find.text('最新'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('comment-more-latest')),
      );
      await tester.tap(find.byKey(const ValueKey('comment-more-latest')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, (CommunityCommentSection.latest, 'latest-next'));
      expect(find.text('body-latest-19'), findsOneWidget);
      expect(find.text('body-latest-20'), findsOneWidget);
      expect(
        repo.calls.where((c) => c.$1 == CommunityCommentSection.hot),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'hot failure does not hide latest or require exhausting hot pages',
    (tester) async {
      final repo = PagedComments()..failHot = true;
      await fixture.mount(tester, repo);
      expect(find.text('重试热评'), findsOneWidget);
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      expect(find.text('body-latest-0'), findsOneWidget);
      expect(find.text('最新'), findsOneWidget);
    },
  );

  testWidgets('one section can time out and retry without blocking latest', (
    tester,
  ) async {
    final hot = Completer<CommunityCommentPage>();
    final repo = PagedComments()..pending[CommunityCommentSection.hot] = hot;
    await fixture.mount(tester, repo);
    await tester.tap(find.text('最新'));
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('body-latest-0'), findsOneWidget);
    expect(find.text('重试热评'), findsNothing);
    await tester.tap(find.text('热评'));
    await tester.pumpAndSettle();
    expect(find.text('重试热评'), findsOneWidget);
    repo.pending.clear();
    await tester.ensureVisible(find.text('重试热评'));
    await tester.tap(find.text('重试热评'));
    await tester.pumpAndSettle();
    expect(find.text('body-hot-0'), findsOneWidget);
    hot.complete(
      CommunityCommentPage(
        assetRevision: 'stale',
        comments: [fixture.comment('stale')],
        publicCount: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('body-stale'), findsNothing);
  });

  testWidgets('new submission is visible immediately in latest section', (
    tester,
  ) async {
    final repo = PagedComments();
    await fixture.mount(tester, repo);
    await tester.enterText(find.byKey(const Key('comment-input')), '新评论');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(find.text('body-new'), findsOneWidget);
    expect(find.byKey(const ValueKey('comment-section-hot')), findsNothing);
    expect(
      find.byKey(const ValueKey('comment-section-latest')),
      findsOneWidget,
    );
    expect(repo.sent.single.body, '新评论');
  });

  testWidgets('account change rejects old hot and latest pages', (
    tester,
  ) async {
    final hot = Completer<CommunityCommentPage>();
    final latest = Completer<CommunityCommentPage>();
    final repo = PagedComments()
      ..pending[CommunityCommentSection.hot] = hot
      ..pending[CommunityCommentSection.latest] = latest;
    await fixture.mount(tester, repo);
    repo.pending.clear();
    await fixture.mount(tester, repo, user: 'other');
    final stale = CommunityCommentPage(
      assetRevision: 'revision',
      comments: [
        fixture.comment('private', status: CommunityCommentStatus.pending),
      ],
      canComment: true,
      publicCount: 0,
    );
    hot.complete(stale);
    latest.complete(stale);
    await tester.pumpAndSettle();
    expect(find.text('body-private'), findsNothing);
    expect(find.text('热评'), findsOneWidget);
  });
}
