import 'package:flutter/material.dart';
import '../../community/activity_repository.dart';
import 'activity_feed.dart';

/// The published catalog and original destinations are shared with the feed.
class CommunityActivitiesPage extends StatelessWidget {
  const CommunityActivitiesPage({
    super.key,
    required this.onOpen,
    this.isVisible = true,
  });
  final void Function(BuildContext, CommunityActivity) onOpen;
  final bool isVisible;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      bottom: false,
      child: ActivityFeed(
        isVisible: isVisible,
        builder: (context, entries, refresh) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final activity = entries[index];
              return Semantics(
                button: true,
                label: activity.title,
                child: InkWell(
                  onTap: () => onOpen(context, activity),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      activity.coverUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : const ColoredBox(color: Color(0xffeeeeee)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
