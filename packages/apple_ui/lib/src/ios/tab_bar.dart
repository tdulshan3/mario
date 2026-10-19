import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/glass.dart';
import '../core/icons.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import 'app_shell.dart';

/// What a tab is (kit Tab Bar "Type").
enum IosTabRole {
  /// A normal tab inside the material capsule.
  normal,

  /// The search tab (kit "Search Role"): a separate material circle at the end on iPhone, the last symbol on iPad.
  search,

  /// One key tab shown like the search tab (kit "Prominent Tab"), e.g. "New".
  prominent,
}

/// One tab of an [IosTabBar] / [IosTabView].
///
///     const IosTab(icon: AppleIcons.houseFill, label: 'Home')
///     const IosTab(icon: AppleIcons.magnifyingglass, label: 'Search', role: IosTabRole.search)
@immutable
class IosTab {
  const IosTab({required this.icon, required this.label, this.role = IosTabRole.normal});

  /// The symbol (iPhone). Use the filled version of a symbol.
  final IconData icon;

  /// One short word: under the symbol on iPhone, the tab text on iPad, and the accessible name.
  final String label;
  final IosTabRole role;
}

// Kit colours that are not tokens: the selected pill is "Fills - Vibrant/Tertiary" plus darker (Light) /
// plus lighter (Dark) on the material, written as one normal fill.
Color _pill(bool dark) => dark ? const Color(0x14FFFFFF) : const Color(0x12000000);
Color _hover(bool dark) => dark ? const Color(0x0DFFFFFF) : const Color(0x0A000000);

