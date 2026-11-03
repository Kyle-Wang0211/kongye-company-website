import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'generated_avatar.dart';

class GeneratedAvatarSession {
  const GeneratedAvatarSession({
    required this.deploymentId,
    required this.viewerUserId,
  });
  final String deploymentId;
  final String viewerUserId;
  @override
  bool operator ==(Object other) =>
      other is GeneratedAvatarSession &&
      deploymentId == other.deploymentId &&
      viewerUserId == other.viewerUserId;
  @override
  int get hashCode => Object.hash(deploymentId, viewerUserId);
}

abstract interface class GeneratedAvatarBackend {
  /// Self ensure sends no account selector. Other reads use existing caller-bound
  /// profile or owned-block-list authorization, never a service-role client read.
  Future<GeneratedAvatarImage?> loadAccount(
    String targetUserId, {
    required GeneratedAvatarSession session,
    required bool fromBlockedList,
  });
}

/// Public reads return only existing official PNGs for publicly visible authors.
/// This separate capability does not widen private/profile/blocked reads.
abstract interface class GeneratedAvatarPublicBackend {
  Future<GeneratedAvatarImage?> loadPublicAccount(String targetUserId);
}

class SupabaseGeneratedAvatarBackend
    implements GeneratedAvatarBackend, GeneratedAvatarPublicBackend {
  @override
  Future<GeneratedAvatarImage?> loadPublicAccount(String targetUserId) async {
    final client = Supabase.instance.client;
    final viewer = client.auth.currentUser?.id;
    final response = await client.functions.invoke(
      'read-generated-avatar',
      body: <String, Object>{
        'profile_user_id': targetUserId,
        'context': 'public',
      },
    );
    if (!identical(Supabase.instance.client, client) ||
        client.auth.currentUser?.id != viewer ||
        response.status != 200 ||
        response.data is! Map) {
      return null;
    }
    return GeneratedAvatarImage.tryParse(response.data['avatar']);
  }

  @override
  Future<GeneratedAvatarImage?> loadAccount(
    String targetUserId, {
    required GeneratedAvatarSession session,
    required bool fromBlockedList,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser?.id != session.viewerUserId) return null;
    final self = targetUserId == session.viewerUserId;
    final response = await client.functions.invoke(
      self ? 'ensure-generated-avatar' : 'read-generated-avatar',
      body: self
          ? const <String, Object>{}
          : <String, Object>{
              'profile_user_id': targetUserId,
              'context': fromBlockedList ? 'blocked' : 'profile',
            },
    );
    if (!identical(Supabase.instance.client, client) ||
        client.auth.currentUser?.id != session.viewerUserId ||
        response.status != 200 ||
        response.data is! Map) {
      return null;
    }
    return GeneratedAvatarImage.tryParse(response.data['avatar']);
  }
}

/// Disk cache and in-flight work are partitioned by viewer, target, deployment,
/// generator version and read context. Identity is rechecked around every await.
class GeneratedAvatarRepository {
  GeneratedAvatarRepository({
    required this.directory,
    required this.backend,
    required this.currentSession,
  });
  factory GeneratedAvatarRepository.forSession(
    GeneratedAvatarSession? Function() currentSession,
  ) => GeneratedAvatarRepository(
    directory: () async => Directory(
      '${(await getApplicationCacheDirectory()).path}/generated_avatars_v2',
    ),
    backend: SupabaseGeneratedAvatarBackend(),
    currentSession: currentSession,
  );
  final Future<Directory> Function() directory;
  final GeneratedAvatarBackend backend;
  final GeneratedAvatarSession? Function() currentSession;
  final _pending = <String, Future<GeneratedAvatarImage?>>{};
  bool _current(GeneratedAvatarSession? expected) {
    try {
      return currentSession() == expected;
    } catch (_) {
      return false;
    }
  }

  Future<GeneratedAvatarImage?> load({
    required String deploymentId,
    required String userId,
    GeneratedAvatarImage? supplied,
    bool fromBlockedList = false,
    bool readPublic = false,
  }) {
    GeneratedAvatarSession? session;
    try {
      session = currentSession();
    } catch (_) {
      return Future.value(null);
    }
    if (deploymentId.trim().isEmpty ||
        userId.trim().isEmpty ||
        (session != null && session.deploymentId != deploymentId) ||
        (readPublic && fromBlockedList) ||
        (!readPublic &&
            (session == null || session.viewerUserId.trim().isEmpty))) {
      return Future.value(null);
    }
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              GeneratedAvatarImage.version,
              deploymentId,
              session?.viewerUserId ?? 'guest',
              userId,
              readPublic
                  ? 'public'
                  : fromBlockedList
                  ? 'blocked'
                  : 'profile',
            ]),
          ),
        )
        .toString();
    if (supplied != null) return _saveAndReturn(key, supplied, session);
    final expected = session;
    return _pending.putIfAbsent(
      key,
      () => _load(key, userId, fromBlockedList, expected, readPublic)
          .whenComplete(() {
            _pending.remove(key);
          }),
    );
  }

  Future<GeneratedAvatarImage?> _load(
    String key,
    String userId,
    bool blocked,
    GeneratedAvatarSession? session,
    bool readPublic,
  ) async {
    if (!_current(session)) return null;
    try {
      final folder = await directory();
      if (!_current(session)) return null;
      final file = File('${folder.path}/$key.json');
      if (await file.exists()) {
        final cached = GeneratedAvatarImage.tryParse(
          jsonDecode(await file.readAsString()),
        );
        if (!_current(session)) return null;
        if (cached != null) return cached;
      }
    } catch (_) {
      /* No reset or rotation is reachable on a cache failure. */
    }
    if (!_current(session)) return null;
    try {
      final GeneratedAvatarImage? image;
      if (readPublic) {
        final publicBackend = backend;
        if (publicBackend is! GeneratedAvatarPublicBackend) return null;
        image = await (publicBackend as GeneratedAvatarPublicBackend)
            .loadPublicAccount(userId);
      } else {
        image = await backend.loadAccount(
          userId,
          session: session!,
          fromBlockedList: blocked,
        );
      }
      if (!_current(session) || image == null) return null;
      return await _saveAndReturn(key, image, session);
    } catch (_) {
      return null;
    }
  }

  Future<GeneratedAvatarImage?> _saveAndReturn(
    String key,
    GeneratedAvatarImage image,
    GeneratedAvatarSession? session,
  ) async {
    if (!_current(session)) return null;
    File? temporary;
    try {
      final folder = await directory();
      if (!_current(session)) return null;
      await folder.create(recursive: true);
      if (!_current(session)) return null;
      final nonce = Random.secure().nextInt(0x100000000).toRadixString(16);
      temporary = File('${folder.path}/$key.$nonce.tmp');
      await temporary.writeAsString(jsonEncode(image.toJson()), flush: true);
      if (!_current(session)) {
        await temporary.delete();
        return null;
      }
      final saved = await temporary.rename('${folder.path}/$key.json');
      if (!_current(session)) {
        await saved.delete();
        return null;
      }
    } catch (_) {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
    }
    return _current(session) ? image : null;
  }
}
