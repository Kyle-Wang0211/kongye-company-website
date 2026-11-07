import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/aether_cpp_card_demo.dart';
import 'package:pocketworld_flutter/ui/community/first_pair_policy.dart';
import 'package:pocketworld_flutter/ui/community/masonry_policy.dart';
import 'package:pocketworld_flutter/ui/community/work_card.dart';
import 'package:pocketworld_flutter/ui/community/community_loading.dart';
import 'package:pocketworld_flutter/ui/startup_splash_gate.dart';
import 'package:pocketworld_flutter/ui/vault_page.dart';
import 'package:pocketworld_flutter/ui/community/work_detail_page.dart';
import 'package:pocketworld_flutter/ui/design_system.dart';

class CoverService extends CommunityService {
  CoverService()
    : super(
        client: SupabaseClient(
          'https://offline.invalid',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final pending = Completer<List<FeedWork>>();
  int modelUrls = 0;
  int fetches = 0;
  @override
  Future<int?> recordView(String id) async => 0;
  @override
  String thumbnailUrlFor(String path) => 'https://offline.invalid/$path';
  @override
  String modelUrlFor(String path) {
    modelUrls++;
    return 'file:///tmp/$path';
  }

  @override
  Future<List<FeedWork>> fetchPublicFeed({
    int limit = 20,
    int offset = 0,
    FeedSort sortBy = FeedSort.recent,
    String? query,
    String? authorUserId,
    DateTime? afterPublishedAt,
    String? afterId,
  }) {
    fetches++;
    return fetches == 1 ? pending.future : Future.value([]);
  }
}

FeedWork coverWork(int n, {String? cover}) => FeedWork(
  id: 'cover-$n',
  userId: 'creator',
  title: 'Work $n',
  description: null,
  format: 'glb',
  modelStoragePath: '$n.glb',
  thumbnailStoragePath: cover,
  likesCount: 0,
  viewsCount: 0,
  publishedAt: null,
  authorDisplayName: 'Creator',
  authorAvatarUrl: null,
  likedByMe: false,
);
Widget app(Widget child) => MaterialApp(
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  home: Scaffold(body: child),
);
Future<void> cacheCover(
  WidgetTester t,
  CommunityService service,
  String path, {
  int width = 300,
  int height = 400,
}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await t.runAsync(() => picture.toImage(width, height));
  picture.dispose();
  final key = await ResizeImage(
    NetworkImage(service.thumbnailUrlFor(path)),
    width: 358,
  ).obtainKey(ImageConfiguration.empty);
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image!))),
  );
}

