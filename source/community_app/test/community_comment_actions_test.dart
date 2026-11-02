// Fake renderer transport exercises actual detail/panel/viewer integration locally.
// ignore_for_file: invalid_use_of_internal_member
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:pocketworld_flutter/auth/auth_scope.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/ui/community/public_work_entry.dart';
import 'public_work_sign_in_test.dart' show TestUser;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/comments/comment_models.dart';
import 'package:pocketworld_flutter/community/comments/comment_repository.dart';
import 'package:pocketworld_flutter/community/comments/comment_moderation_repository.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/comments/community_comments_panel.dart';
import 'package:pocketworld_flutter/ui/community/work_detail_page.dart';
import 'package:pocketworld_flutter/ui/shared/community_viewer_session.dart';
import 'package:pocketworld_flutter/ui/shared/product_model_view.dart';

late File _modelFile;
late String _modelSha;

class _Service extends CommunityService {
  _Service() : super(client: Supabase.instance.client);
  String? user = 'me';
  int likes = 0;
  @override
  String? get currentUserId => user;
  @override
  String modelUrlFor(String path) => 'https://offline.invalid/$path';
  @override
  Future<int?> recordView(String workId) async => 5;
  @override
  Future<bool> toggleLike({
    required String workId,
    required bool currentlyLiked,
  }) async {
    likes++;
    return !currentlyLiked;
  }
}

CommunityComment _comment(
  String id, {
  String user = 'me',
  CommunityCommentStatus status = CommunityCommentStatus.published,
  bool moderationPending = false,
  String? parentId,
  List<CommunityCommentAttachment> attachments = const [],
}) => CommunityComment(
  id: id,
  workId: 'work',
  userId: user,
  body: '内容$id',
  parentId: parentId,
  attachments: attachments,
  authorName: '作者$id',
  createdAt: DateTime.utc(2026),
  status: status,
  moderationPending: moderationPending,
  moderationCaseId: status == CommunityCommentStatus.hidden ? 'case1' : null,
  moderationReason: status == CommunityCommentStatus.hidden ? '评论含有人身攻击' : null,
  anchor: CommunityCommentAnchor(position: [1, 2, 3], normal: [0, 1, 0]),
);

class _Comments implements CommunityCommentRepository {
  final drafts = <CommunityCommentDraft>[];
  String? assetSha256;
  _Comments() : assetSha256 = _modelSha;
  List<CommunityComment> rows = [];
  int fetches = 0;
  Completer<CommunityCommentPage>? nextFetch;
  @override
  Future<CommunityCommentPage> fetch(String id) async {
    fetches++;
    return nextFetch != null
        ? nextFetch!.future
        : CommunityCommentPage(
            assetRevision: 'asset-$id',
            assetSha256: assetSha256,
            comments: rows.where((r) => r.workId == id).toList(),
            canComment: true,
            publicCount: rows.where((r) => r.published).length,
          );
  }

  @override
  Future<CommunityComment> submit(CommunityCommentDraft draft) async {
    drafts.add(draft);
    return _comment('submitted', moderationPending: true);
  }

  @override
  Future<void> remove(String workId, String commentId) async {}
  @override
  Future<CommunityComment> setLiked(
    String workId,
    String commentId,
    bool liked,
  ) async => _comment(commentId);
}

class _PagedComments extends _Comments
    implements CommunityCommentFeedRepository {
  bool hold = false;
  final pending = <CommunityCommentSection, Completer<CommunityCommentPage>>{};
  Future<CommunityCommentPage> page() => fetch('work');
  @override
  Future<CommunityCommentPage> fetchSection(
    String workId, {
    required CommunityCommentSection section,
    String? cursor,
  }) {
    if (hold) {
      return (pending[section] = Completer<CommunityCommentPage>()).future;
    }
    return page();
  }
}

