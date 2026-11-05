import 'dart:convert';

import 'package:flutter/material.dart';

import '../../community/feed_models.dart';
import '../../community/publication_cover_url.dart';
import '../splash_solving_orb.dart';
import 'public_work_handoff_stub.dart'
    if (dart.library.js_interop) 'public_work_handoff_web.dart';
import 'public_work_exit_stub.dart'
    if (dart.library.js_interop) 'public_work_exit_web.dart';

/// A single navigation handoff from the visible public feed, not a replacement
/// for the public repository/RLS lookup performed by PublicWorkEntry.
FeedWork? readOpeningWork() {
  try {
    final raw = openingWorkJson();
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final age =
        DateTime.now().millisecondsSinceEpoch - (data['savedAt'] as num);
    if (age < 0 || age > 60000) return null;
    final row = data['work'] as Map<String, dynamic>;
    if (row['id'] != Uri.base.queryParameters['work']) return null;
    final profile = data['profile'] as Map<String, dynamic>?;
    final author = profile?['id'] == row['user_id'] ? profile : null;
    return FeedWork(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      title: row['title'] as String? ?? '',
      description: row['description'] as String?,
      format: row['format'] as String? ?? 'glb',
      modelStoragePath: row['model_storage_path'] as String?,
      initialView: row['initial_view'] is Map
          ? Map<String, dynamic>.from(row['initial_view'] as Map)
          : null,
      thumbnailStoragePath: row['thumbnail_storage_path'] as String?,
      fileSizeBytes: (row['file_size_bytes'] as num?)?.toInt(),
      likedByMe: false,
      likesCount: (row['likes_count'] as num?)?.toInt() ?? 0,
      viewsCount: (row['views_count'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.tryParse(row['published_at'] as String? ?? ''),
      authorDisplayName: author?['display_name'] as String? ?? '',
      authorAvatarUrl: author?['avatar_url'] as String?,
      authorHandle: author?['handle'] as String?,
      publishRegion: row['publish_region'] as String?,
    );
  } catch (_) {
    return null;
  }
}

/// Enter the black detail surface immediately while auth initializes. A clicked
/// cover stays visible; direct links reuse the production app's existing orb.
class PublicWorkOpening extends StatelessWidget {
  PublicWorkOpening({super.key, FeedWork? work})
    : work = work ?? readOpeningWork();
  final FeedWork? work;

  Widget _orb() => const Center(child: SplashSolvingOrb());

  @override
  Widget build(BuildContext context) {
    final path = work?.thumbnailStoragePath;
    final cover = path == null || path.isEmpty
        ? null
        : publicationCoverUrl(Uri.https('api.kongye.space'), path) ??
              Uri.https(
                'api.kongye.space',
                '/storage/v1/object/public/thumbnails/$path',
              ).toString();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          onPressed: exitPublicWork,
        ),
        title: Text(
          work?.title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SizedBox.expand(
          child: cover == null
              ? _orb()
              : Image.network(
                  cover,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _orb(),
                ),
        ),
      ),
    );
  }
}
