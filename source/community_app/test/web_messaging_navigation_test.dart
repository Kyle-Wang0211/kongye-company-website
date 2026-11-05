@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/community/social_profile_models.dart';
import 'package:pocketworld_flutter/community/social_profile_repository.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/main_community_web.dart';
import 'package:pocketworld_flutter/ui/community/user_profile_page.dart';
import 'package:pocketworld_flutter/ui/social/web_messaging_entry.dart';

import 'web_messaging_entry_test.dart' show User, Repository;

class Profiles implements SocialProfileRepository {
  Profiles(this.currentUserId);
  @override
  String? currentUserId;
  @override
  Future<SocialProfile> fetchProfile(String id) async => SocialProfile.fromMap({
    'id': id,
    'display_name': 'Profile peer',
    'handle': 'peer',
    'followers_count': 0,
    'following_count': 0,
    'public_works_count': 0,
  });
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository action');
}

class RouteUser extends User {
  CurrentUserState current = const CurrentUserBootstrapping();
  @override
  CurrentUserState get state => current;
  void enter() {
    identity = const AuthenticatedUser(id: InternalUserID('owner'));
    current = CurrentUserSignedIn(identity!);
    notifyListeners();
  }
}

Future<void> profile(
  WidgetTester tester,
  Profiles repo, {
  VoidCallback? favorites,
  VoidCallback? inbox,
  ValueChanged<SocialProfile>? message,
  Future<void> Function()? signIn,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: UserProfilePage(
        userId: 'peer',
        repository: repo,
        worksLoader: (_) async => [],
        onOpenFavorites: favorites,
        onOpenMessages: inbox,
        onMessage: message,
        onSignIn: signIn,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('own profile retains favorites and opens its inbox', (
    tester,
  ) async {
    var favorites = 0, inbox = 0;
    await profile(
      tester,
      Profiles('peer'),
      favorites: () => favorites++,
      inbox: () => inbox++,
      message: (_) => fail('Self must not open peer chat'),
    );
    await tester.tap(find.byKey(const ValueKey('profile-favorites-button')));
    await tester.tap(find.byKey(const ValueKey('profile-messages-button')));
    expect([favorites, inbox], [1, 1]);
    expect(
      find.byKey(const ValueKey('profile-message-peer-button')),
      findsNothing,
    );
  });

  testWidgets('visitor private chat uses loaded peer identity after sign-in', (
    tester,
  ) async {
    final repo = Profiles(null);
    var signIns = 0;
    SocialProfile? requested;
    await profile(
      tester,
      repo,
      message: (value) => requested = value,
      signIn: () async {
        signIns++;
        repo.currentUserId = 'owner';
      },
    );
    await tester.tap(find.byKey(const ValueKey('profile-message-peer-button')));
    await tester.pumpAndSettle();
    expect(signIns, 1);
    expect(requested?.id, 'peer');
    expect(requested?.displayName, 'Profile peer');
  });

  testWidgets('cancelled sign-in does not open private chat', (tester) async {
    var calls = 0;
    await profile(
      tester,
      Profiles(null),
      message: (_) => calls++,
      signIn: () async {},
    );
    await tester.tap(find.byKey(const ValueKey('profile-message-peer-button')));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets(
    'messages route waits for bootstrap then binds normal authenticated inbox',
    (tester) async {
      final user = RouteUser()..identity = null;
      final repo = Repository(user);
      addTearDown(() {
        repo.dispose();
        repo.api.close();
        repo.changes.close();
        user.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: const SizedBox.shrink(),
          initialRoute: '/messages',
          onGenerateRoute: (settings) =>
              communityMessagingRoute(settings, user, repository: repo),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      user.enter();
      await tester.pumpAndSettle();
      expect(find.text('Private peer'), findsOneWidget);
    },
  );

  testWidgets(
    'typed profile route opens canonical peer and preserves display name',
    (tester) async {
      final user = RouteUser()..enter();
      final repo = Repository(user);
      addTearDown(() {
        repo.dispose();
        repo.api.close();
        repo.changes.close();
        user.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).pushNamed(
                '/messages',
                arguments: const WebMessagingPeer(
                  id: 'peer',
                  displayName: 'Profile peer',
                ),
              ),
              child: const Text('Open peer'),
            ),
          ),
          onGenerateRoute: (settings) =>
              communityMessagingRoute(settings, user, repository: repo),
        ),
      );
      await tester.tap(find.text('Open peer'));
      await tester.pumpAndSettle();
      expect(repo.opens, 1);
      expect(find.text('Profile peer'), findsOneWidget);
      expect(find.text('Private history 1'), findsOneWidget);
    },
  );
}