Future<void> frames(WidgetTester t, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    StartupSplashGate.instance.markDone();
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  test('cover proportions retain portrait and landscape source dimensions', () {
    expect(masonryCoverAspectRatio(.5), .5);
    expect(masonryCoverAspectRatio(2), 2);
  });
  testWidgets('works without a valid cover are not exposed in the community', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final service = CoverService();
    var rendererCalls = 0;
    await t.pumpWidget(
      app(
        VaultPage(
          service: service,
          viewerHostBuilderForTesting: (_, _, _, _) {
            rendererCalls++;
            return const SizedBox();
          },
        ),
      ),
    );
    service.pending.complete([coverWork(0), coverWork(1), coverWork(2)]);
    await frames(t, 24);
    expect(find.text('Work 0'), findsNothing);
    expect(find.text('Work 1'), findsNothing);
    expect(
      find.byKey(const ValueKey('work-cover-placeholder-cover-0')),
      findsNothing,
    );
    expect(service.modelUrls, 0);
    expect(rendererCalls, 0);
    expect(find.byType(Image), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('cover media has black backing while metadata remains white', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final service = CoverService();
    await cacheCover(t, service, 'poster.png');
    await t.pumpWidget(
      app(
        SizedBox(
          width: 191,
          child: WorkCard(
            work: coverWork(0, cover: 'poster.png'),
            service: service,
            onTap: () {},
          ),
        ),
      ),
    );
    await frames(t);
    final cover = find.byKey(const ValueKey('work-cover-cover-0'));
    expect(
      find.descendant(
        of: cover,
        matching: find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.black,
        ),
      ),
      findsOneWidget,
    );
    final info = find.byKey(const ValueKey('work-info-cover-0'));
    final panel = t
        .widgetList<ColoredBox>(
          find.ancestor(of: info, matching: find.byType(ColoredBox)),
        )
        .first;
    expect(panel.color, AetherColors.bgCanvas);
    expect(service.modelUrls, 0);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'pending tail cover times out locally without blocking the feed',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = CoverService();
      await cacheCover(t, service, 'poster.png');
      final pending = Completer<ImageInfo>();
      final key = await ResizeImage(
        NetworkImage(service.thumbnailUrlFor('pending.png')),
        width: 358,
      ).obtainKey(ImageConfiguration.empty);
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(pending.future),
      );
      await t.pumpWidget(app(VaultPage(service: service)));
      service.pending.complete([
        coverWork(0, cover: 'poster.png'),
        coverWork(1, cover: 'poster.png'),
        coverWork(2, cover: 'pending.png'),
      ]);
      await frames(t, 12);
      expect(find.text('Work 0'), findsOneWidget);
      expect(find.text('Work 1'), findsOneWidget);
      await t.pump(const Duration(seconds: 31));
      await frames(t, 2);
      expect(
        find.byKey(const ValueKey('work-cover-error-cover-2')),
        findsNothing,
      );
      expect(find.text('Work 2'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(service.modelUrls, 0);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'published feed media requires a cover rather than a model fallback',
    () {
      expect(hasCommunityPreviewSource(coverWork(0)), isFalse);
      expect(
        hasCommunityPreviewSource(coverWork(0, cover: 'poster.png')),
        isTrue,
      );
    },
  );
  testWidgets(
    'GLB card prepares from its cover with no model URL or renderer',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = CoverService();
      await cacheCover(t, service, 'poster.png');
      CommunityCardMetrics? metrics;
      var mounts = 0;
      await t.pumpWidget(
        app(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 190,
              child: WorkCard(
                work: coverWork(0, cover: 'poster.png'),
                service: service,
                prepareWhileHidden: true,
                onPrepared: (m) => metrics = m,
                viewerHostBuilderForTesting: (_, _, _, _) {
                  mounts++;
                  return const SizedBox.expand();
                },
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await frames(t);
      expect(service.modelUrls, 0);
      expect(mounts, 0);
      expect(find.byType(AetherCppCardDemo), findsNothing);
      expect(metrics, isNotNull);
      expect(metrics!.viewerSize.aspectRatio, closeTo(3 / 4, .001));
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'feed reveals matching image cards without GLB work on refresh or scroll',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final service = CoverService();
      await cacheCover(t, service, 'poster.png');
      var mounts = 0;
      await t.pumpWidget(
        app(
          VaultPage(
            service: service,
            viewerHostBuilderForTesting: (_, _, _, _) {
              mounts++;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      expect(find.byType(CommunityCardSkeleton), findsNWidgets(6));
      service.pending.complete(
        List.generate(20, (n) => coverWork(n, cover: 'poster.png')),
      );
      await frames(t, 28);
      expect(service.modelUrls, 0);
      expect(mounts, 0);
      expect(find.text('Work 0'), findsOneWidget);
      final a = t.getSize(find.byKey(const ValueKey('work-cover-cover-0')));
      final b = t.getSize(find.byKey(const ValueKey('work-cover-cover-1')));
      expect(a, b);
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, -900));
      await frames(t, 15);
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, 1600));
      await frames(t, 15);
      expect(service.modelUrls, 0);
      expect(mounts, 0);
      await t.tap(find.text('Work 0'));
      await frames(t, 5);
      expect(find.byType(WorkDetailPage), findsOneWidget);
      expect(service.modelUrls, greaterThan(0));
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
