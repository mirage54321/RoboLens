import 'package:flutter/material.dart';
import 'cursor_controller.dart';

class TapCursor extends StatelessWidget {
  const TapCursor({
    super.key,
    required this.child,
    this.onTap,
    this.behavior,
  });

  final Widget child;
  final VoidCallback? onTap;
  final HitTestBehavior? behavior;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: onTap == null
          ? null
          : (_) => CursorController.instance.setHovering(true),
      onExit: onTap == null
          ? null
          : (_) => CursorController.instance.setHovering(false),
      child: GestureDetector(
        onTap: onTap,
        behavior: behavior,
        child: child,
      ),
    );
  }
}