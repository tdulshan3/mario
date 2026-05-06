/// ShellToolbar — top bar with logo, current notebook name, and action icons.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/colors.dart';
import '../auth/auth_notifier.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _LogoMark(),
                const SizedBox(width: 12),
                Text(
                  currentName ?? 'Mario',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Search (Ctrl+Shift+F)',
                  onPressed: () {},
                  icon: const Icon(Icons.search, size: 18),
                ),
                IconButton(
                  tooltip: 'Share',
                  onPressed: () {},
                  icon: const Icon(Icons.ios_share, size: 18),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () {},
                  icon: const Icon(Icons.settings_outlined, size: 18),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: () =>
                      ref.read(authNotifierProvider.notifier).signOut(),
                  icon: const Icon(Icons.logout, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: MarioColors.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        'M',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
