/// ShellToolbar — top bar with logo, "Mario" brand + current notebook name,
/// global search, share, settings, and a window-close button. Doubles as the
/// drag-to-move area now that the OS title bar is hidden.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

import '../../ui/colors.dart';
import '../ai/ai_state.dart';
import '../search/global_search.dart';
import '../sharing/share_dialog.dart';
import 'shell_state.dart';

class ShellToolbar extends ConsumerWidget implements PreferredSizeWidget {
  const ShellToolbar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    final notebooks = ref.watch(notebooksStreamProvider).valueOrNull ?? const [];
    final currentName = notebooks
        .where((n) => n.id == selection.notebookId)
        .map((n) => n.name)
        .firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    final border = scheme.outlineVariant;
    final muted = scheme.onSurfaceVariant;

    final useWindowControls = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS);

    final bar = Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              // Breakpoints — collapse from least- to most-essential as width
              // shrinks. Desktop min window is 800px so most users see all.
              final showBrand = w >= 360;
              final showNotebookName = currentName != null && w >= 560;
              final showSearch = w >= 420;
              final showShare = w >= 640;
              final showSettings = w >= 480;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                // Outer row splits into two parts: an Expanded brand/name
                // group on the left (which absorbs any slack from a short
                // notebook name), and the icon strip on the right. Without
                // the Expanded wrap, a Flexible+Spacer pair would leave the
                // unused space at the *end* of the row — pushing icons
                // toward center instead of pinning them to the right edge.
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _LogoMark(),
                          if (showBrand) ...[
                            const SizedBox(width: 12),
                            Text(
                              'Mario',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          if (showNotebookName) ...[
                            const SizedBox(width: 8),
                            Text('•',
                                style: GoogleFonts.inter(
                                    fontSize: 13, color: muted)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                currentName,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: ref.watch(aiPanelProvider).isOpen
                          ? 'Hide AI panel'
                          : 'Ask AI / Quiz',
                      onPressed: () =>
                          ref.read(aiPanelProvider.notifier).toggle(),
                      icon: Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: ref.watch(aiPanelProvider).isOpen
                            ? MarioColors.primaryPressed
                            : null,
                      ),
                    ),
                    if (showSearch)
                      IconButton(
                        tooltip: 'Search (Ctrl+Shift+F)',
                        onPressed: () => showGlobalSearch(context),
                        icon: const Icon(Icons.search, size: 18),
                      ),
                    if (showShare)
                      IconButton(
                        tooltip: 'Share',
                        onPressed: () => showShareDialog(context, ref),
                        icon: const Icon(Icons.ios_share, size: 18),
                      ),
                    if (showSettings)
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => context.push('/settings'),
                        icon: const Icon(Icons.settings_outlined, size: 18),
                      ),
                    // Overflow menu picks up anything we hid above so the
                    // user can still reach those actions on narrow widths.
                    if (!showSearch || !showShare || !showSettings)
                      _OverflowMenu(
                        showSearch: !showSearch,
                        showShare: !showShare,
                        showSettings: !showSettings,
                        onSearch: () => showGlobalSearch(context),
                        onShare: () => showShareDialog(context, ref),
                        onSettings: () => context.push('/settings'),
                      ),
                    if (useWindowControls)
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => windowManager.close(),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    return useWindowControls ? DragToMoveArea(child: bar) : bar;
  }
}

enum _OverflowAction { search, share, settings }

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.showSearch,
    required this.showShare,
    required this.showSettings,
    required this.onSearch,
    required this.onShare,
    required this.onSettings,
  });

  final bool showSearch;
  final bool showShare;
  final bool showSettings;
  final VoidCallback onSearch;
  final VoidCallback onShare;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_OverflowAction>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, size: 18),
      itemBuilder: (_) => [
        if (showSearch)
          const PopupMenuItem(
              value: _OverflowAction.search, child: Text('Search')),
        if (showShare)
          const PopupMenuItem(
              value: _OverflowAction.share, child: Text('Share')),
        if (showSettings)
          const PopupMenuItem(
              value: _OverflowAction.settings, child: Text('Settings')),
      ],
      onSelected: (a) {
        switch (a) {
          case _OverflowAction.search:
            onSearch();
          case _OverflowAction.share:
            onShare();
          case _OverflowAction.settings:
            onSettings();
        }
      },
    );
  }
}

class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'M',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimary,
          height: 1,
        ),
      ),
    );
  }
}
