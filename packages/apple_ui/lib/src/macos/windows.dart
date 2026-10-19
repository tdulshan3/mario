import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_chrome.dart';
import 'scroll_views.dart';
import 'toolbars.dart';

/// How a [MacWindow] is drawn.
enum MacWindowStyle {
  /// The app IS the window (Flutter desktop app, or the whole browser tab): fills its parent, square corners,
  /// no shadow. The operating system draws the real title bar buttons. The default.
  page,

  /// A drawn Mac window for mockups, screenshots and demos: radius 16 (continuous corners), window shadow,
  /// a 1 px white 20% inner stroke in Dark Mode. Give it a size (SizedBox) or let its parent size it.
  window,

  /// A small floating panel (Colors, Fonts, a tool palette): radius 15, one 0 5 20 shadow, 10 px traffic lights,
  /// centred title, optional tab row.
  utility,
}

/// Title bar style (kit "Window Type"). One style per window; [unified] is the default.
enum MacToolbarStyle {
  /// Unified toolbar + title: one 52 px row, XL (36 px) toolbar items. Finder, Mail, Notes, most apps.
  unified,

  /// Unified compact: one 40 px row, medium (24 px) toolbar items. Many items or a small window.
  compact,

  /// Expanded: the title on its own 31 px row, then a 44 px toolbar row (XL items).
  expanded,

  /// No toolbar: a 31 px bar with the traffic lights and the title (About boxes, small forms).
  none,
}

/// What the title bar needs to know about its window (style, and whether it sits in the main pane next to a sidebar).
class _MacWindowScope extends InheritedWidget {
  const _MacWindowScope({required this.style, required this.mainPane, required super.child});
  final MacWindowStyle style;
  final bool mainPane;

  static _MacWindowScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_MacWindowScope>();

  @override
  bool updateShouldNotify(_MacWindowScope old) => old.style != style || old.mainPane != mainPane;
}

/// A macOS window (kit page "Windows"): the frame, an optional sidebar, the title bar, and the content area —
/// plus an optional list column (Mail / Notes) and inspector pane on the right.
///
///     // A Flutter desktop app: the window IS the app window (style: page, the default).
///     MacWindow(
///       sidebar: MacSidebar(children: [ … ]),
///       titlebar: MacTitlebar(title: 'Recents', subtitle: '14 items', actions: [
///         MacToolbarButton(icon: AppleIcons.squareAndArrowUp, label: 'Share', onPressed: share),
///       ]),
///       inspector: showInspector ? MacInspector(child: details) : null,
///       child: MacContent(child: MacStack(children: [ … ])),
///     )
///
///     // A mockup window with traffic lights (screenshots, demos, Electron-like custom frames):
///     SizedBox(width: 840, height: 400, child: MacWindow(
///       style: MacWindowStyle.window,
///       titlebar: const MacTitlebar(title: 'Budget 2027', toolbarStyle: MacToolbarStyle.none,
///                                   windowControls: MacWindowControls()),
///       child: MacContent(child: Text('…')),
///     ))
///
/// [inactive] null (default) follows the app window focus: when another window is focused, accent colours,
/// selections and toolbar materials turn grey and the scroll bars hide (macOS `mac-inactive`).
class MacWindow extends StatefulWidget {
  const MacWindow({
    super.key,
    this.style = MacWindowStyle.page,
    this.sidebar,
    this.titlebar,
    this.listColumn,
    this.inspector,
    this.child,
    this.inactive,
  });

  final MacWindowStyle style;

  /// A [MacSidebar] on the left, full window height. The traffic lights then go in its header.
  final Widget? sidebar;

  /// A [MacTitlebar] at the top of the main pane.
  final Widget? titlebar;

  /// A [MacListColumn] between the sidebar and the content (three-column windows: Mail, Notes).
  final Widget? listColumn;

  /// A [MacInspector] on the right of the content.
  final Widget? inspector;

  /// The content area, usually a [MacContent].
  final Widget? child;

  /// Draw the window as not focused. Null = follow the app window focus.
  final bool? inactive;

