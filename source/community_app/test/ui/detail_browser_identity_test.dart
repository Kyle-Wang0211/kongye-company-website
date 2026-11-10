import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/work_detail_page.dart';
import 'package:pw_shared_viewer/pw_shared_viewer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Service extends CommunityService {
  _Service()
    : super(
        client: SupabaseClient(
          'https://example.test',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  String? userId;
  @override
  String? get currentUserId => userId;
  @override
  Future<int?> recordView(String workId) async => null;
  @override
  Future<FeedWork> fetchPublicWork(String workId) async => _work('first.glb');
  @override
  String modelUrlFor(String path) => 'https://example.test/$path';
}

FeedWork _work(String path) => FeedWork(
  id: '11111111-1111-4111-8111-111111111111',
  userId: 'author',
  title: 'Known title',
  description: 'Known description',
  format: 'glb',
  modelStoragePath: path,
  thumbnailStoragePath: null,
  likesCount: 0,
  viewsCount: 0,
  publishedAt: DateTime.utc(2026, 11, 10),
  authorDisplayName: 'Known author',
  authorAvatarUrl: null,
  likedByMe: false,
);

void main() {
  testWidgets('browser public model keeps its controller across identity changes', (
    tester,
  ) async {
    final service = _Service();
    final revision = ValueNotifier(0);
    final controllers = <SharedViewerController>{};
    var path = 'first.glb';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (_, _, _) => WorkDetailPage(
            work: _work(path),
            service: service,
            viewerHostBuilder: (_, controller, _, _) {
              controllers.add(controller);
              // Leave the model pending to verify metadata precedes readiness.
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.text('Known title'), findsOneWidget);
    expect(find.text('Known description'), findsOneWidget);
    expect(controllers.length, 1);
    final first = controllers.single;
    for (final identity in ['first-user', 'second-user', null]) {
      service.userId = identity;
      revision.value++;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(controllers, {first});
    }
    path = 'second.glb';
    revision.value++;
    await tester.pump();
    await tester.pump();
    expect(controllers.length, 2);
    await tester.pumpWidget(const SizedBox());
    revision.dispose();
  }, skip: !kIsWeb);
}
