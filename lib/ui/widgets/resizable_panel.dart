/// ResizablePanel — fixed-width side panel with a draggable right edge.
import 'package:flutter/material.dart';

import '../colors.dart';

class ResizablePanel extends StatefulWidget {
  const ResizablePanel({
    super.key,
    required this.child,
    this.initialWidth = 240,
    this.minWidth = 160,
    this.maxWidth = 480,
  });

  final Widget child;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;

  @override
  State<ResizablePanel> createState() => _ResizablePanelState();
}

class _ResizablePanelState extends State<ResizablePanel> {
  late double _width = widget.initialWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;
    return SizedBox(
      width: _width,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 6,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    _width = (_width + d.delta.dx)
                        .clamp(widget.minWidth, widget.maxWidth);
                  });
                },
                child: Center(
                  child: Container(width: 1, color: border),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
