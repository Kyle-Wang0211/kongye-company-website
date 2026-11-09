import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/community/community_navigation_frame.dart';

class _DraftPage extends StatefulWidget {
  const _DraftPage({super.key, required this.label});
  final String label;
  @override
  State<_DraftPage> createState() => _DraftPageState();
}

class _DraftPageState extends State<_DraftPage> {
  final text = TextEditingController(text: 'retained draft');
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text(widget.label),
        Text(
          CommunityNavigationScope.maybeOf(context) == null
              ? 'missing scope'
              : 'scope bound',
        ),
        TextField(key: ValueKey('draft-${widget.label}'), controller: text),
      ],
    ),
  );
}

Widget _app({
  required GlobalKey<NavigatorState> navigator,
  required CommunitySidebarRouteObserver observer,
  required CommunityNavigationController controller,
  required ValueNotifier<bool> visible,
  GlobalKey<_DraftPageState>? homeKey,
  String? initialRoute,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  navigatorKey: navigator,
  navigatorObservers: [observer],
  initialRoute: initialRoute,
  builder: (context, child) => AnimatedBuilder(
    animation: Listenable.merge([observer, visible]),
    builder: (context, _) => CommunityNavigationFrame(
      controller: controller,
      visible: visible.value,
      selectedDestination: communitySidebarDestination(
        Uri.parse('https://example.invalid/community/?profile=owner'),
        observer.currentRoute,
        ownerId: 'owner',
      ),
      onHome: () {},
      onFollowing: () {},
      onMyProfile: () {
        if (communityOwnProfileIsTop(
          Uri.parse('https://example.invalid/community/?profile=owner'),
          observer.currentRouteObject?.settings,
          'owner',
        )) {
          return;
        }
        navigator.currentState!.pushNamed('/profile');
      },
      onMessages: () {
        if (communityInboxIsTop(observer.currentRouteObject?.settings)) return;
        navigator.currentState!.pushNamed('/messages');
      },
      onSettings: () {},
      child: child!,
    ),
  ),
  home: _DraftPage(key: homeKey, label: 'Profile page'),
  onGenerateRoute: (settings) => MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => _DraftPage(label: settings.name!),
  ),
);

