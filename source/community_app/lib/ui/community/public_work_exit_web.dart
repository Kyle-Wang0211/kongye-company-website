import 'dart:js_interop';

@JS('window.location.assign')
external void _assignLocation(JSString value);

/// Return a direct-linked detail to the same site's community homepage.
/// Do not depend on browser history (the detail can be a new tab).
void exitPublicWork() {
  _assignLocation(Uri.base.resolve('../').toString().toJS);
}
