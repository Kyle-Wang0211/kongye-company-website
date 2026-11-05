import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/unavailable_auth_service.dart';
import 'package:pocketworld_flutter/community/web_social_api.dart';
import 'package:pocketworld_flutter/ui/social/web_profile_edit_entry.dart';

class Owner extends CurrentUser {
  Owner() : super(service: const UnavailableAuthService());
  AuthenticatedUser? identity = const AuthenticatedUser(
    id: InternalUserID('owner'),
  );
  @override
  AuthenticatedUser? get signedInUser => identity;
  void leave() {
    identity = null;
    notifyListeners();
  }
}

WebSocialProfile projection({
  String name = '原昵称',
  int version = 0,
  String? status,
  String editId = 'edit',
  bool owner = true,
}) => WebSocialProfile(
  id: 'owner',
  displayName: name,
  bio: '原简介',
  isOwner: owner,
  version: owner ? version : null,
  worksCount: 0,
  likesCount: 0,
  edits: status == null
      ? []
      : [
          {'id': editId, 'status': status},
        ],
);

class ProfileApi extends WebSocialApi {
  ProfileApi()
    : super(
        apiOrigin: Uri.https('api.example.test'),
        supabaseOrigin: null,
        publishableKey: null,
        region: null,
        authNamespace: null,
        accessToken: () => 'test-only',
        currentUserId: () => 'owner',
        profilesEnabled: true,
      );
  WebSocialProfile value = projection();
  int reads = 0, writes = 0;
  int? submittedVersion;
  Object? failure;
  Completer<WebProfileEditReceipt>? pending;
  @override
  Future<WebSocialProfile> profile(String userId) async {
    reads++;
    return value;
  }

  @override
  Future<WebProfileEditReceipt> editProfile({
    required int version,
    String? displayName,
    String? handle,
    String? bio,
  }) async {
    writes++;
    submittedVersion = version;
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    value = projection(status: 'pending');
    return const WebProfileEditReceipt('edit', 'pending');
  }
}

Future<void> open(
  WidgetTester tester,
  Owner owner,
  ProfileApi api, {
  bool ready = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: WebProfileEditEntry(
        user: owner,
        ownerId: 'owner',
        api: api,
        backendReady: ready,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> submit(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('profile-name')), '新昵称');
  await tester.pump();
  await tester.ensureVisible(find.text('保存修改'));
  await tester.tap(find.text('保存修改'));
  await tester.pump();
}

Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('default OFF does not read or write the injected backend', (
    tester,
  ) async {
    final owner = Owner();
    final api = ProfileApi();
    addTearDown(owner.dispose);
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: WebProfileEditEntry(user: owner, ownerId: 'owner', api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('个人资料编辑暂未开放。'), findsOneWidget);
    expect(api.reads, 0);
    expect(api.writes, 0);
  });

  testWidgets(
    'pending exact receipt becomes approved only after server projection',
    (tester) async {
      final owner = Owner();
      final api = ProfileApi();
      addTearDown(owner.dispose);
      addTearDown(api.close);
      await open(tester, owner, api);
      await submit(tester);
      await tester.pump();
      expect(api.writes, 1);
      expect(api.submittedVersion, 0);
      expect(
        tester.widget<Text>(find.byKey(const Key('approved-name'))).data,
        '原昵称',
      );
      api.value = projection(name: '新昵称', version: 1, status: 'approved');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('approved-name'))).data,
        '新昵称',
      );
      expect(find.text('个人资料已更新'), findsOneWidget);
      expect(api.writes, 1);
      await close(tester);
    },
  );

  testWidgets('technical retry is distinct from review and never resubmits', (
    tester,
  ) async {
    final owner = Owner();
    final api = ProfileApi();
    addTearDown(owner.dispose);
    addTearDown(api.close);
    await open(tester, owner, api);
    await submit(tester);
    await tester.pump();
    api.value = projection(status: 'retry');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('审核服务暂时繁忙，系统将自动重试。'), findsOneWidget);
    expect(find.textContaining('进一步审核'), findsNothing);
    api.value = projection(status: 'review');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.textContaining('进一步审核'), findsOneWidget);
    expect(api.writes, 1);
    await close(tester);
  });

  testWidgets(
    'unknown outcome blocks another POST and refresh stays read-only',
    (tester) async {
      final owner = Owner();
      final api = ProfileApi()
        ..failure = const WebSocialUnavailableException(
          'transport_unavailable',
        );
      addTearDown(owner.dispose);
      addTearDown(api.close);
      await open(tester, owner, api);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('提交结果待确认'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('刷新审核状态'));
      await tester.pumpAndSettle();
      expect(api.reads, greaterThan(1));
      expect(api.writes, 1);
      await close(tester);
    },
  );

  testWidgets('version conflict refreshes version and preserves unsent draft', (
    tester,
  ) async {
    final owner = Owner();
    final api = ProfileApi();
    addTearDown(owner.dispose);
    addTearDown(api.close);
    await open(tester, owner, api);
    api.value = projection(name: '另一页面昵称', version: 2);
    api.failure = const WebSocialRequestException(409);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('其他页面更新'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('profile-name')))
          .controller!
          .text,
      '新昵称',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('approved-name'))).data,
      '另一页面昵称',
    );
    api.failure = null;
    await tester.ensureVisible(find.text('保存修改'));
    await tester.tap(find.text('保存修改'));
    await tester.pump();
    await tester.pump();
    expect(api.submittedVersion, 2);
    await close(tester);
  });

  testWidgets(
    'logout during a POST removes draft and ignores delayed receipt',
    (tester) async {
      final owner = Owner();
      final api = ProfileApi()..pending = Completer<WebProfileEditReceipt>();
      addTearDown(owner.dispose);
      addTearDown(api.close);
      await open(tester, owner, api);
      await submit(tester);
      owner.leave();
      await tester.pumpAndSettle();
      expect(find.text('会话已结束，请重新登录。'), findsOneWidget);
      api.pending!.complete(const WebProfileEditReceipt('edit', 'approved'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-name')), findsNothing);
      expect(find.text('个人资料已更新'), findsNothing);
      expect(api.writes, 1);
    },
  );

  testWidgets('foreign projection never opens an editor', (tester) async {
    final owner = Owner();
    final api = ProfileApi()..value = projection(owner: false);
    addTearDown(owner.dispose);
    addTearDown(api.close);
    await open(tester, owner, api);
    expect(find.byKey(const Key('profile-name')), findsNothing);
    expect(find.textContaining('暂时无法读取'), findsOneWidget);
    expect(api.writes, 0);
  });
}
