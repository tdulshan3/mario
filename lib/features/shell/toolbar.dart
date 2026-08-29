/// ShellToolbar — the design's top bar (artboard 2a).
///
/// 68px of glass over the ground, split into three zones:
///
///   left    the mark and the "Mario" wordmark
///   centre  a search pill, centred on the *bar* rather than on the space
///           left over between the two side clusters
///   right   Share, the Ask Mario primary, and the signed-in avatar
///
/// The app has more actions than the artboard draws. Settings has no zone in
/// the new bar, so it lives in the overflow menu, and in the account menu the
/// avatar opens; Share folds into the overflow menu whenever the bar cannot
/// hold both the Share button and the centre pill. Nothing was dropped.
///
/// Every width the bar reserves is measured rather than guessed — the labels
/// with a [TextPainter] against the face that is actually resident, the
/// controls from the same constants the controls are built from. And the pill
/// is sized against the widest form the bar will ever take, not the form it
/// happens to have at this width, so no control disappears as the window
/// grows.
///
/// The window close button stays visible rather than folding into the menu:
/// Linux runs with `TitleBarStyle.hidden` (see
/// `platform/linux/window_config_linux.dart`), so this is the only close
/// affordance the window has. The bar also doubles as the drag-to-move area.
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
import '../sharing/share_dialog.dart';

/// The mark, as the design specifies it — the raster mark, not the SVG logo
/// the login screen draws.
const String kMarioMarkAsset = 'assets/logo/mario_mark.png';

/// The real global-search binding, from `keyboard_shortcuts.dart`
/// (`SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true)`).
/// It is control-based on every platform, so the hint reads the same
/// everywhere rather than pretending to be ⌘K on macOS.
const String _kSearchShortcut = 'Ctrl+Shift+F';

/// The bar's fixed geometry. The controls below and the width arithmetic in
/// [ShellToolbar.build] both read these, so a control cannot change size
/// without the space reserved for it changing with it.
const double _kMarkSize = 38;
const double _kWordmarkGap = 10;
const double _kAvatarSize = 38;
const double _kIconButtonSize = 40;
const double _kButtonIconSize = 16;

/// A pill button's outline is part of its width — [BoxDecoration] counts the
/// border into the box. Share always carries one; Ask Mario grows one when the
/// AI panel is open, so the reserve carries it either way.
const double _kButtonOutline = 1;

/// The centre pill never grows past [_kPillMax]. Below [_kPillMin] the
/// placeholder has nothing left to say, so the pill gives way to the search
/// icon in the right cluster.
const double _kPillMax = 460;
const double _kPillMin = 190;

/// Clear space the pill keeps between itself and each side cluster.
const double _kPillClearance = MarioSpace.x6;

/// The width [text] will actually occupy in [style], for the font that is
/// resident right now.
///
/// The bar used to carry these numbers as constants (62 for the wordmark, 138
/// for "Ask Mario", 106 for "Share"). They were right for Caprasimo and
/// Figtree — which google_fonts fetches at runtime — and wrong for every frame
/// before those arrive, where the bar reserved room for a face that was not on
/// screen and the pill overlapped the buttons. Measuring is exact for whichever
/// face is loaded, and [_FontChangeBuilder] re-runs the arithmetic when the
/// real one lands.
double _labelWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The laid-out width of a labelled bar button — [_AskMarioButton] showing its
/// label, or a [_SecondaryBarButton]. Both are icon, gap, label inside
/// [MarioSpace.x4] of horizontal padding.
double _labelledButtonWidth(double labelWidth) =>
    _kButtonOutline * 2 +
    MarioSpace.x4 * 2 +
    _kButtonIconSize +
    MarioSpace.x2 +
    labelWidth;

class ShellToolbar extends ConsumerWidget implements PreferredSizeWidget {
  const ShellToolbar({super.key});

