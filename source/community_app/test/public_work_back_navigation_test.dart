@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pocketworld_flutter/community/community_service.dart';
import 'package:pocketworld_flutter/community/feed_models.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/work_detail_page.dart';

import 'community_comments_panel_test.dart' show FakeComments;

class _PublicReadService extends CommunityService {
  _PublicReadService() : super(client: Supabase.instance.client);

  @override
  Future<int?> recordView(String workId) async => 1;
}

const _work = FeedWork(
  id: 'e497c950-5c29-46f1-9c2b-18dddb5c978a',
  userId: 'creator',
  title: 'Paris',
  description: '',
  format: 'glb',
  modelStoragePath: null,
  thumbnailStoragePath: null,
  likesCount: 0,
  viewsCount: 1,
  publishedAt: null,
  authorDisplayName: 'Public creator',
  authorAvatarUrl: null,
  likedByMe: false,
);

Widget _detail({VoidCallback? onExit}) => WorkDetailPage(
  work: _work,
  service: _PublicReadService(),
  commentRepository: FakeComments(),
  onExit: onExit,
);

MaterialApp _app({
  Widget? home,
  String? initialRoute,
  Map<String, WidgetBuilder> routes = const {},
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  home: home,
  initialRoute: initialRoute,
  routes: routes,
);

Future<void> _backFromWork(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left_rounded));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      anonKey: 'anonymous-fixture',
      httpClient: MockClient((_) async => http.Response('{}', 404)),
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });

  testWidgets('direct shared work at root invokes the homepage exit', (
    tester,
  ) async {
    var exits = 0;
    await tester.pumpWidget(_app(home: _detail(onExit: () => exits++)));
    await tester.pumpAndSettle();
    await _backFromWork(tester);
    expect(exits, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'shared deep link honors its homepage exit above a Flutter root route',
    (tester) async {
      var exits = 0;
      await tester.pumpWidget(
        _app(
          initialRoute: '/shared-work',
          routes: {
            '/': (_) => const Scaffold(body: Text('Legacy Flutter feed')),
            '/shared-work': (_) => _detail(onExit: () => exits++),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Navigator.of(tester.element(find.byType(WorkDetailPage))).canPop(),
        isTrue,
      );
      await _backFromWork(tester);
      expect(exits, 1);
      expect(find.byType(WorkDetailPage), findsOneWidget);
      expect(find.text('Legacy Flutter feed'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('work opened within a public profile pops back to that profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push<void>(MaterialPageRoute<void>(builder: (_) => _detail())),
              child: const Text('Public author work'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Public author work'));
    await tester.pumpAndSettle();
    await _backFromWork(tester);
    expect(find.text('Public author work'), findsOneWidget);
    expect(find.byType(WorkDetailPage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
