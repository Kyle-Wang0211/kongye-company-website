import 'package:flutter/material.dart';

/// Opens above the root shell so its tab bar is covered by the same barrier.
Future<void> showMeSettingsDrawer({
  required BuildContext context,
  required Widget child,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (drawerContext, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Dismissible(
        key: const ValueKey('me-settings-right-swipe'),
        direction: DismissDirection.startToEnd,
        resizeDuration: null,
        onDismissed: (_) => Navigator.of(drawerContext).pop(),
        child: MeSettingsDrawer(child: child),
      ),
    ),
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Contains the existing settings page, without duplicating settings actions.
class MeSettingsDrawer extends StatelessWidget {
  const MeSettingsDrawer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.sizeOf(context).width * .75,
      shape: const RoundedRectangleBorder(),
      child: child,
    );
  }
}