/// The app's tab bar (kit "Tab Bar - iPhone" and "Tab Bar - iPad"). Usually [IosTabView] builds it for you.
///
/// iPhone (compact): a floating capsule of Regular blur material, symbol 18 Semibold over a 10 pt Semibold label, the
/// selected tab in the accent colour on a grey pill; a search/prominent tab is a separate 62 circle at the right edge.
/// [minimized] shows only the selected symbol in a 48 circle. iPad (regular): one 44 tall material capsule with a
/// sidebar button, text tabs (15 Medium, Bold when selected) and the search symbol. Give it the full width.
///
///     IosTabBar(
///       tabs: const [
///         IosTab(icon: AppleIcons.houseFill, label: 'Home'),
///         IosTab(icon: AppleIcons.book, label: 'Library'),
///         IosTab(icon: AppleIcons.magnifyingglass, label: 'Search', role: IosTabRole.search),
///       ],
///       selectedIndex: index,
///       onChanged: (i) => setState(() => index = i),
///     )
class IosTabBar extends StatelessWidget {
  const IosTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.minimized = false,
    this.onMinimizedChanged,
    this.onSidebarToggle,
    this.sidebarVisible,
    this.regular,
    this.semanticLabel = 'Tab bar',
  }) : assert(tabs.length >= 1);

  /// 2–5 tabs; tabs with [IosTabRole.search] / [IosTabRole.prominent] go last.
  final List<IosTab> tabs;
  final int selectedIndex;

  /// Receives the tapped tab's index. Null = disabled.
  final ValueChanged<int>? onChanged;

  /// iPhone only: just the selected tab's symbol in a circle (after scrolling down). Ignored on iPad.
  final bool minimized;

  /// Called with false when the minimized bar's tab is tapped.
  final ValueChanged<bool>? onMinimizedChanged;

  /// iPad: shows the sidebar button at the start. Null = automatic inside an [IosAppShell] that has a sidebar.
  final VoidCallback? onSidebarToggle;

  /// iPad: the sidebar is visible (accessible name of the sidebar button). Null = from the [IosAppShell].
  final bool? sidebarVisible;

  /// Force the iPad (true) or iPhone (false) look. Null = [IosLayout.isRegular].
  final bool? regular;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final isRegular = regular ?? IosLayout.isRegular(context);
    final shell = IosAppShellScope.maybeOf(context);
    final toggle = onSidebarToggle ?? (shell != null && shell.hasSidebar ? shell.toggleSidebar : null);
    final visible = sidebarVisible ?? shell?.sidebarVisible ?? false;
    final normal = <int>[
      for (var i = 0; i < tabs.length; i++)
        if (tabs[i].role == IosTabRole.normal) i,
    ];
    final separate = <int>[
      for (var i = 0; i < tabs.length; i++)
        if (tabs[i].role != IosTabRole.normal) i,
    ];
    Widget bar = isRegular
        ? _regular(context, normal, separate, toggle, visible)
        : (minimized ? _minimized(context, separate) : _compact(context, normal, separate));
    return Semantics(container: true, explicitChildNodes: true, label: semanticLabel, child: bar);
  }

  void _select(int i) => onChanged?.call(i);

  // iPhone: frame padding 12 / 21 / 21 (kit 402 × 95), capsule padding 4 / 10, tabs 54 tall.
  Widget _compact(BuildContext context, List<int> normal, List<int> separate) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(21, 12, 21, 21),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Tab width before shrinking: 85 (kit 93 minus the 8 pt overlap of its -8 gap); 112 with a separate circle.
          final basis = separate.isEmpty ? 85.0 : 112.0;
          final available = constraints.maxWidth - separate.length * (62 + 8) - 20;
          final tabWidth = normal.isEmpty
              ? basis
              : (constraints.hasBoundedWidth ? math.min(basis, available / normal.length) : basis);
          final capsule = AppleGlass(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final i in normal)
                  _CompactTab(
                    tab: tabs[i],
                    width: tabWidth,
                    selected: i == selectedIndex,
                    onTap: onChanged == null ? null : () => _select(i),
                  ),
              ],
            ),
          );
          return Row(
            mainAxisAlignment: separate.isEmpty ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              capsule,
              if (separate.isNotEmpty) const Spacer(),
              for (final i in separate) ...[
                if (i != separate.first) const SizedBox(width: 8),
                _RoundTab(
                  tab: tabs[i],
                  size: 62,
                  selected: i == selectedIndex,
                  onTap: onChanged == null ? null : () => _select(i),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // iPhone minimized (kit Minimized = True): frame padding 12 / 28 / 28, 48 circles.
  Widget _minimized(BuildContext context, List<int> separate) {
    final theme = AppleTheme.of(context);
    final current = tabs[selectedIndex.clamp(0, tabs.length - 1)];
    final selectedCircle = Semantics(
      button: true,
      selected: true,
      label: current.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onMinimizedChanged?.call(false),
        child: AppleGlass(
          padding: const EdgeInsets.all(4),
          child: SizedBox(width: 40, height: 40, child: Center(child: _symbol(current.icon, 18, theme.accentColor))),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      child: Row(
        children: [
          selectedCircle,
          const Spacer(),
          for (final i in separate) ...[
            if (i != separate.first) const SizedBox(width: 8),
            _RoundTab(
              tab: tabs[i],
              size: 48,
              selected: i == selectedIndex,
              onTap: onChanged == null ? null : () => _select(i),
            ),
          ],
        ],
      ),
    );
  }

  // iPad: one 44 tall capsule, padding 4.
  Widget _regular(
    BuildContext context,
    List<int> normal,
    List<int> separate,
    VoidCallback? toggle,
    bool sidebarVisible,
  ) {
    return Center(
      child: AppleGlass(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (toggle != null)
              _RegularTab(
                icon: AppleIcons.sidebarLeft,
                label: sidebarVisible ? 'Hide Sidebar' : 'Show Sidebar',
                selected: false,
                onTap: toggle,
              ),
            for (final i in normal)
              _RegularTab(
                label: tabs[i].label,
                selected: i == selectedIndex,
                onTap: onChanged == null ? null : () => _select(i),
              ),
            for (final i in separate)
              _RegularTab(
                icon: tabs[i].icon,
                label: tabs[i].label,
                selected: i == selectedIndex,
                onTap: onChanged == null ? null : () => _select(i),
              ),
          ],
        ),
      ),
    );
  }
}

/// A symbol that takes [size] of layout space and is drawn 1.2× like an SF Symbol.
Widget _symbol(IconData icon, double size, Color color) => SizedBox(
  width: size,
  height: size,
  child: OverflowBox(
    maxWidth: size * 1.2,
    maxHeight: size * 1.2,
    child: Icon(icon, size: size * 1.2, color: color),
  ),
);

/// Pressed / hovered state for a tab.
abstract class _PressableState<T extends StatefulWidget> extends State<T> {
  bool pressed = false;
  bool hovered = false;

  Widget pressable({
    required VoidCallback? onTap,
    required Widget child,
    required String label,
    required bool selected,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onTap == null ? null : (_) => setState(() => pressed = true),
          onTapUp: onTap == null ? null : (_) => setState(() => pressed = false),
          onTapCancel: onTap == null ? null : () => setState(() => pressed = false),
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

// iPhone tab (kit "_Tab Bar Button - iPhone"): padding 6 / 8 / 7, symbol box 28, 1 gap, label 10/12 Semibold.
class _CompactTab extends StatefulWidget {
  const _CompactTab({required this.tab, required this.width, required this.selected, required this.onTap});
  final IosTab tab;
  final double width;
  final bool selected;
  final VoidCallback? onTap;
  @override
  State<_CompactTab> createState() => _CompactTabState();
}

class _CompactTabState extends _PressableState<_CompactTab> {
  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final color = widget.selected ? theme.accentColor : theme.ios.labelControlPrimary;
    final label = appleFont(size: 10).copyWith(
      fontSize: 10,
      height: 12 / 10,
      letterSpacing: 0.12,
      fontWeight: FontWeight.w600,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: TextDecoration.none,
    );
    final showPill = widget.selected || pressed;
    return pressable(
      onTap: widget.onTap,
      label: widget.tab.label,
      selected: widget.selected,
      child: SizedBox(
        width: widget.width,
        height: 54,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The pill reaches 6 past the tab on each side (kit "Selection", 4 inside the material).
            if (showPill)
              Positioned(
                left: -6,
                right: -6,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: ShapeDecoration(color: _pill(theme.isDark), shape: const StadiumBorder()),
                ),
              ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 7),
                child: Column(
                  children: [
                    SizedBox(height: 28, child: Center(child: _symbol(widget.tab.icon, 18, color))),
                    const SizedBox(height: 1),
                    Text(
                      widget.tab.label,
                      style: label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Separate circle (kit "_Tab Bar Button Round - iPhone"): material, symbol 17 (search) / 18 (prominent), pill inset 4.
class _RoundTab extends StatefulWidget {
  const _RoundTab({required this.tab, required this.size, required this.selected, required this.onTap});
  final IosTab tab;
  final double size;
  final bool selected;
  final VoidCallback? onTap;
  @override
  State<_RoundTab> createState() => _RoundTabState();
}

class _RoundTabState extends _PressableState<_RoundTab> {
  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final color = widget.selected ? theme.accentColor : theme.ios.labelControlPrimary;
    final symbolSize = widget.tab.role == IosTabRole.search ? 17.0 : 18.0;
    return pressable(
      onTap: widget.onTap,
      label: widget.tab.label,
      selected: widget.selected,
      child: AppleGlass(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            children: [
              if (widget.selected || pressed)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(color: _pill(theme.isDark), shape: const CircleBorder()),
                    ),
                  ),
                ),
              Center(child: _symbol(widget.tab.icon, symbolSize, color)),
            ],
          ),
        ),
      ),
    );
  }
}

// iPad tab (kit "_Tab Bar Button - iPad - Text" / "- Symbol"): 36 tall; text padding 18, symbol tabs 54 wide.
class _RegularTab extends StatefulWidget {
  const _RegularTab({this.icon, required this.label, required this.selected, required this.onTap});
  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  State<_RegularTab> createState() => _RegularTabState();
}

class _RegularTabState extends _PressableState<_RegularTab> {
  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final color = widget.selected ? theme.accentColor : c.tabTextUnselected;
    final fill = widget.selected || pressed
        ? _pill(theme.isDark)
        : (hovered ? _hover(theme.isDark) : const Color(0x00000000));
    final Widget content = widget.icon != null
        ? SizedBox(width: 54, height: 36, child: Center(child: _symbol(widget.icon!, 15, color)))
        : Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              maxLines: 1,
              style: appleFont(size: 15).copyWith(
                fontSize: 15,
                height: 20 / 15,
                letterSpacing: -0.23,
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
                leadingDistribution: TextLeadingDistribution.even,
                decoration: TextDecoration.none,
              ),
            ),
          );
    return pressable(
      onTap: widget.onTap,
      label: widget.label,
      selected: widget.selected,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
        child: content,
      ),
    );
  }
}

