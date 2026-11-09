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
  for (final width in [390.0, 1280.0]) {
    testWidgets('profile shell stays responsive at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var home = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CommunityProfileShell(
            onHome: () => home++,
            onFollowing: () {},
            onMyProfile: () {},
            onSettings: () {},
            onMessages: () {},
            onPublish: () {},
            child: const Scaffold(body: Text('Profile content')),
          ),
        ),
      );
      expect(
        find.byKey(const Key('profile-community-sidebar')),
        width >= 900 ? findsOneWidget : findsNothing,
      );
      expect(find.text('Profile content'), findsOneWidget);
      if (width >= 900) {
        await tester.tap(find.text('Explore'));
        expect(home, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
