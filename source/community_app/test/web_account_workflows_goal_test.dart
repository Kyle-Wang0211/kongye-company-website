import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pocketworld_flutter/ui/social/web_account_workflow_repository.dart';
import 'package:pocketworld_flutter/ui/social/web_account_privacy_page.dart';
import 'package:pocketworld_flutter/ui/social/web_publication_status_page.dart';
import 'package:pocketworld_flutter/ui/social/web_report_review_page.dart';

void main() {
  test(
    'deletion validates exact202 self receipt and preserves requested status',
    () async {
      final client = SupabaseClient('http://localhost', 'test');
      final repository = WebAccountWorkflowRepository(
        client: client,
        accountId: 'self',
        userIdProvider: () => 'self',
        invoke: (name, body) async {
          expect(name, 'delete-account');
          expect(body, {'confirm': true});
          return FunctionResponse(
            status: 202,
            data: {
              'ok': true,
              'account_erasure_status': 'requested',
              'erasure_pending': true,
              'requested_user_id': 'self',
            },
          );
        },
      );
      expect(
        await repository.requestDeletion(),
        WebDeletionRequestStatus.pending,
      );
      final invalid = WebAccountWorkflowRepository(
        client: client,
        accountId: 'self',
        userIdProvider: () => 'self',
        invoke: (_, _) async => FunctionResponse(
          status: 202,
          data: {
            'ok': true,
            'account_erasure_status': 'requested',
            'erasure_pending': true,
            'requested_user_id': 'other',
          },
        ),
      );
      await expectLater(invalid.requestDeletion(), throwsStateError);
      client.dispose();
    },
  );
  test(
    'withdraw validates owner receipt and rejects ambiguous or stale identity',
    () async {
      final client = SupabaseClient('http://localhost', 'test');
      String owner = 'self';
      final pending = Completer<FunctionResponse>();
      final repository = WebAccountWorkflowRepository(
        client: client,
        accountId: 'self',
        userIdProvider: () => owner,
        invoke: (name, body) {
          expect(name, 'publication-review');
          expect(body, {'action': 'withdraw', 'work_id': 'work'});
          return pending.future;
        },
      );
      final result = repository.withdraw('work');
      owner = 'other';
      pending.complete(
        FunctionResponse(
          status: 200,
          data: {
            'ok': true,
            'work_id': 'work',
            'status': 'withdrawn',
            'physical_erasure': 'held',
            'evidence_retained': true,
          },
        ),
      );
      await expectLater(result, throwsStateError);
      client.dispose();
    },
  );
  testWidgets(
    'withdraw waits for confirmation and backend then reloads actual state',
    (tester) async {
      final pending = Completer<void>();
      var loads = 0, calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WebPublicationStatusPage(
            accountId: 'self',
            loader: () async {
              loads++;
              return [
                WebPublicationSummary(
                  id: 'work',
                  title: 'Work',
                  stage: loads == 1 ? 'published' : 'withdrawn',
                  canWithdraw: loads == 1,
                ),
              ];
            },
            onOpen: (_) {},
            onWithdraw: (_) {
              calls++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤回发布'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('确认撤回'));
      await tester.pump();
      expect(calls, 1);
      expect(loads, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.text('已撤回'), findsWidgets);
      expect(find.text('在社区查看'), findsNothing);
    },
  );
  testWidgets('stable account switch invalidates withdrawal confirmation', (
    tester,
  ) async {
    var calls = 0;
    Widget page(String id) => MaterialApp(
      home: WebPublicationStatusPage(
        accountId: id,
        loader: () async => [
          const WebPublicationSummary(
            id: 'work',
            title: 'Work',
            stage: 'published',
            canWithdraw: true,
          ),
        ],
        onOpen: (_) {},
        onWithdraw: (_) async {
          calls++;
        },
      ),
    );
    await tester.pumpWidget(page('a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤回发布'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page('b'));
    await tester.pump();
    await tester.tap(find.text('确认撤回'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
  testWidgets('reviewer cannot take lead action and lead must own claim', (
    tester,
  ) async {
    Widget page(String role, String? claimed) => MaterialApp(
      home: WebReportReviewPage(
        accountId: 'self',
        loader: () async => WebReportReviewQueue(
          userId: 'self',
          role: role,
          items: [
            WebReportReviewItem(
              id: 1,
              reason: 'spam',
              status: claimed == null ? 'pending' : 'in_review',
              targetId: 'target',
              claimedBy: claimed,
            ),
          ],
        ),
        onClaim: (_) async {},
        onTransition: (_, _, _) async {},
      ),
    );
    await tester.pumpWidget(page('reviewer', 'self'));
    await tester.pumpAndSettle();
    expect(find.text('确认采取措施'), findsNothing);
    expect(find.text('不予采纳'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page('lead', null));
    await tester.pumpAndSettle();
    expect(find.text('确认采取措施'), findsNothing);
    expect(find.text('领取处理'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page('lead', 'self'));
    await tester.pumpAndSettle();
    expect(find.text('确认采取措施'), findsOneWidget);
  });
  testWidgets(
    'review failure retains feedback and requires fresh queue before retry',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.green),
          home: WebReportReviewPage(
            accountId: 'self',
            loader: () async => const WebReportReviewQueue(
              userId: 'self',
              role: 'reviewer',
              items: [
                WebReportReviewItem(
                  id: 1,
                  reason: 'spam',
                  status: 'in_review',
                  targetId: 'target',
                  claimedBy: 'self',
                ),
              ],
            ),
            onClaim: (_) async {},
            onTransition: (_, _, feedback) async {
              calls++;
              expect(feedback, '保留处理说明');
              throw StateError('ambiguous');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('不予采纳'));
      await tester.pumpAndSettle();
      final colors = Theme.of(
        tester.element(find.byType(AlertDialog)),
      ).colorScheme;
      expect((colors.primary.r - colors.primary.g).abs(), lessThan(.012));
      await tester.enterText(find.byType(TextFormField), '保留处理说明');
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '不予采纳'))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('处理说明已保留'), findsOneWidget);
      await tester.tap(find.byTooltip('刷新队列'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不予采纳'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
        '保留处理说明',
      );
      expect(calls, 1);
    },
  );
  test(
    'restore accepts only confirmed matching work with no failed assets',
    () async {
      final client = SupabaseClient('http://localhost', 'test');
      var failed = 0;
      final repository = WebAccountWorkflowRepository(
        client: client,
        accountId: 'self',
        userIdProvider: () => 'self',
        invoke: (name, body) async {
          expect(name, 'admin-moderate-work');
          expect(body, {'work_id': 'work', 'status': 'ok'});
          return FunctionResponse(
            status: 200,
            data: {
              'ok': true,
              'work_id': 'work',
              'status': 'ok',
              'assets_failed': failed,
              'failed': failed == 0 ? [] : ['asset'],
            },
          );
        },
      );
      await repository.restoreWork('work');
      failed = 1;
      await expectLater(repository.restoreWork('work'), throwsStateError);
      client.dispose();
    },
  );
  testWidgets(
    'lead restore waits for backend and preserves actioned report history',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WebReportReviewPage(
            accountId: 'self',
            loader: () async => const WebReportReviewQueue(
              userId: 'self',
              role: 'lead',
              items: [
                WebReportReviewItem(
                  id: 1,
                  reason: 'spam',
                  status: 'actioned',
                  targetId: 'target',
                  sourceWorkId: 'work',
                ),
              ],
            ),
            onClaim: (_) async {},
            onTransition: (_, _, _) async {},
            onRestoreWork: (id) {
              expect(id, 'work');
              calls++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复关联作品'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('确认恢复'));
      await tester.pump();
      expect(calls, 1);
      expect(find.textContaining('恢复结果已确认'), findsNothing);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('恢复结果已确认'), findsOneWidget);
      expect(find.textContaining('actioned'), findsOneWidget);
    },
  );
}
