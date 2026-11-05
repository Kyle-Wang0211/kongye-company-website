import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/ui/social/web_account_privacy_page.dart';

void main() {
  Future<void> open(WidgetTester tester, WebAccountPrivacyPage page) async {
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  testWidgets('missing services are unavailable and policies use callbacks', (
    tester,
  ) async {
    var policyOpened = false;
    await open(
      tester,
      WebAccountPrivacyPage(onOpenPrivacyPolicy: () => policyOpened = true),
    );
    expect(find.text('Blocked users service is unavailable.'), findsOneWidget);
    expect(find.text('No blocked users'), findsNothing);
    await tester.tap(find.text('Privacy policy'));
    expect(policyOpened, isTrue);
    expect(
      find.textContaining('Deletion requests are unavailable.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Request account deletion'),
      findsNothing,
    );
  });

  testWidgets('failed loading can retry and resolve to the true empty state', (
    tester,
  ) async {
    var attempts = 0;
    await open(
      tester,
      WebAccountPrivacyPage(
        loadBlockedUsers: () async {
          if (++attempts == 1) throw StateError('offline');
          return [];
        },
      ),
    );
    expect(find.text('Could not load blocked users.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('No blocked users'), findsOneWidget);
  });

  testWidgets('unblocking requires confirmation and retains user on failure', (
    tester,
  ) async {
    var calls = 0;
    final result = Completer<void>();
    await open(
      tester,
      WebAccountPrivacyPage(
        loadBlockedUsers: () async => [
          const WebBlockedUser(id: 'u1', displayName: 'Blocked person'),
        ],
        onUnblock: (id) {
          expect(id, 'u1');
          calls++;
          return result.future;
        },
      ),
    );
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm unblock'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Blocked person'), findsOneWidget);
    expect(find.text('Working…'), findsOneWidget);
    result.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Blocked person'), findsOneWidget);
    expect(find.text('Could not unblock user. Please retry.'), findsOneWidget);
  });

  testWidgets('only server confirmed unblock removes the row', (tester) async {
    final result = Completer<void>();
    await open(
      tester,
      WebAccountPrivacyPage(
        loadBlockedUsers: () async => [
          const WebBlockedUser(id: 'u1', displayName: 'Blocked person'),
        ],
        onUnblock: (_) => result.future,
      ),
    );
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm unblock'));
    await tester.pumpAndSettle();
    expect(find.text('Blocked person'), findsOneWidget);
    result.complete();
    await tester.pumpAndSettle();
    expect(find.text('Blocked person'), findsNothing);
    expect(find.text('No blocked users'), findsOneWidget);
  });

  testWidgets('deletion needs acknowledgement and remains a pending request', (
    tester,
  ) async {
    var calls = 0;
    final result = Completer<WebDeletionRequestStatus>();
    await open(
      tester,
      WebAccountPrivacyPage(
        onRequestDeletion: () {
          calls++;
          return result.future;
        },
      ),
    );
    await tester.ensureVisible(find.text('Request account deletion'));
    await tester.tap(find.text('Request account deletion'));
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, 'Submit request');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(calls, 0);
    expect(
      Theme.of(tester.element(find.byType(Checkbox))).colorScheme.primary,
      const Color(0xFF111111),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Submitting…'), findsOneWidget);
    result.complete(WebDeletionRequestStatus.pending);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Request submitted, awaiting processing. Deletion is not confirmed.',
      ),
      findsOneWidget,
    );
    expect(find.byType(WebAccountPrivacyPage), findsOneWidget);
    expect(find.text('Request account deletion'), findsNothing);
  });

  testWidgets('failed deletion reports unconfirmed request without success', (
    tester,
  ) async {
    await open(
      tester,
      WebAccountPrivacyPage(
        onRequestDeletion: () async {
          throw StateError('offline');
        },
      ),
    );
    await tester.ensureVisible(find.text('Request account deletion'));
    await tester.tap(find.text('Request account deletion'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    expect(
      find.text('Submission could not be confirmed. Please retry later.'),
      findsOneWidget,
    );
    expect(find.textContaining('Request submitted,'), findsNothing);
    expect(find.byType(WebAccountPrivacyPage), findsOneWidget);
  });

  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('page fits width $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await open(tester, const WebAccountPrivacyPage());
      await tester.scrollUntilVisible(
        find.textContaining('Deletion requests are unavailable.'),
        200,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