class _Renderer {
  final sessions = CommunityViewerSessions();
  _Renderer() {
    _renderers.add(this);
  }
  String? loadedFormat;
  SharedViewerController? controller;
  int mounts = 0;
  int disposals = 0;
  final requests = <Map<String, Object?>>[];
  Widget host(
    BuildContext context,
    SharedViewerController controller,
    VoidCallback ready,
    ValueChanged<Object> error,
  ) => _Host(renderer: this, controller: controller, ready: ready);
  Future<void> request(Map<String, Object?> req) async {
    requests.add(req);
    if (req['method'] == 'load') {
      loadedFormat = (req['args'] as Map)['format'] as String;
    }
    controller!.receive({
      'protocol': sharedViewerProtocol,
      'id': req['id'],
      'ok': true,
      'result': req['method'] == 'getState'
          ? {
              'status': loadedFormat == null ? 'empty' : 'ready',
              'format': loadedFormat,
              'error': null,
              'disposed': false,
            }
          : null,
    });
  }

  void pick() => controller!.receive({
    'protocol': sharedViewerProtocol,
    'type': 'pw-viewer-surface-picked',
    'anchor': {
      'position': [1, 2, 3],
      'normal': [0, 1, 0],
      'cameraPosition': [4, 5, 6],
      'cameraTarget': [0, 0, 0],
    },
  });
  void layout(
    String? id, {
    bool expanded = true,
    double x = .8,
    double y = .4,
  }) => controller!.receive({
    'protocol': sharedViewerProtocol,
    'type': 'pw-viewer-surface-marker-layout',
    'layout': id == null
        ? null
        : {'id': id, 'x': x, 'y': y, 'expanded': expanded},
  });
  void marker(String id) => controller!.receive({
    'protocol': sharedViewerProtocol,
    'type': 'pw-viewer-surface-marker-selected',
    'id': id,
  });
}

class _Host extends StatefulWidget {
  const _Host({
    required this.renderer,
    required this.controller,
    required this.ready,
  });
  final _Renderer renderer;
  final SharedViewerController controller;
  final VoidCallback ready;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    widget.renderer.mounts++;
    widget.renderer.controller = widget.controller;
    widget.controller.attachTransport(
      widget.renderer.request,
      registerLocal: (path) async =>
          Uri.parse('http://127.0.0.1:1234/model.glb'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.ready();
    });
  }

  @override
  void dispose() {
    widget.renderer.disposals++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: ValueKey('fake-model-host'), color: Colors.black);
}

FeedWork _work(String id, {String format = 'glb'}) => FeedWork(
  id: id,
  userId: 'owner',
  title: '作品$id',
  description: '作品说明',
  format: format,
  modelStoragePath: '$id.$format',
  thumbnailStoragePath: 'existing.jpg',
  likesCount: 3,
  viewsCount: 4,
  publishedAt: null,
  authorDisplayName: '作者',
  authorAvatarUrl: null,
  likedByMe: false,
);
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Service service,
  _Comments comments,
  _Renderer renderer, {
  String work = 'work',
  String format = 'glb',
  CommunityCommentImagePicker? picker,
  String? modelPath,
  CommunityCommentModerationRepository? moderationRepository,
  TestUser? auth,
  LocaleNotifier? locale,
  bool webLayout = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      builder: auth == null
          ? null
          : (context, child) => LocaleScope(
              notifier: locale!,
              child: AuthScope(currentUser: auth, child: child!),
            ),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: WorkDetailPage(
        work: _work(work, format: format),
        webCommentLayoutForTesting: webLayout,
        service: service,
        commentRepository: comments,
        communitySessions: renderer.sessions,
        commentModerationRepository: moderationRepository,
        commentImagePicker: picker,
        viewerHostBuilder: renderer.host,
        resolveModelPath: (_) async => modelPath ?? _modelFile.path,
      ),
    ),
  );
  await _flush(tester);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('work-detail-comments')));
  await _flush(tester);
}