void main() {
  testWidgets(
    'Navigator routes retain one identical sidebar and shared scope',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      final observer = CommunitySidebarRouteObserver();
      final controller = CommunityNavigationController();
      final visible = ValueNotifier(true);
      final home = GlobalKey<_DraftPageState>();
      await tester.pumpWidget(
        _app(
          navigator: navigator,
          observer: observer,
          controller: controller,
          visible: visible,
          homeKey: home,
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byKey(const Key('profile-community-sidebar'));
      final original = tester.element(sidebar);
      final homeState = home.currentState!;
      await tester.enterText(
        find.byKey(const ValueKey('draft-Profile page')),
        'keep this input',
      );
      for (final route in [
        '/messages',
        '/profile-edit',
        '/privacy',
        '/favorites',
      ]) {
        navigator.currentState!.pushNamed(route);
        await tester.pumpAndSettle();
        expect(find.text(route), findsOneWidget);
        expect(find.text('scope bound'), findsOneWidget);
        expect(sidebar, findsOneWidget);
        expect(tester.element(sidebar), same(original));
        expect(tester.getSize(sidebar).width, 204);
        expect(observer.currentRoute, route);
        final selected = route == '/messages' ? 'Messages' : 'Me';
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == selected &&
                w.properties.selected == true,
          ),
          findsOneWidget,
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(home.currentState, same(homeState));
        expect(home.currentState!.text.text, 'keep this input');
        expect(tester.element(sidebar), same(original));
      }
      // Exercise actual anonymous conversation pushes beneath the named inbox.
      navigator.currentState!.pushNamed('/messages');
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const _DraftPage(label: 'Conversation'),
        ),
      );
      await tester.pumpAndSettle();
      expect(observer.currentRoute, '/messages');
      expect(find.text('Conversation'), findsOneWidget);
      expect(tester.element(sidebar), same(original));
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('/messages'), findsOneWidget);
      expect(observer.currentRoute, '/messages');
      await tester.pumpWidget(const SizedBox());
      observer.dispose();
      visible.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'direct messages route has frame on first mount and back retains it',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final observer = CommunitySidebarRouteObserver();
      final controller = CommunityNavigationController();
      final visible = ValueNotifier(true);
      await tester.pumpWidget(
        _app(
          navigator: navigator,
          observer: observer,
          controller: controller,
          visible: visible,
          initialRoute: '/messages',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('/messages'), findsOneWidget);
      expect(
        find.byKey(const Key('profile-community-sidebar')),
        findsOneWidget,
      );
      expect(observer.currentRoute, '/messages');
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Profile page'), findsOneWidget);
      expect(
        find.byKey(const Key('profile-community-sidebar')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      observer.dispose();
      visible.dispose();
    },
  );

  testWidgets('hidden and visible frame keep Navigator and draft state alive', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final observer = CommunitySidebarRouteObserver();
    final controller = CommunityNavigationController();
    final visible = ValueNotifier(false);
    final home = GlobalKey<_DraftPageState>();
    await tester.pumpWidget(
      _app(
        navigator: navigator,
        observer: observer,
        controller: controller,
        visible: visible,
        homeKey: home,
      ),
    );
    await tester.pumpAndSettle();
    final originalNavigator = navigator.currentState;
    final originalHome = home.currentState;
    expect(find.byKey(const Key('profile-community-sidebar')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('draft-Profile page')),
      'retained while frame toggles',
    );
    for (final value in [true, false, true]) {
      visible.value = value;
      await tester.pumpAndSettle();
      expect(navigator.currentState, same(originalNavigator));
      expect(home.currentState, same(originalHome));
      expect(home.currentState!.text.text, 'retained while frame toggles');
      expect(
        find.byKey(const Key('profile-community-sidebar')),
        value ? findsOneWidget : findsNothing,
      );
    }
    await tester.pumpWidget(const SizedBox());
    observer.dispose();
    visible.dispose();
  });

  testWidgets(
    'sidebar returns from inherited destinations to inbox and own profile',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      final observer = CommunitySidebarRouteObserver();
      final visible = ValueNotifier(true);
      await tester.pumpWidget(
        _app(
          navigator: navigator,
          observer: observer,
          controller: CommunityNavigationController(),
          visible: visible,
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byKey(const Key('profile-community-sidebar'));
      final originalSidebar = tester.element(sidebar);
      navigator.currentState!.pushNamed('/messages');
      await tester.pumpAndSettle();
      final inbox = observer.currentRouteObject;
      await tester.tap(
        find.byKey(const ValueKey('sidebar-destination-messages')),
      );
      await tester.pumpAndSettle();
      expect(observer.currentRouteObject, same(inbox));
      for (final namedPeer in [false, true]) {
        final draft = GlobalKey<_DraftPageState>();
        final conversation = MaterialPageRoute<void>(
          settings: namedPeer
              ? const RouteSettings(
                  name: '/messages',
                  arguments: {'peerId': 'synthetic'},
                )
              : const RouteSettings(),
          builder: (_) => _DraftPage(key: draft, label: 'Conversation draft'),
        );
        navigator.currentState!.push(conversation);
        await tester.pumpAndSettle();
        expect(observer.currentRoute, '/messages');
        expect(observer.currentRouteObject, same(conversation));
        expect(
          communityInboxIsTop(observer.currentRouteObject!.settings),
          false,
        );
        await tester.enterText(
          find.byKey(const ValueKey('draft-Conversation draft')),
          'keep conversation',
        );
        final originalDraft = draft.currentState;
        await tester.tap(
          find.byKey(const ValueKey('sidebar-destination-messages')),
        );
        await tester.pumpAndSettle();
        expect(find.text('/messages'), findsOneWidget);
        expect(observer.currentRouteObject, isNot(same(conversation)));
        expect(
          communityInboxIsTop(observer.currentRouteObject!.settings),
          true,
        );
        expect(tester.element(sidebar), same(originalSidebar));
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(observer.currentRouteObject, same(conversation));
        expect(draft.currentState, same(originalDraft));
        expect(draft.currentState!.text.text, 'keep conversation');
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
      }
      navigator.currentState!.pushNamed('/profile');
      await tester.pumpAndSettle();
      final profile = observer.currentRouteObject;
      await tester.tap(
        find.byKey(const ValueKey('sidebar-destination-profile')),
      );
      await tester.pumpAndSettle();
      expect(observer.currentRouteObject, same(profile));
      final workDraft = GlobalKey<_DraftPageState>();
      final work = MaterialPageRoute<void>(
        builder: (_) => _DraftPage(key: workDraft, label: 'Work draft'),
      );
      navigator.currentState!.push(work);
      await tester.pumpAndSettle();
      expect(observer.currentRoute, '/profile');
      expect(observer.currentRouteObject, same(work));
      await tester.enterText(
        find.byKey(const ValueKey('draft-Work draft')),
        'keep work',
      );
      final originalWorkDraft = workDraft.currentState;
      await tester.tap(
        find.byKey(const ValueKey('sidebar-destination-profile')),
      );
      await tester.pumpAndSettle();
      expect(find.text('/profile'), findsOneWidget);
      expect(observer.currentRouteObject, isNot(same(work)));
      expect(tester.element(sidebar), same(originalSidebar));
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(observer.currentRouteObject, same(work));
      expect(workDraft.currentState, same(originalWorkDraft));
      expect(workDraft.currentState!.text.text, 'keep work');
      await tester.pumpWidget(const SizedBox());
      observer.dispose();
      visible.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('replacing a route below top keeps actual top identity', (
    tester,
  ) async {
    final observer = CommunitySidebarRouteObserver();
    MaterialPageRoute<void> route(String? name) => MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => const SizedBox(),
    );
    final profile = route('/profile'),
        conversation = route(null),
        replacement = route('/messages');
    observer.didPush(profile, null);
    observer.didPush(conversation, profile);
    observer.didReplace(newRoute: replacement, oldRoute: profile);
    expect(observer.currentRouteObject, same(conversation));
    expect(observer.currentRoute, '/profile');
    observer.didPop(conversation, replacement);
    expect(observer.currentRouteObject, same(replacement));
    expect(observer.currentRoute, '/messages');
    await tester.pump();
    observer.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sidebar destinations stay in route semantics and remain actionable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final navigator = GlobalKey<NavigatorState>();
        final observer = CommunitySidebarRouteObserver();
        final visible = ValueNotifier(true);
        await tester.pumpWidget(
          _app(
            navigator: navigator,
            observer: observer,
            controller: CommunityNavigationController(),
            visible: visible,
            locale: const Locale('zh'),
            initialRoute: '/messages',
          ),
        );
        await tester.pumpAndSettle();
        void expectDestinations() {
          for (final label in ['热门', '关注', '我的', '消息']) {
            final finder = find.bySemanticsLabel(
              RegExp('^${RegExp.escape(label)}\$'),
            );
            expect(
              finder,
              findsOneWidget,
              reason:
                  '$label must remain in the actual semantics tree above Navigator',
            );
            final data = tester.getSemantics(finder).getSemanticsData();
            expect(
              data.flagsCollection.isButton,
              true,
              reason: '$label must be a button',
            );
            expect(
              data.hasAction(SemanticsAction.tap),
              true,
              reason: '$label must remain actionable',
            );
          }
        }

        expectDestinations();
        await tester.tap(find.bySemanticsLabel('我的'));
        await tester.pumpAndSettle();
        expect(find.text('/profile'), findsOneWidget);
        expectDestinations();
        tester.view.physicalSize = const Size(800, 900);
        await tester.pumpAndSettle();
        expectDestinations();
        await tester.tap(find.bySemanticsLabel('消息'));
        await tester.pumpAndSettle();
        expect(find.text('/messages'), findsOneWidget);
        expectDestinations();
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expectDestinations();
        await tester.pumpWidget(const SizedBox());
        observer.dispose();
        visible.dispose();
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  test('route visibility preserves standalone auth and full work entry', () {
    final messages = Uri.parse('https://example.invalid/community/#/messages');
    expect(communitySidebarVisible(messages, '/'), true);
    expect(communitySidebarDestination(messages, '/'), 'messages');
    for (final entry in [
      Uri.parse('https://example.invalid/community/?auth=signin'),
      Uri.parse('https://example.invalid/community/?work=synthetic'),
    ]) {
      expect(communitySidebarVisible(entry, '/'), false);
      expect(communitySidebarVisible(entry, '/profile-edit'), true);
      expect(communitySidebarVisible(entry, '/?profile=owner'), true);
      expect(communitySidebarDestination(entry, '/messages'), 'messages');
    }
    final profile = Uri.parse(
      'https://example.invalid/community/?profile=owner',
    );
    expect(
      communitySidebarDestination(profile, '/', ownerId: 'owner'),
      'profile',
    );
    expect(communitySidebarDestination(profile, '/', ownerId: 'other'), '');
  });

  test(
    'document guards are newest first, deny on errors, and unregister cleanly',
    () async {
      final controller = CommunityNavigationController();
      final first = Object(), second = Object();
      final calls = <String>[];
      controller.registerExitGuard(first, () async {
        calls.add('first');
        return true;
      });
      controller.registerExitGuard(second, () async {
        calls.add('second');
        return false;
      });
      expect(await controller.confirmDocumentExit(), false);
      expect(calls, ['second']);
      calls.clear();
      controller.registerExitGuard(second, () async {
        calls.add('second');
        return true;
      });
      expect(await controller.confirmDocumentExit(), true);
      expect(calls, ['second', 'first']);
      controller.unregisterExitGuard(second);
      calls.clear();
      expect(await controller.confirmDocumentExit(), true);
      expect(calls, ['first']);
      controller.registerExitGuard(
        second,
        () async => throw StateError('synthetic failure'),
      );
      expect(await controller.confirmDocumentExit(), false);
      controller.unregisterExitGuard(first);
      controller.unregisterExitGuard(second);
      expect(await controller.confirmDocumentExit(), true);
    },
  );

  testWidgets('disposed route observer does not emit queued notification', (
    tester,
  ) async {
    final observer = CommunitySidebarRouteObserver();
    var notified = 0;
    observer.addListener(() => notified++);
    observer.didPush(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/messages'),
        builder: (_) => const SizedBox(),
      ),
      null,
    );
    observer.dispose();
    await tester.pump();
    expect(notified, 0);
    expect(tester.takeException(), isNull);
  });
}
