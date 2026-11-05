// Native account/local-file retention is unavailable in a browser.
// Remote/community viewers never construct a local binding and retain their existing path.
import 'package:pw_shared_viewer/pw_shared_viewer.dart';

Never _unsupported() =>
    throw UnsupportedError('Native local-work retention is unavailable on Web');

abstract interface class UnavailableLocalStore {
  bool get isActive;
  void Function() addRevocationListener(void Function() listener);
}

abstract class LocalWorkViewerBinding {
  UnavailableLocalStore get store => _unsupported();
  bool get canRetain => false;
  bool matchesLocalReference(String? value) => _unsupported();
  bool sameSource(LocalWorkViewerBinding? other) => _unsupported();
}

class LocalWorkViewerSessions {
  static final instance = LocalWorkViewerSessions();
  Future<LocalWorkViewerLease?> adoptLoaded({
    required LocalWorkViewerBinding binding,
    required LocalWorkLoadedSource source,
    required bool Function() isCurrent,
  }) async => null;
  Future<LocalWorkViewerLease?> acquire(LocalWorkViewerBinding binding) =>
      Future.error(
        UnsupportedError('Native local-work retention is unavailable on Web'),
      );
}

abstract class LocalWorkViewerLease {
  bool get isValid => false;
  SharedViewerController get controller => _unsupported();
  SharedViewerRetainedSession get retainedSession => _unsupported();
  bool get hasLoadedScene => _unsupported();
  String get canonicalPath => _unsupported();
  Future<bool> verifyLoadedScene(SharedModelFormat format) => _unsupported();
  Future<void> ensureLoaded(Future<void> Function() load) => _unsupported();
  void release() => _unsupported();
}

abstract class LocalWorkLoadedSource {
  String get canonicalPath => _unsupported();
  String get fileIdentity => _unsupported();
  SharedModelFormat get format => _unsupported();
  SharedViewerController get controller => _unsupported();
  SharedViewerRetainedSession get retainedSession => _unsupported();
  bool get isCurrent => false;
  bool get matchesCurrentFile => false;
}

abstract class LocalWorkPendingSource {
  static LocalWorkPendingSource? capture({
    required String reference,
    required SharedModelFormat format,
    required SharedViewerController controller,
    required SharedViewerRetainedSession retainedSession,
    required bool Function() isCurrent,
  }) => _unsupported();
  LocalWorkLoadedSource? complete() => _unsupported();
}