  @override
  State<MacWindow> createState() => _MacWindowState();
}

class _MacWindowState extends State<MacWindow> {
  late final AppLifecycleListener _lifecycle;
  bool _appFocused = true;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _appFocused = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        final focused = s == AppLifecycleState.resumed;
        if (focused != _appFocused && mounted) setState(() => _appFocused = focused);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final inactive = widget.inactive ?? !_appFocused;
    final hasSidebar = widget.sidebar != null;

    Widget body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.listColumn,
        Expanded(child: widget.child ?? const SizedBox.shrink()),
        ?widget.inspector,
      ],
    );
    Widget main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.titlebar != null) widget.titlebar!,
        Expanded(child: body),
      ],
    );
    main = _MacWindowScope(style: widget.style, mainPane: hasSidebar, child: main);
    if (hasSidebar) {
      main = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MacWindowScope(style: widget.style, mainPane: false, child: widget.sidebar!),
          Expanded(
            child: ColoredBox(color: c.windowBg, child: main),
          ),
        ],
      );
    }
    Widget content = DefaultTextStyle(
      style: MacTypography.of(context).body,
      child: ColoredBox(color: c.windowBg, child: main),
    );
    content = MacWindowState(inactive: inactive, child: content);
    if (widget.style == MacWindowStyle.page) return content;

    // Kit "Window BG": radius 16 (continuous), window background, 0 18 54 (inactive 0 7 21) + 0 0 1 black 80%;
    // Dark: 1 px white 20% inner stroke. Utility panel: radius 15, one 0 5 20 black 30% shadow, no stroke.
    final utility = widget.style == MacWindowStyle.utility;
    final radius = utility ? 15.0 : 16.0;
    final dark = theme.isDark;
    final shadows = utility
        ? const [_Shadow(0, 5, 20, Color(0x4D000000))]
        : inactive
        ? [_Shadow(0, 7, 21, dark ? const Color(0x59000000) : const Color(0x33000000)), const _Shadow(0, 0, 1, Color(0xCC000000))]
        : [_Shadow(0, 18, 54, dark ? const Color(0x91000000) : const Color(0x4D000000)), const _Shadow(0, 0, 1, Color(0xCC000000))];
    final shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));
    return CustomPaint(
      painter: _WindowShadowPainter(shadows, shape),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: CustomPaint(
          foregroundPainter: dark && !utility ? _InnerStrokePainter(shape, const Color(0x33FFFFFF)) : null,
          child: content,
        ),
      ),
    );
  }
}

class _Shadow {
  const _Shadow(this.dx, this.dy, this.blur, this.color);
  final double dx;
  final double dy;
  final double blur;
  final Color color;
}

/// CSS box-shadow: the window shape shifted by (dx, dy), blurred with sigma = blur / 2.
class _WindowShadowPainter extends CustomPainter {
  _WindowShadowPainter(this.shadows, this.shape);
  final List<_Shadow> shadows;
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    for (final s in shadows) {
      final paint = Paint()
        ..color = s.color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blur / 2);
      canvas.drawPath(shape.getOuterPath(rect.shift(Offset(s.dx, s.dy))), paint);
    }
  }

  @override
  bool shouldRepaint(_WindowShadowPainter old) => old.shadows != shadows || old.shape != shape;
}

class _InnerStrokePainter extends CustomPainter {
  _InnerStrokePainter(this.shape, this.color);
  final ShapeBorder shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = shape.getOuterPath(Offset.zero & size);
    final inner = (shape as RoundedSuperellipseBorder)
        .copyWith(borderRadius: BorderRadius.circular(15))
        .getOuterPath((Offset.zero & size).deflate(1));
    canvas.drawPath(Path.combine(PathOperation.difference, outer, inner), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_InnerStrokePainter old) => old.color != color || old.shape != shape;
}

