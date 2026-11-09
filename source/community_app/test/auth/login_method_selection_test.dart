import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/aether_prefs.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/config/backend_deployment.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/auth_minimal_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/auth_root_view.dart';

class RecordingService extends MockAuthServiceImpl {
  final requests = <SignInRequest>[];
  Completer<void>? hold;

  @override
  Future<AuthenticatedUser> signIn(SignInRequest request) async {
    requests.add(request);
    if (hold != null) await hold!.future;
    return super.signIn(request);
  }
}

Future<RecordingService> mount(
  WidgetTester tester, {
  BackendRegion region = BackendRegion.china,
  Locale locale = const Locale('zh'),
  bool? webLayout,
}) async {
  AetherPrefs.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final service = RecordingService();
  final user = CurrentUser(
    service: service,
    deployment: BackendDeployment(
      region: region,
      id: 'synthetic-login-test',
      supabaseUrl: 'https://example.test',
      anonKey: 'synthetic-key',
    ),
  );
  final notifier = LocaleNotifier();
  addTearDown(user.dispose);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    LocaleScope(
      notifier: notifier,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: webLayout == null
            ? AuthRootView(currentUser: user)
            : AuthFormLayoutScope(
                webLayout: webLayout,
                child: AuthRootView(currentUser: user),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

Future<void> chooseMode(WidgetTester tester, String mode) async {
  final target = find.byKey(ValueKey('auth-method-$mode'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> chooseCountry(WidgetTester tester, String iso) async {
  final selector = find.byKey(const ValueKey('phone-country-selector'));
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('phone-country-search')),
    iso,
  );
  await tester.pumpAndSettle();
  final row = find.byKey(ValueKey('phone-country-$iso'));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> submit(
  WidgetTester tester,
  String account, [
  String password = ' password unchanged ',
]) async {
  await tester.enterText(find.byType(TextField).first, account);
  await tester.enterText(find.byType(TextField).last, password);
  await tester.ensureVisible(find.byKey(const ValueKey('auth-policy-consent')));
  await tester.tap(find.byKey(const ValueKey('auth-policy-consent')));
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('China has explicit phone/email modes and selectable +86', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('手机号登录'), findsOneWidget);
    expect(find.text('邮箱登录'), findsOneWidget);
    expect(find.text('手机号或邮箱'), findsNothing);
    expect(find.text('+86'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('phone-country-selector')),
      findsOneWidget,
    );
    final input = tester.widget<TextField>(find.byType(TextField).first);
    expect(input.keyboardType, TextInputType.phone);
    expect(
      input.autofillHints,
      contains(AutofillHints.telephoneNumberNational),
    );
  });

  testWidgets('country picker searches Chinese names and uses PNG rows', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('phone-country-selector')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('phone-country-search')),
      '英国',
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('phone-country-GB'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byType(Image)),
      findsOneWidget,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('+44'), findsOneWidget);
  });

  testWidgets(
    'explicit code choice retains identity and requires a separate send action',
    (tester) async {
      final service = await mount(tester);
      await tester.enterText(find.byType(TextField).first, '13800000000');
      await tester.tap(find.byKey(const ValueKey('auth-use-code')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '13800000000',
      );
      expect(service.requests, isEmpty);
      await chooseMode(tester, 'email');
      expect(find.byKey(const ValueKey('auth-use-code')), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2));
      await chooseMode(tester, 'phone');
      await tester.tap(find.byKey(const ValueKey('auth-use-password')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
    },
  );

  testWidgets('mode switching preserves separate drafts and password', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField).first, '13800000000');
    await tester.enterText(find.byType(TextField).last, ' unchanged pass ');
    await chooseMode(tester, 'email');
    expect(find.text('+86'), findsNothing);
    var input = tester.widget<TextField>(find.byType(TextField).first);
    expect(input.keyboardType, TextInputType.emailAddress);
    expect(input.controller!.text, isEmpty);
    expect(input.autofillHints, contains(AutofillHints.email));
    await tester.enterText(find.byType(TextField).first, 'person@example.test');
    await chooseMode(tester, 'phone');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '13800000000',
    );
    await chooseMode(tester, 'email');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'person@example.test',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      ' unchanged pass ',
    );
  });

  testWidgets('email mode sends normalized email and unchanged password', (
    tester,
  ) async {
    final service = await mount(tester);
    await chooseMode(tester, 'email');
    await submit(tester, ' PERSON@Example.TEST ');
    final request = service.requests.single as SignInRequestEmail;
    expect(request.email, 'person@example.test');
    expect(request.password, ' password unchanged ');
  });

  for (final entry in [
    ('CN', '13800000000', '+8613800000000'),
    ('CN', '8613800000000', '+8613800000000'),
    ('CN', '0086 13800000000', '+8613800000000'),
    ('GB', '7700 900123', '+447700900123'),
    ('US', '+1 (415) 555-0123', '+14155550123'),
    ('IT', '0212345678', '+390212345678'),
  ]) {
    testWidgets('selected-country password request $entry', (tester) async {
      final service = await mount(tester);
      if (entry.$1 != 'CN') await chooseCountry(tester, entry.$1);
      await submit(tester, entry.$2);
      expect(service.requests, hasLength(1));
      final request = service.requests.single as SignInRequestPhonePassword;
      expect(request.phoneNumber, entry.$3);
      expect(request.password, ' password unchanged ');
    });
  }

  testWidgets('phone/email modes reject incompatible identity input', (
    tester,
  ) async {
    final service = await mount(tester);
    for (final value in ['person@example.test', '+44 7700 900123', '1' * 65]) {
      await submit(tester, value);
      expect(service.requests, isEmpty);
      expect(
        tester.widget<MinimalCta>(find.byType(MinimalCta)).enabled,
        isFalse,
      );
    }
    await chooseMode(tester, 'email');
    await submit(tester, '+8613800000000');
    expect(service.requests, isEmpty);
  });

  testWidgets(
    'international deployment defaults to email with phone available',
    (tester) async {
      await mount(
        tester,
        region: BackendRegion.international,
        locale: const Locale('en'),
      );
      expect(find.text('Phone login'), findsOneWidget);
      expect(find.text('Email login'), findsOneWidget);
      expect(find.text('+86'), findsNothing);
      await chooseMode(tester, 'phone');
      expect(
        find.byKey(const ValueKey('phone-country-selector')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'busy request freezes identity controls and prevents duplicates',
    (tester) async {
      final service = await mount(tester);
      service.hold = Completer<void>();
      await tester.enterText(find.byType(TextField).first, '13800000000');
      await tester.enterText(find.byType(TextField).last, 'Password-123');
      await tester.ensureVisible(
        find.byKey(const ValueKey('auth-policy-consent')),
      );
      await tester.tap(find.byKey(const ValueKey('auth-policy-consent')));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(service.requests, hasLength(1));
      for (final key in [
        'auth-method-email',
        'auth-method-phone',
        'phone-country-selector',
      ]) {
        expect(
          tester.widget<TextButton>(find.byKey(ValueKey(key))).onPressed,
          isNull,
        );
      }
      expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(service.requests, hasLength(1));
      service.hold!.complete();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'login defaults password and exposes explicit code choice with recovery',
    (tester) async {
      await mount(tester);
      for (final mode in ['phone', 'email']) {
        await chooseMode(tester, mode);
        expect(
          find.byKey(const ValueKey('auth-use-code')),
          mode == 'phone' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('验证码登录'),
          mode == 'phone' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('auth-email-code-address')),
          findsNothing,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField).last).obscureText,
          isTrue,
        );
      }
      final reset = find.text('忘记密码');
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(find.text('重置密码'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'login uses an eye icon, no top-right language control and right-aligned recovery',
    (tester) async {
      await mount(tester);
      expect(find.byType(CompactLanguageToggle), findsNothing);
      expect(find.byTooltip('显示密码'), findsOneWidget);
      expect(find.text('显示密码'), findsNothing);
      final password = find.byType(TextField).last;
      final reset = find.byKey(const ValueKey('auth-forgot-password'));
      expect(reset, findsOneWidget);
      expect(
        tester.getTopLeft(reset).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(password).dy),
      );
      expect(
        (tester.getBottomRight(reset).dx - tester.getBottomRight(password).dx)
            .abs(),
        lessThan(1),
      );
      await tester.ensureVisible(find.byTooltip('显示密码'));
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pump();
      expect(tester.widget<TextField>(password).obscureText, isFalse);
    },
  );
  testWidgets('country indicators are bundled flag images with a down arrow', (
    tester,
  ) async {
    await mount(tester);
    final flag = tester.widget<Image>(find.byType(Image).first);
    expect((flag.image as AssetImage).assetName, 'assets/auth/flags/cn.png');
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    await chooseCountry(tester, 'US');
    final selected = tester.widget<Image>(find.byType(Image).first);
    expect(
      (selected.image as AssetImage).assetName,
      'assets/auth/flags/us.png',
    );
    expect(find.text('+1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'country artwork and prefix are compact while field labels are larger',
    (tester) async {
      await mount(tester);
      expect(tester.widget<Image>(find.byType(Image).first).width, 20);
      expect(tester.widget<Image>(find.byType(Image).first).height, 15);
      expect(tester.widget<Text>(find.text('+86')).style!.fontSize, 13);
      expect(tester.widget<Text>(find.text('手机号')).style!.fontSize, 14);
      expect(tester.widget<Text>(find.text('密码')).style!.fontSize, 14);
    },
  );
}