/// A tab app (SwiftUI `TabView`): the [IosAppShell] + an [IosTabBar] + one page per tab. Pages are built the
/// first time their tab is opened and keep their state and scroll position.
/// iPhone: the bar floats at the bottom. iPad: the bar sits at the top centre; with a [sidebar] it gets a sidebar button.
///
///     IosTabView(
///       tabs: const [
///         IosTab(icon: AppleIcons.houseFill, label: 'Home'),
///         IosTab(icon: AppleIcons.book, label: 'Library'),
///         IosTab(icon: AppleIcons.magnifyingglass, label: 'Search', role: IosTabRole.search),
///       ],
///       pageBuilder: (context, index) => [HomePage(), LibraryPage(), SearchPage()][index],
///       minimizeOnScroll: true,
///     )
class IosTabView extends StatefulWidget {
  const IosTabView({
    super.key,
    required this.tabs,
    required this.pageBuilder,
    this.selectedIndex,
    this.initialIndex = 0,
    this.onChanged,
    this.sidebar,
    this.minimizeOnScroll = false,
  });

  final List<IosTab> tabs;

  /// The page for a tab index. Pages scroll themselves (ListView, CustomScrollView…); the shell's MediaQuery
  /// padding keeps them clear of the status bar, the home indicator and the tab bar.
  final IndexedWidgetBuilder pageBuilder;