final _renderers = <_Renderer>[];
void _detailTestWidgets(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    _renderers.clear();
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _flush(tester);
      for (final renderer in _renderers) {
        await renderer.sessions.dispose();
      }
    }
  });
}

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync(
      'pw-detail-comment-fixture-',
    );
    final json = utf8.encode(
      '{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[]}]}',
    );
    final paddedLength = (json.length + 3) ~/ 4 * 4;
    final bytes = Uint8List(20 + paddedLength);
    final header = ByteData.sublistView(bytes);
    header.setUint32(0, 0x46546c67, Endian.little);
    header.setUint32(4, 2, Endian.little);
    header.setUint32(8, bytes.length, Endian.little);
    header.setUint32(12, paddedLength, Endian.little);
    header.setUint32(16, 0x4e4f534a, Endian.little);
    bytes.fillRange(20, bytes.length, 32);
    bytes.setRange(20, 20 + json.length, json);
    _modelFile = File('${dir.path}/fixture.glb')..writeAsBytesSync(bytes);
    _modelSha = sha256.convert(bytes).toString();
    addTearDown(() => dir.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://offline.invalid',
      anonKey: 'anon',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });

  _detailTestWidgets(
    'feed detail resolves real auth scope and returns to same work',
    (tester) async {
      final auth = TestUser(), locale = LocaleNotifier();
      final service = _Service()..user = null;
      final comments = _Comments()..rows = [_comment('public', user: 'reader')];
      final renderer = _Renderer();
      await _mount(
        tester,
        service,
        comments,
        renderer,
        auth: auth,
        locale: locale,
      );
      await _open(tester);
      expect(find.text('内容public'), findsOneWidget);
      final login = find.widgetWithText(TextButton, '登录后发表评论');
      expect(login, findsOneWidget);
      final detailState = tester.state(find.byType(WorkDetailPage));
      await tester.tap(login);
      await tester.pumpAndSettle();
      expect(find.byType(PublicWorkSignIn), findsOneWidget);
      // The real route observes the existing CurrentUser, including nested auth.
      service.user = 'owner';
      auth.finishLogin();
      await tester.pumpAndSettle();
      expect(find.byType(PublicWorkSignIn), findsNothing);
      expect(tester.state(find.byType(WorkDetailPage)), same(detailState));
      // The signed-in renderer session is intentionally partitioned by identity.
      await _open(tester);
      expect(find.text('内容public'), findsOneWidget);
      expect(find.text('回复'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      locale.dispose();
    },
  );

  _detailTestWidgets(
    'detail close hides actual panel without popping work and reopens',
    (tester) async {
      final renderer = _Renderer(),
          comments = _Comments()..rows = [_comment('public')];
      await _mount(tester, _Service(), comments, renderer);
      await _open(tester);
      final detailState = tester.state(find.byType(WorkDetailPage));
      await tester.tap(find.byTooltip('关闭评论'));
      await _flush(tester);
      expect(find.byTooltip('关闭评论'), findsNothing);
      expect(tester.state(find.byType(WorkDetailPage)), same(detailState));
      await _open(tester);
      expect(find.text('内容public'), findsOneWidget);
      expect(renderer.mounts, 1);
    },
  );

  _detailTestWidgets(
    'manual refresh visibly waits once then finishes or offers retry',
    (tester) async {
      final comments = _Comments()..rows = [_comment('public')];
      await _mount(tester, _Service(), comments, _Renderer());
      await _open(tester);
      final before = comments.fetches;
      comments.nextFetch = Completer<CommunityCommentPage>();
      await tester.tap(find.byTooltip('刷新评论'));
      await tester.pump();
      final refresh = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == '刷新评论',
      );
      expect(comments.fetches, before + 1);
      expect(tester.widget<IconButton>(refresh).onPressed, isNull);
      expect(
        find.descendant(
          of: refresh,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(refresh);
      expect(comments.fetches, before + 1);
      comments.nextFetch!.completeError(StateError('offline'));
      await _flush(tester);
      expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
      expect(find.text('评论暂时无法加载'), findsOneWidget);
      comments.nextFetch = null;
      await tester.tap(refresh);
      await _flush(tester);
      expect(find.text('内容public'), findsOneWidget);
    },
  );

  _detailTestWidgets(
    'paged manual refresh has one visible in-flight request per section',
    (tester) async {
      final comments = _PagedComments()..rows = [_comment('public')];
      await _mount(tester, _Service(), comments, _Renderer());
      await _open(tester);
      comments.hold = true;
      final refresh = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == '刷新评论',
      );
      await tester.tap(refresh);
      await tester.pump();
      expect(tester.widget<IconButton>(refresh).onPressed, isNull);
      expect(
        find.descendant(
          of: refresh,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(comments.pending.length, 2);
      final requests = comments.pending.values.toList();
      await tester.tap(refresh);
      expect(comments.pending.values.toList(), requests);
      for (final request in requests) {
        request.complete(await comments.page());
      }
      await _flush(tester);
      expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
      expect(
        find.descendant(
          of: refresh,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(find.text('内容public'), findsOneWidget);
      await tester.tap(find.text('最新'));
      await _flush(tester);
      expect(find.text('内容public'), findsOneWidget);
      await tester.tap(find.text('热评'));
      await _flush(tester);
      expect(find.text('内容public'), findsOneWidget);
    },
  );

  _detailTestWidgets(
    'authenticated work author reply remains attributed and targets its parent',
    (tester) async {
      final comments = _Comments()
        ..rows = [
          _comment('parent', user: 'reader'),
          _comment('answer', user: 'owner', parentId: 'parent'),
        ];
      await _mount(
        tester,
        _Service()..user = 'owner',
        comments,
        _Renderer(),
        webLayout: true,
      );
      await _open(tester);
      expect(find.text('作者回复'), findsOneWidget);
      await tester.tap(find.text('回复').first);
      await tester.enterText(
        find.byKey(const Key('comment-input')),
        'Author reply',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('comment-send')));
      await _flush(tester);
      expect(comments.drafts.single.parentId, 'parent');
      expect(comments.drafts.single.body, 'Author reply');
    },
  );

  _detailTestWidgets(
    'desktop comments drag clamps width without covering or reloading viewer',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final renderer = _Renderer();
      await _mount(
        tester,
        _Service(),
        _Comments()..rows = [_comment('public')],
        renderer,
        webLayout: true,
      );
      await _open(tester);
      final divider = find.byKey(const ValueKey('community-comments-resize'));
      final panel = find.byKey(const ValueKey('inline-community-comments'));
      final model = find.byKey(const ValueKey('fake-model-host'));
      expect(divider, findsOneWidget);
      expect(tester.getSize(panel).width, 360);
      await tester.drag(divider, const Offset(-100, 0));
      await tester.pump();
      expect(tester.getSize(panel).width, closeTo(460, 1));
      await tester.drag(divider, const Offset(80, 0));
      await tester.pump();
      expect(tester.getSize(panel).width, closeTo(380, 1));
      await tester.drag(divider, const Offset(-2000, 0));
      await tester.pump();
      expect(tester.getSize(panel).width, 640);
      expect(
        tester.getRect(model).right,
        lessThanOrEqualTo(tester.getRect(divider).left),
      );
      expect(
        tester.getRect(divider).right,
        lessThanOrEqualTo(tester.getRect(panel).left),
      );
      expect(tester.getSize(model).width, greaterThanOrEqualTo(320));
      await tester.drag(divider, const Offset(2000, 0));
      await tester.pump();
      expect(tester.getSize(panel).width, 280);
      await tester.drag(divider, const Offset(-140, 0));
      await tester.pump();
      expect(tester.getSize(panel).width, 420);
      await tester.tap(find.byTooltip('关闭评论'));
      await _flush(tester);
      await _open(tester);
      expect(tester.getSize(panel).width, 420);
      await tester.drag(divider, const Offset(-1000, 0));
      await tester.pump();
      tester.view.physicalSize = const Size(800, 900);
      await tester.pump();
      expect(tester.getSize(panel).width, lessThanOrEqualTo(400));
      expect(tester.getSize(model).width, greaterThanOrEqualTo(320));
      expect(
        tester.getRect(model).right,
        lessThanOrEqualTo(tester.getRect(panel).left),
      );
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('community-comments-resize')),
        findsNothing,
      );
      expect(tester.getSize(panel).width, 390);
      expect(
        tester.getRect(model).bottom,
        lessThanOrEqualTo(tester.getRect(panel).top),
      );
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pump();
      expect(tester.getSize(panel).width, 640);
      expect(renderer.mounts, 1);
      expect(renderer.disposals, 0);
      expect(tester.takeException(), isNull);
    },
  );

  _detailTestWidgets(
    'desktop resize border has keyboard adjustments and an accessible label',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      try {
        await _mount(
          tester,
          _Service(),
          _Comments(),
          _Renderer(),
          webLayout: true,
        );
        await _open(tester);
        final divider = find.byKey(const ValueKey('community-comments-resize'));
        final panel = find.byKey(const ValueKey('inline-community-comments'));
        expect(find.bySemanticsLabel('调整评论栏宽度'), findsOneWidget);
        await tester.tap(divider);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(tester.getSize(panel).width, 380);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(tester.getSize(panel).width, 360);
        final mouse = tester.widgetList<MouseRegion>(
          find.ancestor(of: divider, matching: find.byType(MouseRegion)),
        );
        expect(
          mouse.any((m) => m.cursor == SystemMouseCursors.resizeLeftRight),
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  _detailTestWidgets(
    'resize down gates platform pointers synchronously and restores cancel close narrow and dispose',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final renderer = _Renderer();
      await _mount(tester, _Service(), _Comments(), renderer, webLayout: true);
      await _open(tester);
      final viewer = tester.widget<ProductModelView>(
        find.byType(ProductModelView),
      );
      expect(
        viewer.pointerEventsEnabledNotifier,
        isNotNull,
        reason:
            'The actual detail-to-platform-view transport must carry the synchronous gate',
      );
      final gate = viewer.pointerEventsEnabledNotifier!;
      final divider = find.byKey(const ValueKey('community-comments-resize'));
      expect(gate.value, isTrue);
      final first = await tester.startGesture(tester.getCenter(divider));
      expect(gate.value, isFalse); // Before the next frame or pan recognition.
      await first.moveBy(const Offset(-80, 0));
      await tester.pump();
      expect(gate.value, isFalse);
      await first.cancel();
      expect(gate.value, isTrue);
      final second = await tester.startGesture(tester.getCenter(divider));
      expect(gate.value, isFalse);
      await second.up();
      expect(gate.value, isTrue);
      final third = await tester.startGesture(tester.getCenter(divider));
      final close = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == '关闭评论',
      );
      tester.widget<IconButton>(close).onPressed!();
      expect(gate.value, isTrue);
      await third.cancel();
      await _flush(tester);
      await _open(tester);
      final fourth = await tester.startGesture(tester.getCenter(divider));
      expect(gate.value, isFalse);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(gate.value, isTrue);
      await fourth.cancel();
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pump();
      final fifth = await tester.startGesture(tester.getCenter(divider));
      expect(gate.value, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(gate.value, isTrue);
      await fifth.cancel();
      expect(renderer.mounts, 1);
    },
  );

  for (final width in [1920.0, 2560.0]) {
    _detailTestWidgets(
      'sidebar maximum is exactly half of $width without obscuring viewer',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final renderer = _Renderer();
        await _mount(
          tester,
          _Service(),
          _Comments(),
          renderer,
          webLayout: true,
        );
        await _open(tester);
        await tester.drag(
          find.byKey(const ValueKey('community-comments-resize')),
          const Offset(-3000, 0),
        );
        await tester.pump();
        final panel = find.byKey(const ValueKey('inline-community-comments'));
        final model = find.byKey(const ValueKey('fake-model-host'));
        expect(tester.getSize(panel).width, greaterThanOrEqualTo(width / 2));
        expect(tester.getSize(panel).width, closeTo(width * .5, 1));
        expect(tester.getSize(model).width, greaterThanOrEqualTo(320));
        expect(
          tester.getRect(model).right,
          lessThanOrEqualTo(tester.getRect(panel).left),
        );
        expect(renderer.mounts, 1);
        expect(renderer.disposals, 0);
      },
    );
  }

  for (final webPolicy in [true, false]) {
    _detailTestWidgets(
      'viewer activity policy web=$webPolicy avoids only redundant web drag updates',
      (tester) async {
        final renderer = _Renderer();
        late StateSetter rebuild;
        var panelWidth = 200.0;
        var active = true;
        var background = Colors.black;
        var rotationSpeed = .6;
        var autoRotate = false;
        var untilTouched = false;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Scaffold(
                  body: Row(
                    children: [
                      Expanded(
                        child: ProductModelView(
                          modelUrl: _modelFile.path,
                          interactive: true,
                          active: active,
                          background: background,
                          autoRotateSpeed: rotationSpeed,
                          autoRotate: autoRotate,
                          autoRotateUntilTouched: untilTouched,
                          webActivityUpdatesForTesting: webPolicy,
                          hostBuilder: renderer.host,
                        ),
                      ),
                      GestureDetector(
                        key: const ValueKey('activity-resize'),
                        dragStartBehavior: DragStartBehavior.down,
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (details) =>
                            setState(() => panelWidth -= details.delta.dx),
                        child: const SizedBox(
                          width: 8,
                          height: double.infinity,
                        ),
                      ),
                      SizedBox(width: panelWidth),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        await _flush(tester);
        final baseline = renderer.requests.length;
        final drag = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('activity-resize'))),
        );
        for (var step = 0; step < 25; step++) {
          await drag.moveBy(const Offset(-2, 0));
          await tester.pump();
        }
        await drag.up();
        await _flush(tester);
        final updates = renderer.requests
            .skip(baseline)
            .where((r) => ['configure', 'resume', 'load'].contains(r['method']))
            .toList();
        if (webPolicy) {
          expect(
            updates,
            isEmpty,
            reason:
                'Size-only web parent updates must not reconfigure/resume/reload',
          );
        } else {
          expect(updates.where((r) => r['method'] == 'configure'), isNotEmpty);
        }
        expect(renderer.mounts, 1);
        var checkpoint = renderer.requests.length;
        rebuild(() {
          background = Colors.blue;
          rotationSpeed = 1.2;
          autoRotate = true;
          untilTouched = true;
        });
        await _flush(tester);
        final configured = renderer.requests
            .skip(checkpoint)
            .singleWhere((r) => r['method'] == 'configure');
        expect((configured['args'] as Map)['background'], 0x2196f3);
        expect((configured['args'] as Map)['autoRotate'], isTrue);
        expect((configured['args'] as Map)['autoRotateUntilTouched'], isTrue);
        expect(
          (configured['args'] as Map)['autoRotateSpeed'],
          closeTo(1.2 * 30 / 3.141592653589793, 0.0001),
        );
        checkpoint = renderer.requests.length;
        rebuild(() => active = false);
        await _flush(tester);
        expect(
          renderer.requests
              .skip(checkpoint)
              .where((r) => r['method'] == 'pause'),
          isNotEmpty,
        );
        checkpoint = renderer.requests.length;
        rebuild(() => active = true);
        await _flush(tester);
        expect(
          renderer.requests
              .skip(checkpoint)
              .where((r) => r['method'] == 'resume'),
          isNotEmpty,
        );
      },
    );
  }

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    _detailTestWidgets(
      'web inline comments at $size keep viewer mounted on close',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final renderer = _Renderer();
        await _mount(
          tester,
          _Service(),
          _Comments()..rows = [_comment('public')],
          renderer,
          webLayout: true,
        );
        await _open(tester);
        final panel = find.byKey(const ValueKey('inline-community-comments'));
        final model = find.byKey(const ValueKey('fake-model-host'));
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('内容public'), findsOneWidget);
        if (size.width >= 760) {
          expect(
            tester.getRect(panel).left,
            greaterThanOrEqualTo(tester.getRect(model).right),
          );
          expect(
            tester.getSize(panel).height,
            closeTo(tester.getSize(model).height, 1),
          );
        } else {
          expect(
            tester.getRect(panel).top,
            greaterThanOrEqualTo(tester.getRect(model).bottom),
          );
          expect(tester.getSize(panel).width, size.width);
        }
        await tester.tap(find.byTooltip('关闭评论'));
        await _flush(tester);
        expect(find.byTooltip('关闭评论'), findsNothing);
        expect(renderer.mounts, 1);
        expect(renderer.disposals, 0);
        await _open(tester);
        expect(find.text('内容public'), findsOneWidget);
        expect(renderer.mounts, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
