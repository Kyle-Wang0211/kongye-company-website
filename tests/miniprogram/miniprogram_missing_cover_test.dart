import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pocketworld_flutter/ui/vault_page.dart';
import 'package:pocketworld_flutter/ui/startup_splash_gate.dart';
import 'community_cover_only_test.dart'
    show CoverService, coverWork, cacheCover, frames, app;

void main() {
  testWidgets('missing cover after the first pair cannot hide later works', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    StartupSplashGate.instance.markDone();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final service = CoverService();
    await cacheCover(t, service, 'poster.png', width: 300, height: 180);
    await t.pumpWidget(app(VaultPage(service: service)));
    service.pending.complete([
      coverWork(0, cover: 'poster.png'),
      coverWork(1, cover: 'poster.png'),
      coverWork(2),
      coverWork(3, cover: 'poster.png'),
      coverWork(4, cover: 'poster.png'),
    ]);
    await frames(t, 36);
    expect(find.text('Work 3'), findsOneWidget);
    expect(service.modelUrls, 0);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}
