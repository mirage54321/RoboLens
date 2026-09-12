import 'package:flutter/material.dart';
import 'cursor_controller.dart';

const _kGlowColor = Color(0xFF00B3AC);


class CustomCursorOverlay extends StatelessWidget {
  final Widget child;
  const CustomCursorOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) =>
          CursorController.instance.updatePosition(event.position),
      onExit: (_) => CursorController.instance.hide(),
      child: Stack(
        children: [
          child,
          IgnorePointer(
            child: AnimatedBuilder(
              animation: CursorController.instance,
              builder: (context, _) {
                final c = CursorController.instance;
                if (!c.visible || c.position == null) {
                  return const SizedBox.shrink();
                }
                final size = c.hovering ? 40.0 : 20.0;
                return AnimatedPositioned(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  left: c.position!.dx - size / 2,
                  top: c.position!.dy - size / 2,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kGlowColor.withValues(
                          alpha: c.hovering ? 0.16 : 0.0),
                      border: Border.all(
                        color: _kGlowColor.withValues(
                            alpha: c.hovering ? 0.55 : 0.22),
                        width: c.hovering ? 1.4 : 1.0,
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