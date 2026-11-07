import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/card_live_governor.dart';
import 'package:pocketworld_flutter/ui/community/masonry_layout.dart';
import 'package:pocketworld_flutter/ui/community/masonry_policy.dart';
import 'package:pocketworld_flutter/ui/community/work_card.dart';
import 'package:pocketworld_flutter/ui/community/generated_account_avatar.dart';
import 'package:pocketworld_flutter/ui/vault_page.dart' show TopicCard;
import 'package:pocketworld_flutter/ui/design_system.dart';

FeedWork _work(int i, {String? thumb, bool full = false}) => FeedWork(
  id: 'work-$i',
  userId: 'user-$i',
  title: i.isEven ? 'City $i' : 'A carefully collected corner of the city $i',
  description: full ? 'A longer description that occupies two lines' : null,
  format: 'ply',
  modelStoragePath: null,
  thumbnailStoragePath: thumb,
  likesCount: 3,
  viewsCount: full ? 20 : 0,
  publishedAt: DateTime.utc(2026, 10, 23),
  authorDisplayName: 'Creator $i',
  authorHandle: 'creator$i',
  authorAvatarUrl: null,
  likedByMe: false,
);

class _Service extends CommunityService {
  _Service(List<FeedWork> _)
    : super(
        client: SupabaseClient(
          'https://offline.invalid',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  @override
  String thumbnailUrlFor(String path) => 'https://offline.invalid/thumbs/$path';
}

Future<void> _cachePosters(
  WidgetTester tester,
  CommunityService service, {
  int count = 8,
}) async {
  final cacheWidth =
      (tester.view.physicalSize.width - 32 * tester.view.devicePixelRatio)
          .round()
          .clamp(64, 1024);
  for (var i = 0; i < count; i++) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await tester.runAsync(
      () => picture.toImage(300, i.isEven ? 400 : 300),
    );
    picture.dispose();
    final key = await ResizeImage(
      NetworkImage(service.thumbnailUrlFor('$i.png')),
      width: cacheWidth,
    ).obtainKey(ImageConfiguration.empty);
    PaintingBinding.instance.imageCache.putIfAbsent(
      key,
      () =>
          OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image!))),
    );
  }
}

