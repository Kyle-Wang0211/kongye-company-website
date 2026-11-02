import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/config/backend_deployment.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/auth_root_view.dart';

class RecordingProvider extends MockAuthServiceImpl {
  final requests = <SignInRequest>[];

  @override
  Future<AuthenticatedUser> signIn(SignInRequest request) {
    requests.add(request);
    return super.signIn(request);
  }
}

Future<CurrentUser> mountLogin(
  WidgetTester tester,
  RecordingProvider provider,
  BackendRegion region,
) async {
  final user = CurrentUser(
    service: provider,
    deployment: BackendDeployment(
      region: region,
      id: 'synthetic-login-test',
      supabaseUrl: 'https://example.test',
      anonKey: 'synthetic-key',
    ),
  );
  final locale = LocaleNotifier();
  addTearDown(user.dispose);
  addTearDown(locale.dispose);
  await user.bootstrap();
  await tester.pumpWidget(
    LocaleScope(
      notifier: locale,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: AuthRootView(currentUser: user),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return user;
}

void expectNoFixedPrefix() {
  expect(find.byKey(const ValueKey('auth-phone-country-prefix')), findsNothing);
  expect(
    find.byKey(const ValueKey('auth-phone-country-separator')),
    findsNothing,
  );
  expect(find.text('+86'), findsNothing);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final region in BackendRegion.values) {
    testWidgets('password login has no fixed country prefix in $region', (
      tester,
    ) async {
      await mountLogin(tester, RecordingProvider(), region);
      expectNoFixedPrefix();
      for (final account in [
        '13800000000',
        'person@example.test',
        '+44 7700 900123',
      ]) {
        await tester.enterText(find.byType(TextField).first, account);
        await tester.pump();
        expectNoFixedPrefix();
        final field = tester.widget<TextField>(find.byType(TextField).first);
        expect(field.controller!.text, account);
        expect(field.keyboardType, TextInputType.emailAddress);
        expect(field.autofillHints, [AutofillHints.username]);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final entry in [
    (BackendRegion.china, '13800000000', '+8613800000000'),
    (BackendRegion.china, '+44 7700 900123', '+447700900123'),
    (BackendRegion.international, '+44 7700 900123', '+447700900123'),
  ]) {
    testWidgets('password submission preserves normalization for $entry', (
      tester,
    ) async {
      final provider = RecordingProvider();
      final user = await mountLogin(tester, provider, entry.$1);
      const password = ' password unchanged ';
      await tester.enterText(find.byType(TextField).first, entry.$2);
      await tester.enterText(find.byType(TextField).last, password);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(provider.requests, hasLength(1));
      final request = provider.requests.single as SignInRequestPhonePassword;
      expect(request.phoneNumber, entry.$3);
      expect(request.password, password);
      expect(user.isSignedIn, isTrue);
      expectNoFixedPrefix();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
