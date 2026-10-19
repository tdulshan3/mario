import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/theme.dart';
import 'window.dart';

/// What the nearest [IosAppShell] / [IosSplitView] tells the widgets inside it ([IosSidebar], [IosTabBar], your
/// own iPhone back button: `IosAppShellScope.maybeOf(context)?.setSidebarVisible(true)`).
class IosAppShellScope extends InheritedWidget {
  const IosAppShellScope({
    super.key,
    required this.isRegular,
    required this.hasSidebar,
    required this.sidebarVisible,
    required this.setSidebarVisible,
    this.regularTabBarInset = 0,
    required super.child,
  });

  /// iPad-like size (≥ 744 × 600).
  final bool isRegular;
  final bool hasSidebar;

  /// iPad: the sidebar column is shown. iPhone: the sidebar is the page on screen (instead of the main column).
  final bool sidebarVisible;
  final ValueChanged<bool> setSidebarVisible;

  /// iPad with a tab bar: the 54 pt (44 row + 10) the shell added to the body's top MediaQuery padding for the
  /// floating tab bar. A navigation bar that puts its buttons in the tab bar's row (like the kit) subtracts it.
  final double regularTabBarInset;

  void toggleSidebar() => setSidebarVisible(!sidebarVisible);

  static IosAppShellScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<IosAppShellScope>();

  @override
  bool updateShouldNotify(IosAppShellScope old) =>
      old.isRegular != isRegular ||
      old.hasSidebar != hasSidebar ||
      old.sidebarVisible != sidebarVisible ||
      old.regularTabBarInset != regularTabBarInset;
}

/// The root layout of every iPhone/iPad screen in apple_ui (kit "Safe Areas and Margins" + Examples).
/// Fills the screen, keeps content out of the safe areas and places the sidebar and the tab bar:
///   iPhone (compact): [body] full screen, [tabBar] floating at the bottom (21 above the screen edge), sidebar hidden
///     — or, for a sidebar app without tabs, the [sidebar] as the full-screen first page.
///   iPad (regular): [sidebar] column (320) on the left, [tabBar] at the top centre of the main column.
/// The body gets a MediaQuery whose padding is the free area (status bar, home indicator, tab bar), so ListView,
/// CustomScrollView and SafeArea inside it keep clear of the bars automatically. Tab apps: use [IosTabView].
///
///     IosAppShell(
///       sidebar: IosSidebar(sections: …, selectedId: id, onSelected: (v) => setState(() => id = v)),
///       body: DetailPage(id: id),
///     )
class IosAppShell extends StatefulWidget {
  const IosAppShell({
    super.key,
    required this.body,
    this.sidebar,
    this.tabBar,
    this.sidebarVisible,
    this.onSidebarVisibleChanged,
    this.compactShowsSidebar,
    this.onCompactShowsSidebarChanged,
  });

  final Widget body;

  /// An [IosSidebar]. iPad: left column. iPhone: hidden, or the first page of a sidebar app (no [tabBar]).
  final Widget? sidebar;

  /// An [IosTabBar] (IosTabView sets it).
  final Widget? tabBar;

  /// iPad: the sidebar column is shown (controlled). Null = the shell keeps it (starts shown).
  final bool? sidebarVisible;
  final ValueChanged<bool>? onSidebarVisibleChanged;

  /// iPhone: the sidebar is the page on screen (controlled). Null = the shell keeps it (starts true for a sidebar app
  /// without a tab bar). Choosing a sidebar row switches to [body].
  final bool? compactShowsSidebar;
  final ValueChanged<bool>? onCompactShowsSidebarChanged;

  @override
  State<IosAppShell> createState() => _IosAppShellState();
}

class _IosAppShellState extends State<IosAppShell> {
  bool _regularVisible = true;
  late bool _compactSidebar = widget.sidebar != null && widget.tabBar == null;

  @override
  Widget build(BuildContext context) {
    return _ShellLayout(
      body: widget.body,
      sidebar: widget.sidebar,
      tabBar: widget.tabBar,
      regularVisible: widget.sidebarVisible ?? _regularVisible,
      compactSidebar: widget.compactShowsSidebar ?? _compactSidebar,
      onRegularVisible: (v) {
        if (widget.sidebarVisible == null) setState(() => _regularVisible = v);
        widget.onSidebarVisibleChanged?.call(v);
      },
      onCompactSidebar: (v) {
        if (widget.compactShowsSidebar == null) setState(() => _compactSidebar = v);
        widget.onCompactShowsSidebarChanged?.call(v);
      },
      safeAreas: true,
    );
  }
}

