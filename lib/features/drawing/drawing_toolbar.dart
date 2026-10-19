/// DrawingToolbar — tool switcher, color picker, width slider, undo/redo, clear.
library;

import 'package:flutter/material.dart';

import '../../ui/colors.dart';
import '../../ui/mac/mac_look.dart';
import 'drawing_canvas.dart';
import 'mac_drawing_toolbar.dart';
import 'stroke.dart';

const drawingPalette = <Color>[
  Color(0xFF1A1A1A),
  Colors.white,
  MarioColors.primary,
  MarioColors.labelRed,
  MarioColors.labelOrange,
  MarioColors.labelGreen,
  MarioColors.labelTeal,
  MarioColors.labelPurple,
];

class DrawingToolbar extends StatelessWidget {
  const DrawingToolbar({
    super.key,
    required this.controller,
    required this.onCollapse,
    this.onExport,
    required this.onSave,
    this.collapsed = false,
  });

  final DrawingController controller;
  final VoidCallback onCollapse;

  /// PNG export, when the caller has a repaint boundary to capture.
  ///
  /// Null hides the button. The full-page canvas has no boundary to render
  /// from, and an always-enabled "Save as PNG" that silently does nothing is
  /// worse than no button — it was wired to an empty closure before this.
  final VoidCallback? onExport;
  final VoidCallback onSave;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    // The desktop builds draw the same controls in the macOS look.
    if (useMacLook) {
      return MacDrawingToolbar(
        controller: controller,
        onCollapse: onCollapse,
        onExport: onExport,
        onSave: onSave,
        collapsed: collapsed,
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark ? MarioColors.borderDark : MarioColors.border;

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: divider)),
        ),
        child: Wrap(
          alignment: WrapAlignment.start,
          runAlignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            _ToolButton(
              icon: Icons.edit_outlined,
              tooltip: 'Pen',
              selected: controller.mode == StrokeMode.pen,
              onPressed: () => controller.setMode(StrokeMode.pen),
            ),
            _ToolButton(
              icon: Icons.brush_outlined,
              tooltip: 'Highlighter',
              selected: controller.mode == StrokeMode.highlighter,
              onPressed: () => controller.setMode(StrokeMode.highlighter),
            ),
            _ToolButton(
              icon: Icons.cleaning_services_outlined,
              tooltip: 'Eraser',
              selected: controller.mode == StrokeMode.eraser,
              onPressed: () => controller.setMode(StrokeMode.eraser),
            ),
            const SizedBox(width: 8),
            for (final c in drawingPalette)
              _ColorSwatch(
                color: c,
                selected: controller.color.toARGB32() == c.toARGB32(),
                onTap: () => controller.setColor(c),
              ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: Slider(
                value: controller.width.clamp(1, 20),
                min: 1,
                max: 20,
                divisions: 19,
                label: controller.width.toStringAsFixed(0),
                onChanged: controller.setWidth,
              ),
            ),
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo, size: 18),
              onPressed: controller.canUndo ? controller.undo : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo, size: 18),
              onPressed: controller.canRedo ? controller.redo : null,
            ),
            IconButton(
              tooltip: 'Clear all',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: controller.canUndo ? controller.clearAll : null,
            ),
            if (onExport != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Save as PNG',
                icon: const Icon(Icons.download_outlined, size: 18),
                onPressed: onExport,
              ),
            ],
            IconButton(
              tooltip: 'Save changes',
              icon: const Icon(Icons.check, size: 18),
              onPressed: onSave,
            ),
            IconButton(
              tooltip: collapsed ? 'Expand' : 'Collapse',
              icon: Icon(
                collapsed ? Icons.unfold_more : Icons.unfold_less,
                size: 18,
              ),
              onPressed: onCollapse,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? MarioColors.primary.withValues(alpha: isDark ? 0.18 : 0.32)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch(
      {required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}
