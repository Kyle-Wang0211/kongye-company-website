import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/ui/auth/auth_minimal_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/auth_shared_widgets.dart';
import 'package:pocketworld_flutter/ui/auth/email_sign_in_view.dart';
import 'package:pocketworld_flutter/ui/auth/phone_sign_in_view.dart';
import 'package:pocketworld_flutter/ui/auth/otp_verification_view.dart';
import 'package:pocketworld_flutter/ui/auth/login_code_view.dart';
import 'package:pocketworld_flutter/ui/auth/reset_password_view.dart';
import 'login_method_selection_test.dart' as login;

void main() {
  testWidgets('platform form widths stay centered and retain draft on resize', (
    t,
  ) async {
    await login.mount(t, webLayout: true);
    await t.enterText(find.byType(TextField).first, '13800000000');
    for (final width in [2048.0, 1440.0, 844.0, 390.0, 320.0]) {
      t.view.physicalSize = Size(width, 1200);
      await t.pumpAndSettle();
      final field = find.byType(TextField).first;
      final rect = t.getRect(field);
      final expected = width >= 1080
          ? width / 3
          : width - (width < 600 ? 32 : 48);
      expect(rect.width, closeTo(expected, 1));
      expect(rect.center.dx, closeTo(width / 2, 1));
      expect(t.widget<TextField>(field).controller!.text, '13800000000');
      expect(t.takeException(), isNull);
    }
  });
  testWidgets(
    'long persistent labels wrap and six boxes fit narrow text scale 1.6',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      final focus = FocusNode();
      final shake = AnimationController(vsync: t);
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      addTearDown(shake.dispose);
      const label =
          'Confirm your new password using the exact same characters, including spaces';
      for (final width in [320.0, 390.0]) {
        t.view.physicalSize = Size(width, 500);
        await t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: AuthFormBody(
                  child: Column(
                    children: [
                      LabeledField(label: label, controller: controller),
                      AuthField(title: label, controller: controller),
                      OtpBoxRow(
                        controller: controller,
                        focusNode: focus,
                        otpLength: 6,
                        shake: shake,
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        for (final text in [label, label.toUpperCase()]) {
          final finder = find.text(text);
          expect(finder, findsOneWidget);
          final paragraph = t.renderObject<RenderParagraph>(finder);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(paragraph.size.height, greaterThan(30));
        }
        final first = t.getRect(find.byType(OtpBox).first);
        final last = t.getRect(find.byType(OtpBox).last);
        expect(first.left, greaterThanOrEqualTo(16));
        expect(last.right, lessThanOrEqualTo(width - 16));
        expect(t.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'all auth pages center at wide widths and scroll on narrow short screens',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final user = CurrentUser(service: MockAuthServiceImpl());
      final locale = LocaleNotifier();
      addTearDown(user.dispose);
      addTearDown(locale.dispose);
      final pages = <Widget>[
        EmailSignUpPage(currentUser: user),
        ResetPasswordView(currentUser: user),
        Scaffold(
          body: SingleChildScrollView(
            child: PhoneSignInView(
              currentUser: user,
              intent: PhoneIntent.signUp,
            ),
          ),
        ),
        LoginCodeView(currentUser: user, target: '+8613800000000'),
        OtpVerificationView(
          currentUser: user,
          email: 'synthetic@example.invalid',
          password: 'Synthetic-123',
        ),
      ];
      for (final width in [2048.0, 1440.0, 844.0, 390.0, 320.0]) {
        t.view.physicalSize = Size(width, width < 500 ? 500 : 1200);
        for (final page in pages) {
          await t.pumpWidget(
            LocaleScope(
              notifier: locale,
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(width < 500 ? 1.6 : 1),
                    viewInsets: EdgeInsets.only(bottom: width < 500 ? 120 : 0),
                  ),
                  child: AuthFormLayoutScope(webLayout: true, child: child!),
                ),
                locale: const Locale('en'),
                localizationsDelegates: AppL10n.localizationsDelegates,
                supportedLocales: AppL10n.supportedLocales,
                home: page,
              ),
            ),
          );
          await t.pumpAndSettle();
          final form = find.byType(AuthFormBody).first;
          final boxes = find.descendant(
            of: form,
            matching: find.byType(TextField),
          );
          expect(boxes, findsWidgets);
          await t.ensureVisible(boxes.last);
          await t.pumpAndSettle();
          expect(
            t.getRect(boxes.first).left,
            greaterThanOrEqualTo(
              width >= 1080 ? width / 3 - 1 : (width < 600 ? 16 : 24),
            ),
          );
          expect(
            t.getRect(boxes.last).right,
            lessThanOrEqualTo(
              width >= 1080
                  ? 2 * width / 3 + 1
                  : width - (width < 600 ? 16 : 24),
            ),
          );
          expect(
            t.takeException(),
            isNull,
            reason: '${page.runtimeType} at $width',
          );
          await t.pumpWidget(const SizedBox());
          await t.pump();
        }
      }
    },
  );
}
