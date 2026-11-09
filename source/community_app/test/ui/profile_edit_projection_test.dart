import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/current_user.dart';
import 'package:pocketworld_flutter/auth/mock_auth_service.dart';
import 'package:pocketworld_flutter/community/web_social_api.dart';
import 'package:pocketworld_flutter/ui/social/web_profile_edit_entry.dart';

class _User extends CurrentUser {
  _User() : super(service: MockAuthServiceImpl());
  int refreshes = 0;
  @override
  AuthenticatedUser get signedInUser => const AuthenticatedUser(
    id: InternalUserID('synthetic-owner'),
    displayName: 'Published',
  );
  @override
  Future<bool> refreshProfile() async {
    refreshes++;
    return true;
  }
}

class _Api extends WebSocialApi {
  _Api(this.status)
    : super(
        apiOrigin: null,
        supabaseOrigin: null,
        publishableKey: null,
        region: null,
        authNamespace: null,
        accessToken: () => null,
        currentUserId: () => null,
      );
  final String status;
  bool submitted = false;
  @override
  Future<WebSocialProfile> profile(String id) async => WebSocialProfile(
    id: id,
    displayName: submitted && status == 'approved'
        ? 'Approved new'
        : 'Published',
    bio: '',
    isOwner: true,
    version: submitted ? 2 : 1,
    worksCount: 0,
    likesCount: 0,
    edits: submitted
        ? [
            {'id': 'edit-synthetic', 'status': status},
          ]
        : [],
  );
  @override
  Future<WebProfileEditReceipt> editProfile({
    required int version,
    String? displayName,
    String? handle,
    String? bio,
  }) async {
    submitted = true;
    return WebProfileEditReceipt('edit-synthetic', status);
  }
}

void main() {
  for (final status in ['approved', 'pending', 'rejected']) {
    testWidgets('$status edit refreshes live identity only after approval', (
      tester,
    ) async {
      final user = _User();
      final api = _Api(status);
      await tester.pumpWidget(
        MaterialApp(
          home: WebProfileEditEntry(
            user: user,
            ownerId: 'synthetic-owner',
            api: api,
            backendReady: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Draft new',
      );
      await tester.pumpAndSettle();
      final save = find.text('保存修改');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(api.submitted, true);
      expect(user.refreshes, status == 'approved' ? 1 : 0);
      final published = tester
          .widget<Text>(find.byKey(const Key('approved-name')))
          .data;
      expect(published, status == 'approved' ? 'Approved new' : 'Published');
      await tester.pumpWidget(const SizedBox());
      user.dispose();
      api.close();
    });
  }
}