  /// The selected tab (controlled). Null = the view keeps it, starting at [initialIndex].
  final int? selectedIndex;
  final int initialIndex;
  final ValueChanged<int>? onChanged;

  /// iPad: an [IosSidebar] column (shown/hidden with the sidebar button). Hidden on iPhone.
  final Widget? sidebar;

  /// iPhone: minimize the tab bar while scrolling down, expand on scroll up (SwiftUI `.tabBarMinimizeBehavior(.onScrollDown)`).
  final bool minimizeOnScroll;

  @override
  State<IosTabView> createState() => _IosTabViewState();
}

class _IosTabViewState extends State<IosTabView> {
  late int _index = widget.selectedIndex ?? widget.initialIndex;
  final Set<int> _visited = <int>{};
  bool _minimized = false;
  double _travel = 0;

  int get _current => (widget.selectedIndex ?? _index).clamp(0, widget.tabs.length - 1);

  void _select(int i) {
    setState(() {
      _index = i;
      _minimized = false;
      _travel = 0;
    });
    widget.onChanged?.call(i);
  }

  bool _onScroll(ScrollUpdateNotification n) {
    if (!widget.minimizeOnScroll || n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (IosLayout.isRegular(context)) return false;
    final delta = n.scrollDelta ?? 0;
    _travel = (delta > 0) == (_travel > 0) ? _travel + delta : delta;
    if (_travel > 6 && n.metrics.pixels > 40 && !_minimized) setState(() => _minimized = true);
    if ((_travel < -6 || n.metrics.pixels <= 0) && _minimized) setState(() => _minimized = false);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    _visited.add(current);
    return IosAppShell(
      sidebar: widget.sidebar,
      tabBar: IosTabBar(
        tabs: widget.tabs,
        selectedIndex: current,
        onChanged: _select,
        minimized: _minimized,
        onMinimizedChanged: (v) => setState(() => _minimized = v),
      ),
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: _onScroll,
        child: IndexedStack(
          index: current,
          sizing: StackFit.expand,
          children: [
            for (var i = 0; i < widget.tabs.length; i++)
              _visited.contains(i) ? widget.pageBuilder(context, i) : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}
