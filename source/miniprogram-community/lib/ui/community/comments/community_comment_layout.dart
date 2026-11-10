import 'package:flutter/material.dart';

/// Shared comment information layout for App, mini program and website.
class CommunityCommentHeader extends StatelessWidget {
  const CommunityCommentHeader({
    super.key,
    required this.author,
    required this.date,
    required this.likesCount,
    required this.liked,
    required this.likeLabel,
    required this.locationLabel,
    required this.showLikes,
    this.badge,
    this.mineLabel,
    this.onLike,
    this.onLocation,
  });

  final String author, date, likeLabel, locationLabel;
  final int likesCount;
  final bool liked, showLikes;
  final Widget? badge;
  final String? mineLabel;
  final VoidCallback? onLike, onLocation;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Row(
          children: [
            Flexible(
              child: Text(
                author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xff777777)),
              ),
            ),
            ?badge,
            if (mineLabel != null)
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Text(
                  mineLabel!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xff999999),
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              date,
              style: const TextStyle(fontSize: 11, color: Color(0xff999999)),
            ),
          ],
        ),
      ),
      if (onLocation != null)
        IconButton(
          tooltip: locationLabel,
          onPressed: onLocation,
          padding: const EdgeInsets.all(5),
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            Icons.location_on_outlined,
            size: 18,
            color: Color(0xff777777),
          ),
        ),
      if (showLikes)
        Semantics(
          label: likeLabel,
          button: true,
          enabled: onLike != null,
          child: InkWell(
            onTap: onLike,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$likesCount',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff777777),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    liked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
                    size: 18,
                    color: const Color(0xff777777),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class CommunityCommentComposerRow extends StatelessWidget {
  const CommunityCommentComposerRow({
    super.key,
    required this.avatar,
    required this.input,
    required this.emojiButton,
    required this.imageButton,
  });

  final Widget avatar, input, emojiButton, imageButton;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff7f7f7),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          avatar,
          const SizedBox(width: 10),
          Expanded(child: input),
          const SizedBox(width: 4),
          emojiButton,
          imageButton,
        ],
      ),
    ),
  );
}
