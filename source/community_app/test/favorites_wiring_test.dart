import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/unavailable_auth_service.dart';
import 'package:pocketworld_flutter/community/web_social_api.dart';
import 'package:pocketworld_flutter/config/backend_deployment.dart';
import 'package:pocketworld_flutter/main_community_web.dart';

const ownerA = '22222222-2222-4222-8222-222222222222';
const ownerB = '33333333-3333-4333-8333-333333333333';
const work = '11111111-1111-4111-8111-111111111111';

class FixtureUser extends CurrentUser {
  FixtureUser()
    : super(
        service: const UnavailableAuthService(),
        deployment: const BackendDeployment(
          region: BackendRegion.china,
          id: 'cn-primary',
          supabaseUrl: 'https://api.kongye.space',
          anonKey: 'fixture-public',
        ),
      );
  AuthenticatedUser? identity = const AuthenticatedUser(
    id: InternalUserID(ownerA),
  );
  @override
  AuthenticatedUser? get signedInUser => identity;
}

class FixtureApi extends WebSocialApi {
  FixtureApi()
    : super(
        apiOrigin: Uri.parse('https://api.kongye.space'),
        supabaseOrigin: null,
        publishableKey: null,
        region: 'china',
        authNamespace: null,
        accessToken: () => null,
        currentUserId: () => null,
        favoritesEnabled: true,
      );
  final loads = <WebFavoriteCursor?>[];
  Completer<WebFavoritePage>? pendingLoad;
  Completer<bool>? pendingRemoval;
  final mutations = <bool>[];
  @override
  Future<WebFavoritePage> listFavorites({
    int limit = 30,
    WebFavoriteCursor? before,
  }) async {
    expect(limit, 100);
    loads.add(before);
    if (pendingLoad != null) return pendingLoad!.future;
    return const WebFavoritePage([
      WebFavorite(work, ownerB, 'Saved fixture', '2026-11-05T00:00:00Z'),
    ], null);
  }

  @override
  Future<bool> setFavorite(String id, bool saved) {
    expect(id, work);
    mutations.add(saved);
    return pendingRemoval?.future ?? Future.value(saved);
  }
}

void main() {
  testWidgets(
    'favorites route waits for Auth bootstrap before exposing a login form',
    (tester) async {
      final user = FixtureUser();
      user.identity = null;
      await tester.pumpWidget(
        MaterialApp(
          home: const SizedBox.shrink(),
          initialRoute: '/favorites',
          onGenerateRoute: (settings) =>
              communityFavoritesRoute(settings, user),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      user.dispose();
    },
  );

  testWidgets(
    'account entry loads existing API and waits for confirmed cancellation',
    (tester) async {
      final user = FixtureUser();
      final api = FixtureApi();
      final removal = Completer<bool>();
      api.pendingRemoval = removal;
      await tester.pumpWidget(
        MaterialApp(
          home: WebFavoritesAccountEntry(user: user, ownerId: ownerA, api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved fixture'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('remove-favorite-$work')));
      await tester.pump();
      expect(find.text('Saved fixture'), findsOneWidget);
      expect(api.mutations, [false]);
      removal.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('No favorites yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
      user.dispose();
    },
  );
  testWidgets(
    'old account entry discards late list after route identity changes',
    (tester) async {
      final user = FixtureUser();
      final oldApi = FixtureApi();
      final pending = Completer<WebFavoritePage>();
      oldApi.pendingLoad = pending;
      await tester.pumpWidget(
        MaterialApp(
          home: WebFavoritesAccountEntry(
            key: const ValueKey(ownerA),
            user: user,
            ownerId: ownerA,
            api: oldApi,
          ),
        ),
      );
      await tester.pump();
      user.identity = const AuthenticatedUser(id: InternalUserID(ownerB));
      final newApi = FixtureApi();
      await tester.pumpWidget(
        MaterialApp(
          home: WebFavoritesAccountEntry(
            key: const ValueKey(ownerB),
            user: user,
            ownerId: ownerB,
            api: newApi,
          ),
        ),
      );
      await tester.pumpAndSettle();
      pending.complete(
        const WebFavoritePage([
          WebFavorite(
            work,
            ownerB,
            'Old private title',
            '2026-11-05T00:00:00Z',
          ),
        ], null),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old private title'), findsNothing);
      expect(find.text('Saved fixture'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      oldApi.close();
      newApi.close();
      user.dispose();
    },
  );
}
