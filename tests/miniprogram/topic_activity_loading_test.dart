import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pocketworld_flutter/ui/community/community_loading.dart';
import 'package:pocketworld_flutter/ui/community/masonry_layout.dart';
import 'package:pocketworld_flutter/ui/startup_splash_gate.dart';

import 'community_cover_only_test.dart' show CoverService, app;
import 'package:pocketworld_flutter/ui/community/skeleton_shimmer.dart';
import 'package:pocketworld_flutter/ui/vault_page.dart';

// A real image stream with a manually delivered decoded frame. No HTTP, assets,
// timers or image-codec races participate in these loading-state assertions.
class _ControlledImage extends ImageProvider<_ControlledImage> {
  final _ControlledCompleter frames = _ControlledCompleter();

  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _ControlledImage key,
    ImageDecoderCallback decode,
  ) => frames;
}

class _ControlledCompleter extends ImageStreamCompleter {
  void decode(ui.Image image) => setImage(ImageInfo(image: image.clone()));
}

void main() {
  late ui.Image decoded;
  setUp(() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    decoded = picture.toImageSync(16, 9);
    picture.dispose();
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    decoded.dispose();
  });

  Future<void> show(
    WidgetTester tester,
    List<_ControlledImage> images, {
    bool reducedMotion = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 361,
                child: TopicCard(
                  activities: [
                    for (var i = 0; i < images.length; i++)
                      TopicActivity(title: 'Activity $i', image: images[i]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder getSkeleton() => find.byType(SkeletonBox);

  Color skeletonColor(WidgetTester tester) {
    final painted = find.descendant(
      of: getSkeleton(),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
    );
    return (tester.widget<Container>(painted.first).decoration!
            as BoxDecoration)
        .color!;
  }

  testWidgets('pending artwork reuses full 16:9 gray pulse until first frame', (
    tester,
  ) async {
    final image = _ControlledImage();
    await show(tester, [image]);
    expect(getSkeleton(), findsOneWidget);
    final frame = tester.getRect(find.byType(TopicCard));
    expect(frame.size, const Size(361, 203.0625));
    expect(tester.getRect(getSkeleton()), frame);
    expect(skeletonColor(tester), kSkeletonBase);
    await tester.pump(kSkeletonPulsePeriod ~/ 2);
    final midway = skeletonColor(tester);
    expect(midway, isNot(kSkeletonBase));
    expect(midway, isNot(kSkeletonHighlight));
    await tester.pump(kSkeletonPulsePeriod ~/ 2);
    expect(skeletonColor(tester), kSkeletonHighlight);

    image.frames.decode(decoded);
    await tester.pump();
    expect(getSkeleton(), findsNothing);
    expect(tester.getRect(find.byType(TopicCard)), frame);
    final artwork = tester.widget<Image>(find.byType(Image));
    expect(artwork.fit, BoxFit.fitWidth);
    expect(artwork.alignment, Alignment.topCenter);
    expect(tester.getSize(find.byType(Image)), frame.size);
  });

  testWidgets('a replacement image waits for its own decoded frame', (
    tester,
  ) async {
    final original = _ControlledImage()..frames.decode(decoded);
    await show(tester, [original]);
    expect(getSkeleton(), findsNothing);
    final replacement = _ControlledImage();
    await show(tester, [replacement]);
    expect(getSkeleton(), findsOneWidget);
    replacement.frames.decode(decoded);
    await tester.pump();
    expect(getSkeleton(), findsNothing);
  });

  testWidgets('another activity independently shows loading on page change', (
    tester,
  ) async {
    final first = _ControlledImage()..frames.decode(decoded);
    final second = _ControlledImage();
    await show(tester, [first, second]);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    // Advance ballistic paging in bounded frames; pulse animations deliberately
    // prevent pumpAndSettle while the image remains pending.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(getSkeleton(), findsOneWidget);
    expect(
      tester.getRect(getSkeleton()),
      tester.getRect(find.byType(TopicCard)),
    );
    second.frames.decode(decoded);
    await tester.pump();
    expect(getSkeleton(), findsNothing);
  });

  testWidgets(
    'pending feed retains the activity frame above six work skeletons',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      StartupSplashGate.instance.markDone();
      final service = CoverService();
      await tester.pumpWidget(
        app(
          VaultPage(
            service: service,
            activities: [
              TopicActivity(
                title: 'Pending activity',
                image: _ControlledImage(),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(service.fetches, 1);
      final masonry = tester.widget<CommunityMasonry>(
        find.byType(CommunityMasonry),
      );
      expect(masonry.itemCount, 6);
      for (var i = 0; i < masonry.itemCount; i++) {
        expect(
          masonry.itemBuilder(tester.element(find.byType(CommunityMasonry)), i),
          isA<CommunityCardSkeleton>(),
        );
      }
      final activityFrame = find.byWidgetPredicate(
        (widget) =>
            widget is AspectRatio && widget.aspectRatio == kTopicActivityAspect,
      );
      expect(activityFrame, findsOneWidget);
      expect(tester.getSize(activityFrame), const Size(389, 218.8125));
      expect(
        find.descendant(of: activityFrame, matching: getSkeleton()),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cached synchronous first frame never leaves a placeholder', (
    tester,
  ) async {
    final image = _ControlledImage()..frames.decode(decoded);
    await show(tester, [image]);
    expect(getSkeleton(), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await tester.pump(kSkeletonPulsePeriod);
    expect(getSkeleton(), findsNothing);
  });

  testWidgets('reduced motion keeps the same pending skeleton static gray', (
    tester,
  ) async {
    await show(tester, [_ControlledImage()], reducedMotion: true);
    expect(getSkeleton(), findsOneWidget);
    expect(tester.widget<SkeletonBox>(getSkeleton()).animate, isFalse);
    expect(skeletonColor(tester), kSkeletonBase);
    await tester.pump(kSkeletonPulsePeriod);
    expect(skeletonColor(tester), kSkeletonBase);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
