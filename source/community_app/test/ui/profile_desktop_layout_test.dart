import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/community/social_profile_models.dart';
import 'package:pocketworld_flutter/community/social_profile_repository.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/user_profile_page.dart';

class _Profiles implements SocialProfileRepository {
  _Profiles({this.viewer = 'owner'});
  String? viewer;
  @override
  String? get currentUserId => viewer;
  @override
  Future<SocialProfile> fetchProfile(String id) async => SocialProfile(
    id: id,
    displayName: '示例昵称',
    handle: 'example',
    avatarUrl: null,
    bio: '作品与生活',
    lastRegion: null,
    followersCount: 17,
    followingCount: 9,
    publicWorksCount: 0,
    isFollowing: false,
    isBlockedByViewer: false,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> show(
    WidgetTester tester,
    double width, {
    String? viewer = 'owner',
    VoidCallback? edit,
    VoidCallback? favorites,
    VoidCallback? settings,
    VoidCallback? likes,
    VoidCallback? history,
    Future<int> Function(String)? receivedLikesLoader,
    Map<String, WidgetBuilder> libraryTabs = const {},
    double textScale = 1,
    Key? pageKey,
    _Profiles? repository,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: UserProfilePage(
          key: pageKey,
          userId: 'owner',
          repository: repository ?? _Profiles(viewer: viewer),
          worksLoader: (_) async => [],
          onEditNickname: edit,
          onOpenFavorites: favorites,
          onOpenLikes: likes,
          onOpenHistory: history,
          receivedLikesLoader: receivedLikesLoader,
          libraryTabs: libraryTabs,
          accountActions: settings == null ? const {} : {'账号与隐私': settings},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('desktop pencil and horizontal actions invoke supplied routes', (
    tester,
  ) async {
    var edits = 0;
    var favorites = 0;
    var settings = 0;
    await show(
      tester,
      1100,
      edit: () => edits++,
      favorites: () => favorites++,
      settings: () => settings++,
    );
    expect(
      find.byKey(const ValueKey('profile-desktop-content')),
      findsOneWidget,
    );
    expect(find.text('示例昵称'), findsOneWidget);
    expect(find.text('暂无公开作品'), findsOneWidget);
    expect(find.text('账号与隐私'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('profile-edit-nickname')));
    await tester.tap(find.byKey(const ValueKey('profile-favorites-button')));
    expect(edits, 1);
    expect(favorites, 1);
    await tester.tap(find.byKey(const ValueKey('profile-account-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账号与隐私'));
    await tester.pumpAndSettle();
    expect(settings, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('visitor has no owner editing or account actions', (
    tester,
  ) async {
    await show(
      tester,
      1100,
      viewer: 'visitor',
      edit: () {},
      favorites: () {},
      settings: () {},
    );
    expect(find.byKey(const ValueKey('profile-edit-nickname')), findsNothing);
    expect(find.byKey(const ValueKey('profile-account-menu')), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-favorites-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('profile-follow-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow viewport preserves profile and nickname editing', (
    tester,
  ) async {
    var edits = 0;
    await show(tester, 320, edit: () => edits++);
    expect(find.byKey(const ValueKey('profile-desktop-content')), findsNothing);
    expect(find.text('示例昵称'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-edit-nickname')));
    expect(edits, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'received likes uses authoritative loader and routes are functional',
    (tester) async {
      var likes = 0;
      var history = 0;
      await show(
        tester,
        1100,
        likes: () => likes++,
        history: () => history++,
        receivedLikesLoader: (id) async {
          expect(id, 'owner');
          return 123;
        },
      );
      expect(find.text('获赞  123'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-likes-button')));
      await tester.tap(find.byKey(const ValueKey('profile-history-button')));
      expect(likes, 1);
      expect(history, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed received-likes load is unknown and does not hide profile',
    (tester) async {
      await show(
        tester,
        1100,
        receivedLikesLoader: (_) async => throw StateError('fixture failure'),
      );
      expect(find.text('获赞  —'), findsOneWidget);
      expect(find.text('示例昵称'), findsOneWidget);
      expect(find.text('获赞  0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'visitor does not load private received-likes or expose owner tabs',
    (tester) async {
      var reads = 0;
      await show(
        tester,
        1100,
        viewer: 'visitor',
        likes: () {},
        history: () {},
        receivedLikesLoader: (_) async {
          reads++;
          return 123;
        },
      );
      expect(reads, 0);
      expect(find.text('获赞  123'), findsNothing);
      expect(find.byKey(const ValueKey('profile-likes-button')), findsNothing);
      expect(
        find.byKey(const ValueKey('profile-history-button')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'inline library switches preserve header and works tab returns to grid',
    (tester) async {
      var fallback = 0;
      await show(
        tester,
        1100,
        favorites: () => fallback++,
        libraryTabs: {
          'favorites': (_) =>
              Scaffold(body: ListView(children: const [Text('收藏示例')])),
          'likes': (_) => const Center(child: Text('喜欢示例')),
          'history': (_) => const Center(child: Text('历史示例')),
        },
      );
      await tester.tap(find.byKey(const ValueKey('profile-favorites-button')));
      await tester.pumpAndSettle();
      expect(fallback, 0);
      expect(find.text('收藏示例'), findsOneWidget);
      expect(find.text('示例昵称'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-works-tab')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-likes-button')));
      await tester.pumpAndSettle();
      expect(find.text('喜欢示例'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-history-button')));
      await tester.pumpAndSettle();
      expect(find.text('历史示例'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-works-tab')));
      await tester.pumpAndSettle();
      expect(find.text('暂无公开作品'), findsOneWidget);
      expect(find.text('历史示例'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'narrow enlarged text uses tabs and account menu without overflow',
    (tester) async {
      await show(
        tester,
        390,
        textScale: 1.3,
        edit: () {},
        settings: () {},
        libraryTabs: {
          'likes': (_) => const Center(child: Text('喜欢示例')),
          'favorites': (_) => const Center(child: Text('收藏示例')),
          'history': (_) => const Center(child: Text('历史示例')),
        },
      );
      expect(
        find.byKey(const ValueKey('profile-compact-content')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('profile-account-menu')),
        findsOneWidget,
      );
      expect(find.text('账号与隐私'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('profile-likes-button')));
      await tester.pumpAndSettle();
      expect(find.text('喜欢示例'), findsOneWidget);
      expect(find.text('示例昵称'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('private slots are not constructed for visitors', (tester) async {
    var builds = 0;
    await show(
      tester,
      1100,
      viewer: 'visitor',
      libraryTabs: {
        'favorites': (_) {
          builds++;
          return const Text('私密内容');
        },
      },
    );
    expect(builds, 0);
    expect(
      find.byKey(const ValueKey('profile-favorites-button')),
      findsNothing,
    );
    expect(find.text('私密内容'), findsNothing);
  });
  testWidgets('removing selected slot resets to works', (tester) async {
    const pageKey = ValueKey('same-page');
    await show(
      tester,
      1100,
      pageKey: pageKey,
      libraryTabs: {'likes': (_) => const Center(child: Text('喜欢示例'))},
    );
    await tester.tap(find.byKey(const ValueKey('profile-likes-button')));
    await tester.pumpAndSettle();
    expect(find.text('喜欢示例'), findsOneWidget);
    await show(tester, 1100, pageKey: pageKey);
    expect(find.text('喜欢示例'), findsNothing);
    expect(find.text('暂无公开作品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'losing ownership removes mounted private content and resets selected tab',
    (tester) async {
      final repository = _Profiles();
      const pageKey = ValueKey('same-owner-page');
      final slots = <String, WidgetBuilder>{'likes': (_) => const Text('私密内容')};
      await show(
        tester,
        1100,
        pageKey: pageKey,
        repository: repository,
        libraryTabs: slots,
      );
      await tester.tap(find.byKey(const ValueKey('profile-likes-button')));
      await tester.pumpAndSettle();
      expect(find.text('私密内容'), findsOneWidget);
      repository.viewer = 'visitor';
      await show(
        tester,
        1100,
        pageKey: pageKey,
        repository: repository,
        libraryTabs: slots,
      );
      expect(find.text('私密内容'), findsNothing);
      expect(find.byKey(const ValueKey('profile-likes-button')), findsNothing);
      repository.viewer = 'owner';
      await show(
        tester,
        1100,
        pageKey: pageKey,
        repository: repository,
        libraryTabs: slots,
      );
      expect(find.text('私密内容'), findsNothing);
      expect(find.text('暂无公开作品'), findsOneWidget);
    },
  );
}
