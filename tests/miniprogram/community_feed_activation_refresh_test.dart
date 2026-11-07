import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/vault_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pocketworld_flutter/ui/startup_splash_gate.dart';
import 'package:pocketworld_flutter/ui/community/card_live_governor.dart';
import 'community_cover_only_test.dart' show coverWork, cacheCover, frames;

class ActivationService extends CommunityService {
  ActivationService()
    : super(
        client: SupabaseClient(
          'https://offline.invalid',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  int calls = 0;
  List<FeedWork> rows = const [];
  Completer<List<FeedWork>>? pending;

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
    calls++;
    return pending?.future ?? Future.value(rows);
  }
}

Widget app(ActivationService service, {bool visible = true}) => MaterialApp(
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  home: VaultPage(service: service, isVisible: visible),
);

void main() {
  testWidgets('activation replaces feed after publication, edit and deletion', (
    t,
  ) async {
    StartupSplashGate.instance.markDone();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(() {
      CardViewerRegistry.releaseAll('activation test');
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    final service = ActivationService();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await cacheCover(t, service, 'poster.png');
    await t.pumpWidget(app(service));
    await frames(t);
    expect(find.text('Work 0'), findsNothing);
    service.rows = [coverWork(0, cover: 'poster.png')];
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await frames(t);
    expect(find.text('Work 0'), findsOneWidget);
    service.rows = [
      FeedWork(
        id: 'cover-0',
        userId: 'creator',
        title: 'Edited work',
        description: null,
        format: 'glb',
        modelStoragePath: '0.glb',
        thumbnailStoragePath: 'poster.png',
        likesCount: 0,
        viewsCount: 0,
        publishedAt: null,
        authorDisplayName: 'Creator',
        authorAvatarUrl: null,
        likedByMe: false,
      ),
    ];
    await t.pumpWidget(app(service, visible: false));
    await t.pumpWidget(app(service));
    await frames(t);
    expect(find.text('Work 0'), findsNothing);
    expect(find.text('Edited work'), findsOneWidget);
    service.rows = const [];
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await frames(t);
    expect(find.text('Edited work'), findsNothing);
    expect(service.calls, 4);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('resume refreshes; repeated resumed callbacks are coalesced', (
    t,
  ) async {
    final service = ActivationService();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpWidget(app(service));
    await t.pump();
    expect(service.calls, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(service.calls, 2);
    await t.pumpWidget(const SizedBox());
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(service.calls, 2, reason: 'disposed feed must remove its observer');
    expect(t.takeException(), isNull);
  });

  testWidgets('hidden tab defers resume refresh until activated once', (
    t,
  ) async {
    final service = ActivationService();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpWidget(app(service, visible: false));
    await t.pump();
    expect(service.calls, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(service.calls, 1);
    await t.pumpWidget(app(service));
    await t.pump();
    expect(service.calls, 2);
    await t.pumpWidget(app(service));
    await t.pump();
    expect(
      service.calls,
      2,
      reason: 'ordinary rebuild is not a tab activation',
    );
  });

  testWidgets(
    'activation waits for initial feed instead of concurrent requests',
    (t) async {
      final service = ActivationService();
      final first = Completer<List<FeedWork>>();
      service.pending = first;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpWidget(app(service));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(service.calls, 1);
      service.pending = null;
      first.complete(const []);
      await t.pump();
      await t.pump();
      expect(service.calls, 2);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'in-flight refresh may finish after disposal without a new request',
    (t) async {
      final service = ActivationService();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpWidget(app(service));
      await t.pump();
      final refresh = Completer<List<FeedWork>>();
      service.pending = refresh;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(service.calls, 2);
      await t.pumpWidget(const SizedBox());
      refresh.complete(const []);
      await t.pump();
      expect(service.calls, 2);
      expect(t.takeException(), isNull);
    },
  );
}
