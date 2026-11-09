import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/auth_scope.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/ui/community/community_profile_shell.dart';
import 'package:pocketworld_flutter/ui/community/current_author_name.dart';

class _User extends CurrentUser {
  _User() : super(service: MockAuthServiceImpl());
  String name = 'Old approved';
  @override
  AuthenticatedUser get signedInUser =>
      AuthenticatedUser(id: const InternalUserID('owner'), displayName: name);
  void publish(String value) {
    name = value;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'approved owner update repaints retained author labels only for same UUID',
    (tester) async {
      final user = _User();
      await tester.pumpWidget(
        MaterialApp(
          home: AuthScope(
            currentUser: user,
            child: Builder(
              builder: (context) => Column(
                children: [
                  Text(currentAuthorName(context, 'owner', 'Old snapshot')),
                  Text(
                    currentAuthorName(context, 'someone-else', 'Other author'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Old approved'), findsOneWidget);
      user.publish('New approved');
      await tester.pump();
      expect(find.text('New approved'), findsOneWidget);
      expect(find.text('Other author'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      user.dispose();
    },
  );

  Widget shell({Widget? child, VoidCallback? home}) => MaterialApp(
    home: CommunityProfileShell(
      onHome: home ?? () {},
      onFollowing: () {},
      onMyProfile: () {},
      onSettings: () {},
      onMessages: () {},
      child: child ?? const Scaffold(body: Text('Profile content')),
    ),
  );
  for (final spec in [
    (1280.0, 204.0),
    (1000.0, 80.0),
    (600.0, 56.0),
    (390.0, 56.0),
  ]) {
    testWidgets('canonical community rail at ${spec.$1}', (tester) async {
      tester.view.physicalSize = Size(spec.$1, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(shell());
      await tester.pump();
      final sidebar = find.byKey(const Key('profile-community-sidebar'));
      expect(tester.getSize(sidebar).width, spec.$2);
      expect(
        (tester.widget<Container>(sidebar).padding! as EdgeInsets).bottom,
        spec.$1 <= 600 ? 18 : 20,
      );
      final footer = find.byKey(const ValueKey('sidebar-destination-settings'));
      expect(
        find.descendant(
          of: footer,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ConstrainedBox &&
                widget.constraints.minHeight == (spec.$1 <= 600 ? 44 : 42),
          ),
        ),
        findsOneWidget,
      );
      if (spec.$1 <= 600) expect(tester.getSize(footer).height, 44);
      final primary = find.byKey(const Key('sidebar-primary'));
      final iconKeys = ['hot', 'following', 'profile', 'messages'];
      for (final destination in iconKeys) {
        expect(
          find.descendant(
            of: primary,
            matching: find.byKey(ValueKey('sidebar-destination-$destination')),
          ),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byKey(ValueKey('sidebar-icon-$destination'))),
          const Size(22, 22),
        );
      }
      expect(
        find.byKey(const ValueKey('sidebar-destination-publish')),
        findsNothing,
      );
      expect(find.text('Publish'), findsNothing);
      expect(find.text('Account and privacy'), findsNothing);
      expect(find.text('Profile content'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('profile-shell-content'))).dx,
        spec.$2,
      );
      if (spec.$1 > 1000) {
        final item = find.byKey(const ValueKey('sidebar-destination-hot'));
        expect(tester.getTopLeft(item), const Offset(18, 104));
        expect(tester.getSize(item).height, 48);
        expect(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('sidebar-destination-following')),
              )
              .dy,
          162,
        );
        final text = tester.widget<Text>(find.text('Me'));
        expect(text.style?.fontSize, 15);
        expect(text.style?.height, 1.5);
        expect(text.style?.fontWeight, FontWeight.w600);
        expect(text.style?.letterSpacing, 0);
        final selected = tester.widget<Material>(
          find.descendant(
            of: find.byKey(const ValueKey('sidebar-destination-profile')),
            matching: find.byType(Material),
          ),
        );
        expect(selected.color, const Color(0xfff3f3f3));
        expect(selected.borderRadius, BorderRadius.circular(8));
        expect(
          tester.widget<Text>(find.text('Hot')).style?.color,
          const Color(0xff737373),
        );
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('京ICP备2026067702号-1'), findsOneWidget);
      } else {
        expect(find.text('Me'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('one content subtree survives desktop to rail resize', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(shell(child: const _Counter()));
    await tester.tap(find.text('count 0'));
    await tester.pump();
    tester.view.physicalSize = const Size(390, 900);
    await tester.pump();
    expect(find.text('count 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('short viewport scrolls navigation without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(shell());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('count $count'),
    ),
  );
}