Widget _app(Widget child, {String? fontFamily}) => MaterialApp(
  locale: const Locale('en'),
  theme: ThemeData(fontFamily: fontFamily),
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  home: Scaffold(body: child),
);
Widget _grid(
  _Service service, {
  bool thumbnails = false,
  VoidCallback? onTap,
}) => CommunityMasonry(
  header: const TopicCard(autoPlay: false),
  itemCount: 8,
  itemBuilder: (_, i) => WorkCard(
    key: ValueKey('card-$i'),
    work: _work(i, thumb: '$i.png'),
    service: service,
    rotationAllowed: false,
    onTap: onTap ?? () {},
    coverAspectRatio: thumbnails
        ? null
        : masonryCoverAspectRatio(i.isEven ? 3 / 4 : 1),
  ),
);
void main() {
  setUp(
    () => VisibilityDetectorController.instance.updateInterval = Duration.zero,
  );
  tearDown(() {
    CardViewerRegistry.releaseAll('test cleanup');
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  test(
    'source image proportions stay continuous and invalid dimensions stay null',
    () {
      expect(masonryCoverAspectRatio(0.1), 0.1);
      expect(masonryCoverAspectRatio(10), 10);
      for (final value in [3 / 4, 0.8, 0.9, 0.99, 1.0, 1.01, 1.1, 1.2, 4 / 3]) {
        expect(masonryCoverAspectRatio(value), value);
      }
      for (final value in [
        null,
        0.0,
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(masonryCoverAspectRatio(value), isNull);
      }
    },
  );
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('unobstructed covers occupy two staggered columns at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var taps = 0;
      final service = _Service([]);
      await _cachePosters(t, service);
      await t.pumpWidget(_app(_grid(service, onTap: () => taps++)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 32));
      await t.pump(const Duration(milliseconds: 32));
      var a = t.getRect(find.byKey(const ValueKey('card-0')));
      final b = t.getRect(find.byKey(const ValueKey('card-1')));
      expect(a.top, b.top);
      expect(a.width, closeTo(b.width, 0.01));
      expect(b.left - a.right, closeTo(4, 0.01));
      expect(a.left, closeTo(2, 0.01));
      expect(b.right, closeTo(width - 2, 0.01));
      // At tablet width the second row begins below the initial viewport.
      // Scroll it into the lazy grid before measuring the next left card.
      if (width == 768) {
        await t.drag(find.byType(CustomScrollView), const Offset(0, -200));
        await t.pump();
        a = t.getRect(find.byKey(const ValueKey('card-0')));
      }
      final nextInLeftColumn = [
        for (var i = 2; i < 8; i++)
          if (find.byKey(ValueKey('card-$i')).evaluate().isNotEmpty)
            t.getRect(find.byKey(ValueKey('card-$i'))),
      ].firstWhere((r) => (r.left - a.left).abs() < 0.01);
      expect(nextInLeftColumn.top - a.bottom, closeTo(6, 0.01));
      expect(a.height, isNot(b.height));
      final first = find.byKey(const ValueKey('card-0'));
      expect(
        find.descendant(of: first, matching: find.byType(LiquidGlass)),
        findsNothing,
      );
      final outerClip = t.widget<ClipRRect>(
        find.descendant(of: first, matching: find.byType(ClipRRect)).first,
      );
      expect(outerClip.borderRadius, BorderRadius.circular(4));
      final topicClip = t.widget<ClipRRect>(
        find
            .descendant(
              of: find.byType(TopicCard),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(topicClip.borderRadius, BorderRadius.circular(4));
      final topicBounds = t.getRect(find.byType(TopicCard));
      expect(topicBounds.left, closeTo(2, 0.01));
      expect(topicBounds.right, closeTo(width - 2, 0.01));
      expect(
        find.descendant(of: first, matching: find.byType(LiquidGlassLayer)),
        findsNothing,
      );
      final coverFinder = find.byKey(const ValueKey('work-cover-work-0'));
      final coverBounds = t.getRect(coverFinder);
      final infoBounds = t.getRect(
        find.byKey(const ValueKey('work-info-work-0')),
      );
      expect(coverBounds.width / coverBounds.height, closeTo(3 / 4, 0.01));
      expect(infoBounds.top, closeTo(coverBounds.bottom, 0.01));
      expect(
        find.descendant(of: coverFinder, matching: find.byType(Text)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: coverFinder,
          matching: find.byType(GeneratedAccountAvatar),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: coverFinder,
          matching: find.byIcon(Icons.favorite_outline_rounded),
        ),
        findsNothing,
      );
      final titleFinder = find.descendant(
        of: first,
        matching: find.text(_work(0).title),
      );
      final title = t.widget<Text>(titleFinder);
      expect(title.maxLines, 2);
      expect(title.style!.fontSize, 13);
      final titleBounds = t.getRect(titleFinder);
      final avatarFinder = find.descendant(
        of: first,
        matching: find.byType(GeneratedAccountAvatar),
      );
      final avatar = t.widget<GeneratedAccountAvatar>(avatarFinder);
      expect(avatar.userId, _work(0).userId);
      final avatarBounds = t.getRect(avatarFinder);
      final authorBounds = t.getRect(
        find.descendant(of: first, matching: find.text('Creator 0')),
      );
      final heartBounds = t.getRect(
        find.descendant(
          of: first,
          matching: find.byIcon(Icons.favorite_outline_rounded),
        ),
      );
      final countBounds = t.getRect(
        find.descendant(of: first, matching: find.text('3')),
      );
      expect(avatarBounds.top, greaterThanOrEqualTo(titleBounds.bottom));
      expect(
        (avatarBounds.center.dy - authorBounds.center.dy).abs(),
        lessThan(1),
      );
      expect(
        (heartBounds.center.dy - countBounds.center.dy).abs(),
        lessThan(1),
      );
      expect(authorBounds.left, greaterThan(avatarBounds.right));
      expect(countBounds.left, greaterThan(heartBounds.right));

      await t.tapAt(a.topCenter + const Offset(0, 20));
      await t.pump();
      expect(taps, 1);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('one-line titles use less metadata height than two-line titles', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final service = _Service([]);
    await _cachePosters(t, service);
    await t.pumpWidget(_app(_grid(service)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 32));
    await t.pump(const Duration(milliseconds: 32));
    final short = find.byKey(const ValueKey('card-0'));
    final long = find.byKey(const ValueKey('card-1'));
    final shortTitle = t.getRect(
      find.descendant(of: short, matching: find.text(_work(0).title)),
    );
    final longTitle = t.getRect(
      find.descendant(of: long, matching: find.text(_work(1).title)),
    );
    final shortInfo = t.getRect(find.byKey(const ValueKey('work-info-work-0')));
    final longInfo = t.getRect(find.byKey(const ValueKey('work-info-work-1')));
    expect(longTitle.height, closeTo(shortTitle.height * 2, 0.1));
    expect(
      longInfo.height - shortInfo.height,
      closeTo(longTitle.height - shortTitle.height, 0.1),
    );
    expect(find.text('Creator 0'), findsOneWidget);
    expect(find.text('@creator0'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('large text grows metadata below unchanged narrow covers', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final service = _Service([]);
    await _cachePosters(t, service, count: 4);
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: CommunityMasonry(
            itemCount: 4,
            itemBuilder: (context, i) => WorkCard(
              key: ValueKey('large-$i'),
              work: FeedWork(
                id: 'full-$i',
                userId: 'u',
                title: 'A long title',
                description: 'Long description covering two lines',
                format: 'ply',
                modelStoragePath: null,
                thumbnailStoragePath: '$i.png',
                likesCount: 3,
                viewsCount: 20,
                publishedAt: null,
                authorDisplayName: 'Creator',
                authorAvatarUrl: null,
                likedByMe: false,
              ),
              service: service,
              onTap: () {},
              rotationAllowed: false,
              coverAspectRatio: masonryCoverAspectRatio(i.isEven ? 3 / 4 : 1),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 32));
    await t.pump(const Duration(milliseconds: 32));
    for (var i = 0; i < 4; i++) {
      final card = find.byKey(ValueKey('large-$i'));
      final bounds = t.getRect(card);
      final cover = t.getRect(find.byKey(ValueKey('work-cover-full-$i')));
      final info = t.getRect(find.byKey(ValueKey('work-info-full-$i')));
      expect(info.top, closeTo(cover.bottom, 0.01));
      expect(info.bottom, closeTo(bounds.bottom, 0.01));
      expect(cover.width / cover.height, closeTo(i.isEven ? 3 / 4 : 1, 0.01));
      expect(
        find.descendant(of: card, matching: find.byType(LiquidGlass)),
        findsNothing,
      );
      expect(find.text('Long description covering two lines'), findsNothing);
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.remove_red_eye_outlined),
        ),
        findsNothing,
      );
    }
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'reveal keeps card geometry and author taps stay below the cover',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var revealed = false;
      var authorTaps = 0;
      var detailTaps = 0;
      late StateSetter update;
      final service = _Service([]);
      await _cachePosters(t, service, count: 2);
      await t.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return CommunityMasonry(
                itemCount: 1,
                itemBuilder: (_, i) => WorkCard(
                  key: const ValueKey('reveal-card'),
                  work: _work(1, thumb: '1.png'),
                  service: service,
                  revealed: revealed,
                  rotationAllowed: false,
                  onAuthorTap: (_) => authorTaps++,
                  onTap: () => detailTaps++,
                  coverAspectRatio: masonryCoverAspectRatio(1),
                ),
              );
            },
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 32));
      await t.pump(const Duration(milliseconds: 32));
      final card = find.byKey(const ValueKey('reveal-card'));
      final cover = find.byKey(const ValueKey('work-cover-work-1'));
      final info = find.byKey(const ValueKey('work-info-work-1'));
      final beforeCard = t.getRect(card);
      final beforeCover = t.getRect(cover);
      final beforeInfo = t.getRect(info);
      expect(
        t
            .widget<Visibility>(
              find
                  .descendant(of: card, matching: find.byType(Visibility))
                  .first,
            )
            .visible,
        isFalse,
      );
      update(() => revealed = true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      expect(t.getRect(card), beforeCard);
      expect(t.getRect(cover), beforeCover);
      expect(t.getRect(info), beforeInfo);
      expect(beforeInfo.top, beforeCover.bottom);
      expect(
        t
            .widget<Visibility>(
              find
                  .descendant(of: card, matching: find.byType(Visibility))
                  .first,
            )
            .visible,
        isTrue,
      );
      await t.tap(find.byKey(const ValueKey('work-avatar-work-1')));
      await t.pump();
      expect(authorTaps, 1);
      expect(detailTaps, 0);
      await t.tap(find.text('Creator 1'));
      await t.pump();
      expect(authorTaps, 2);
      expect(detailTaps, 0);
      await t.tapAt(beforeCover.center);
      await t.pump();
      expect(detailTaps, 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('390px actual Flutter preview with synthetic offline covers', (
    t,
  ) async {
    final path = Platform.environment['PW_MASONRY_PREVIEW_PATH']!;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final service = _Service(
      List.generate(8, (i) => _work(i, thumb: '$i.png')),
    );
    // Populate Flutter's image cache with deterministic in-memory thumbnails.
    // The screenshot still paints the actual Image.network and WorkCard tree.
    for (var i = 0; i < 8; i++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(
        i.isEven ? const Color(0xffe8e0d5) : const Color(0xffdce6e3),
        BlendMode.src,
      );
      canvas.drawOval(
        const Rect.fromLTWH(40, 270, 220, 40),
        Paint()..color = const Color(0x22000000),
      );
      canvas.drawPath(
        Path()
          ..moveTo(70, 140)
          ..lineTo(160, 95)
          ..lineTo(245, 140)
          ..lineTo(245, 252)
          ..lineTo(160, 296)
          ..lineTo(70, 252)
          ..close(),
        Paint()
          ..color = i.isEven
              ? const Color(0xff95806b)
              : const Color(0xff64827a),
      );
      canvas.drawPath(
        Path()
          ..moveTo(70, 140)
          ..lineTo(160, 185)
          ..lineTo(160, 296)
          ..lineTo(70, 252)
          ..close(),
        Paint()..color = const Color(0x33000000),
      );
      canvas.drawPath(
        Path()
          ..moveTo(70, 140)
          ..lineTo(160, 95)
          ..lineTo(245, 140)
          ..lineTo(160, 185)
          ..close(),
        Paint()..color = const Color(0x30ffffff),
      );
      final picture = recorder.endRecording();
      final image = await t.runAsync(
        () => picture.toImage(300, i.isEven ? 380 : 300),
      );
      picture.dispose();
      final key = await ResizeImage(
        NetworkImage(service.thumbnailUrlFor('$i.png')),
        width: 358,
      ).obtainKey(ImageConfiguration.empty);
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: image!)),
        ),
      );
    }
    const fontPath = '/System/Library/Fonts/Supplemental/Arial.ttf';
    if (File(fontPath).existsSync()) {
      await t.runAsync(() async {
        final loader = FontLoader('PreviewSans')
          ..addFont(
            Future.value(
              ByteData.sublistView(await File(fontPath).readAsBytes()),
            ),
          );
        await loader.load();
      });
    }
    await t.runAsync(() async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    const boundaryKey = ValueKey('masonry-preview');
    await t.pumpWidget(
      _app(
        RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(
            color: AetherColors.bg,
            child: _grid(service, thumbnails: true),
          ),
        ),
        fontFamily: 'PreviewSans',
      ),
    );
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(TopicCard), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(path).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }, skip: Platform.environment['PW_MASONRY_PREVIEW_PATH'] == null);
}
