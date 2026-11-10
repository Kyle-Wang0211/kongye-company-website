Future<dynamic> loadSelectionBox(String directory, String filename) async =>
    null;

Future<void> saveSelectionBox(
  String directory,
  String filename,
  Map<String, dynamic> json,
) => Future.error(
  UnsupportedError('Local selection files require native storage'),
);
