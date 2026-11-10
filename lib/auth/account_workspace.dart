import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../config/backend_deployment.dart';

/// Immutable local ownership boundary. Neither credentials nor user IDs occur
/// in directory names; the versioned tuple cannot collide through delimiters.
@immutable
class AccountWorkspace {
  factory AccountWorkspace({
    required BackendDeployment deployment,
    required String userId,
  }) {
    deployment.validate();
    if (userId.isEmpty ||
        userId.trim() != userId ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(userId)) {
      throw ArgumentError.value(userId, 'userId', 'Invalid account identity');
    }
    final frozen = BackendDeployment(
      region: deployment.region,
      id: deployment.id,
      supabaseUrl: deployment.supabaseUrl,
      anonKey: deployment.anonKey,
      configEndpoints: List.unmodifiable(deployment.configEndpoints),
      publicCdnOrigins: List.unmodifiable(deployment.publicCdnOrigins),
    );
    final canonical = jsonEncode([
      'pocketworld.account.v1',
      deployment.region.name,
      deployment.id,
      Uri.parse(deployment.supabaseUrl).origin,
      userId,
    ]);
    return AccountWorkspace._(
      frozen,
      userId,
      sha256.convert(utf8.encode(canonical)).toString(),
    );
  }

  const AccountWorkspace._(this.deployment, this.userId, this.namespace);
  final BackendDeployment deployment;
  final String userId;
  final String namespace;

  @override
  bool operator ==(Object other) =>
      other is AccountWorkspace && namespace == other.namespace;
  @override
  int get hashCode => namespace.hashCode;
}
