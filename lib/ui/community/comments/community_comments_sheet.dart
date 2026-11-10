import 'package:flutter/material.dart';

typedef CommunityCommentsSheetBuilder =
    Widget Function(
      ScrollController scrollController,
      bool expanded,
      VoidCallback toggleExpanded,
    );

/// A persistent half/full-screen sheet. The viewer stays mounted underneath.
class CommunityCommentsSheet extends StatefulWidget {
  const CommunityCommentsSheet({
    super.key,
    required this.visible,
    required this.onClose,
    required this.builder,
  });

  final bool visible;
  final VoidCallback onClose;
  final CommunityCommentsSheetBuilder builder;

  @override
  State<CommunityCommentsSheet> createState() => _CommunityCommentsSheetState();
}

class _CommunityCommentsSheetState extends State<CommunityCommentsSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
  final _sheet = DraggableScrollableController();
  bool _expanded = false;
  double _half = .5;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _entrance.forward();
  }

  @override
  void didUpdateWidget(covariant CommunityCommentsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      if (_sheet.isAttached) _sheet.jumpTo(_half);
      _expanded = false;
      _entrance.forward();
    } else {
      _entrance.reverse();
    }
  }

  void _toggleExpanded() {
    if (!_sheet.isAttached) return;
    _sheet.animateTo(
      _expanded ? _half : 1,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _dragHeader(DragUpdateDetails details, double height) {
    if (!_sheet.isAttached) return;
    _sheet.jumpTo((_sheet.size - details.delta.dy / height).clamp(_half, 1));
  }

  void _settleHeader(DragEndDetails details) {
    if (!_sheet.isAttached) return;
    final downward = (details.primaryVelocity ?? 0) > 300;
    final target = !downward && _sheet.size > (_half + 1) / 2 ? 1.0 : _half;
    _sheet.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _sheet.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return IgnorePointer(
      ignoring: !widget.visible,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            top: media.padding.top,
            bottom: media.viewInsets.bottom,
            child: LayoutBuilder(
              builder: (context, viewport) {
                _half = (media.size.height / 2 / viewport.maxHeight).clamp(
                  .5,
                  1,
                );
                return SlideTransition(
                  position: _slide,
                  child: NotificationListener<DraggableScrollableNotification>(
                    onNotification: (notification) {
                      final expanded = notification.extent > (_half + 1) / 2;
                      if (expanded != _expanded) {
                        setState(() => _expanded = expanded);
                      }
                      return false;
                    },
                    child: DraggableScrollableSheet(
                      controller: _sheet,
                      initialChildSize: _half,
                      minChildSize: _half,
                      maxChildSize: 1,
                      snap: true,
                      shouldCloseOnMinExtent: false,
                      builder: (context, scrollController) => GestureDetector(
                        onVerticalDragUpdate: (details) =>
                            _dragHeader(details, viewport.maxHeight),
                        onVerticalDragEnd: _settleHeader,
                        child: Material(
                          key: const ValueKey('community-comments-sheet'),
                          color: Colors.white,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SafeArea(
                            top: false,
                            child: widget.builder(
                              scrollController,
                              _expanded,
                              _toggleExpanded,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