  /// 68px including the 1px hairline the glass draws along its bottom edge.
  static const double _height = 68;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final bar = MarioGlass(
      opacity: 0.72,
      border: Border(bottom: BorderSide(color: marioDivider(context))),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          // The border contributes the remaining pixel of [_height].
          height: _height - 1,
          child: _FontChangeBuilder(
            builder: (context) {
              final textTheme = Theme.of(context).textTheme;

              // The three labels the bar has to leave room for, measured
              // against the face that is on screen right now.
              final wordmarkLabel = _labelWidth(context, 'Mario',
                  textTheme.headlineMedium?.copyWith(fontSize: 21));
              final askLabel = _labelWidth(context, 'Ask Mario',
                  textTheme.titleLarge?.copyWith(fontSize: 14));
              final shareLabel = _labelWidth(context, 'Share',
                  textTheme.titleLarge?.copyWith(fontSize: 14));

              // What each cluster measures in the widest form it will ever
              // take: wordmark out, Ask labelled, and the avatar if this
              // account has initials to show at all.
              //
              // The pill is sized against *these*, not against the clusters as
              // they stand at the current width. Reserving for the final form
              // is what makes the pill's arrival monotonic in the window width:
              // its test reduces to `pillFor(rightReserve) >= _kPillMin`, a
              // plain threshold on w. Sizing it against the current form is
              // what let a later breakpoint — Share, at 900 — take the room
              // back and blink the pill out of existence as the window got
              // *wider*.
              final leftReserve = _kMarkSize + _kWordmarkGap + wordmarkLabel;
              var rightReserve = _kIconButtonSize; // Settings
              if (useWindowControls) {
                rightReserve += _kIconButtonSize + MarioSpace.x2;
              }
              if (initials != null) {
                rightReserve += _kAvatarSize + MarioSpace.x2;
              }
              rightReserve += _labelledButtonWidth(askLabel) + MarioSpace.x2;
              // Share no longer has an overflow menu to fall back into, so it
              // is always on the bar — as an icon when the label will not fit.
              // Only the icon's width is unconditional; the label is the part
              // that has to earn its room.
              rightReserve += _kIconButtonSize + MarioSpace.x2;
              final shareReserve =
                  _labelledButtonWidth(shareLabel) - _kIconButtonSize;

              return LayoutBuilder(
                builder: (context, constraints) {
                  const pad = MarioSpace.x4;
                  final w = constraints.maxWidth - pad * 2;

                  // Collapse from least- to most-essential as the window
                  // narrows. Desktop minimum is 800px, so most users see
                  // everything.
                  final showWordmark = w >= 340;
                  final showAskLabel = w >= 560;
                  final avatarInitials = w >= 440 ? initials : null;

                  // The centre pill is centred on the bar, not on the slack
                  // between the clusters, so its width is the largest that
                  // clears the wider of the two sides twice over.
                  double pillFor(double right) => math.min(
                        _kPillMax,
                        w -
                            math.max(leftReserve, right) * 2 -
                            _kPillClearance * 2,
                      );

                  // Share's LABEL is the enhancement — the control itself is
                  // always there. The pill is never narrower with the icon-only
                  // Share than with the labelled one, so both stay on plain
                  // width thresholds and neither can vanish as the window
                  // widens.
                  final shareRight = rightReserve + shareReserve;
                  final showShareButton = pillFor(shareRight) >= _kPillMin;
                  final pillWidth =
                      pillFor(showShareButton ? shareRight : rightReserve);
                  final showPill = pillWidth >= _kPillMin;

                  final right = <Widget>[
                    // When the pill will not fit, search keeps a one-click
                    // home here rather than dropping into the overflow menu.
                    if (!showPill)
                      _BarIconButton(
                        icon: Icons.search,
                        tooltip: 'Search ($_kSearchShortcut)',
                        onTap: () => showGlobalSearch(context),
                      ),
                    if (showShareButton)
                      _SecondaryBarButton(
                        icon: Icons.ios_share,
                        label: 'Share',
                        onTap: () => showShareDialog(context, ref),
                      )
                    else
                      _BarIconButton(
                        icon: Icons.ios_share,
                        tooltip: 'Share',
                        onTap: () => showShareDialog(context, ref),
                      ),
                    _AskMarioButton(
                      active: aiOpen,
                      showLabel: showAskLabel,
                      onTap: () => ref.read(aiPanelProvider.notifier).toggle(),
                    ),
                    _BarIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Settings',
                      onTap: () => context.push('/settings'),
                    ),
                    if (avatarInitials != null)
                      _AccountMenu(
                        initials: avatarInitials,
                        account: account,
                        email: email,
                        onSettings: () => context.push('/settings'),
                        onSignOut: () =>
                            ref.read(authNotifierProvider.notifier).signOut(),
                      ),
                    if (useWindowControls)
                      _BarIconButton(
                        icon: Icons.close,
                        tooltip: 'Close',
                        onTap: () => windowManager.close(),
                      ),
                  ];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: pad),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Row(
                            children: [
                              _Wordmark(showWordmark: showWordmark),
                              const Spacer(),
                              for (var i = 0; i < right.length; i++) ...[
                                if (i > 0) const SizedBox(width: MarioSpace.x2),
                                right[i],
                              ],
                            ],
                          ),
                        ),
                        // Sits above the row but only claims its own bounds,
                        // so taps outside the pill still reach the clusters.
                        if (showPill)
                          Positioned.fill(
                            child: Center(
                              child: _SearchPill(
                                width: pillWidth,
                                onTap: () => showGlobalSearch(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
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

/// Left zone — the mark, rounded, and the wordmark in the display face.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.showWordmark});

  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(13),
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
          Text(
            'Mario',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 21),
          ),
        ],
      ],
    );
  }
}

/// Centre zone — the search pill. Opens the same global search the toolbar's
/// search action has always opened.
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.width, required this.onTap});

  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Below this the key hint would eat the placeholder; the shortcut still
    // works, and the tooltip still names it.
    final showHint = width >= 300;

    return SizedBox(
      width: width,
      height: 42,
      child: MarioGlass(
        opacity: 0.62,
        borderRadius: BorderRadius.circular(MarioRadius.pill),
        border: Border.all(color: marioDivider(context)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(MarioRadius.pill),
            child: Tooltip(
              message: 'Search ($_kSearchShortcut)',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.search,
                        size: 17, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Search notes, notebooks, anything',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    if (showHint) ...[
                      const SizedBox(width: 10),
                      const MarioKeyHint(_kSearchShortcut),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The design's primary button, wired to the AI side panel.
///
/// Closed, it is the coral primary the artboard draws. Open, it flips to a
/// tinted, outlined state so the bar shows the panel is up — the same toggle
/// the old icon button expressed by recolouring itself.
/// The AI entry point, with a slow glass sheen travelling across it.
///
/// Two layers make the "glass": a fixed gloss — a highlight over the top half,
/// the way light sits on a curved surface — and a soft band that sweeps left to
/// right on a long cycle. The sweep is deliberately slow and low-contrast: this
/// button is always on screen, and anything brisk enough to notice twice is
/// something you then cannot stop noticing while you write.
///
/// The animation stops dead when the platform asks for reduced motion. It is
/// decoration with no informational content, so there is nothing to preserve
/// by animating it anyway.
///
/// Note for widget tests: the controller repeats while the AI panel is closed,
/// so `pumpAndSettle` on a tree containing this button times out unless the
/// panel is open. Pump fixed durations, or wrap the subject in a MediaQuery
/// with `disableAnimations: true`, which parks the controller at rest.
class _AskMarioButton extends StatefulWidget {
  const _AskMarioButton({
    required this.active,
    required this.showLabel,
    required this.onTap,
  });

  final bool active;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  State<_AskMarioButton> createState() => _AskMarioButtonState();
}

class _AskMarioButtonState extends State<_AskMarioButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSheen();
  }

  @override
  void didUpdateWidget(_AskMarioButton old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncSheen();
  }

  /// Runs the sheen only when it can do its job.
  ///
  /// It repeated forever, which meant the app never idled: an ever-running
  /// controller schedules a frame every 16ms for the life of the process, and
  /// every one of those frames re-ran the toolbar's backdrop blur — and every
  /// other blur on screen with it. That is a constant cost paid to animate a
  /// button nobody is looking at, and it is why the app felt heavy even at
  /// rest.
  ///
  /// The panel being open is the signal that matters: the sheen exists to make
  /// the button noticeable, and once the user is already in the AI panel it
  /// has nothing left to advertise.
  void _syncSheen() {
    final wanted = !MediaQuery.of(context).disableAnimations && !widget.active;
    if (wanted) {
      if (!_sheen.isAnimating) _sheen.repeat();
    } else if (_sheen.isAnimating || _sheen.value != 0) {
      // Reset as well as stop, so a controller parked mid-sweep does not leave
      // a stripe frozen across the button.
      _sheen.stop();
      _sheen.value = 0;
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = marioMode(context).isDark;
    final active = widget.active;
    final bg = active ? scheme.primary.withValues(alpha: 0.16) : scheme.primary;
    // Active, the fill is only a 16% gold tint, so the label cannot also be
    // gold: #F2C14E on the cream ground measures 1.59:1 and the whole button
    // vanishes. Take a ramp step that separates from the ground instead —
    // dark gold on the light grounds, pale gold on the dark ones — so the
    // state still reads as gold without becoming invisible.
    final fg = active
        ? (dark ? MarioColors.accent300 : MarioColors.accent700)
        : scheme.onPrimary;

    // The sheen is white on the solid gold fill, where it reads as light on a
    // glossy surface. Over the active state's 16% tint there is far less to
    // catch, so it borrows the foreground's own gold instead of washing the
    // button toward grey.
    // Tuned down hard from the first pass. At 0.42 the band read as a stripe
    // painted across the button rather than light moving over it — on a fill
    // that is already gold, a white sheen that strong just bleaches a diagonal
    // through the middle. Light on a real glossy surface is a hint, not a mark.
    final sheenColour = active
        ? fg.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.16);
    final radius = BorderRadius.circular(MarioRadius.pill);

    // The fill is the ancestor and the ink Material sits inside it, so the
    // press splash lands on top of the gold instead of behind it.
    return Tooltip(
      message: active ? 'Hide AI panel' : 'Ask AI / Quiz',
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: active ? Border.all(color: fg, width: _kButtonOutline) : null,
          boxShadow: active ? const [] : marioShadow(context, level: 0),
        ),
        child: ClipRRect(
          borderRadius: radius,
          // Centre, not the default topStart. The gloss and sheen layers are
          // Positioned.fill, but the content Material is not — so with the
          // default alignment it took its intrinsic height and sat pinned to
          // the TOP of the 40px button. Adding the Stack for the sheen is what
          // broke the label's alignment; this is the missing half of it.
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Fixed gloss: brighter across the top, fading by the middle.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: active ? 0.04 : 0.10),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.55],
                      ),
                    ),
                  ),
                ),
              ),
              // The travelling band. RepaintBoundary keeps the repaint to this
              // button rather than the whole toolbar it sits in.
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _sheen,
                      builder: (context, _) {
                        // Runs from fully off the left to fully off the right,
                        // so the band enters and leaves rather than popping.
                        final x = -1.6 + _sheen.value * 3.2;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(x - 0.28, -1),
                              end: Alignment(x + 0.28, 1),
                              colors: [
                                sheenColour.withValues(alpha: 0),
                                sheenColour,
                                sheenColour.withValues(alpha: 0),
                              ],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: radius,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal:
                            widget.showLabel ? MarioSpace.x4 : MarioSpace.x3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome,
                            size: _kButtonIconSize, color: fg),
                        if (widget.showLabel) ...[
                          const SizedBox(width: MarioSpace.x2),
                          Text(
                            'Ask Mario',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontSize: 14, height: 1, color: fg),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The design's secondary button — an outlined pill on the glass.
class _SecondaryBarButton extends StatelessWidget {
  const _SecondaryBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MarioRadius.pill),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: MarioSpace.x4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MarioRadius.pill),
            border: Border.all(color: scheme.outline, width: _kButtonOutline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: _kButtonIconSize, color: scheme.onSurface),
              const SizedBox(width: MarioSpace.x2),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    // height: 1 for the same reason as the Ask button —
                    // Caprasimo's 1.12 leading sits the glyphs low in their
                    // line box, so a Row centres the BOX correctly and the
                    // text still looks off.
                    .titleLarge
                    ?.copyWith(
                        fontSize: 14, height: 1, color: scheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bare icon action, sized to sit level with the pill buttons.
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
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MarioRadius.pill),
          child: SizedBox(
            width: _kIconButtonSize,
            height: _kIconButtonSize,
            child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _OverflowRow extends StatelessWidget {
  const _OverflowRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: MarioSpace.x3),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontSize: 14, color: scheme.onSurface),
        ),
      ],
    );
  }
}

