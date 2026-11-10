/// Browser effects are isolated so nonce/replay/lifecycle tests use no web APIs.
abstract interface class WechatSignInPort {
  bool get available;
  String? readPending();
  void writePending(String value);
  void clearPending();

  /// Removes callback credentials from the address bar before returning them.
  String takeFragment();
  bool navigate(String state);
}
