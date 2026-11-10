// Loading cards paint nothing; complete cards reveal media and metadata together.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/aether_cpp_card_demo.dart';
import 'package:pocketworld_flutter/ui/community/card_live_governor.dart';
import 'package:pocketworld_flutter/ui/community/generated_account_avatar.dart';
import 'package:pocketworld_flutter/ui/community/skeleton_shimmer.dart';
import 'package:pocketworld_flutter/ui/community/work_card.dart';

class _Service extends CommunityService {
  _Service()
    : super(
        client: SupabaseClient(
          'https://offline.invalid',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  int modelUrls = 0;
  @override
  String modelUrlFor(String path) {
    modelUrls++;
    return 'https://offline.invalid/$path';
  }

  @override
  String thumbnailUrlFor(String path) => 'https://offline.invalid/$path';
  @override
  Future<bool> toggleLike({
    required String workId,
    required bool currentlyLiked,
  }) async => !currentlyLiked;
}

FeedWork _work({String? thumb, String? model, String title = 'City'}) =>
    FeedWork(
      id: 'w1',
      userId: 'u1',
      title: title,
      description: null,
      format: model == null ? 'ply' : 'glb',
      modelStoragePath: model,
      thumbnailStoragePath: thumb,
      likesCount: 3,
      viewsCount: 9,
      publishedAt: DateTime.utc(2026, 8, 21),
      authorDisplayName: 'kyle',
      authorHandle: 'kyle',
      authorAvatarUrl: null,
      likedByMe: false,
    );

Future<void> _cache(WidgetTester t, _Service service) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await t.runAsync(() => picture.toImage(300, 400));
  picture.dispose();
  final key = await ResizeImage(
    NetworkImage(service.thumbnailUrlFor('poster.png')),
    width: 358,
  ).obtainKey(ImageConfiguration.empty);
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image!))),
  );
}

Widget _app(
  _Service service,
  FeedWork work, {
  bool revealed = true,
  VoidCallback? onTap,
  ValueChanged<FeedWork>? onAuthorTap,
}) => MaterialApp(
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 190,
        child: WorkCard(
          work: work,
          service: service,
          viewerHostBuilderForTesting: (_, _, _, _) => const SizedBox.expand(),
          onTap: onTap ?? () {},
          onAuthorTap: onAuthorTap,
          revealed: revealed,
          prepareWhileHidden: !revealed,
        ),
      ),
    ),
  ),
);

bool _visible(WidgetTester t) => t
    .widget<Visibility>(
      find
          .descendant(
            of: find.byType(WorkCard),
            matching: find.byType(Visibility),
          )
          .first,
    )
    .visible;

void main() {
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );
  tearDown(() {
    CardViewerRegistry.releaseAll('two-state test cleanup');
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  Future<void> viewport(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  for (final thumb in <String?>['pending.png', null]) {
    testWidgets(
      '${thumb == null ? "missing" : "pending"} media shows only its loading shell without a work tap target',
      (t) async {
        final service = _Service();
        var taps = 0;
        await t.pumpWidget(
          _app(service, _work(thumb: thumb), onTap: () => taps++),
        );
        await t.pump();
        expect(_visible(t), isFalse);
        if (find.byType(SkeletonWorkCard).evaluate().isNotEmpty) {
          expect(find.byType(SkeletonBox), findsWidgets);
        }
        expect(find.text('City').hitTestable(), findsNothing);
        expect(
          find.byIcon(Icons.favorite_outline_rounded).hitTestable(),
          findsNothing,
        );
        await t.tapAt(t.getCenter(find.byType(WorkCard)));
        expect(
          taps,
          0,
          reason: 'a work is not exposed before its cover has decoded',
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'ready poster exposes cover title plus avatar, author and likes with working taps',
    (t) async {
      await viewport(t);
      final service = _Service();
      await _cache(t, service);
      var cardTaps = 0;
      final authorTaps = <FeedWork>[];
      await t.pumpWidget(
        _app(
          service,
          _work(thumb: 'poster.png'),
          onTap: () => cardTaps++,
          onAuthorTap: authorTaps.add,
        ),
      );
      await t.pump();
      await t.pump();
      expect(_visible(t), isTrue);
      expect(find.text('City'), findsOneWidget);
      expect(find.text('kyle', findRichText: true), findsOneWidget);
      expect(find.text('@kyle', findRichText: true), findsNothing);
      expect(find.byType(GeneratedAccountAvatar), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      final cover = t.getRect(find.byKey(const ValueKey('work-cover-w1')));
      final info = t.getRect(find.byKey(const ValueKey('work-info-w1')));
      expect(info.top, closeTo(cover.bottom, 0.001));
      await t.tap(find.byKey(const ValueKey('work-avatar-w1')));
      expect(authorTaps.single.id, 'w1');
      expect(cardTaps, 0);
      await t.tap(find.text('City'));
      expect(cardTaps, 1);
      await t.tap(find.byIcon(Icons.favorite_outline_rounded));
      await t.pump();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(cardTaps, 1, reason: 'liking must not also navigate');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'cover titles vary in height while metadata stays fixed',
    (t) async {
      await viewport(t);
      final service = _Service();
      await _cache(t, service);
      await t.pumpWidget(_app(service, _work(thumb: 'poster.png')));
      await t.pump();
      await t.pump();
      final info = find.byKey(const ValueKey('work-info-w1'));
      final oneLine = t.getSize(info).height;
      const longTitle =
          'A carefully collected corner of the city with many details';
      await t.pumpWidget(
        _app(service, _work(thumb: 'poster.png', title: longTitle)),
      );
      await t.pump();
      expect(t.getSize(info).height, oneLine);
      final titleText = t.widget<Text>(find.text(longTitle));
      expect(titleText.maxLines, 2);
      expect(titleText.overflow, TextOverflow.ellipsis);
      expect(
        find.byKey(const ValueKey('work-cover-title-w1')),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('unavailable poster does not expose the work', (t) async {
    final service = _Service();
    await t.pumpWidget(_app(service, _work(thumb: 'does-not-exist.png')));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(_visible(t), isFalse);
    expect(find.text('City').hitTestable(), findsNothing);
    expect(find.byType(SkeletonWorkCard), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'a decoded GLB cover reveals metadata without downloading or rendering the model',
    (t) async {
      await viewport(t);
      final service = _Service();
      await _cache(t, service);
      await t.pumpWidget(
        _app(service, _work(thumb: 'poster.png', model: 'model.glb')),
      );
      await t.pump();
      await t.pump();
      expect(_visible(t), isTrue);
      expect(find.text('City').hitTestable(), findsOneWidget);
      expect(find.byType(AetherCppCardDemo, skipOffstage: false), findsNothing);
      expect(CardViewerRegistry.aliveCount, 0);
      expect(service.modelUrls, 0);
      final image = t.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      expect(
        t.getRect(find.byKey(const ValueKey('work-cover-w1'))).size.aspectRatio,
        closeTo(3 / 4, 0.001),
      );
      await t.pumpWidget(const SizedBox());
    },
  );
}
