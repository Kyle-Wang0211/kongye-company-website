@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/unavailable_auth_service.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/main_community_web.dart';

class _User extends CurrentUser {
  _User() : super(service: const UnavailableAuthService());
  CurrentUserState current = const CurrentUserSignedOut();
  @override
  CurrentUserState get state => current;
  @override
  AuthenticatedUser? get signedInUser => current is CurrentUserSignedIn
      ? (current as CurrentUserSignedIn).user
      : null;
  void enter(String id, {String? name}) {
    current = CurrentUserSignedIn(
      AuthenticatedUser(id: InternalUserID(id), displayName: name),
    );
    notifyListeners();
  }
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

  testWidgets('account replacement removes private routes and root dialogs', (
    tester,
  ) async {
    final user = _User()..enter('actor-a');
    final locale = LocaleNotifier();
    addTearDown(user.dispose);
    addTearDown(locale.dispose);
    await tester.pumpWidget(CommunityWebApp(user: user, locale: locale));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: Text('Private account route', key: ValueKey('private-page')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    showDialog<void>(
      context: tester.element(find.byKey(const ValueKey('private-page'))),
      builder: (_) =>
          const AlertDialog(content: Text('Private draft confirmation')),
    );
    await tester.pumpAndSettle();
    user.enter('actor-a', name: 'Updated name');
    await tester.pumpAndSettle();
    expect(find.text('Private draft confirmation'), findsOneWidget);
    user.enter('actor-b');
    await tester.pumpAndSettle();
    expect(find.text('Private draft confirmation'), findsNothing);
    expect(find.text('Private account route'), findsNothing);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator).first),
      isNot(same(navigator)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('first successful sign-in preserves the public reading route', (
    tester,
  ) async {
    final user = _User();
    final locale = LocaleNotifier();
    addTearDown(user.dispose);
    addTearDown(locale.dispose);
    await tester.pumpWidget(CommunityWebApp(user: user, locale: locale));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Public reading')),
      ),
    );
    await tester.pumpAndSettle();
    user.enter('actor-a');
    await tester.pumpAndSettle();
    expect(find.text('Public reading'), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator).first),
      same(navigator),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
