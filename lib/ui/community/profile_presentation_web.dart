import 'dart:js_interop';

@JS('window.localStorage.setItem')
external void _store(JSString key, JSString value);

/// Invalidation carries no draft name, token or profile data. Receivers re-read
/// their canonical public projection with their own authorization.
void notifyProfilePresentationChanged(String userId) {
  try {
    _store(
      'pw-profile-presentation-changed-v1'.toJS,
      '$userId:${DateTime.now().microsecondsSinceEpoch}'.toJS,
    );
  } catch (_) {
    /* Storage-disabled browsers refresh on focus/return. */
  }
}
