import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/unavailable_auth_service.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/main_community_web.dart';
import 'package:pocketworld_flutter/ui/vault_page.dart';
import 'package:pocketworld_flutter/ui/auth/auth_root_view.dart';

class _User extends CurrentUser {
  _User(this.current) : super(service: const UnavailableAuthService());
  final CurrentUserState current;
  @override
  CurrentUserState get state => current;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      anonKey: 'anonymous-fixture',
      httpClient: MockClient((_) async => http.Response('[]', 200)),
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });
  for (final ready in [false, true]) {
    testWidgets('mobile feed waits for initialization: $ready', (tester) async {
      final user = _User(
        ready ? const CurrentUserSignedOut() : const CurrentUserBootstrapping(),
      );
      final locale = LocaleNotifier();
      addTearDown(user.dispose);
      addTearDown(locale.dispose);
      var exits = 0;
      await tester.pumpWidget(
        CommunityWebApp(
          user: user,
          locale: locale,
          onExit: () => exits++,
          entryUri: Uri.parse('https://kongye.space/community/?feed=1'),
        ),
      );
      await tester.pump();
      expect(find.byType(VaultPage), ready ? findsOneWidget : findsNothing);
      if (ready) {
        expect(
          tester.widget<VaultPage>(find.byType(VaultPage)).activities.length,
          3,
        );
      }
      expect(exits, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
  testWidgets('guest explicit publication still opens authentication', (
    tester,
  ) async {
    final user = _User(const CurrentUserSignedOut());
    final locale = LocaleNotifier();
    addTearDown(user.dispose);
    addTearDown(locale.dispose);
    await tester.pumpWidget(
      CommunityWebApp(
        user: user,
        locale: locale,
        entryUri: Uri.parse('https://kongye.space/community/?feed=1&publish=1'),
      ),
    );
    await tester.pump();
    expect(find.byType(AuthRootView), findsOneWidget);
    expect(find.byType(VaultPage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
