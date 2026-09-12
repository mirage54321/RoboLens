import 'package:flutter/material.dart';

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
      child: GestureDetector(
        onTap: onTap,
        behavior: behavior,
        child: child,
      ),
    );
  }
}