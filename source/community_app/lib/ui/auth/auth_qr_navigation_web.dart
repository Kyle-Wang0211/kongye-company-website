import 'dart:js_interop';

@JS('window.location.assign')
external void _assignLocation(JSString value);

void openQrLogin({required String language, String? returnTo}) {
  final target = Uri.base
      .resolve('/login/')
      .replace(
        queryParameters: {
          'method': 'qr',
          'lang': language,
          'returnTo': ?returnTo,
        },
      );
  _assignLocation(target.toString().toJS);
}
