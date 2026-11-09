import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/ui/community/community_navigation_frame.dart';
import 'package:pocketworld_flutter/ui/social/web_profile_edit_page.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    CommunityNavigationController controller, {
    Future<WebProfileSaveResult> Function(WebProfileDraft)? save,
  }) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityNavigationScope(
          controller: controller,
          child: WebProfileEditPage(
            initialProfile: const WebProfileDraft(
              displayName: '已公开昵称',
              bio: '',
            ),
            save: save ?? (_) async => WebProfileSaveResult.pendingReview,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'clean draft permits document navigation and disposed dirty draft unregisters',
    (tester) async {
      final controller = CommunityNavigationController();
      await show(tester, controller);
      expect(await controller.confirmDocumentExit(), true);
      await tester.enterText(find.byKey(const Key('profile-name')), '本地草稿');
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(await controller.confirmDocumentExit(), true);
    },
  );

  testWidgets(
    'sidebar and Back share one discard confirmation and cancel retains draft',
    (tester) async {
      final controller = CommunityNavigationController();
      await show(tester, controller);
      await tester.enterText(find.byKey(const Key('profile-bio')), '未保存简介');
      await tester.pump();
      final first = controller.confirmDocumentExit();
      final second = controller.confirmDocumentExit();
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(await first, false);
      expect(await second, false);
      expect(find.text('未保存简介'), findsOneWidget);
      final accepted = controller.confirmDocumentExit();
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      expect(await accepted, true);
      // The caller owns navigation; confirming itself neither writes nor pops.
      expect(find.byKey(const Key('profile-bio')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'saving blocks document exit and durable save clears the dirty guard',
    (tester) async {
      final controller = CommunityNavigationController();
      final saved = Completer<WebProfileSaveResult>();
      await show(tester, controller, save: (_) => saved.future);
      await tester.enterText(find.byKey(const Key('profile-name')), '新昵称草稿');
      await tester.pump();
      await tester.ensureVisible(find.text('保存修改'));
      await tester.tap(find.text('保存修改'));
      await tester.pump();
      expect(await controller.confirmDocumentExit(), false);
      expect(find.text('放弃未保存的修改？'), findsNothing);
      saved.complete(WebProfileSaveResult.pendingReview);
      await tester.pumpAndSettle();
      expect(await controller.confirmDocumentExit(), true);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('rejected save keeps unsaved draft protected', (tester) async {
    final controller = CommunityNavigationController();
    await show(
      tester,
      controller,
      save: (_) async => WebProfileSaveResult.rejected,
    );
    await tester.enterText(find.byKey(const Key('profile-name')), '仍未保存');
    await tester.pump();
    await tester.ensureVisible(find.text('保存修改'));
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    final pending = controller.confirmDocumentExit();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(await pending, false);
    await tester.pumpWidget(const SizedBox());
  });
}
