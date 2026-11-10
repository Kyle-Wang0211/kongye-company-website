import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-account, per-work preferences on the current device or browser.
/// Independent comment keys avoid overwriting concurrent changes to other rows.
class CommentVisibilityStore {
  const CommentVisibilityStore();

  String _prefix(String scope) =>
      'community.comment.hidden.v1.${sha256.convert(utf8.encode(scope))}.';

  Future<Set<String>> read(String scope) async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = _prefix(scope);
    return preferences
        .getKeys()
        .where((key) {
          return key.startsWith(prefix) && preferences.getBool(key) == true;
        })
        .map((key) => key.substring(prefix.length))
        .toSet();
  }

  Future<void> setHidden(String scope, String commentId, bool hidden) async {
    final preferences = await SharedPreferences.getInstance();
    final key = '${_prefix(scope)}$commentId';
    final saved = hidden
        ? await preferences.setBool(key, true)
        : await preferences.remove(key);
    if (!saved) throw StateError('Unable to save comment visibility');
  }
}
