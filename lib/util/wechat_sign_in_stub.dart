import '../auth/wechat_sign_in_port.dart';

WechatSignInPort createWechatSignInPort() => _Unavailable();

class _Unavailable implements WechatSignInPort {
  @override
  bool get available => false;
  @override
  String? readPending() => null;
  @override
  void writePending(String value) {}
  @override
  void clearPending() {}
  @override
  String takeFragment() => '';
  @override
  bool navigate(String state) => false;
}
