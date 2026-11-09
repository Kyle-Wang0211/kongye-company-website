import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/skeleton_shimmer.dart';
import 'package:pocketworld_flutter/ui/community/public_work_opening.dart';
import 'package:pocketworld_flutter/ui/community/work_detail_page.dart';
import 'package:pocketworld_flutter/ui/shared/community_viewer_session.dart';
import 'package:pocketworld_flutter/ui/shared/product_model_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Hold the response before headers/chunks, when ImageLoadingBuilder receives
// null progress despite there being no decoded image frame yet.
class _PendingImageClient implements HttpClient {
  bool requested = false;
  final pendingRequest = Completer<HttpClientRequest>();
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requested = true;
    return pendingRequest.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoRetention extends CommunityViewerSessions {
  @override
  Future<CommunityViewerLease?> acquire(String identity) async => null;
}

class _Service extends CommunityService {
  _Service()
    : super(
        client: SupabaseClient(
          'https://example.test',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  int models = 0;
  @override
  Future<int?> recordView(String workId) async => null;
  @override
  String modelUrlFor(String path) {
    models++;
    return 'https://example.test/$path';
  }
}

FeedWork _work(
  String format, {
  String author = 'Known author',
  String? thumbnail,
}) => FeedWork(
  id: 'shell-$format',
  userId: 'author',
  title: 'Known title',
  description: 'Known description',
  format: format,
  modelStoragePath: 'model.$format',
  thumbnailStoragePath: thumbnail,
  likesCount: 12,
  viewsCount: 34,
  publishedAt: null,
  authorDisplayName: author,
  authorAvatarUrl: null,
  likedByMe: false,
);
Widget _app(Widget page) => MaterialApp(
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  home: page,
);
void main() {
  testWidgets(
    'pending cover before first chunk keeps full main-area skeleton',
    (tester) async {
      final client = _PendingImageClient();
      final previous = debugNetworkImageHttpClientProvider;
      debugNetworkImageHttpClientProvider = () => client;
      try {
        await tester.pumpWidget(
          _app(
            PublicWorkOpening(
              work: _work('glb', thumbnail: 'owner/pending-cover.png'),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(client.requested, isTrue);
        expect(client.pendingRequest.isCompleted, isFalse);
        expect(find.text('Known author'), findsOneWidget);
        expect(find.text('0%'), findsNothing);
        expect(find.byType(SkeletonBox), findsOneWidget);
        final size = tester.getSize(find.byType(SkeletonBox));
        expect(size.width, greaterThan(500));
        expect(size.height, greaterThan(300));
        expect(find.byType(RawImage), findsNothing);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugNetworkImageHttpClientProvider = previous;
        PaintingBinding.instance.imageCache.clear();
      }
    },
  );
  testWidgets(
    'unknown metadata has complete shimmering shell and indeterminate loader',
    (tester) async {
      await tester.pumpWidget(_app(PublicWorkOpening()));
      for (final field in [
        'title',
        'author',
        'description',
        'views',
        'likes',
      ]) {
        expect(find.byKey(ValueKey('work-opening-$field')), findsOneWidget);
      }
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(find.byType(SkeletonBox), findsNWidgets(6));
      expect(find.text('0%'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('handoff shows known fields while only unknown author shimmers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(PublicWorkOpening(work: _work('glb', author: ''))),
    );
    for (final value in ['Known title', 'Known description', '12', '34']) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.byType(SkeletonBox), findsNWidgets(2));
    expect(find.byKey(const ValueKey('work-opening-author')), findsOneWidget);
    await tester.pumpWidget(_app(PublicWorkOpening(work: _work('glb'))));
    expect(find.text('Known author'), findsOneWidget);
    expect(find.byType(SkeletonBox), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final format in ['glb', 'ply']) {
    testWidgets('$format metadata paints while model starts immediately', (
      tester,
    ) async {
      final service = _Service();
      final sessions = _NoRetention();

      await tester.pumpWidget(
        _app(
          WorkDetailPage(
            work: _work(format),
            service: service,
            communitySessions: sessions,
            viewerHostBuilder: (_, _, _, _) => const SizedBox.expand(),
          ),
        ),
      );
      for (final value in [
        'Known title',
        'Known description',
        'Known author',
        '12',
        '34',
      ]) {
        expect(find.text(value), findsOneWidget);
        expect(tester.renderObject(find.text(value)).debugNeedsPaint, isFalse);
      }
      // URL dispatch has already happened on the first frame; metadata never
      // serializes the model path behind another post-frame event.
      expect(service.models, greaterThan(0));
      expect(find.byType(ProductModelView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await sessions.dispose();
    });
  }
}
