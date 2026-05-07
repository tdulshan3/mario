/// PanelHeader — uppercase-style title with an optional collapse chevron.
/// Shared between Notebook / Section / Page side panels.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../colors.dart';

class PanelHeader extends StatelessWidget {
  const PanelHeader({super.key, required this.title, this.onCollapse});

  final String title;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 6),
      child: Row(
        children: [
          Expanded(
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
          if (onCollapse != null)
            IconButton(
              tooltip: 'Collapse',
              onPressed: onCollapse,
              icon: const Icon(Icons.chevron_left, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: muted,
            ),
        ],
      ),
    );
  }
}
