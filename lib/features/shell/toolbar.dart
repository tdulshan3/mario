/// ShellToolbar — the Simple design's top bar.
///
/// 43px, including the hairline along its bottom edge. That is the headline
/// change of the remodel: the bar used to be 68px of glass with pill buttons
/// and a measured, centred search pill. It is now a flat strip separated from
/// the page by a 1px rule, and everything in it is small — a 20px mark, a
/// 28px search field, 28px icon buttons, a 24px avatar.
///
/// Three zones, laid out exactly as the design does it:
///
///   left    the 20px mark and the "Mario" wordmark — the last Caprasimo in
///           the interface
///   centre  a 340px search field, centred in the space *between* the two
///           clusters (two equal flexes), not on the bar itself
///   right   Ask, Settings, the avatar, and the window close
///
/// Share is not on this bar any more. The design moves it to the editor's
/// format row, beside "Saved" — which is where it belongs, since it shares
/// the page you are looking at. See `canvas_toolbar.dart`.
///
/// None of the width arithmetic the old bar needed survives. It measured
/// label widths with a `TextPainter` and re-ran on font load because the
/// centre pill was positioned against the *bar*, so it had to know exactly
/// how wide both clusters would get. Centring between the clusters, the way
/// the design specifies, makes that self-solving: the flexes take whatever is
/// left. Two plain width thresholds are all that is left of it.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../ui/colors.dart';
import '../../ui/organic.dart';
import '../../ui/theme.dart';
import '../ai/ai_state.dart';
import '../auth/auth_notifier.dart';
import '../search/global_search.dart';

/// The mark, as the design specifies it — the raster mark, not the SVG logo
/// the login screen draws.
const String kMarioMarkAsset = 'assets/logo/mario_mark.png';

/// The real global-search binding, from `keyboard_shortcuts.dart`
/// (`SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true)`).
/// It is control-based on every platform, so the hint reads the same
/// everywhere rather than pretending to be ⌘K on macOS.
const String _kSearchShortcut = 'Ctrl+Shift+F';

/// How the design draws that binding in the field: spaced glyphs, not a
/// plus-joined string.
const String _kSearchHint = 'Ctrl ⇧ F';

/// The bar's geometry, straight off the artboard.
const double _kBarHeight = 43;
const double _kMarkSize = 20;
const double _kWordmarkGap = 8;
const double _kSearchWidth = 340;
const double _kFieldHeight = 28;
const double _kIconButtonSize = 28;
const double _kAvatarSize = 24;

/// Below this the wordmark drops and the mark stands alone.
const double _kWordmarkMin = 340;

/// Below this the centre field has nothing useful left to show, so it gives
/// way to a search icon in the right cluster.
const double _kSearchMin = 620;

class ShellToolbar extends ConsumerWidget implements PreferredSizeWidget {
  const ShellToolbar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(_kBarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = marioTokens(context);
    final aiOpen = ref.watch(aiPanelProvider).isOpen;
    final user = ref.watch(authStateProvider).valueOrNull;
    final initials = _initialsOf(user?.displayName, user?.email);
    final name = user?.displayName?.trim();
    final email = user?.email?.trim();
    final account = (name != null && name.isNotEmpty) ? name : email;

    final useWindowControls = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS);

