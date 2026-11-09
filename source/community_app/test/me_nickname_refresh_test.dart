import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/aether_prefs.dart';
import 'package:pocketworld_flutter/auth/account_workspace.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/auth_scope.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/community/social_profile_models.dart';
import 'package:pocketworld_flutter/community/social_profile_repository.dart';
import 'package:pocketworld_flutter/config/backend_deployment.dart';
import 'package:pocketworld_flutter/l10n/app_localizations.dart';
import 'package:pocketworld_flutter/i18n/locale_notifier.dart';
import 'package:pocketworld_flutter/ui/me_settings_drawer.dart';
import 'package:pocketworld_flutter/me/profile_likes_repository.dart';
import 'package:pocketworld_flutter/me/scan_record_store.dart';
import 'package:pocketworld_flutter/ui/me_page.dart';

class _SignedInUser extends CurrentUser {
  _SignedInUser(this.identity)
    : super(
        service: MockAuthServiceImpl(),
        deployment: BackendDeployment.legacyGlobal,
      );
  final AuthenticatedUser identity;
  @override
  AuthenticatedUser get signedInUser => identity;
}

class _Profiles implements SocialProfileRepository {
  bool fail = true;
  String? nickname;
  int reads = 0;
  final pending = <String, Completer<SocialProfile>>{};
  @override
  Future<SocialProfile> fetchProfile(String id) async {
    reads++;
    if (pending.containsKey(id)) return pending[id]!.future;
    if (fail) throw StateError('controlled failure');
    return SocialProfile(
      id: id,
      displayName: nickname ?? '资料$id',
      handle: null,
      avatarUrl: null,
      bio: null,
      lastRegion: null,
      followersCount: 7,
      followingCount: 9,
      publicWorksCount: 0,
      isFollowing: false,
      isBlockedByViewer: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Likes implements ProfileLikesRepository {
  final pending = <String, Completer<int>>{};
  @override
  Future<int> fetchReceivedLikes(String id) async {
    if (pending.containsKey(id)) return pending[id]!.future;
    return id == 'alice' ? 11 : 2;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  late _Profiles profiles;
  late _Likes likes;
  Future<CurrentUser> user(String id) async {
    await ScanRecordStore.activateAccount(
      AccountWorkspace(deployment: BackendDeployment.legacyGlobal, userId: id),
      documentsDirectory: docs,
    );
    final current = _SignedInUser(
      AuthenticatedUser(id: InternalUserID(id), displayName: '账号$id'),
    );
    addTearDown(current.dispose);
    return current;
  }

  Widget app(CurrentUser current, {bool visible = true}) => AuthScope(
    currentUser: current,
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: MePage(
        isVisible: visible,
        socialProfileRepository: profiles,
        profileLikesRepository: likes,
      ),
    ),
  );
  setUp(() async {
    AetherPrefs.setMockInitialValues({});
    docs = await Directory.systemTemp.createTemp('me-profile-behavior-');
    profiles = _Profiles();
    likes = _Likes();
  });
  tearDown(() async {
    await ScanRecordStore.activateAccount(null);
    await docs.delete(recursive: true);
  });
  testWidgets('closing settings reloads a renamed profile with the same UUID', (
    tester,
  ) async {
    profiles.fail = false;
    final current = (await tester.runAsync(() => user('alice')))!;
    final locale = LocaleNotifier();
    addTearDown(locale.dispose);
    await tester.pumpWidget(LocaleScope(notifier: locale, child: app(current)));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('资料alice'), findsOneWidget);
    final before = profiles.reads;
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(MeSettingsDrawer), findsOneWidget);
    // Simulate the canonical repository value after a successful rename.
    profiles.nickname = '改名后的资料';
    final drawerContext = tester.element(find.byType(MeSettingsDrawer));
    Navigator.of(drawerContext).pop();
    await tester.pumpAndSettle();
    expect(profiles.reads, greaterThan(before));
    expect(find.text('改名后的资料'), findsOneWidget);
    expect(find.text('资料alice'), findsNothing);
  });
  testWidgets('settings rename supersedes an older pending profile read', (
    tester,
  ) async {
    profiles.fail = false;
    final old = Completer<SocialProfile>();
    profiles.pending['alice'] = old;
    final current = (await tester.runAsync(() => user('alice')))!;
    final locale = LocaleNotifier();
    addTearDown(locale.dispose);
    await tester.pumpWidget(LocaleScope(notifier: locale, child: app(current)));
    await tester.pump();
    expect(profiles.reads, 1);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump(const Duration(milliseconds: 300));
    profiles.pending.remove('alice');
    profiles.nickname = 'fresh renamed profile';
    Navigator.of(tester.element(find.byType(MeSettingsDrawer))).pop();
    await tester.pumpAndSettle();
    expect(find.text('fresh renamed profile'), findsOneWidget);
    expect(profiles.reads, 2);
    old.complete(
      const SocialProfile(
        id: 'alice',
        displayName: 'stale delayed profile',
        handle: null,
        avatarUrl: null,
        bio: null,
        lastRegion: null,
        followersCount: 1,
        followingCount: 1,
        publicWorksCount: 0,
        isFollowing: false,
        isBlockedByViewer: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('fresh renamed profile'), findsOneWidget);
    expect(find.text('stale delayed profile'), findsNothing);
  });
}
