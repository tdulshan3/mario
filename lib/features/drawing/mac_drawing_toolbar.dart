/// The drawing toolbar in the macOS look — the desktop builds' counterpart
/// of `DrawingToolbar`'s Material row.
///
/// A band like the format bar above it (window background, separator below,
/// small controls): the tool as one segmented control, the ink in a colour
/// well that opens the drawing palette, the stroke width on a slider with its
/// value beside it, Undo · Redo as push-button segments, then Clear, Save as
/// PNG (where there is something to capture), Save changes and Collapse.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

import '../editor/mac_segment_tooltips.dart';
import 'drawing_canvas.dart';
import 'drawing_toolbar.dart' show drawingPalette;
import 'stroke.dart';

class MacDrawingToolbar extends StatelessWidget {
  const MacDrawingToolbar({
    super.key,
    required this.controller,
    required this.onCollapse,
    required this.onExport,
    required this.onSave,
    required this.collapsed,
  });

  final DrawingController controller;
  final VoidCallback onCollapse;

  /// Null hides Save as PNG (see `DrawingToolbar.onExport`).
  final VoidCallback? onExport;
  final VoidCallback onSave;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final c = context.macColors;
        final width = controller.width.clamp(1.0, 20.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.windowBg,
            border: Border(bottom: BorderSide(color: c.separator)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: MacControlSizeScope(
              size: MacControlSize.small,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MacSegmentTooltips(
                    messages: const ['Pen', 'Highlighter', 'Eraser'],
                    child: MacSegmentedControl<StrokeMode>(
                      segments: const [
                        MacSegment(
                          value: StrokeMode.pen,
                          icon: CupertinoIcons.pencil_outline,
                          semanticLabel: 'Pen',
                        ),
                        MacSegment(
                          value: StrokeMode.highlighter,
                          icon: CupertinoIcons.paintbrush,
                          semanticLabel: 'Highlighter',
                        ),
                        // No eraser among the symbols; a struck-out pencil
                        // says "undraw".
                        MacSegment(
                          value: StrokeMode.eraser,
                          icon: CupertinoIcons.pencil_slash,
                          semanticLabel: 'Eraser',
                        ),
                      ],
                      value: controller.mode,
                      equal: true,
                      semanticLabel: 'Tool',
                      onChanged: controller.setMode,
                    ),
                  ),
                  MacTooltip(
                    message: 'Color',
                    child: MacColorWell(
                      color: controller.color,
                      palette: drawingPalette,
                      onChanged: controller.setColor,
                      semanticLabel: 'Color',
                    ),
                  ),
                  MacTooltip(
                    message: 'Stroke width',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        SizedBox(
                          width: 100,
                          child: MacSlider(
                            value: width,
                            min: 1,
                            max: 20,
                            // Whole pixels, as the ribbon's 19 divisions.
                            onChanged: (v) =>
                                controller.setWidth(v.roundToDouble()),
                            semanticLabel: 'Stroke width',
                          ),
                        ),
                        Text(
                          '${width.round()} px',
                          style: MacTypography.of(context)
                              .subheadline
                              .copyWith(color: c.labelSecondary),
                        ),
                      ],
                    ),
                  ),
                  MacSegmentTooltips(
                    messages: const ['Undo', 'Redo'],
                    child: MacSegmentedControl<bool>.momentary(
                      segments: [
                        MacSegment(
                          value: false,
                          icon: AppleIcons.undo,
                          semanticLabel: 'Undo',
                          enabled: controller.canUndo,
                        ),
                        MacSegment(
                          value: true,
                          icon: AppleIcons.redo,
                          semanticLabel: 'Redo',
                          enabled: controller.canRedo,
                        ),
                      ],
                      equal: true,
                      semanticLabel: 'History',
                      onPressed: (redo) =>
                          redo ? controller.redo() : controller.undo(),
                    ),
                  ),
                  _button(
                    icon: AppleIcons.trash,
                    tooltip: 'Clear all',
                    onPressed: controller.canUndo ? controller.clearAll : null,
                  ),
                  if (onExport != null)
                    _button(
                      icon: AppleIcons.squareAndArrowDown,
                      tooltip: 'Save as PNG',
                      onPressed: onExport,
                    ),
                  _button(
                    icon: AppleIcons.checkmark,
                    tooltip: 'Save changes',
                    onPressed: onSave,
                  ),
                  _button(
                    icon: collapsed
                        ? AppleIcons.chevronDown
                        : AppleIcons.chevronUp,
                    tooltip: collapsed ? 'Expand' : 'Collapse',
                    onPressed: onCollapse,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _button({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) =>
      MacTooltip(
        message: tooltip,
        child: MacButton(
          icon: icon,
          semanticLabel: tooltip,
          onPressed: onPressed,
        ),
      );
}