    // Container, not DecoratedBox: it insets the child by the border's own
    // dimensions, so the hairline is the last pixel OF the 43 rather than a
    // 44th one — and the bar measures the height the design gives it. A
    // DecoratedBox sizes to its child instead, which left the bar 1px short of
    // the slot the AppBar had reserved for it.
    final bar = Container(
      height: _kBarHeight,
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final showWordmark = w >= _kWordmarkMin;
            final showSearch = w >= _kSearchMin;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  _Wordmark(showWordmark: showWordmark),
                  const Spacer(),
                  if (showSearch)
                    SizedBox(
                      width: _kSearchWidth,
                      child: Tooltip(
                        message: 'Search ($_kSearchShortcut)',
                        child: MarioSearchField(
                          hint: 'Search',
                          trailing: _kSearchHint,
                          height: _kFieldHeight,
                          onTap: () => showGlobalSearch(context),
                        ),
                      ),
                    ),
                  const Spacer(),
                  // gap:2 between the right-cluster controls, and the
                  // avatar carries 4px of its own on each side.
                  if (!showSearch)
                    _BarIconButton(
                      icon: Icons.search,
                      tooltip: 'Search ($_kSearchShortcut)',
                      onTap: () => showGlobalSearch(context),
                    ),
                  _AskButton(
                    active: aiOpen,
                    onTap: () => ref.read(aiPanelProvider.notifier).toggle(),
                  ),
                  const SizedBox(width: 2),
                  _BarIconButton(
                    icon: Icons.settings_outlined,
                    tooltip: 'Settings',
                    onTap: () => context.push('/settings'),
                  ),
                  if (initials != null) ...[
                    const SizedBox(width: 4),
                    _AccountMenu(
                      initials: initials,
                      account: account,
                      email: email,
                      onSettings: () => context.push('/settings'),
                      onSignOut: () =>
                          ref.read(authNotifierProvider.notifier).signOut(),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (useWindowControls) ...[
                    const SizedBox(width: 2),
                    _BarIconButton(
                      icon: Icons.close,
                      tooltip: 'Close',
                      onTap: () => windowManager.close(),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );

    return useWindowControls ? DragToMoveArea(child: bar) : bar;
  }
}

/// Initials for the avatar, from whatever the auth state actually carries.
///
/// Returns null when there is nothing real to show — the caller then omits
/// the avatar rather than filling the slot with an invented monogram.
String? _initialsOf(String? displayName, String? email) {
  String take(String s, int count) =>
      String.fromCharCodes(s.runes.take(count)).toUpperCase();

  final name = displayName?.trim() ?? '';
  if (name.isNotEmpty) {
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return take(parts.first, 1) + take(parts.last, 1);
    return take(parts.first, math.min(2, parts.first.runes.length));
  }

  final local = (email?.trim() ?? '').split('@').first;
  if (local.isNotEmpty) {
    return take(local, math.min(2, local.runes.length));
  }
  return null;
}

/// Left zone — the 20px mark, and the wordmark at 14px.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.showWordmark});

  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(MarioRadius.xs),
          child: Image.asset(
            kMarioMarkAsset,
            width: _kMarkSize,
            height: _kMarkSize,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(width: _kWordmarkGap),
          Text('Mario', style: MarioType.wordmark(t.ink)),
        ],
      ],
    );
  }
}

/// The AI entry point.
///
/// The remodel strips this right back. It was a coral pill carrying a slow
/// animated sheen — two extra paint layers and a repeating controller on a
/// button that is on screen the entire time you are writing. The design draws
/// it as a label with an accent-tinted icon and no chrome at all, so that is
/// what it is now; the only state it shows is a `--fill` wash when the panel
/// is open.
class _AskButton extends StatelessWidget {
  const _AskButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Tooltip(
      message: active ? 'Hide Mario' : 'Ask Mario',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: _kFieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? t.fill : Colors.transparent,
            borderRadius: BorderRadius.circular(MarioRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 16, color: t.accentBase),
              const SizedBox(width: 6),
              Text(
                'Ask',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bare icon action — 28px square, 17px glyph in the secondary tone.
class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _kIconButtonSize,
          height: _kIconButtonSize,
          child: Icon(icon, size: 17, color: t.sec),
        ),
      ),
    );
  }
}

/// One row of a popup menu — icon, gap, label.
class _OverflowRow extends StatelessWidget {
  const _OverflowRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: t.sec),
        const SizedBox(width: MarioSpace.x3),
        Text(
          label,
          style: TextStyle(fontSize: 13, height: 1.2, color: t.ink),
        ),
      ],
    );
  }
}

enum _AccountAction { settings, signOut }

/// The signed-in account, and what you can do with it.
///
/// The avatar is the button for this menu: the account it names, Settings,
/// and Sign out. It looks like a plain 24px chip, which is all the design
/// draws — but a chip in that corner reads as an account button, so it
/// behaves as one rather than swallowing the tap.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.initials,
    required this.account,
    required this.email,
    required this.onSettings,
    required this.onSignOut,
  });

  final String initials;

  /// What the account is called: the display name if it has one, otherwise
  /// the email. Both come from the auth state; nothing here is invented.
  final String? account;
  final String? email;

  final VoidCallback onSettings;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    final title = account ?? 'Signed in';

    // Only worth a second line when it is not already the first one.
    final subtitle =
        (email != null && email!.isNotEmpty && email != account) ? email : null;

    return PopupMenuButton<_AccountAction>(
      tooltip: title,
      position: PopupMenuPosition.under,
      color: t.paper,
      elevation: 0,
      constraints: const BoxConstraints(minWidth: 208, maxWidth: 288),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MarioRadius.md),
        side: BorderSide(color: t.line),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: 1.2, color: t.mut),
                ),
              ],
            ],
          ),
        ),
        PopupMenuDivider(height: MarioSpace.x2, thickness: 1, color: t.line),
        const PopupMenuItem(
          value: _AccountAction.settings,
          child: _OverflowRow(icon: Icons.settings_outlined, label: 'Settings'),
        ),
        const PopupMenuItem(
          value: _AccountAction.signOut,
          child: _OverflowRow(icon: Icons.logout, label: 'Sign out'),
        ),
      ],
      onSelected: (a) {
        switch (a) {
          case _AccountAction.settings:
            onSettings();
          case _AccountAction.signOut:
            onSignOut();
        }
      },
      child: MarioAvatar(initials: initials, size: _kAvatarSize),
    );
  }
}
