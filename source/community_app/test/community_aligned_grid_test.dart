import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/ui/community/work_card.dart';
import 'package:pocketworld_flutter/ui/community/masonry_layout.dart';
import 'package:pocketworld_flutter/ui/community/community_loading.dart';
import 'package:pocketworld_flutter/ui/vault_page.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';

class DelayedCover extends ImageProvider<DelayedCover> {
  final result = Completer<ImageInfo>();
  @override
  Future<DelayedCover> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    DelayedCover key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(result.future);
}

FeedWork work(String id, {String? thumbnail = 'cover', String? title}) =>
    FeedWork(
      id: id,
      userId: 'author-$id',
      title: title ?? 'Real title $id',
      description: 'Detail-only description',
      format: 'ply',
      modelStoragePath: 'must-not-download.ply',
      thumbnailStoragePath: thumbnail,
      likesCount: 12,
      viewsCount: 31,
      publishedAt: DateTime.utc(2026, 11, 2),
      authorDisplayName: 'Real author $id',
      authorAvatarUrl: null,
      likedByMe: false,
    );
Future<ImageInfo> pixels(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.white, BlendMode.src);
  return ImageInfo(image: await recorder.endRecording().toImage(width, height));
}

class PagedFeed extends CommunityService {
  PagedFeed()
    : super(
        client: SupabaseClient(
          'https://example.test',
          'synthetic-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
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
    final result = Completer<List<FeedWork>>();
    requests.add(result);
    return result.future;
  }
}

void main() {
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );
  testWidgets(
    'metadata renders before independent covers; mixed aspects and errors keep equal bounds',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final a = DelayedCover(), b = DelayedCover(), c = DelayedCover();
      final service = CommunityService(
        client: SupabaseClient(
          'https://example.test',
          'synthetic-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
      final works = [
        work('a'),
        work(
          'b',
          title: 'Long title that takes two lines but keeps every row aligned',
        ),
        work('c'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommunityMasonry(
              itemCount: 3,
              itemBuilder: (_, i) => WorkCard(
                work: works[i],
                service: service,
                onTap: () {},
                coverImageForTesting: [a, b, c][i],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Real title a'), findsOneWidget);
      expect(find.text('Real author a'), findsOneWidget);
      expect(find.text('Detail-only description'), findsNothing);
      final before = tester.getSize(find.byKey(const ValueKey('work-cover-a')));
      final card = tester.getSize(find.byKey(const ValueKey('work-info-a')));
      expect(before.width / before.height, closeTo(3 / 4, .001));
      expect(tester.getSize(find.byKey(const ValueKey('work-info-b'))), card);
      expect(
        tester.getSize(find.byType(WorkCard).at(0)),
        tester.getSize(find.byType(WorkCard).at(1)),
      );
      expect(
        find.byKey(const ValueKey('work-cover-loading-a')),
        findsOneWidget,
      );
      a.result.complete(await pixels(80, 20));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('work-cover-loading-a')), findsNothing);
      expect(
        find.byKey(const ValueKey('work-cover-loading-b')),
        findsOneWidget,
      );
      b.result.complete(await pixels(20, 80));
      c.result.completeError(StateError('unavailable cover'));
      await tester.pump();
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('work-cover-a'))),
        before,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('work-cover-b'))),
        before,
      );
      expect(tester.getSize(find.byKey(const ValueKey('work-info-b'))), card);
      await tester.pump();
      expect(find.byKey(const ValueKey('work-cover-error-c')), findsOneWidget);
      expect(find.text('Real title c'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('missing cover leaves usable metadata and finite placeholder', (
    tester,
  ) async {
    final service = CommunityService(
      client: SupabaseClient(
        'https://example.test',
        'synthetic-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: WorkCard(
              work: work('missing', thumbnail: null),
              service: service,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Real title missing'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('work-cover-error-missing')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'initial and paging shells resolve independently; failed page preserves cards and cursor retry',
    (tester) async {
      final feed = PagedFeed();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: VaultPage(service: feed),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<CommunityMasonry>(find.byType(CommunityMasonry))
            .itemCount,
        6,
      );
      expect(find.byType(CommunityCardSkeleton), findsWidgets);
      expect(find.byType(WorkCard), findsNothing);
      feed.requests.single.complete(
        List.generate(20, (i) => work('$i', thumbnail: null)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(CommunityCardSkeleton), findsNothing);
      expect(find.text('Real title 0'), findsOneWidget);
      expect(find.text('Real author 0'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Real title 0')).dy,
        tester.getTopLeft(find.text('Real title 1')).dy,
      );
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(feed.requests, hasLength(2));
      expect(feed.cursors.last, '19');
      expect(
        find.byKey(const ValueKey('community-page-loading-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('community-page-loading-1')),
        findsOneWidget,
      );
      feed.requests.last.completeError(StateError('temporary page failure'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CommunityCardSkeleton), findsNothing);
      expect(find.text('Real title 19'), findsOneWidget);
      expect(feed.requests, hasLength(2));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(feed.requests, hasLength(3));
      expect(feed.cursors.last, '19');
      feed.requests.last.complete([
        work('19', thumbnail: null),
        work('20', thumbnail: null),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CommunityCardSkeleton), findsNothing);
      expect(find.text('Real title 20'), findsOneWidget);
      expect(find.text('Real title 19'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'enlarged text keeps long titles and counted likes aligned without clipping',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = CommunityService(
        client: SupabaseClient(
          'https://example.test',
          'synthetic-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
      final works = [
        work(
          'large-a',
          thumbnail: null,
          title: 'A long real title that needs two lines',
        ),
        work('large-b', thumbnail: null),
      ];
      for (final scale in [2.0, 3.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: CommunityMasonry(
                  itemCount: works.length,
                  itemBuilder: (_, i) =>
                      WorkCard(work: works[i], service: service, onTap: () {}),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'No RenderFlex overflow at text scale $scale',
        );
        expect(find.text('12'), findsNWidgets(2));
        final a = find.byKey(const ValueKey('work-info-large-a'));
        final b = find.byKey(const ValueKey('work-info-large-b'));
        expect(tester.getSize(a), tester.getSize(b));
        expect(tester.getTopLeft(a).dy, tester.getTopLeft(b).dy);
        final dateBounds = tester.getRect(find.text('2026-11-02').first);
        final infoBounds = tester.getRect(a);
        expect(dateBounds.bottom, lessThanOrEqualTo(infoBounds.bottom - 5));
        expect(
          tester.getSize(find.byType(WorkCard).first),
          tester.getSize(find.byType(WorkCard).last),
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('reduced motion keeps loading surface static', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SizedBox(width: 180, height: 240, child: CommunityShimmer()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester
        .widget<DecoratedBox>(find.byType(DecoratedBox).last)
        .decoration;
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<DecoratedBox>(find.byType(DecoratedBox).last).decoration,
      before,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
