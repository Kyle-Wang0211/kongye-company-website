import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';

typedef _StartNative = Uint64 Function();
typedef _Start = int Function();
typedef _StatusNative = Int32 Function(Uint64);
typedef _Status = int Function(int);
typedef _ErrorNative = Pointer<Uint8> Function(Uint64);
typedef _Error = Pointer<Uint8> Function(int);

const _frameworkRelativePath =
    'Frameworks/PWSharedWebViewBridge.framework/PWSharedWebViewBridge';
const _maximumWait = Duration(seconds: 10);

/// Optional compatibility route for a host whose Runner must remain unchanged.
/// Empty defines preserve normal native plugin registration on every platform.
final nativeWebViewBootstrap = NativeWebViewBootstrap(
  isIOS: Platform.isIOS,
  expectedRawSha256:
      const String.fromEnvironment('PW_IOS_WEBVIEW_BRIDGE_SHA256'),
);

/// Coalesces only an outstanding registration; completed results are never cached.
/// The injectable boundary tests ordering and errors, not actual native success.
class NativeWebViewBootstrap {
  NativeWebViewBootstrap({
    required bool isIOS,
    required String expectedRawSha256,
    Future<void> Function(String expectedRawSha256)? register,
  })  : _expectedRawSha256 = expectedRawSha256,
        requiresRegistration = isIOS && expectedRawSha256.isNotEmpty,
        _register = register ?? _registerNative;

  final String _expectedRawSha256;
  final bool requiresRegistration;
  final Future<void> Function(String) _register;
  Future<void>? _inFlight;

  Future<void> ensureRegistered() {
    if (!requiresRegistration) return Future<void>.value();
    return _inFlight ??= Future<void>.sync(
      () => _register(_expectedRawSha256),
    ).whenComplete(() {
      _inFlight = null;
    });
  }

  /// The native host uses this boundary for every WebView controller creation.
  Future<T?> createController<T>({
    required T Function() create,
    required bool Function() isDisposed,
  }) async {
    if (isDisposed()) return null;
    await ensureRegistered();
    if (isDisposed()) return null;
    return create();
  }
}

Future<void> _registerNative(String expectedRawSha256) =>
    ensureNativeWebViewRegistered(expectedRawSha256: expectedRawSha256);

/// Verifies the final bundled bridge binary, then registers the official plugin.
///
/// Call before creating any WebView controller. The hash must come from the
/// approved, final signed candidate's raw bridge Mach-O bytes. This function
/// never caches registration success; every call revalidates the attached engine.
Future<void> ensureNativeWebViewRegistered({
  required String expectedRawSha256,
}) async {
  if (!Platform.isIOS) {
    throw UnsupportedError('The native WebView bootstrap supports iOS only.');
  }
  final expected = expectedRawSha256.toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
    throw ArgumentError.value(
      expectedRawSha256,
      'expectedRawSha256',
      'Expected a complete SHA-256 digest.',
    );
  }

  final elapsed = Stopwatch()..start();
  final binary = File.fromUri(
    File(Platform.resolvedExecutable)
        .parent
        .uri
        .resolve(_frameworkRelativePath),
  );
  final actual =
      await sha256.bind(binary.openRead()).first.timeout(_maximumWait);
  if (actual.toString() != expected) {
    throw StateError(
      'Bundled WebView bridge SHA-256 does not match the candidate.',
    );
  }
  _checkDeadline(elapsed);

  // dyld resolves @executable_path inside the current signed app bundle.
  final library = DynamicLibrary.open(
    '@executable_path/$_frameworkRelativePath',
  );
  final start = library.lookupFunction<_StartNative, _Start>(
    'pw_shared_webview_register_start',
  );
  final status = library.lookupFunction<_StatusNative, _Status>(
    'pw_shared_webview_register_status',
  );
  final error = library.lookupFunction<_ErrorNative, _Error>(
    'pw_shared_webview_register_error',
  );
  _checkDeadline(elapsed);
  final requestID = start();
  if (requestID == 0) {
    throw StateError(
      'WebView registration is busy or request IDs are exhausted.',
    );
  }

  while (true) {
    _checkDeadline(elapsed);
    final result = status(requestID);
    if (result == 1) {
      return;
    }
    if (result < 0) {
      throw StateError(
        'WebView registration failed ($result): '
        '${_readStaticError(error(requestID))}',
      );
    }
    if (result != 0) {
      throw StateError('WebView bridge returned an unknown status: $result');
    }
    final remaining = _maximumWait - elapsed.elapsed;
    await Future<void>.delayed(
      remaining < const Duration(milliseconds: 20)
          ? remaining
          : const Duration(milliseconds: 20),
    );
  }
}

void _checkDeadline(Stopwatch elapsed) {
  if (elapsed.elapsed >= _maximumWait) {
    throw TimeoutException(
      'WebView native registration timed out.',
      _maximumWait,
    );
  }
}

String _readStaticError(Pointer<Uint8> pointer) {
  if (pointer == nullptr) {
    return 'bridge returned a null error pointer';
  }
  final bytes = <int>[];
  for (var index = 0; index < 512; index++) {
    final value = pointer[index];
    if (value == 0) {
      return String.fromCharCodes(bytes);
    }
    bytes.add(value);
  }
  return 'bridge returned an unterminated error string';
}
