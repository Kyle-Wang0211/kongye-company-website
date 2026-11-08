import 'dart:js_interop';
import '../auth/wechat_sign_in_port.dart';

@JS('window.sessionStorage.getItem')
external JSString? _get(JSString key);
@JS('window.sessionStorage.setItem')
external void _set(JSString key, JSString value);
@JS('window.sessionStorage.removeItem')
external void _remove(JSString key);
@JS('window.location.href')
external JSString get _href;
@JS('window.history.replaceState')
external void _replace(JSAny? state, JSString title, JSString url);
@JS('window.__wxjs_environment')
external JSString? get _environment;
@JS('window.navigator.userAgent')
external JSString get _userAgent;
@JS('window.pwWechatSignInNavigate')
external JSBoolean _navigate(JSString state);

WechatSignInPort createWechatSignInPort() => _Browser();

class _Browser implements WechatSignInPort {
  static const _key = 'pocketworld.wechat.signIn.pending.v1';
  @override
  bool get available {
    try {
      return Uri.parse(_href.toDart).queryParameters['feed'] == '1' &&
          (_environment?.toDart == 'miniprogram' ||
              _userAgent.toDart.toLowerCase().contains('miniprogram'));
    } catch (_) {
      return false;
    }
  }

  @override
  String? readPending() => _get(_key.toJS)?.toDart;
  @override
  void writePending(String value) => _set(_key.toJS, value.toJS);
  @override
  void clearPending() => _remove(_key.toJS);
  @override
  String takeFragment() {
    final uri = Uri.parse(_href.toDart);
    final fragment = uri.fragment;
    if (RegExp(r'(^|&)wechat_(code|state|error)(=|&|$)').hasMatch(fragment)) {
      _replace(null, ''.toJS, uri.replace(fragment: '').toString().toJS);
      return fragment;
    }
    return '';
  }

  @override
  bool navigate(String state) => _navigate(state.toJS).toDart;
}
