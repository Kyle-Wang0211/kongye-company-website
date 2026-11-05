import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/community/comments/comment_models.dart';
import 'package:pocketworld_flutter/community/comments/comment_repository.dart';
import 'package:pocketworld_flutter/ui/community/comments/community_comments_panel.dart';

CommunityComment comment(
  String id, {
  String user = 'me',
  CommunityCommentStatus status = CommunityCommentStatus.published,
  String? parentId,
  CommunityCommentAnchor? anchor,
  bool moderationPending = false,
}) => CommunityComment(
  id: id,
  workId: 'work',
  userId: user,
  body: 'body-$id',
  authorName: '用户$id',
  createdAt: DateTime.utc(2026, 10, 29),
  status: status,
  parentId: parentId,
  anchor: anchor,
  moderationPending: moderationPending,
);

class FakeComments implements CommunityCommentRepository {
  List<CommunityComment> rows = [];
  final List<CommunityCommentDraft> sent = [];
  int publicCount = 0;
  int fetches = 0;
  CommunityComment? submitResult;
  String? assetSha256;
  bool failSubmit = false;
  Object? submitError;
  Completer<CommunityComment>? pendingSubmit;
  Completer<CommunityCommentPage>? pendingFetch;
  @override
  Future<CommunityCommentPage> fetch(String workId) async {
    fetches++;
    return pendingFetch == null
        ? CommunityCommentPage(
            assetRevision: 'revision',
            assetSha256: assetSha256,
            comments: rows,
            canComment: true,
            publicCount: publicCount,
          )
        : pendingFetch!.future;
  }

  @override
  Future<CommunityComment> submit(CommunityCommentDraft draft) async {
    sent.add(draft);
    if (submitError != null) throw submitError!;
    if (failSubmit) throw Exception('offline');
    return pendingSubmit == null
        ? submitResult ?? comment('new', moderationPending: true)
        : pendingSubmit!.future;
  }

  @override
  Future<void> remove(String workId, String commentId) async {}
  @override
  Future<CommunityComment> setLiked(
    String workId,
    String commentId,
    bool liked,
  ) async => comment(commentId);
}

class ReportComments extends FakeComments
    implements CommunityCommentReportRepository {
  @override
  Future<String> report(CommunityCommentReportDraft draft) async => '1';
}