enum _AccountAction { settings, signOut }

/// The signed-in account, and what you can do with it.
///
/// The avatar used to be a tooltip and nothing else — a 38px chip in the
/// corner that reads as an account button but swallowed every tap. It is the
/// button for this menu now: the account it names, Settings (the same route
/// the overflow menu pushes) and Sign out (the same call the Account section
/// of Settings makes). Styled as [_OverflowMenu] is, so the two menus in the
/// same corner match.
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = account ?? 'Signed in';

    // Only worth a second line when it is not already the first one.
    final subtitle =
        (email != null && email!.isNotEmpty && email != account) ? email : null;

    return PopupMenuButton<_AccountAction>(
      tooltip: title,
      position: PopupMenuPosition.under,
      color: scheme.surfaceContainerHigh,
      elevation: 0,
      constraints: const BoxConstraints(minWidth: 208, maxWidth: 288),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MarioRadius.md),
        side: BorderSide(color: marioDivider(context)),
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
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        PopupMenuDivider(
          height: MarioSpace.x2,
          thickness: 1,
          color: marioDivider(context),
        ),
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

/// Rebuilds its subtree when a font finishes loading.
///
/// The bar reserves room for its own labels by measuring them, which is only
/// right for the face that is resident. google_fonts fetches Caprasimo and
/// Figtree at runtime, so the first frames of a cold start measure the
/// fallback. When the real face lands the engine re-lays-out every paragraph
/// on screen — but not the arithmetic that ran in [build], which is what this
/// exists to re-run.
class _FontChangeBuilder extends StatefulWidget {
  const _FontChangeBuilder({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_FontChangeBuilder> createState() => _FontChangeBuilderState();
}

class _FontChangeBuilderState extends State<_FontChangeBuilder> {
  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    super.dispose();
  }

  void _fontsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
