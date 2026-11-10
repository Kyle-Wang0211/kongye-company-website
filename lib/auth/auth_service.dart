// Dart port of Core/Auth/AuthService.swift — provider-agnostic protocol.
// Concrete implementations: firebase_auth_service.dart / mock_auth_service.dart.

import 'auth_models.dart';

abstract class AuthService {
  /// Currently signed-in user, or null if signed out.
  Future<AuthenticatedUser?> currentUser();

  /// Sign in with an existing account. Throws `AuthException` on failure.
  Future<AuthenticatedUser> signIn(SignInRequest request);

  /// Create a new account. Throws `AuthException` on failure.
  Future<AuthenticatedUser> signUp(SignUpRequest request);

  /// Send a login OTP for an existing phone account. Signup uses
  /// startPhoneSignup so an account is never created without a password.
  Future<PhoneVerificationChallenge> startPhoneVerification(
    String phoneNumber, {
    bool forSignUp = false,
  });

  Future<PhoneVerificationChallenge> startPhoneSignup({
    required String phoneNumber,
    required String password,
    String? displayName,
  });

  /// Resend email verification link to the currently-signed-in user.
  Future<void> sendEmailVerification();

  /// Resend the native signup OTP without storing or resending a password.
  Future<void> resendEmailOtp({required String email});

  /// Verify the native signup OTP and establish its authenticated session.
  Future<AuthenticatedUser> verifyEmailSignupOtp({
    required String email,
    required String token,
  });

  /// Start password-reset email flow for a given email. With the
  /// Supabase "Reset password" template configured to render `{{ .Token }}`,
  /// this sends a 6-digit OTP rather than a clickable link.
  Future<void> sendPasswordReset(String email);

  /// Validate the recovery code without creating a login session. Returns a
  /// short-lived, single-use credential restricted to completing this reset.
  Future<String> verifyPasswordResetCode({
    required String email,
    required String token,
  });

  /// Set a password using the verified recovery credential. Does not sign in.
  Future<void> completePasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
  });

  /// Drop the current session locally and in the provider.
  Future<void> signOut();

  /// Delete the user's account at the provider AND clear local state.
  /// Irreversible.
  Future<void> deleteAccount();

  /// Update the signed-in user's canonical profile display name through the
  /// authenticated name endpoint. Returns the refreshed
  /// AuthenticatedUser so callers can drop the new value into local
  /// state without a re-sign-in. Throws AuthException on failure
  /// (network / not signed in / provider error).
  Future<AuthenticatedUser> updateDisplayName(String displayName);

  /// Set the signed-in user's unique handle (the "@" style identifier).
  ///
  /// Two-track naming, mirroring Discord / WeChat:
  ///   · displayName — repeatable, Chinese/emoji allowed, shown everywhere
  ///   · handle      — globally unique, lowercase ASCII, lets people find you
  ///
  /// Returns nothing: handle does not live on [AuthenticatedUser] (which is
  /// built from the auth session's metadata, and handle lives in
  /// public.profiles). Read it back through MeStatsViewModel.
  ///
  /// Throws AuthException on failure — including the ones only the server can
  /// decide: handle already taken, reserved name, rename cooldown.
  Future<void> updateHandle(String handle);
}

/// Optional capability for presentation refreshes that must never use cached
/// provider metadata as a substitute for a canonical profile read.
abstract interface class CanonicalProfileReader {
  Future<AuthenticatedUser?> currentCanonicalProfile();
}
