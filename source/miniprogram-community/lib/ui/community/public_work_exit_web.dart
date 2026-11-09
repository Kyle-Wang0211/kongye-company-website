import 'dart:js_interop';

@JS('window.location.assign')
external void _assignLocation(JSString value);

void openCommunityActivity(int screen) {
  final destination = Uri.base
      .resolve('/screen.html')
      .replace(queryParameters: {'screen': '$screen', 'mini': '1'});
  _assignLocation(destination.toString().toJS);
}

/// Return a direct-linked detail to the same site's community homepage.
/// Do not depend on browser history (the detail can be a new tab).
void exitPublicWork() {
  _assignLocation(
    (Uri.base.queryParameters['feed'] == '1'
            ? Uri.base.replace(queryParameters: {'feed': '1'}, fragment: '')
            : Uri.base.resolve('../'))
        .toString()
        .toJS,
  );
}

@JS('window.location.replace')
external void _replaceLocation(JSString value);

/// Replace the Flutter root so browser Back cannot reopen an empty handoff.
void exitCommunityHome() {
  _replaceLocation(
    (Uri.base.queryParameters['feed'] == '1'
            ? Uri.base.replace(queryParameters: {'feed': '1'}, fragment: '')
            : Uri.base.resolve('../'))
        .toString()
        .toJS,
  );
}

/// Only the two existing community panels are valid cross-page destinations.
void openCommunitySettings() =>
    _assignLocation(Uri.base.resolve('../?panel=settings').toString().toJS);
void openCommunityFollowing() =>
    _assignLocation(Uri.base.resolve('../?panel=following').toString().toJS);
void openCommunityFiling() =>
    _assignLocation('https://beian.miit.gov.cn/'.toJS);
