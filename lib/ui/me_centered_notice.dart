import 'package:flutter/material.dart';
import 'design_system.dart';

/// In-app notices also supply their own text style when hosted by an Overlay.
class MeCenteredNotice extends StatelessWidget {
  const MeCenteredNotice(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: AetherColors.bgElevated,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              inherit: false,
              color: AetherColors.textPrimary,
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    ),
  );
}