/// The window content area below the title bar (web `mac-window__content`): 20 px padding on every side and
/// macOS scroll bars. Put ONE [MacStack] in it (or a table, list or editor with [flush]).
///
///     MacContent(child: MacStack(children: [ … ]))
///     MacContent(flush: true, child: table)              // edge to edge: no padding
///     MacContent(scroll: false, child: MacEmptyState(title: 'No Selection'))
class MacContent extends StatelessWidget {
  const MacContent({super.key, required this.child, this.flush = false, this.scroll = true, this.controller});

  final Widget child;

  /// No 20 px padding: for a table, list or editor that runs edge to edge.
  final bool flush;

  /// Scroll the content with macOS scroll bars (default true). False = the child fills the area.
  final bool scroll;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.all(flush ? 0 : 20);
    if (!scroll) return Padding(padding: padding, child: child);
    return MacScrollView(padding: padding, controller: controller, child: child);
  }
}

/// The traffic lights: close (red), minimize (yellow), zoom (green), always at the top-left in this order.
/// 14 px circles 9 px apart (68 × 14 with 8 px trailing space); 10 px circles 7 px apart in utility panels.
/// Grey while the window is inactive; the × − + glyphs appear while the pointer is over the group.
///
/// ONLY for mockups, screenshots, demos, and desktop windows that hide the native title bar and draw their own
/// frame. A normal Flutter desktop app keeps the system's traffic lights: leave room with [MacWindowControls.space].
///
///     const MacWindowControls()                                         // mockup: three coloured lights
///     MacWindowControls(onClose: close, onMinimize: minimize, onZoom: zoom)
///     const MacWindowControls(zoomEnabled: false)                        // fixed-size window: zoom unavailable
///     const MacWindowControls.space()                                   // empty 68 × 14 gap for the system lights
class MacWindowControls extends StatefulWidget {
  const MacWindowControls({
    super.key,
    this.onClose,
    this.onMinimize,
    this.onZoom,
    this.closeEnabled = true,
    this.minimizeEnabled = true,
    this.zoomEnabled = true,
    this.utility,
  }) : _space = false;

  /// Reserves the space of the lights without drawing them (the operating system draws the real ones there).
  const MacWindowControls.space({super.key, this.utility})
    : onClose = null,
      onMinimize = null,
      onZoom = null,
      closeEnabled = true,
      minimizeEnabled = true,
      zoomEnabled = true,
      _space = true;

  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onZoom;

  /// False = that light is unavailable: grey, no glyph, not clickable.
  final bool closeEnabled;
  final bool minimizeEnabled;
  final bool zoomEnabled;

  /// 10 px utility-panel lights. Null = automatic (true inside a `MacWindow(style: MacWindowStyle.utility)`).
  final bool? utility;
  final bool _space;

  @override
  State<MacWindowControls> createState() => _MacWindowControlsState();
}

class _MacWindowControlsState extends State<MacWindowControls> {
  bool _hovered = false;
  int _focused = 0;

  // Kit "Window Controls": fills and their 0.5 px rings (black 45% overlay, pre-blended). Same in Light and Dark.
  static const _fills = [Color(0xFFFF5C60), Color(0xFFFAC800), Color(0xFF35C759)];
  static const _rings = [Color(0xFFFF3335), Color(0xFFF8AF00), Color(0xFF1DAE31)];
  static final _glyphs = [
    Path()
      ..moveTo(4.25, 4.25)
      ..lineTo(11.75, 11.75)
      ..moveTo(11.75, 4.25)
      ..lineTo(4.25, 11.75),
    Path()
      ..moveTo(3, 8)
      ..lineTo(13, 8),
    Path()
      ..moveTo(8, 3)
      ..lineTo(8, 13)
      ..moveTo(3, 8)
      ..lineTo(13, 8),
  ];
  static const _names = ['Close', 'Minimize', 'Zoom'];

