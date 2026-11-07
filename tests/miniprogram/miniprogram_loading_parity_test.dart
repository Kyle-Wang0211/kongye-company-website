import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/vault_page.dart';
import 'package:pocketworld_flutter/ui/community/work_card.dart';
import 'package:pocketworld_flutter/ui/community/community_loading.dart';
import 'package:pocketworld_flutter/ui/startup_splash_gate.dart';
import 'community_cover_only_test.dart'
    show CoverService, coverWork, cacheCover, frames;

FeedWork pageWork(int n) => FeedWork(
  id: 'cover-$n',
  userId: 'creator',
  title: 'Work $n',
  description: null,
  format: 'glb',
  modelStoragePath: '$n.glb',
  thumbnailStoragePath: 'poster.png',
  likesCount: 0,
  viewsCount: 0,
  publishedAt: DateTime.utc(2026, 11, 7),
  authorDisplayName: 'Creator',
  authorAvatarUrl: null,
  likedByMe: false,
);

class PagedService extends CoverService {
  final requests = <Completer<List<FeedWork>>>[];
  final cursors = <String?>[];
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
    cursors.add(afterId);
    final request = Completer<List<FeedWork>>();
    requests.add(request);
    return request.future;
  }
}

Widget zhApp(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  setUp(() {
    StartupSplashGate.instance.markDone();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets('first fetch shows existing six-card skeleton before metadata', (
    t,
  ) async {
    await phone(t);
    final service = CoverService();
    await t.pumpWidget(zhApp(VaultPage(service: service)));
    expect(find.byType(CommunityCardSkeleton), findsNWidgets(6));
    expect(find.byType(WorkCard), findsNothing);
    service.pending.complete([]);
    await frames(t, 2);
    expect(find.byType(CommunityCardSkeleton), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('only a skeleton appears until the cover decodes successfully', (
    t,
  ) async {
    await phone(t);
    final service = CoverService();
    final pending = Completer<ImageInfo>();
    final key = await ResizeImage(
      NetworkImage(service.thumbnailUrlFor('pending.png')),
      width: 358,
    ).obtainKey(ImageConfiguration.empty);
    PaintingBinding.instance.imageCache.putIfAbsent(
      key,
      () => OneFrameImageStreamCompleter(pending.future),
    );
    await t.pumpWidget(
      zhApp(
        SizedBox(
          width: 191,
          child: WorkCard(
            work: coverWork(2, cover: 'pending.png'),
            service: service,
            onTap: () {},
          ),
        ),
      ),
    );
    await frames(t, 2);
    expect(find.text('Work 2').hitTestable(), findsNothing);
    expect(find.byType(CommunityCardSkeleton), findsWidgets);
    pending.completeError(StateError('unavailable'));
    await frames(t, 4);
    expect(
      find.byKey(const ValueKey('work-cover-error-cover-2')),
      findsNothing,
    );
    expect(find.text('Work 2').hitTestable(), findsNothing);
    expect(service.modelUrls, 0);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('slow and failed middle cover do not hide later feed cards', (
    t,
  ) async {
    await phone(t);
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
    await t.pumpWidget(zhApp(VaultPage(service: service)));
    service.pending.complete([
      coverWork(0, cover: 'poster.png'),
      coverWork(1, cover: 'poster.png'),
      coverWork(2, cover: 'pending.png'),
      coverWork(3, cover: 'poster.png'),
    ]);
    await frames(t, 12);
    expect(find.text('Work 2').hitTestable(), findsNothing);
    expect(find.text('Work 3'), findsOneWidget);
    expect(find.byType(CommunityCardSkeleton), findsWidgets);
    pending.completeError(StateError('unavailable'));
    await frames(t, 4);
    expect(find.text('Work 2').hitTestable(), findsNothing);
    expect(find.text('Work 3'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(
      find.byKey(const ValueKey('work-cover-error-cover-2')),
      findsNothing,
    );
    expect(service.modelUrls, 0);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'offline initial request keeps shells without exposing an error action',
    (t) async {
      await phone(t);
      final service = PagedService();
      await cacheCover(t, service, 'poster.png');
      await t.pumpWidget(zhApp(VaultPage(service: service)));
      service.requests.single.completeError(StateError('offline'));
      await frames(t, 3);
      expect(find.byType(CommunityCardSkeleton), findsNWidgets(6));
      expect(find.text('Retry'), findsNothing);
      expect(find.text('重试'), findsNothing);
      final refresh = t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      service.requests.last.complete([pageWork(0), pageWork(1)]);
      await refresh;
      await frames(t, 8);
      expect(find.text('Work 0'), findsOneWidget);
      expect(find.byType(CommunityCardSkeleton), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('horizontal activity autoplay does not request another feed page', (
    t,
  ) async {
    await phone(t);
    final service = PagedService();
    await cacheCover(t, service, 'poster.png');
    final image = MemoryImage(
      Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      ),
    );
    await t.pumpWidget(
      zhApp(
        VaultPage(
          service: service,
          activities: [
            for (var i = 0; i < 3; i++)
              TopicActivity(title: 'Activity $i', image: image),
          ],
        ),
      ),
    );
    service.requests.single.complete(List.generate(20, pageWork));
    await frames(t, 12);
    await t.pump(kTopicAutoPlayInterval);
    await frames(t, 5);
    expect(service.requests, hasLength(1));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'automatic paging shows shells and retries same cursor without losing cards',
    (t) async {
      await phone(t);
      final service = PagedService();
      await cacheCover(t, service, 'poster.png');
      await t.pumpWidget(zhApp(VaultPage(service: service)));
      service.requests.single.complete(List.generate(20, pageWork));
      await frames(t, 12);
      final scroll = t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(scroll.maxScrollExtent);
      await frames(t, 3);
      expect(service.requests, hasLength(2));
      expect(
        find.byKey(const ValueKey('community-page-loading-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('community-page-loading-1')),
        findsOneWidget,
      );
      service.requests.last.completeError(StateError('temporary'));
      await frames(t, 3);
      expect(find.text('Work 19'), findsOneWidget);
      expect(find.byType(CommunityCardSkeleton), findsNothing);
      expect(find.text('重试'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      final cursor = service.cursors.last;
      expect(cursor, 'cover-19');
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, -100));
      await frames(t, 2);
      expect(service.requests, hasLength(3));
      expect(service.cursors.last, cursor);
      service.requests.last.complete([pageWork(19), pageWork(20)]);
      await frames(t, 6);
      expect(find.text('Work 20'), findsOneWidget);
      expect(find.text('Work 19'), findsOneWidget);
      expect(service.modelUrls, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