/// Sidebar + detail columns that fill their parent (inside an [IosWindow], a card, a demo) — the same layout as
/// [IosAppShell] without the device safe areas.
///
///     IosSplitView(sidebar: IosSidebar(…), detail: NotesList())
class IosSplitView extends StatefulWidget {
  const IosSplitView({super.key, required this.sidebar, required this.detail, this.tabBar, this.sidebarVisible, this.onSidebarVisibleChanged});

  final Widget sidebar;
  final Widget detail;

  /// Optional [IosTabBar] floating over the detail column (kit Examples/Sidebar).
  final Widget? tabBar;
  final bool? sidebarVisible;
  final ValueChanged<bool>? onSidebarVisibleChanged;

  @override
  State<IosSplitView> createState() => _IosSplitViewState();
}

class _IosSplitViewState extends State<IosSplitView> {
  bool _regularVisible = true;
  bool _compactSidebar = true;

  @override
  Widget build(BuildContext context) {
    return _ShellLayout(
      body: widget.detail,
      sidebar: widget.sidebar,
      tabBar: widget.tabBar,
      regularVisible: widget.sidebarVisible ?? _regularVisible,
      compactSidebar: _compactSidebar,
      onRegularVisible: (v) {
        if (widget.sidebarVisible == null) setState(() => _regularVisible = v);
        widget.onSidebarVisibleChanged?.call(v);
      },
      onCompactSidebar: (v) => setState(() => _compactSidebar = v),
      safeAreas: false,
    );
  }
}

class _ShellLayout extends StatelessWidget {
  const _ShellLayout({
    required this.body,
    required this.sidebar,
    required this.tabBar,
    required this.regularVisible,
    required this.compactSidebar,
    required this.onRegularVisible,
    required this.onCompactSidebar,
    required this.safeAreas,
  });

  final Widget body;
  final Widget? sidebar;
  final Widget? tabBar;
  final bool regularVisible;
  final bool compactSidebar;
  final ValueChanged<bool> onRegularVisible;
  final ValueChanged<bool> onCompactSidebar;
  final bool safeAreas;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    // A window mockup always shows both columns (kit "Window with Sidebar", 720 × 400).
    final regular = IosLayout.isRegular(context) || IosWindowScope.maybeOf(context) != null;
    final mq = MediaQuery.of(context);
    final pad = safeAreas ? mq.padding : EdgeInsets.zero;
    final hasSidebar = sidebar != null;
    final showSidebar = hasSidebar && (regular ? regularVisible : compactSidebar);
    final hasTabs = tabBar != null;

    Widget withPadding(EdgeInsets p, Widget child) =>
        MediaQuery(data: mq.copyWith(padding: p, viewPadding: p), child: child);

    // Main column: body under the floating tab bar.
    // iPhone: the bar frame (kit 95 tall) sits on the bottom edge; with a home indicator deeper than 34 it moves up.
    // iPad: the bar sits right under the status bar; content starts below its 44 pt row + 10.
    final bottomShift = math.max(0.0, pad.bottom - 34);
    final bodyPadding = EdgeInsets.only(
      left: regular && hasSidebar && regularVisible ? 0 : pad.left,
      right: pad.right,
      top: pad.top + (regular && hasTabs ? 54 : 0),
      bottom: !regular && hasTabs ? 95 + bottomShift : pad.bottom,
    );
    final main = ColoredBox(
      color: theme.ios.bgPrimary,
      child: Stack(children: [
        Positioned.fill(child: withPadding(bodyPadding, body)),
        if (hasTabs && regular) Positioned(top: pad.top, left: 0, right: 0, child: tabBar!),
        if (hasTabs && !regular)
          Positioned(
            left: math.max(0.0, pad.left - 21),
            right: math.max(0.0, pad.right - 21),
            bottom: bottomShift,
            child: tabBar!,
          ),
      ]),
    );

    Widget layout;
    if (!regular) {
      layout = showSidebar ? withPadding(pad, sidebar!) : main;
    } else if (!hasSidebar) {
      layout = main;
    } else {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      layout = Row(children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: regularVisible ? 320 : 0),
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          builder: (context, width, child) => SizedBox(
            width: width,
            child: ClipRect(
              child: OverflowBox(alignment: Alignment.centerRight, minWidth: 320, maxWidth: 320, child: child),
            ),
          ),
          child: withPadding(EdgeInsets.only(top: pad.top, left: pad.left, bottom: pad.bottom), sidebar!),
        ),
        Expanded(child: main),
      ]);
    }

    return IosAppShellScope(
      isRegular: regular,
      hasSidebar: hasSidebar,
      sidebarVisible: showSidebar,
      setSidebarVisible: regular ? onRegularVisible : onCompactSidebar,
      regularTabBarInset: regular && hasTabs ? 54 : 0,
      child: ColoredBox(color: theme.ios.bgPrimary, child: layout),
    );
  }
}
