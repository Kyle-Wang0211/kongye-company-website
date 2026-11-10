import 'package:flutter/widgets.dart';
import '../../auth/auth_scope.dart';

/// A published owner profile refresh repaints existing author labels. Other
/// authors retain the server projection carried by their feed/comment row.
String currentAuthorName(
  BuildContext context,
  String authorId,
  String fallback,
) {
  final current = context
      .dependOnInheritedWidgetOfExactType<AuthScope>()
      ?.notifier
      ?.signedInUser;
  final name = current?.displayName?.trim();
  return current?.id.rawValue == authorId && name != null && name.isNotEmpty
      ? name
      : fallback;
}
