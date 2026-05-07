/// CollapsiblePanel — resizable side panel with collapse-to-strip behavior.
/// When expanded, hands a collapse callback to its child via [builder] so the
/// child can render a chevron in its own header. When collapsed, renders a
/// thin vertical strip with a rotated label that expands on click.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../colors.dart';
import 'resizable_panel.dart';

class CollapsiblePanel extends StatefulWidget {
  const CollapsiblePanel({
    super.key,
    required this.title,
    required this.builder,
    this.initialWidth = 240,
    this.minWidth = 160,
    this.maxWidth = 480,
  });

  final String title;
  final Widget Function(BuildContext context, VoidCallback onCollapse) builder;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;

  @override
  State<CollapsiblePanel> createState() => _CollapsiblePanelState();
}

class _CollapsiblePanelState extends State<CollapsiblePanel> {
  bool _collapsed = false;

  void _toggle() => setState(() => _collapsed = !_collapsed);

  @override
  Widget build(BuildContext context) {
    if (_collapsed) {
      return _CollapsedStrip(title: widget.title, onExpand: _toggle);
    }
    return ResizablePanel(
      initialWidth: widget.initialWidth,
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      child: widget.builder(context, _toggle),
    );
  }
}

class _CollapsedStrip extends StatelessWidget {
  const _CollapsedStrip({required this.title, required this.onExpand});
  final String title;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? MarioColors.surfaceVariantDark
        : MarioColors.surfaceVariant;
    final muted = isDark
        ? MarioColors.onSurfaceMutedDark
        : MarioColors.onSurfaceMuted;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;
    return SizedBox(
      width: 32,
      child: Material(
        color: bg,
        child: InkWell(
          onTap: onExpand,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: border)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Icon(Icons.chevron_right, size: 16, color: muted),
                ),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Center(
                      child: Text(
                        title,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
