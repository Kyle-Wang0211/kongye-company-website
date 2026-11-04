import 'dart:js_interop';

@JS('window.sessionStorage.getItem')
external JSString? _sessionItem(JSString key);

String? openingWorkJson() {
  try {
    return _sessionItem('pw-opening-work-v1'.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}