  @override
  Widget build(BuildContext context) {
    final utility = widget.utility ?? (_MacWindowScope.maybeOf(context)?.style == MacWindowStyle.utility);
    final d = utility ? 10.0 : 14.0;
    final gap = utility ? 7.0 : 9.0;
    final trailing = utility ? 0.0 : 8.0;
    if (widget._space) return SizedBox(width: 3 * d + 2 * gap + trailing, height: d);

    final dark = AppleTheme.of(context).isDark;
    final inactive = MacWindowState.isInactive(context);
    final offFill = dark ? const Color(0x2BFFFFFF) : const Color(0x26000000);
    final offRing = dark ? const Color(0x08FFFFFF) : const Color(0x0F000000);
    final callbacks = [widget.onClose, widget.onMinimize, widget.onZoom];
    final enabled = [widget.closeEnabled, widget.minimizeEnabled, widget.zoomEnabled];
    final active = _hovered || _focused > 0;

    Widget light(int i) {
      return MacPressable(
        onPressed: enabled[i] ? (callbacks[i] ?? () {}) : null,
        semanticLabel: _names[i],
        onFocusChanged: (v) => setState(() => _focused = (_focused + (v ? 1 : -1)).clamp(0, 3)),
        builder: (context, s) {
          final on = enabled[i] && (!inactive || active);
          final showGlyph = enabled[i] && (active || s.pressed);
          Widget dot = CustomPaint(
            size: Size.square(d),
            painter: _LightPainter(
              fill: on ? _fills[i] : offFill,
              ring: on ? _rings[i] : offRing,
              glyph: showGlyph ? _glyphs[i] : null,
              glyphColor: s.pressed ? const Color(0xB3000000) : const Color(0x80000000),
              glyphSize: utility ? 9 : 12,
            ),
          );
          if (s.pressed) {
            // Pressed light darkens (CSS filter: brightness(0.85)).
            dot = ColorFiltered(
              colorFilter: const ColorFilter.matrix([0.85, 0, 0, 0, 0, 0, 0.85, 0, 0, 0, 0, 0, 0.85, 0, 0, 0, 0, 0, 1, 0]),
              child: dot,
            );
          }
          return MacFocusRing(show: s.focused, child: dot);
        },
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: EdgeInsets.only(right: trailing),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            light(0),
            SizedBox(width: gap),
            light(1),
            SizedBox(width: gap),
            light(2),
          ],
        ),
      ),
    );
  }
}

class _LightPainter extends CustomPainter {
  _LightPainter({required this.fill, required this.ring, required this.glyph, required this.glyphColor, required this.glyphSize});
  final Color fill;
  final Color ring;
  final Path? glyph;
  final Color glyphColor;
  final double glyphSize;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = fill);
    // Inset 0.5 px ring.
    canvas.drawCircle(
      c,
      r - 0.25,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = ring,
    );
    if (glyph != null) {
      final box = Rect.fromCenter(center: c, width: glyphSize, height: glyphSize);
      canvas.save();
      canvas.translate(box.left, box.top);
      MacGridGlyphPainter(glyph!, glyphColor).paint(canvas, box.size);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LightPainter old) =>
      old.fill != fill || old.ring != ring || old.glyph != glyph || old.glyphColor != glyphColor || old.glyphSize != glyphSize;
}

/// The title bar of a window, with its toolbar (kit "Windows - Composed"). Children are toolbar items:
/// [MacToolbarButton], [MacToolbarGroup], and the toolbar versions of the segmented control, pop-up button and
/// search field. Order, left to right: lights, [leading] (navigation, view controls), title, space, [actions], search.
///
///     MacTitlebar(                                         // unified (default): 52 px, XL (36 px) items
///       title: 'Documents',
///       subtitle: '14 items',
///       leading: [MacToolbarGroup(children: [
///         MacToolbarButton(icon: AppleIcons.chevronLeft, label: 'Back', onPressed: back),
///         MacToolbarButton(icon: AppleIcons.chevronRight, label: 'Forward', onPressed: null),
///       ])],
///       actions: [
///         MacToolbarButton(icon: AppleIcons.squareAndArrowUp, label: 'Share', onPressed: share),
///         searchField,                                      // last
///       ],
///     )
///     MacTitlebar(title: 'Inbox', toolbarStyle: MacToolbarStyle.compact, actions: [ … ])   // 40 px, medium items
///     MacTitlebar(title: 'Budget 2027', toolbarStyle: MacToolbarStyle.none,
///                 windowControls: const MacWindowControls())                              // mockup, 31 px
///
/// Without a [title] the bar is transparent (no band, no divider), like the kit's "… without Title" windows.
class MacTitlebar extends StatelessWidget {
  const MacTitlebar({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.toolbarStyle = MacToolbarStyle.unified,
    this.windowControls,
    this.leading = const [],
    this.actions = const [],
    this.spacer = true,
    this.bottom,
    this.largeTitle = false,
    this.transparent,
  });

