import 'dart:convert';

import 'package:flutter/material.dart';

import '../../community/feed_models.dart';
import 'work_detail_page.dart' show WorkDetailMetadata;
import 'community_loading.dart';
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
      commentCount: (row['comments_count'] as num?)?.toInt() ?? 0,
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

  Widget _skeleton(String field, double width, {double height = 14}) =>
      SizedBox(
        key: ValueKey('work-opening-$field'),
        width: width,
        height: height,
        child: const CommunityShimmer(),
      );

  Widget _orb() => Stack(
    fit: StackFit.expand,
    children: [
      const CommunityShimmer(),
      const Center(
        child: SizedBox.square(
          dimension: 64,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              Center(
                child: Text(
                  '0%',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _metadata() => work != null
      ? IgnorePointer(
          child: WorkDetailMetadata(
            viewsCount: work!.viewsCount,
            commentsCount: work!.commentCount,
            likesCount: work!.likesCount,
            liked: work!.likedByMe,
            likeBusy: false,
            onLike: () => false,
            author: work!.authorDisplayName,
            authorUserId: work!.userId,
            description: work!.description,
            onComments:
                {'glb', 'gltf', 'ply'}.contains(work!.format.toLowerCase())
                ? () {}
                : null,
          ),
        )
      : Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white12, width: .5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    color: Colors.white54,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: work?.authorDisplayName.isNotEmpty == true
                        ? Text(
                            work!.authorDisplayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: _skeleton('author', 100),
                          ),
                  ),
                  const Icon(
                    Icons.remove_red_eye_outlined,
                    color: Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  if (work == null)
                    _skeleton('views', 28)
                  else
                    Text(
                      '${work!.viewsCount}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.favorite_border,
                    color: Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  if (work == null)
                    _skeleton('likes', 28)
                  else
                    Text(
                      '${work!.likesCount}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                ],
              ),
              if (work == null) ...[
                const SizedBox(height: 8),
                _skeleton('description', 220),
              ] else if (work!.description?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  work!.description!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ],
          ),
        );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          onPressed: exitPublicWork,
        ),
        title: work == null
            ? _skeleton('title', 160, height: 18)
            : Text(
                work!.title,
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
        child: Column(
          children: [
            Expanded(child: SizedBox.expand(child: _orb())),
            _metadata(),
          ],
        ),
      ),
    );
  }
}
