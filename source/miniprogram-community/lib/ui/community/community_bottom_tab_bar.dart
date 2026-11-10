import 'package:flutter/material.dart';
import '../design_system.dart';

class CommunityBottomTabBar extends StatelessWidget {
  const CommunityBottomTabBar({
    super.key,
    required this.current,
    required this.onChanged,
  });
  final String current;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Material(
    color: AetherColors.bgCanvas,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 72,
        child: Row(
          children: [
            for (final entry in const <String, (String, IconData)>{
              'hot': ('首页', Icons.apps_rounded),
              'activities': ('活动', Icons.local_activity_outlined),
              'messages': ('消息', Icons.chat_bubble_outline_rounded),
              'profile': ('我', Icons.person_outline_rounded),
            }.entries)
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(entry.key),
                  child: Semantics(
                    label: entry.value.$1,
                    button: true,
                    selected: current == entry.key,
                    child: Center(
                      child: Icon(
                        entry.value.$2,
                        size: 25,
                        color: current == entry.key
                            ? AetherColors.primary
                            : AetherColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