  /// The document or current view ("Inbox", "Budget 2027"), not the app name. SF Pro Bold 13.
  final String? title;

  /// Grey line under the title: a count, "Edited", a status. Medium 11.
  final String? subtitle;

  /// Document icon before the title.
  final IconData? icon;
  final MacToolbarStyle toolbarStyle;

  /// [MacWindowControls] (mockups / custom frames), or [MacWindowControls.space] to leave room for the system's.
  /// In a window with a sidebar they go in the sidebar header instead.
  final Widget? windowControls;

  /// Toolbar items before the title (back/forward group, segmented control, sidebar button).
  final List<Widget> leading;

  /// Toolbar items at the right end, after the flexible space. The search field goes last.
  final List<Widget> actions;

  /// Push [actions] to the right edge (default true).
  final bool spacer;

  /// A row under the bar, centred: the tab bar of a utility panel or a Settings window ([MacToolbar.tabs]).
  final Widget? bottom;

  /// 15 px title (kit "Window Titles/Window", With Sidebar = True).
  final bool largeTitle;

  /// Force the transparent bar (no band, no divider). Null = automatic: transparent when there is no [title].
  final bool? transparent;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final dark = theme.isDark;
    final scope = _MacWindowScope.maybeOf(context);
    final utility = scope?.style == MacWindowStyle.utility;
    final mainPane = scope?.mainPane ?? false;
    final clear = transparent ?? (title == null);

    final heading = title == null && subtitle == null
        ? null
        : _TitleHeading(title: title, subtitle: subtitle, icon: icon, large: largeTitle, centered: utility);

