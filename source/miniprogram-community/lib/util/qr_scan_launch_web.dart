import 'dart:js_interop';

@JS('window.__wxjs_environment')
external JSString? get _environment;
@JS('window.navigator.userAgent')
external JSString get _userAgent;
@JS('window.wx.miniProgram.navigateTo')
external void _navigate(JSAny options);

bool get qrScanAvailable =>
    _environment?.toDart == 'miniprogram' ||
    _userAgent.toDart.toLowerCase().contains('miniprogram');

void openQrScanner() => _navigate({'url': '/pages/qr-scan/index'}.jsify()!);
