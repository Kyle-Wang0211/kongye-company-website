import 'dart:convert';
import 'dart:io';

Future<dynamic> loadSelectionBox(String directory, String filename) async {
  try {
    final file = File('$directory/$filename');
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  } catch (_) {
    return null;
  }
}

Future<void> saveSelectionBox(
  String directory,
  String filename,
  Map<String, dynamic> json,
) async {
  final file = File('$directory/$filename');
  await file.writeAsString(jsonEncode(json), flush: true);
}
