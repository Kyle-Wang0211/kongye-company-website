import 'package:flutter/material.dart';

/// Mirrors the community homepage's navigation, including its 80/56px rails.
/// The content remains in the same Row slot when the viewport changes.
class CommunityProfileShell extends StatelessWidget {
  const CommunityProfileShell({
    super.key,
    required this.child,
    required this.onHome,
    required this.onFollowing,
    required this.onMyProfile,
    required this.onSettings,
    required this.onMessages,
    this.onPublish,
    this.onOpenFiling,
    this.selectedDestination = 'profile',
  });
  final Widget child;
  final VoidCallback onHome, onFollowing, onMyProfile, onSettings, onMessages;
  // Retained for source compatibility; publishing is a header/account action.
  final VoidCallback? onPublish, onOpenFiling;
  final String selectedDestination;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      final compact = size.maxWidth <= 600;
      final rail = size.maxWidth <= 1000;
      final width = compact
          ? 56.0
          : rail
          ? 80.0
          : 204.0;
      final inset = compact
          ? 6.0
          : rail
          ? 10.0
          : 18.0;
      final logoSize = compact ? 30.0 : 38.0;
      final navGap = compact ? 8.0 : 10.0;
      Widget item(
        String destination,
        String label,
        VoidCallback action, {
        bool footer = false,
      }) => _SidebarItem(
        key: ValueKey('sidebar-destination-$destination'),
        destination: destination,
        label: label,
        onTap: action,
        selected: selectedDestination == destination,
        rail: rail,
        minimumHeight: footer
            ? (compact ? 44 : 42)
            : compact
            ? 44
            : 48,
        leftPadding: footer ? 14 : 16,
      );
      return Material(
        color: Colors.white,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const Key('profile-community-sidebar'),
              width: width,
              padding: EdgeInsets.fromLTRB(
                inset,
                compact ? 18 : 26,
                inset,
                compact ? 18 : 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Color(0xffeeeeee))),
              ),
              child: LayoutBuilder(
                builder: (context, bounds) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: bounds.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: rail ? 0 : 8,
                            ),
                            child: InkWell(
                              onTap: onHome,
                              child: SizedBox(
                                height: logoSize,
                                child: Row(
                                  mainAxisAlignment: rail
                                      ? MainAxisAlignment.center
                                      : MainAxisAlignment.start,
                                  children: [
                                    Container(
                                      key: const Key('sidebar-brand-image'),
                                      width: logoSize,
                                      height: logoSize,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xffeeeeee),
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(7),
                                        child: Image.network(
                                          Uri.base
                                              .resolve('../assets/app-icon.png')
                                              .toString(),
                                          width: logoSize,
                                          height: logoSize,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              SizedBox.square(
                                                dimension: logoSize,
                                              ),
                                        ),
                                      ),
                                    ),
                                    if (!rail) ...[
                                      SizedBox(width: zh ? 11 : 9),
                                      Flexible(
                                        child: Text(
                                          zh ? '窗后城' : 'WorldsWithin',
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: zh ? 21 : 15,
                                            letterSpacing: zh ? 1.26 : 0,
                                            fontWeight: FontWeight.w400,
                                            height: 1.35,
                                            color: const Color(0xff161616),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: compact
                                ? 28
                                : rail
                                ? 32
                                : 40,
                          ),
                          Column(
                            key: const Key('sidebar-primary'),
                            children: [
                              item('hot', zh ? '热门' : 'Hot', onHome),
                              SizedBox(height: navGap),
                              item(
                                'following',
                                zh ? '关注' : 'Following',
                                onFollowing,
                              ),
                              SizedBox(height: navGap),
                              item('profile', zh ? '我的' : 'Me', onMyProfile),
                              SizedBox(height: navGap),
                              item(
                                'messages',
                                zh ? '消息' : 'Messages',
                                onMessages,
                              ),
                            ],
                          ),
                          const Spacer(),
                          Padding(
                            padding: EdgeInsets.only(top: rail ? 30 : 50),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                item(
                                  'settings',
                                  zh ? '设置' : 'Settings',
                                  onSettings,
                                  footer: true,
                                ),
                                if (!rail) ...[
                                  const SizedBox(height: 12),
                                  const SizedBox(height: 14),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      zh
                                          ? '© 2026 北京空也科技有限公司'
                                          : '© 2026 Beijing Kongye Technology Co., Ltd',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 0,
                                        height: 1.7,
                                        color: Color(0xff999999),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: InkWell(
                                      onTap: onOpenFiling,
                                      child: const Text(
                                        '京ICP备2026067702号-1',
                                        style: TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 0,
                                          height: 1.7,
                                          color: Color(0xff999999),
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(key: const Key('profile-shell-content'), child: child),
          ],
        ),
      );
    },
  );
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    super.key,
    required this.destination,
    required this.label,
    required this.onTap,
    required this.selected,
    required this.rail,
    required this.minimumHeight,
    required this.leftPadding,
  });
  final String destination, label;
  final VoidCallback onTap;
  final bool selected, rail;
  final double minimumHeight, leftPadding;
  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hover;
    final color = active ? const Color(0xff161616) : const Color(0xff737373);
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minimumHeight),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: 10,
          horizontal: widget.rail ? 0 : widget.leftPadding,
        ),
        child: Row(
          mainAxisAlignment: widget.rail
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            CustomPaint(
              key: ValueKey('sidebar-icon-${widget.destination}'),
              size: const Size(22, 22),
              painter: CommunitySidebarIconPainter(widget.destination, color),
            ),
            if (!widget.rail) ...[
              const SizedBox(width: 16),
              Flexible(
                child: ExcludeSemantics(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 15,
                      letterSpacing: 0,
                      height: 1.5,
                      color: color,
                      fontWeight: widget.selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: Tooltip(
        message: widget.rail ? widget.label : '',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Material(
            color: active ? const Color(0xfff3f3f3) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Direct transcription of the homepage SVG viewBox=24 paths. No icon font.
class CommunitySidebarIconPainter extends CustomPainter {
  const CommunitySidebarIconPainter(this.destination, this.color);
  final String destination;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = Path();
    switch (destination) {
      case 'hot':
        p.moveTo(13, 3);
        p.relativeCubicTo(1, 5, -3, 5, -2, 9);
        p.relativeCubicTo(1, -1, 3, -2, 4, -4);
        p.relativeCubicTo(2, 2, 4, 5, 4, 7);
        p.relativeArcToPoint(
          const Offset(-14, 0),
          radius: const Radius.circular(7),
        );
        p.relativeCubicTo(0, -3, 2, -6, 4, -8);
        p.relativeCubicTo(0, 3, 1, 4, 2, 5);
      case 'following':
        canvas.drawCircle(const Offset(9, 7), 3, paint);
        p.moveTo(3, 20);
        p.relativeLineTo(0, -2);
        p.relativeArcToPoint(
          const Offset(10, -4),
          radius: const Radius.circular(6),
        );
        p.relativeMoveTo(2, -1);
        p.relativeLineTo(3, 3);
        p.relativeLineTo(4, -6);
      case 'profile':
        canvas.drawCircle(const Offset(12, 7), 4, paint);
        p.moveTo(4, 21);
        p.relativeLineTo(0, -2);
        p.relativeArcToPoint(
          const Offset(16, 0),
          radius: const Radius.circular(8),
        );
        p.relativeLineTo(0, 2);
        p.close();
      case 'messages':
        p.moveTo(21, 11);
        p.relativeArcToPoint(
          const Offset(-9, 9),
          radius: const Radius.circular(9),
        );
        p.lineTo(3, 20);
        p.lineTo(3, 11);
        p.relativeArcToPoint(
          const Offset(18, 0),
          radius: const Radius.circular(9),
        );
        p.close();
      case 'settings':
        p.moveTo(12, 2);
        p.relativeLineTo(9, 5);
        p.relativeLineTo(0, 10);
        p.relativeLineTo(-9, 5);
        p.relativeLineTo(-9, -5);
        p.lineTo(3, 7);
        p.close();
        canvas.drawCircle(const Offset(12, 12), 3, paint);
    }
    canvas.drawPath(p, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CommunitySidebarIconPainter oldDelegate) =>
      oldDelegate.destination != destination || oldDelegate.color != color;
}
