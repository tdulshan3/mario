/// ResizablePanel — fixed-width side panel with a draggable edge.
///
/// [edge] says which side the handle is on. A panel docked on the left (the
/// nav tree) grows as you drag right; one docked on the right (the AI panel)
/// has to grow as you drag *left*, so the delta is inverted.
import 'package:flutter/material.dart';

import '../colors.dart';

/// Which side of the panel carries the drag handle.
enum PanelEdge { right, left }

class ResizablePanel extends StatefulWidget {
  const ResizablePanel({
    super.key,
    required this.child,
    this.initialWidth = 240,
    this.minWidth = 160,
    this.maxWidth = 480,
    this.edge = PanelEdge.right,
  });

  final Widget child;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;
  final PanelEdge edge;

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
            right: widget.edge == PanelEdge.right ? 0 : null,
            left: widget.edge == PanelEdge.left ? 0 : null,
            width: 6,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) {
                  // Dragging the left handle rightwards makes a right-docked
                  // panel narrower, hence the sign flip.
                  final delta = widget.edge == PanelEdge.right
                      ? d.delta.dx
                      : -d.delta.dx;
                  setState(() {
                    _width = (_width + delta)
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
