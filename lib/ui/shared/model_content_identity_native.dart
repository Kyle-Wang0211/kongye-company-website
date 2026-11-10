import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Hash the exact local GLB input off the UI isolate, without retaining its bytes.
/// An unreadable or changing input has no usable identity.
Future<String?> modelFileSha256(String path) async {
  try {
    return await Isolate.run(() async {
      final file = File(path);
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file) return null;
      final digest = await sha256.bind(file.openRead()).first;
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified) {
        return null;
      }
      return digest.toString();
    });
  } catch (_) {
    return null;
  }
}