Future<void> mount(
  WidgetTester tester,
  FakeComments repo, {
  String? user = 'me',
  String? expectedAssetSha256,
  bool requireAssetBinding = false,
  CommunityCommentAnchor? anchor,
  VoidCallback? pick,
  VoidCallback? clear,
  CommunityCommentImagePicker? picker,
  ValueChanged<List<CommunityComment>>? visible,
  ValueChanged<CommunityComment>? selected,
  VoidCallback? signIn,
  Locale locale = const Locale('zh'),
  ValueChanged<String>? moderationCase,
  Duration? refreshInterval,
  bool active = true,
  bool tickerEnabled = true,
  bool presentationVisible = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: TickerMode(
          enabled: tickerEnabled,
          child: CommunityCommentsPanel(
            workId: 'work',
            repository: repo,
            currentUserId: user,
            expectedAssetSha256: expectedAssetSha256,
            requireAssetBinding: requireAssetBinding,
            selectedAnchor: anchor,
            onPickPoint: pick,
            onClearAnchor: clear,
            imagePicker: picker,
            onVisibleCommentsChanged: visible,
            onCommentSelected: selected,
            onSignIn: signIn,
            onModerationCaseSelected: moderationCase,
            refreshInterval: refreshInterval,
            active: active,
            presentationVisible: presentationVisible,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'report action appears only for published other-author logged-in comments',
    (tester) async {
      final repo = ReportComments()
        ..rows = [
          comment('mine'),
          comment('other', user: 'other'),
          comment(
            'hidden',
            user: 'other',
            status: CommunityCommentStatus.hidden,
          ),
        ];
      await mount(tester, repo);
      expect(find.text('举报'), findsOneWidget);
      await mount(tester, repo, user: null);
      expect(find.text('举报'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'hidden pin feed retains rows without rendering content or composer',
    (tester) async {
      final repo = FakeComments()..rows = [comment('pin')];
      List<CommunityComment>? rows;
      await mount(
        tester,
        repo,
        presentationVisible: false,
        visible: (value) => rows = value,
      );
      expect(rows?.map((c) => c.id), ['pin']);
      expect(find.text('body-pin'), findsNothing);
      expect(find.byKey(const Key('comment-input')), findsNothing);
      final state = tester.state(find.byType(CommunityCommentsPanel));
      await mount(tester, repo, visible: (value) => rows = value);
      expect(tester.state(find.byType(CommunityCommentsPanel)), same(state));
      expect(find.text('body-pin'), findsOneWidget);
      expect(find.byKey(const Key('comment-input')), findsOneWidget);
    },
  );
  testWidgets(
    'refresh hides media, clears reply and pins, and opens appeal case',
    (tester) async {
      final original = CommunityComment(
        id: 'target',
        workId: 'work',
        userId: 'me',
        body: 'original text',
        authorName: '原作者',
        createdAt: DateTime.utc(2026),
        status: CommunityCommentStatus.published,
        moderationPending: true,
        anchor: CommunityCommentAnchor(position: [0, 0, 0]),
        attachments: [
          const CommunityCommentAttachment(
            id: 'photo',
            url: 'https://example.invalid/photo.png',
            mimeType: 'image/png',
          ),
        ],
      );
      final repo = FakeComments()
        ..rows = [original]
        ..publicCount = 7;
      final visible = <List<CommunityComment>>[];
      String? selectedCase;
      await mount(
        tester,
        repo,
        visible: visible.add,
        moderationCase: (id) => selectedCase = id,
        refreshInterval: const Duration(seconds: 1),
      );
      addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
      expect(visible.last.single.anchor, isNotNull);
      await tester.tap(find.text('回复'));
      await tester.enterText(
        find.byKey(const Key('comment-input')),
        'keep draft',
      );
      await tester.tap(find.bySemanticsLabel('评论图片 1'));
      await tester.pump();
      expect(find.byTooltip('关闭图片'), findsOneWidget);
      repo.rows = [
        CommunityComment(
          id: 'target',
          workId: 'work',
          userId: 'me',
          body: 'must not render',
          authorName: '原作者',
          createdAt: DateTime.utc(2026),
          status: CommunityCommentStatus.hidden,
          moderationCaseId: 'case-1',
          moderationReason: '包含人身攻击',
          anchor: original.anchor,
          attachments: original.attachments,
        ),
      ];
      repo.publicCount = 6;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('用户评论 6'), findsOneWidget);
      expect(find.text('该评论因违反社区规范已被隐藏'), findsOneWidget);
      expect(find.text('包含人身攻击'), findsOneWidget);
      expect(find.text('must not render'), findsNothing);
      expect(find.text('original text'), findsNothing);
      expect(find.byTooltip('关闭图片'), findsNothing);
      expect(find.bySemanticsLabel('评论图片 1'), findsNothing);
      expect(find.text('查看模型点位'), findsNothing);
      expect(find.text('回复'), findsNothing);
      expect(find.text('回复 原作者'), findsNothing);
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
      expect(find.text('修改重发'), findsNothing);
      expect(find.text('keep draft'), findsOneWidget);
      expect(visible.last.single.anchor, isNull);
      expect(visible.last.single.attachments, isEmpty);
      await tester.tap(find.text('查看原因与申诉'));
      expect(selectedCase, 'case-1');
      await mount(tester, repo, user: 'other');
      expect(find.text('该评论因违反社区规范已被隐藏'), findsNothing);
      expect(find.text('keep draft'), findsNothing);
      expect(find.text('用户评论 6'), findsOneWidget);
    },
  );

  testWidgets(
    'automatic refresh preserves draft and pauses while inactive, offstage, and background',
    (tester) async {
      final repo = FakeComments();
      Future<void> show({bool active = true, bool ticker = true}) => mount(
        tester,
        repo,
        refreshInterval: const Duration(seconds: 1),
        active: active,
        tickerEnabled: ticker,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (tester.binding.lifecycleState == AppLifecycleState.paused) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await show();
      await tester.enterText(
        find.byKey(const Key('comment-input')),
        'unfinished',
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(repo.fetches, 2);
      expect(find.text('unfinished'), findsOneWidget);
      await show(active: false);
      var count = repo.fetches;
      await tester.pump(const Duration(seconds: 3));
      expect(repo.fetches, count);
      await show(ticker: false);
      await tester.pump(const Duration(seconds: 3));
      expect(repo.fetches, count);
      await show();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      count = repo.fetches;
      await tester.pump(const Duration(seconds: 3));
      expect(repo.fetches, count);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(repo.fetches, greaterThan(count));
      expect(find.text('unfinished'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      count = repo.fetches;
      await tester.pump(const Duration(seconds: 3));
      expect(repo.fetches, count);
    },
  );

  testWidgets('automatic refresh never overwrites an in-flight submit', (
    tester,
  ) async {
    final repo = FakeComments()..pendingSubmit = Completer<CommunityComment>();
    final visible = <List<CommunityComment>>[];
    await mount(
      tester,
      repo,
      refreshInterval: const Duration(seconds: 1),
      visible: visible.add,
    );
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
    repo.pendingFetch = Completer<CommunityCommentPage>();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byKey(const Key('comment-input')), 'publish');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pump();
    final count = repo.fetches;
    await tester.pump(const Duration(seconds: 3));
    expect(repo.fetches, count);
    repo.pendingSubmit!.complete(comment('new', moderationPending: true));
    await tester.pump();
    repo.pendingFetch!.complete(
      CommunityCommentPage(
        assetRevision: 'revision',
        comments: [],
        canComment: true,
        publicCount: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('body-new'), findsOneWidget);
    expect(find.text('用户评论 1'), findsOneWidget);
    expect(visible.last.single.id, 'new');
  });

  testWidgets('route behind another page does not poll and back resumes', (
    tester,
  ) async {
    final repo = FakeComments();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        navigatorKey: navigator,
        home: Scaffold(
          body: CommunityCommentsPanel(
            workId: 'work',
            repository: repo,
            currentUserId: 'me',
            refreshInterval: const Duration(seconds: 1),
          ),
        ),
      ),
    );
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('next route')),
      ),
    );
    await tester.pumpAndSettle();
    final count = repo.fetches;
    await tester.pump(const Duration(seconds: 3));
    expect(repo.fetches, count);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repo.fetches, greaterThan(count));
  });

  testWidgets(
    'UTF-16 emoji limit disables send without truncating pasted draft',
    (tester) async {
      final repo = FakeComments();
      await mount(tester, repo);
      final text = '🙂' * 300;
      await tester.enterText(find.byKey(const Key('comment-input')), text);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('comment-send')))
            .onPressed,
        isNotNull,
      );
      expect(find.textContaining('600/600'), findsOneWidget);
      final overlong = '$text字';
      await tester.enterText(find.byKey(const Key('comment-input')), overlong);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('comment-input')))
            .controller!
            .text,
        overlong,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('comment-send')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('601/600'), findsOneWidget);
      expect(repo.sent, isEmpty);
      await tester.enterText(find.byKey(const Key('comment-input')), 'a' * 599);
      await tester.tap(find.byTooltip('添加表情'));
      await tester.pump();
      await tester.tap(find.text('🙂'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('comment-input')))
            .controller!
            .text,
        'a' * 599,
      );
      await tester.enterText(find.byKey(const Key('comment-input')), 'a' * 598);
      await tester.tap(find.text('🙂'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('comment-input')))
            .controller!
            .text,
        'a' * 598 + '🙂',
      );
    },
  );
  testWidgets(
    'identity exception clears existing private state and visible pins',
    (tester) async {
      final repo = FakeComments()
        ..rows = [comment('private', status: CommunityCommentStatus.pending)]
        ..submitError = const CommunityCommentException('identity_changed');
      final events = <List<CommunityComment>>[];
      await mount(tester, repo, visible: (rows) => events.add(rows));
      expect(find.text('body-private'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('comment-input')),
        'private draft',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('comment-send')));
      await tester.pumpAndSettle();
      expect(find.text('body-private'), findsNothing);
      expect(find.text('private draft'), findsNothing);
      expect(events.last, isEmpty);
    },
  );

  testWidgets('selection and composing changes preserve failed-request id', (
    tester,
  ) async {
    final repo = FakeComments()..failSubmit = true;
    await mount(tester, repo);
    await tester.enterText(find.byKey(const Key('comment-input')), 'same body');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<TextField>(find.byKey(const Key('comment-input')))
        .controller!;
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    controller.value = controller.value.copyWith(
      composing: const TextRange(start: 0, end: 2),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(repo.sent.length, 2);
    expect(repo.sent.first.clientRequestId, repo.sent.last.clientRequestId);
  });
  testWidgets(
    'required exact asset hash rejects missing or stale bindings and clears pins',
    (tester) async {
      final hash = 'a' * 64;
      final repo = FakeComments()
        ..rows = [comment('private', status: CommunityCommentStatus.pending)]
        ..assetSha256 = hash;
      final visible = <List<CommunityComment>>[];
      await mount(
        tester,
        repo,
        expectedAssetSha256: hash,
        requireAssetBinding: true,
        visible: (rows) => visible.add(rows),
      );
      expect(find.text('body-private'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('comment-input')), 'draft');
      await mount(
        tester,
        repo,
        expectedAssetSha256: 'b' * 64,
        requireAssetBinding: true,
        visible: (rows) => visible.add(rows),
      );
      expect(find.text('body-private'), findsNothing);
      expect(find.text('draft'), findsNothing);
      expect(visible.last, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('comment-send')))
            .onPressed,
        isNull,
      );
      repo.assetSha256 = null;
      await mount(
        tester,
        repo,
        expectedAssetSha256: hash,
        requireAssetBinding: true,
        visible: (rows) => visible.add(rows),
      );
      expect(find.text('body-private'), findsNothing);
      expect(visible.last, isEmpty);
      await mount(
        tester,
        repo,
        requireAssetBinding: true,
        visible: (rows) => visible.add(rows),
      );
      expect(find.textContaining('模型身份校验中'), findsWidgets);
    },
  );
  testWidgets('private pending rows never leak or inflate public count', (
    tester,
  ) async {
    final repo = FakeComments()
      ..publicCount = 1
      ..rows = [
        comment('public', user: 'other'),
        comment('private', status: CommunityCommentStatus.pending),
        comment('secret', user: 'other', status: CommunityCommentStatus.review),
        comment('deleted', status: CommunityCommentStatus.removed),
      ];
    await mount(tester, repo);
    expect(find.text('用户评论 1'), findsOneWidget);
    expect(find.text('body-private'), findsOneWidget);
    expect(find.text('待发布 · 仅自己可见'), findsOneWidget);
    expect(find.text('body-secret'), findsNothing);
    expect(find.text('body-deleted'), findsNothing);
  });
  testWidgets(
    'published response is public immediately while background audit is pending',
    (tester) async {
      final anchor = CommunityCommentAnchor(position: [1, 2, 3]);
      final repo = FakeComments()
        ..submitResult = comment(
          'new',
          moderationPending: true,
          anchor: anchor,
        );
      final visible = <List<CommunityComment>>[];
      await mount(tester, repo, visible: visible.add);
      await tester.enterText(find.byKey(const Key('comment-input')), '你好🙂');
      await tester.pump();
      await tester.tap(find.byKey(const Key('comment-send')));
      await tester.pumpAndSettle();
      expect(repo.sent.single.body, '你好🙂');
      expect(find.text('待发布 · 仅自己可见'), findsNothing);
      expect(find.text('用户评论 1'), findsOneWidget);
      expect(find.text('body-new'), findsOneWidget);
      expect(find.text('查看模型点位'), findsOneWidget);
      expect(visible.last.single.anchor, same(anchor));
      expect(visible.last.single.moderationPending, isTrue);
      expect(visible.last.single.published, isTrue);
      expect(find.text('发布成功'), findsNothing);
    },
  );
  testWidgets('transport failure preserves draft and retries same id', (
    tester,
  ) async {
    final repo = FakeComments()..failSubmit = true;
    await mount(tester, repo);
    await tester.enterText(find.byKey(const Key('comment-input')), '保留草稿');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(find.text('保留草稿'), findsOneWidget);
    expect(find.text('发送失败，草稿已保留，请重试'), findsOneWidget);
    repo.failSubmit = false;
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(repo.sent.length, 2);
    expect(repo.sent.first.clientRequestId, repo.sent.last.clientRequestId);
  });
  testWidgets(
    'image only submission, cancellation and image removal preserve text',
    (tester) async {
      final repo = FakeComments();
      var cancel = false;
      final png = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j5f8AAAAASUVORK5CYII=',
        ),
      );
      await mount(
        tester,
        repo,
        picker: (_) async => cancel
            ? []
            : [
                CommunityCommentImageDraft(
                  bytes: png,
                  fileName: 'photo.png',
                  mimeType: 'image/png',
                ),
              ],
      );
      await tester.tap(find.byTooltip('添加图片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-send')));
      await tester.pumpAndSettle();
      expect(repo.sent.single.body, '');
      expect(repo.sent.single.images.length, 1);
      await tester.enterText(find.byKey(const Key('comment-input')), '留下');
      cancel = true;
      await tester.tap(find.byTooltip('添加图片'));
      await tester.pumpAndSettle();
      expect(find.text('留下'), findsOneWidget);
      cancel = false;
      await tester.tap(find.byTooltip('添加图片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('移除图片 1'));
      await tester.pumpAndSettle();
      expect(find.text('留下'), findsOneWidget);
    },
  );
  testWidgets('reply, point callback and selected anchor enter draft', (
    tester,
  ) async {
    final repo = FakeComments()..rows = [comment('parent')];
    var picked = false;
    var cleared = false;
    final anchor = CommunityCommentAnchor(position: [1, 2, 3]);
    await mount(
      tester,
      repo,
      anchor: anchor,
      pick: () => picked = true,
      clear: () => cleared = true,
    );
    await tester.tap(find.byTooltip('选择模型点位'));
    expect(picked, isTrue);
    await tester.tap(find.text('回复'));
    await tester.pump();
    expect(find.text('回复 用户parent'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-input')), '回复内容');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(repo.sent.single.parentId, 'parent');
    expect(repo.sent.single.anchor, same(anchor));
    expect(cleared, isTrue);
  });
  testWidgets('account switch clears private comments and composer', (
    tester,
  ) async {
    final repo = FakeComments()
      ..rows = [comment('private', status: CommunityCommentStatus.pending)];
    await mount(tester, repo);
    await tester.enterText(find.byKey(const Key('comment-input')), '私有草稿');
    await mount(tester, repo, user: 'other');
    expect(find.text('body-private'), findsNothing);
    expect(find.text('私有草稿'), findsNothing);
  });
  testWidgets('account switch clears an inherited draft anchor', (
    tester,
  ) async {
    final repo = FakeComments();
    final anchor = CommunityCommentAnchor(position: [1, 2, 3]);
    await mount(tester, repo, anchor: anchor);
    expect(find.text('已选择模型点位'), findsOneWidget);
    await mount(tester, repo, user: 'other', anchor: anchor);
    expect(find.text('已选择模型点位'), findsNothing);
  });
  testWidgets('stale submit response cannot repopulate switched account', (
    tester,
  ) async {
    final repo = FakeComments()..pendingSubmit = Completer<CommunityComment>();
    await mount(tester, repo);
    await tester.enterText(find.byKey(const Key('comment-input')), '旧账号');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pump();
    expect(repo.sent.length, 1);
    await mount(tester, repo, user: 'other');
    repo.pendingSubmit!.complete(
      comment('stale', status: CommunityCommentStatus.pending),
    );
    await tester.pumpAndSettle();
    expect(find.text('body-stale'), findsNothing);
    expect(find.text('旧账号'), findsNothing);
  });
  testWidgets('cancelled image picking preserves failed-request identity', (
    tester,
  ) async {
    final repo = FakeComments()..failSubmit = true;
    await mount(tester, repo, picker: (_) async => []);
    await tester.enterText(
      find.byKey(const Key('comment-input')),
      'same content',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(repo.sent.length, 2);
    expect(repo.sent.first.clientRequestId, repo.sent.last.clientRequestId);
    await tester.enterText(find.byKey(const Key('comment-input')), 'edited');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(
      repo.sent.last.clientRequestId,
      isNot(repo.sent.first.clientRequestId),
    );
  });
  testWidgets('oversize images report capacity and retain text', (
    tester,
  ) async {
    final repo = FakeComments();
    await mount(
      tester,
      repo,
      picker: (_) async => [
        CommunityCommentImageDraft(
          bytes: Uint8List(2 * 1024 * 1024 + 1),
          fileName: 'large.png',
          mimeType: 'image/png',
        ),
      ],
    );
    await tester.enterText(find.byKey(const Key('comment-input')), 'keep text');
    await tester.tap(find.byTooltip('添加图片'));
    await tester.pumpAndSettle();
    expect(find.text('每张图片不能超过 2 MiB'), findsOneWidget);
    expect(find.text('keep text'), findsOneWidget);
    expect(find.byTooltip('移除图片 1'), findsNothing);
  });
  testWidgets('anchor changes preserve body and can be removed', (
    tester,
  ) async {
    final repo = FakeComments();
    await mount(tester, repo);
    await tester.enterText(find.byKey(const Key('comment-input')), 'keep body');
    await mount(
      tester,
      repo,
      anchor: CommunityCommentAnchor(position: [1, 2, 3]),
    );
    expect(find.text('keep body'), findsOneWidget);
    expect(find.text('已选择模型点位'), findsOneWidget);
    await tester.tap(find.byTooltip('移除模型点位'));
    await tester.pump();
    expect(find.text('已选择模型点位'), findsNothing);
    expect(find.text('keep body'), findsOneWidget);
  });
  testWidgets(
    'stale fetch from previous repository cannot expose private rows',
    (tester) async {
      final old = FakeComments()
        ..pendingFetch = Completer<CommunityCommentPage>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: Scaffold(
            body: CommunityCommentsPanel(
              workId: 'work',
              repository: old,
              currentUserId: 'me',
              refreshInterval: null,
            ),
          ),
        ),
      );
      await tester.pump();
      final next = FakeComments();
      await mount(tester, next, user: 'other');
      old.pendingFetch!.complete(
        CommunityCommentPage(
          assetRevision: 'old',
          comments: [
            comment('old-secret', status: CommunityCommentStatus.pending),
          ],
          canComment: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('body-old-secret'), findsNothing);
    },
  );
  testWidgets('rejected comment can be edited and resubmitted for review', (
    tester,
  ) async {
    final repo = FakeComments()
      ..submitResult = comment(
        'legacy-new',
        status: CommunityCommentStatus.pending,
      )
      ..rows = [comment('rejected', status: CommunityCommentStatus.rejected)];
    await mount(tester, repo);
    await tester.tap(find.text('修改重发'));
    await tester.pump();
    expect(find.text('body-rejected'), findsNWidgets(2));
    await tester.enterText(find.byKey(const Key('comment-input')), '已修改');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(repo.sent.single.body, '已修改');
    expect(find.text('待发布 · 仅自己可见'), findsOneWidget);
  });
  testWidgets('identity switch closes a private image preview', (tester) async {
    final repo = FakeComments()
      ..rows = [
        CommunityComment(
          id: 'image-private',
          workId: 'work',
          userId: 'me',
          body: '',
          authorName: '我',
          createdAt: DateTime.utc(2026),
          status: CommunityCommentStatus.review,
          attachments: [
            const CommunityCommentAttachment(
              id: 'image',
              url: 'https://example.invalid/private.png',
              mimeType: 'image/png',
            ),
          ],
        ),
      ];
    await mount(tester, repo);
    await tester.tap(find.bySemanticsLabel('评论图片 1'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭图片'), findsOneWidget);
    await mount(tester, repo, user: 'other');
    expect(find.byTooltip('关闭图片'), findsNothing);
    expect(find.bySemanticsLabel('评论图片 1'), findsNothing);
  });
  testWidgets('stale image picker cannot fill a new account draft', (
    tester,
  ) async {
    final picked = Completer<List<CommunityCommentImageDraft>>();
    final repo = FakeComments();
    await mount(tester, repo, picker: (_) => picked.future);
    await tester.tap(find.byTooltip('添加图片'));
    await tester.pump();
    await mount(tester, repo, user: 'other');
    picked.complete([
      CommunityCommentImageDraft(
        bytes: Uint8List.fromList([1]),
        fileName: 'private.png',
        mimeType: 'image/png',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.byTooltip('移除图片 1'), findsNothing);
  });
  testWidgets('320 pixel screen with keyboard has no overflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(() => tester.view.resetViewInsets());
    final repo = FakeComments()..rows = [comment('public')];
    await mount(
      tester,
      repo,
      anchor: CommunityCommentAnchor(position: [0, 0, 0]),
    );
    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'technical server status preserves the original draft and anchor',
    (tester) async {
      final anchor = CommunityCommentAnchor(position: [1, 2, 3]);
      final repo = FakeComments()
        ..submitResult = comment(
          'failed',
          status: CommunityCommentStatus.error,
        );
      await mount(tester, repo, anchor: anchor);
      await tester.enterText(find.byKey(const Key('comment-input')), '保留草稿');
      await tester.pump();
      await tester.tap(find.byKey(const Key('comment-send')));
      await tester.pumpAndSettle();
      expect(find.text('发送失败，草稿已保留，请重试'), findsOneWidget);
      expect(find.text('已选择模型点位'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('comment-input')))
            .controller!
            .text,
        '保留草稿',
      );
      expect(repo.sent.single.anchor, same(anchor));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