    if (utility) {
      // Kit "Utility Panel": padding 7 · 7 · 5, lights at x 12, y 11, centred title (Bold 13), tab row 4 px below,
      // 1 px divider rgba(60, 60, 67, 0.12). No band.
      return DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x1F3C3C43))),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 7, 7, 6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Center(child: heading ?? const SizedBox(height: 16)),
                  ),
                  if (bottom != null) ...[const SizedBox(height: 4), Center(child: bottom)],
                ],
              ),
              if (windowControls != null) Positioned(left: 5, top: 4, child: windowControls!),
            ],
          ),
        ),
      );
    }

    final xl = toolbarStyle == MacToolbarStyle.unified || toolbarStyle == MacToolbarStyle.expanded;
    // The title takes the free space itself (it is the flexible space when [spacer] is on), so a long title
    // ends in "…" instead of pushing the actions out. 16 = the spacer's minimum 8 + one 8 px gap.
    Widget spacedHeading(Widget h) => Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Align(alignment: AlignmentDirectional.centerStart, child: h),
      ),
    );
    List<Widget> toolbarItems({required bool withHeading}) => [
      ...leading,
      if (withHeading && heading != null && spacer) spacedHeading(heading),
      if (withHeading && heading != null && !spacer) Flexible(child: heading),
      if (spacer && !(withHeading && heading != null)) const MacToolbarSpacer(),
      ...actions,
    ];

    Widget bar;
    switch (toolbarStyle) {
      case MacToolbarStyle.none:
        bar = ConstrainedBox(
          constraints: BoxConstraints(minHeight: mainPane ? 52 : 30),
          child: Padding(
            padding: EdgeInsets.fromLTRB(mainPane ? 18 : 8, 8, 8, 8),
            child: Row(
              children: [
                ?windowControls,
                if (windowControls != null && (heading != null || leading.isNotEmpty)) const SizedBox(width: 16),
                if (leading.isNotEmpty) ...[
                  MacControlSizeScope(
                    size: MacControlSize.medium,
                    child: MacToolbar(children: leading),
                  ),
                  const SizedBox(width: 8),
                ],
                if (heading != null) actions.isEmpty ? Flexible(child: heading) : spacedHeading(heading),
                if (actions.isNotEmpty) ...[
                  if (heading == null) const MacToolbarSpacer(),
                  MacControlSizeScope(
                    size: MacControlSize.medium,
                    child: MacToolbar(children: actions),
                  ),
                ],
              ],
            ),
          ),
        );
      case MacToolbarStyle.unified:
      case MacToolbarStyle.compact:
        bar = ConstrainedBox(
          constraints: BoxConstraints(minHeight: xl ? 52 : 40),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
            child: Row(
              children: [
                if (windowControls != null) ...[windowControls!, const SizedBox(width: 8)],
                Expanded(
                  child: MacControlSizeScope(
                    size: xl ? MacControlSize.xl : MacControlSize.medium,
                    child: MacToolbar(children: toolbarItems(withHeading: true)),
                  ),
                ),
              ],
            ),
          ),
        );
      case MacToolbarStyle.expanded:
        bar = Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (windowControls != null || heading != null)
                Row(
                  children: [
                    ?windowControls,
                    if (windowControls != null && heading != null) const SizedBox(width: 16),
                    if (heading != null) Flexible(child: heading),
                  ],
                ),
              if (windowControls != null || heading != null) const SizedBox(height: 8),
              MacControlSizeScope(
                size: MacControlSize.xl,
                child: MacToolbar(children: toolbarItems(withHeading: false)),
              ),
            ],
          ),
        );
    }
    if (bottom != null) {
      bar = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar,
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Center(child: bottom),
          ),
        ],
      );
    }

    // Kit "Scroll Edge Effect - Hard" (Edge = Top): white 85% · #1F1F1F 55%, 0.67 px divider black 5% · white 10%.
    if (!clear) {
      bar = DecoratedBox(
        decoration: BoxDecoration(color: dark ? const Color(0x8C1F1F1F) : const Color(0xD9FFFFFF)),
        position: DecorationPosition.background,
        child: CustomPaint(foregroundPainter: _DividerPainter(dark ? const Color(0x1AFFFFFF) : const Color(0x0D000000)), child: bar),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DefaultTextStyle(
        style: MacTypography.of(context).body.copyWith(color: c.labelPrimary),
        child: bar,
      ),
    );
  }
}

class _DividerPainter extends CustomPainter {
  _DividerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, size.height - 0.67, size.width, 0.67), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DividerPainter old) => old.color != color;
}

/// Title (+ document icon, + subtitle) of a title bar (`mac-titlebar__heading`).
class _TitleHeading extends StatelessWidget {
  const _TitleHeading({this.title, this.subtitle, this.icon, required this.large, required this.centered});
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final bool large;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final titleSize = large ? 15.0 : 13.0;
    // Kit: the large (With Sidebar) title keeps the 15 px line, so the subtitle sits where it does for 13 px.
    final titleLine = centered ? 16.0 : 15.0;
    final subtitleColor = theme.isDark ? const Color(0xADFFFFFF) : const Color(0xFF999999);
    final iconSize = centered ? 13.0 : 15.0;
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Semantics(
            header: true,
            child: Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: macChromeText(titleSize, titleLine, c.labelPrimary, weight: FontWeight.w700),
            ),
          ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: macChromeText(11, 13, subtitleColor, weight: FontWeight.w500),
          ),
        ],
      ],
    );
    if (icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: iconSize + 2, // the kit symbol (Semibold 15 / Bold 13) is about 2 px wider than its point size
          height: centered ? 16 : titleLine,
          child: OverflowBox(
            minWidth: 0,
            minHeight: 0,
            maxWidth: iconSize * 1.25,
            maxHeight: iconSize * 1.25,
            child: Icon(icon, size: iconSize * 0.98, color: c.labelPrimary),
          ),
        ),
        const SizedBox(width: 3),
        Flexible(child: text),
      ],
    );
  }
}
