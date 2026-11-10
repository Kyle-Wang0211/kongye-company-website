/// Deployment readiness contracts shared by browser and phone builds.
/// A capability requires explicit verification for the selected backend.
abstract final class CommunityCapabilities {
  static const favorites = bool.fromEnvironment(
    'PW_COMMUNITY_FAVORITES_ENABLED',
    defaultValue: bool.fromEnvironment('PW_WEB_FAVORITES_ENABLED'),
  );
  static const messaging = bool.fromEnvironment(
    'PW_COMMUNITY_MESSAGING_READY',
    defaultValue: bool.fromEnvironment('PW_WEB_MESSAGING_READY'),
  );
  static const profiles = bool.fromEnvironment(
    'PW_COMMUNITY_PROFILES_ENABLED',
    defaultValue: bool.fromEnvironment('PW_WEB_PROFILES_ENABLED'),
  );
}
