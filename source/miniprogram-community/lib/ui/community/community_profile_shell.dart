import 'package:flutter/material.dart';
import '../design_system.dart';

/// The community navigation stays mounted beside a desktop profile.
class CommunityProfileShell extends StatelessWidget {
  const CommunityProfileShell({
    super.key,
    required this.child,
    required this.onHome,
    required this.onFollowing,
    required this.onMyProfile,
    required this.onSettings,
    required this.onMessages,
    required this.onPublish,
  });
  final Widget child;
  final VoidCallback onHome,
      onFollowing,
      onMyProfile,
      onSettings,
      onMessages,
      onPublish;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      if (size.maxWidth < 900) return child;
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      Widget item(
        IconData icon,
        String text,
        VoidCallback action, {
        bool selected = false,
      }) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          selected: selected,
          selectedTileColor: AetherColors.bgElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Icon(icon, size: 23),
          title: Text(text),
          onTap: action,
        ),
      );
      return Material(
        color: AetherColors.bgCanvas,
        child: Row(
          children: [
            SizedBox(
              key: const Key('profile-community-sidebar'),
              width: 208,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: onHome,
                    child: Text(
                      zh ? '窗后城' : 'PocketWorld',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AetherColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  item(
                    Icons.local_fire_department_outlined,
                    zh ? '热门' : 'Explore',
                    onHome,
                  ),
                  item(
                    Icons.person_add_alt_outlined,
                    zh ? '关注' : 'Following',
                    onFollowing,
                  ),
                  item(
                    Icons.person_outline,
                    zh ? '我的主页' : 'My profile',
                    onMyProfile,
                    selected: true,
                  ),
                  item(
                    Icons.chat_bubble_outline,
                    zh ? '消息' : 'Messages',
                    onMessages,
                  ),
                  item(
                    Icons.add_box_outlined,
                    zh ? '发布作品' : 'Publish',
                    onPublish,
                  ),
                  const Spacer(),
                  item(
                    Icons.settings_outlined,
                    zh ? '账号与隐私' : 'Account and privacy',
                    onSettings,
                  ),
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '© 2026 PocketWorld',
                      style: TextStyle(
                        fontSize: 11,
                        color: AetherColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: child),
          ],
        ),
      );
    },
  );
}
