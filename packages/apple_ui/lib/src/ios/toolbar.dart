import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/glass.dart';
import '../core/icons.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import 'app_shell.dart';
import 'list.dart';

// Bars of the kit page "Toolbars": navigation bars (top), bottom toolbars, bar buttons and groups (on the classic
// Regular blur material), the toolbar page control and a scaffold that puts bars over scrolling content with the
// scroll edge effect.

/// Metrics of the bar a button sits in: kit "_Buttons - 44pt" (navigation bars, iPad toolbars) or
/// "_Buttons - 48pt" (iPhone bottom toolbars).
@immutable
class _BarMetrics {
  const _BarMetrics(this.size, this.textPad, this.groupPad, this.groupGap);
  final double size;
  final double textPad;
  final double groupPad;
  final double groupGap;
  static const pt44 = _BarMetrics(44, 14, 6, 20);
  static const pt48 = _BarMetrics(48, 12, 10, 18);
}

class _BarScope extends InheritedWidget {
  const _BarScope({
    required this.metrics,
    this.inGroup = false,
    required super.child,
  });
  final _BarMetrics metrics;
  final bool inGroup;

  static _BarScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BarScope>();

  @override
  bool updateShouldNotify(_BarScope oldWidget) =>
      oldWidget.metrics != metrics || oldWidget.inGroup != inGroup;
}

TextStyle _barText(
  Color color, {
  double size = 17,
  FontWeight weight = FontWeight.w500,
}) {
  final line = size == 17 ? 22.0 : 20.0;
  return appleFont(size: size).copyWith(
    fontSize: size,
    height: line / size,
    letterSpacing: size == 17 ? -0.43 : -0.23,
    fontWeight: weight,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
    decoration: TextDecoration.none,
  );
}

// ==========================================================================================================
// Bar button
// ==========================================================================================================

/// A bar button on the Regular blur material (kit "_Buttons - 44pt / 48pt"). Use it ONLY in [IosNavigationBar],
/// [IosToolbar] or [IosBarGroup]; the bar sets its size (44 pt, or 48 pt in an iPhone bottom toolbar).
///
///     IosBarButton(icon: AppleIcons.plus, semanticLabel: 'Add', onPressed: add)        // symbol: a 44 pt circle
///     IosBarButton(label: 'Edit', onPressed: edit)                                     // text: a capsule
///     IosBarButton(icon: AppleIcons.checkmark, semanticLabel: 'Done', prominent: true, onPressed: done)
///     IosBarButton.back(onPressed: () => Navigator.pop(context))                      // back chevron
///     IosBarButton(icon: AppleIcons.star, semanticLabel: 'Starred', selected: on, onPressed: toggle)
/// [onPressed] null = disabled.
class IosBarButton extends StatefulWidget {
  const IosBarButton({
    super.key,
    this.icon,
    this.label,
    this.child,
    required this.onPressed,
    this.prominent = false,
    this.tinted = false,
    this.selected,
    this.semanticLabel,
  }) : back = false,
       assert(
         icon != null || label != null || child != null,
         'IosBarButton needs an icon, a label or a child',
       );

  /// The back button: a chevron, plus [label] (the previous screen's title) when given. Semantic name: "Back".
  const IosBarButton.back({
    super.key,
    required this.onPressed,
    this.label,
    this.semanticLabel,
  }) : icon = null,
       child = null,
       prominent = false,
       tinted = false,
       selected = null,
       back = true;

  /// A symbol. Without [label] the button is a circle; then give it a [semanticLabel].
  final IconData? icon;

  /// Text label (Medium 17). With a label the button is a capsule.
  final String? label;

  /// Custom content instead of [icon] (an avatar, a custom glyph). Drawn in a circle unless [label] is set.
  final Widget? child;
  final VoidCallback? onPressed;

  /// A solid accent fill with white content: THE main action of the bar (Done, Compose). One per bar.
  final bool prominent;

  /// Accent-coloured symbol or label on the normal material (kit State = Tinted).
  final bool tinted;

  /// On/off buttons (a filter, Bold): true = accent capsule inside the material. Null for plain actions.
  final bool? selected;

  /// Accessible name. Required for symbol-only buttons.
  final String? semanticLabel;
  final bool back;

  @override
  State<IosBarButton> createState() => _IosBarButtonState();
}

class _IosBarButtonState extends State<IosBarButton> {
  bool _pressed = false;
  bool _hovered = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final scope = _BarScope.maybeOf(context);
    final m = scope?.metrics ?? _BarMetrics.pt44;
    final inGroup = scope?.inGroup ?? false;
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final selected = widget.selected == true && _enabled;
    final prominent = widget.prominent && _enabled && !inGroup;
    const white = Color(0xFFFFFFFF);
    final fg = !_enabled
        ? c.labelControlTertiary
        : (selected || widget.prominent)
        ? white
        : widget.tinted
        ? theme.accentColor
        : c.labelControlPrimary;
    final circle = widget.label == null;
    final height = inGroup ? 36.0 : m.size;

    // Content: symbol (17 pt, drawn 1.2x like SF Symbols) / back chevron / custom child, then the label.
    final parts = <Widget>[];
    if (widget.back) {
      parts.add(
        SizedBox(
          width: 17,
          height: 20,
          // chevron.backward Semibold 17 is 10.5 x 18.5 in the kit: the Cupertino chevron at 30 matches it.
          child: OverflowBox(
            maxWidth: 40,
            maxHeight: 40,
            child: Transform.translate(
              offset: const Offset(-1, 0),
              child: Icon(AppleIcons.back, size: 30, color: fg),
            ),
          ),
        ),
      );
    } else if (widget.icon != null) {
      parts.add(
        SizedBox(
          width: 17,
          height: 17,
          child: OverflowBox(
            maxWidth: 20.4,
            maxHeight: 20.4,
            child: Icon(widget.icon, size: 20.4, color: fg),
          ),
        ),
      );
    } else if (widget.child != null) {
      parts.add(
        IconTheme(
          data: IconThemeData(color: fg, size: 20.4),
          child: DefaultTextStyle(style: _barText(fg), child: widget.child!),
        ),
      );
    }
    if (widget.label != null) {
      if (parts.isNotEmpty) parts.add(const SizedBox(width: 2));
      parts.add(
        Text(
          widget.label!,
          style: _barText(fg),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    Widget content = Row(mainAxisSize: MainAxisSize.min, children: parts);
    final padX = circle
        ? 0.0
        : (inGroup ? 6.0 : (widget.back ? 12.0 : m.textPad));
    content = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: height,
        minHeight: height,
        maxHeight: height,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padX),
        child: Center(widthFactor: 1, child: content),
      ),
    );
    if (circle) {
      content = SizedBox(width: height, height: height, child: content);
    }

    // Selected: an accent capsule 36 tall inside the material.
    if (selected) {
      final inset = inGroup ? 0.0 : (m.size - 36) / 2;
      content = Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(inset),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: theme.accentColor,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
          content,
        ],
      );
    }

    // Pressed: darker (lighter in Dark Mode), like CSS brightness(0.88) / brightness(1.2); in a group the item fades.
    // iPadOS pointer: a light highlight (the one place iPadOS shows hover).
    final pressed = _pressed && _enabled;
    final hover = _hovered && _enabled && !pressed;
    final pressedColor = theme.isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000);
    final hoverColor = theme.isDark ? const Color(0x14FFFFFF) : const Color(0x0A000000);
    Widget button = inGroup
        ? content
        : AppleGlass(
            style: prominent
                ? AppleGlassStyle.prominent
                : AppleGlassStyle.regular,
            // The tints go INSIDE the material: a ColorFiltered layer around it would cut the backdrop blur.
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                color: pressed ? pressedColor : (hover ? hoverColor : const Color(0x00000000)),
              ),
              child: content,
            ),
          );

    if (pressed && inGroup) {
      button = Opacity(opacity: 0.35, child: button);
    } else if (hover && inGroup) {
      button = ColorFiltered(
        colorFilter: ColorFilter.mode(hoverColor, BlendMode.srcATop),
        child: button,
      );
    }

    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      toggled: widget.selected,
      label:
          widget.semanticLabel ?? widget.label ?? (widget.back ? 'Back' : null),
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: button,
        ),
      ),
    );
  }
}

// ==========================================================================================================
// Bar group and scope filters
// ==========================================================================================================

/// Several related bar buttons in ONE material capsule (kit "Button Group": padding 6, 20 between 36 pt items;
/// 48 pt bars: padding 10, 18 between).
///
///     IosBarGroup(semanticLabel: 'Message', children: [
///       IosBarButton(icon: AppleIcons.heart, semanticLabel: 'Favorite', onPressed: fav),
///       IosBarButton(icon: AppleIcons.flag, semanticLabel: 'Flag', onPressed: flag),
///     ])
class IosBarGroup extends StatelessWidget {
  const IosBarGroup({
    super.key,
    required this.children,
    this.axis = Axis.horizontal,
    this.semanticLabel,
  });

  final List<Widget> children;

  /// [Axis.vertical] = stacked (kit "Preferred Axis = Vertical").
  final Axis axis;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final m = _BarScope.maybeOf(context)?.metrics ?? _BarMetrics.pt44;
    final horizontal = axis == Axis.horizontal;
    final inset = (m.size - 36) / 2;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: _BarScope(
        metrics: m,
        inGroup: true,
        child: AppleGlass(
          padding: horizontal
              ? EdgeInsets.symmetric(horizontal: m.groupPad, vertical: inset)
              : EdgeInsets.symmetric(horizontal: inset, vertical: m.groupPad),
          child: Flex(
            direction: axis,
            mainAxisSize: MainAxisSize.min,
            spacing: m.groupGap,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Scope filters in a material capsule (kit "_Segmented Control Button" in "_Search Accessory": 44 tall,
/// padding 4 / 8, segments at least 121 wide, label Medium 15; the selected one gets a grey capsule).
///
///     IosBarSegmentedControl<String>(segments: const {'all': 'All Mail', 'box': 'Current Mailbox'},
///         value: scope, onChanged: (v) => setState(() => scope = v))
class IosBarSegmentedControl<T> extends StatelessWidget {
  const IosBarSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final Map<T, String> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    return AppleGlass(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in segments.entries)
            Semantics(
              button: true,
              inMutuallyExclusiveGroup: true,
              selected: e.key == value,
              label: e.value,
              onTap: onChanged == null ? null : () => onChanged!(e.key),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onChanged == null ? null : () => onChanged!(e.key),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 121,
                    minHeight: 36,
                    maxHeight: 36,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      if (e.key == value)
                        Positioned(
                          left: -4,
                          right: -4,
                          top: 0,
                          bottom: 0,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: c.fillTertiary,
                              shape: const StadiumBorder(),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Text(
                          e.value,
                          maxLines: 1,
                          style: _barText(
                            e.key == value
                                ? c.labelControlPrimary
                                : c.labelControlSecondary,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================================================================================
// Navigation bar
// ==========================================================================================================

/// Title styles of the navigation bar (kit "Toolbar - Top", Style).
enum IosNavigationBarStyle {
  /// The default, like SwiftUI: [large] on the first screen of a navigation stack (top-level screens), [inline] on
  /// pushed screens and in sheets. iPhone landscape always shows inline titles.
  automatic,

  /// Title centered in the bar (kit "Default"; with a subtitle "Title 2 Line"). Detail screens.
  inline,

  /// Title left-aligned after the leading buttons (kit "Title 2 Line Left").
  leadingTitle,

  /// 34 pt bold title below the bar that collapses into the bar on scroll (kit "Large Title"). Top-level screens.
  large,

  /// 34 pt bold title inside the bar (kit "Compact Large").
  compactLarge,
}

/// The navigation bar at the top of a screen (kit "Toolbar - Top - iPhone / iPad"): 54 pt tall (44 pt controls),
/// side padding 16 (iPhone) / 10 (iPad). Put it in [IosBarScaffold] so content scrolls under it with the scroll
/// edge effect and large titles collapse on scroll.
///
///     IosNavigationBar(
///       title: 'Inbox', subtitle: '12 unread', style: IosNavigationBarStyle.large,
///       leading: [IosBarButton.back(onPressed: () => Navigator.pop(context))],
///       trailing: [IosBarButton(icon: AppleIcons.squareAndPencil, semanticLabel: 'Compose', prominent: true, onPressed: compose)],
///     )
class IosNavigationBar extends StatelessWidget {
  const IosNavigationBar({
    super.key,
    this.title,
    this.subtitle,
    this.style = IosNavigationBarStyle.automatic,
    this.leading = const [],
    this.trailing = const [],
    this.search,
    this.center,
    this.accessory,
    this.collapsed = false,
  }) : _largeBlock = true;

  IosNavigationBar._row(IosNavigationBar b, {required this.collapsed})
    : title = b.title,
      subtitle = b.subtitle,
      style = b.style,
      leading = b.leading,
      trailing = b.trailing,
      search = b.search,
      center = b.center,
      accessory = b.accessory,
      _largeBlock = false,
      super(key: null);

  /// The same bar with another style (resolving [IosNavigationBarStyle.automatic]; inline titles in iPhone landscape).
  IosNavigationBar._restyled(IosNavigationBar b, IosNavigationBarStyle newStyle)
    : title = b.title,
      subtitle = b.subtitle,
      style = newStyle,
      leading = b.leading,
      trailing = b.trailing,
      search = b.search,
      center = b.center,
      accessory = b.accessory,
      collapsed = b.collapsed,
      _largeBlock = b._largeBlock,
      super(key: b.key);

  /// The style actually used here: [IosNavigationBarStyle.automatic] becomes large on the first screen of a navigator
  /// and inline on pushed screens and in sheets; large becomes inline in iPhone landscape (under 500 tall).
  static IosNavigationBarStyle resolveStyle(BuildContext context, IosNavigationBarStyle style) {
    var s = style;
    if (s == IosNavigationBarStyle.automatic) {
      final route = ModalRoute.of(context);
      s = route != null && !route.isFirst ? IosNavigationBarStyle.inline : IosNavigationBarStyle.large;
    }
    if (s == IosNavigationBarStyle.large && MediaQuery.sizeOf(context).height < 500) s = IosNavigationBarStyle.inline;
    return s;
  }

  IosNavigationBar _resolved(BuildContext context) {
    final s = resolveStyle(context, style);
    return s == style ? this : IosNavigationBar._restyled(this, s);
  }

  final String? title;

  /// Second line (12 pt under a 15 pt title; 15 pt under a large title).
  final String? subtitle;
  final IosNavigationBarStyle style;

  /// Bar buttons at the leading edge (the back button first).
  final List<Widget> leading;

  /// Bar buttons at the trailing edge (the main action last).
  final List<Widget> trailing;

  /// iPad: a search field after the trailing buttons (180 wide). Pass a search field widget.
  final Widget? search;

  /// iPad: a tab bar or segmented control centered in the bar; the title then moves below the buttons.
  final Widget? center;

  /// iPad: a row under the bar (a search field + [IosBarSegmentedControl]).
  final Widget? accessory;

  /// [IosNavigationBarStyle.large] only: true shows the small title in the bar instead of the large one.
  /// [IosBarScaffold] sets it while scrolling.
  final bool collapsed;
  final bool _largeBlock;

  /// Height of the bar for [context] (without the large title block): 54 + extras, plus the top safe area.
  static double heightOf(BuildContext context, IosNavigationBar given) {
    final bar = given._resolved(context);
    final regular = IosLayout.isRegular(context);
    var h = 54.0;
    if ((bar.center != null || _tabBarInset(context) > 0) &&
        bar.title != null &&
        (bar.style == IosNavigationBarStyle.inline ||
            bar.style == IosNavigationBarStyle.leadingTitle)) {
      h += bar.style == IosNavigationBarStyle.inline ? 49 : 44;
    }
    if (bar.accessory != null) h += regular ? 60 : 60;
    return h + MediaQuery.paddingOf(context).top - _tabBarInset(context);
  }

  /// iPad with a top tab bar ([IosAppShell]): the bar's buttons share the tab bar's row (like the kit), so the
  /// part of the top padding the shell added for the tab bar is taken back. Large-title bars don't show the small
  /// title there; other bars (pushed screens) show it on a line below the buttons (kit "Tab Bar = True").
  static double _tabBarInset(BuildContext context) => IosAppShellScope.maybeOf(context)?.regularTabBarInset ?? 0;

  @override
  Widget build(BuildContext context) {
    if (resolveStyle(context, style) != style) return _resolved(context).build(context);
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final regular = IosLayout.isRegular(context);
    final padX = regular ? 10.0 : 16.0;
    final gap = regular ? 12.0 : 10.0;
    final titleColor = c.labelVibrantPrimary;
    final subColor = c.labelVibrantSecondary;
    final large = style == IosNavigationBarStyle.large;
    final tabInset = _tabBarInset(context);
    // The title goes on its own line below the buttons when a center control or (iPad) the tab bar takes the row.
    final titleBelow =
        (center != null || tabInset > 0) &&
        title != null &&
        (style == IosNavigationBarStyle.inline ||
            style == IosNavigationBarStyle.leadingTitle);

    Widget side(List<Widget> items) =>
        Row(mainAxisSize: MainAxisSize.min, spacing: gap, children: items);
    final trailingItems = [
      ...trailing,
      if (search != null) SizedBox(width: 180, child: search),
    ];

    // The title in the bar.
    Widget? titleWidget;
    if (title != null &&
        !(tabInset > 0 && large) &&
        !(center != null &&
            (large || style == IosNavigationBarStyle.compactLarge))) {
      final two = subtitle != null;
      final leadingAlign =
          style == IosNavigationBarStyle.leadingTitle ||
          style == IosNavigationBarStyle.compactLarge;
      if (style == IosNavigationBarStyle.compactLarge) {
        titleWidget = Text(
          title!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _titleStyle(34, 41, 0.4, FontWeight.w700, titleColor),
        );
      } else {
        final big = titleBelow; // below the buttons on iPad: Semibold 17 + 12
        titleWidget = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: leadingAlign
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          spacing: two && (regular || big) ? 2 : 0,
          children: [
            Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: two && !big
                  ? _titleStyle(15, 20, -0.23, FontWeight.w600, titleColor)
                  : _titleStyle(17, 22, -0.43, FontWeight.w600, titleColor),
            ),
            if (two)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _titleStyle(12, 16, 0, FontWeight.w500, subColor),
              ),
          ],
        );
        // Single-line centered title: 2 pt below the button centre line (kit y = 13).
        if (!two && !leadingAlign && !big) {
          titleWidget = Padding(
            padding: const EdgeInsets.only(top: 4),
            child: titleWidget,
          );
        }
      }
      if (large) {
        titleWidget = AnimatedOpacity(
          opacity: collapsed ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: ExcludeSemantics(excluding: !collapsed, child: titleWidget),
        );
      }
      if (!large) titleWidget = Semantics(header: true, child: titleWidget);
    }

    // The 44 pt controls row.
    Widget row;
    final leadingTitleRow =
        style == IosNavigationBarStyle.leadingTitle ||
        style == IosNavigationBarStyle.compactLarge;
    if (leadingTitleRow && !titleBelow && center == null) {
      final indent = regular
          ? 12.0
          : (style == IosNavigationBarStyle.leadingTitle && leading.isNotEmpty
                ? 2.0
                : 0.0);
      row = Row(
        children: [
          if (leading.isNotEmpty) side(leading),
          if (leading.isNotEmpty && !regular) SizedBox(width: gap),
          Expanded(
            child: titleWidget == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.only(left: indent),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: titleWidget,
                    ),
                  ),
          ),
          if (trailingItems.isNotEmpty) side(trailingItems),
        ],
      );
    } else {
      row = CustomMultiChildLayout(
        delegate: _NavRowDelegate(gap: gap),
        children: [
          if (leading.isNotEmpty)
            LayoutId(id: _NavSlot.leading, child: side(leading)),
          if (trailingItems.isNotEmpty)
            LayoutId(id: _NavSlot.trailing, child: side(trailingItems)),
          if (titleWidget != null && !titleBelow)
            LayoutId(id: _NavSlot.title, child: titleWidget),
          if (center != null) LayoutId(id: _NavSlot.center, child: center!),
        ],
      );
    }

    final children = <Widget>[
      SizedBox(
        height: 44,
        child: _BarScope(metrics: _BarMetrics.pt44, child: row),
      ),
    ];
    if (titleBelow) {
      final left = style == IosNavigationBarStyle.leadingTitle;
      children.add(
        Padding(
          padding: EdgeInsets.only(top: left ? 9 : 13, left: left ? 10 : 0),
          child: Align(
            alignment: left ? Alignment.centerLeft : Alignment.center,
            child: titleWidget,
          ),
        ),
      );
    }
    Widget bar = Padding(
      padding: EdgeInsets.fromLTRB(
        padX,
        MediaQuery.paddingOf(context).top - tabInset,
        padX,
        10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    final column = <Widget>[bar];
    if (large && _largeBlock && title != null) {
      column.add(IosLargeTitle(title: title!, subtitle: subtitle));
    }
    if (accessory != null) {
      column.add(
        Padding(
          padding: EdgeInsets.fromLTRB(padX, 6, padX, 10),
          child: SizedBox(
            height: 44,
            child: _BarScope(
              metrics: _BarMetrics.pt44,
              child: Center(child: accessory),
            ),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: column,
    );
  }
}

TextStyle _titleStyle(
  double size,
  double line,
  double tracking,
  FontWeight weight,
  Color color,
) => appleFont(size: size).copyWith(
  fontSize: size,
  height: line / size,
  letterSpacing: tracking,
  fontWeight: weight,
  color: color,
  leadingDistribution: TextLeadingDistribution.even,
  decoration: TextDecoration.none,
);

/// The large title block under a navigation bar (kit "Large Title": Bold 34/41, subtitle Medium 15/20 in the
/// secondary label colour; iPhone padding 0 16 10, iPad 4 20 14 with 2 between the lines). Follows Dynamic Type.
/// [IosBarScaffold] puts it at the top of the scrolling content for you.
class IosLargeTitle extends StatelessWidget {
  const IosLargeTitle({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  /// Distance from the top of the block to the bottom of the title text (the bar collapses after scrolling this far).
  static double titleBottomOf(BuildContext context) {
    final regular = IosLayout.isRegular(context);
    final t = IosTypography.of(context).largeTitleEmphasized;
    return (regular ? 4.0 : 0.0) + t.fontSize! * t.height!;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    final regular = IosLayout.isRegular(context);
    final t = IosTypography.of(context);
    return Padding(
      padding: regular
          ? const EdgeInsets.fromLTRB(20, 4, 20, 14)
          : const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: regular ? 2 : 0,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: t.largeTitleEmphasized.copyWith(
                color: c.labelVibrantPrimary,
              ),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: t.subheadline.copyWith(
                fontWeight: FontWeight.w500,
                color: c.labelVibrantSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

enum _NavSlot { leading, trailing, title, center }

/// Leading at the start, trailing at the end, the title centered in the bar when it fits between them
/// (otherwise centered in the free space, like UIKit), an optional center item exactly in the middle.
class _NavRowDelegate extends MultiChildLayoutDelegate {
  _NavRowDelegate({required this.gap});
  final double gap;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);
    var lead = Size.zero, trail = Size.zero;
    if (hasChild(_NavSlot.leading)) {
      lead = layoutChild(_NavSlot.leading, loose);
      positionChild(
        _NavSlot.leading,
        Offset(0, (size.height - lead.height) / 2),
      );
    }
    if (hasChild(_NavSlot.trailing)) {
      trail = layoutChild(_NavSlot.trailing, loose);
      positionChild(
        _NavSlot.trailing,
        Offset(size.width - trail.width, (size.height - trail.height) / 2),
      );
    }
    if (hasChild(_NavSlot.center)) {
      final s = layoutChild(_NavSlot.center, loose);
      positionChild(
        _NavSlot.center,
        Offset((size.width - s.width) / 2, (size.height - s.height) / 2),
      );
    }
    if (hasChild(_NavSlot.title)) {
      final left = lead.width > 0 ? lead.width + gap : 0.0;
      final right = trail.width > 0 ? trail.width + gap : 0.0;
      final free = math.max(0.0, size.width - left - right);
      final s = layoutChild(
        _NavSlot.title,
        BoxConstraints(maxWidth: free, maxHeight: size.height),
      );
      var x = (size.width - s.width) / 2;
      if (x < left) x = left;
      if (x + s.width > size.width - right) x = size.width - right - s.width;
      positionChild(_NavSlot.title, Offset(x, (size.height - s.height) / 2));
    }
  }

  @override
  bool shouldRelayout(_NavRowDelegate oldDelegate) => oldDelegate.gap != gap;
}

// ==========================================================================================================
// Bottom toolbar and page control
// ==========================================================================================================

/// The bottom toolbar (kit "Toolbar - Bottom"): iPhone 48 pt buttons, padding 4 / 28 / 32 (84 tall);
/// iPad 44 pt buttons, padding 4 / 10 / 10 (58 tall). 12 between items. Put it in [IosBarScaffold].
///
///     IosToolbar(
///       leading: [IosBarButton(icon: AppleIcons.trash, semanticLabel: 'Delete', onPressed: delete)],
///       trailing: [IosBarButton(icon: AppleIcons.squareAndPencil, semanticLabel: 'Compose', prominent: true, onPressed: compose)],
///     )
///     IosToolbar(search: mySearchField, trailing: [IosBarButton(icon: AppleIcons.xmark, semanticLabel: 'Cancel', onPressed: cancel)])
class IosToolbar extends StatelessWidget {
  const IosToolbar({
    super.key,
    this.leading = const [],
    this.center = const [],
    this.trailing = const [],
    this.search,
    this.semanticLabel = 'Toolbar',
  });

  final List<Widget> leading;

  /// Items in the middle (or an [IosToolbarPageControl]).
  final List<Widget> center;
  final List<Widget> trailing;

  /// A search field that fills the toolbar (iPhone search). [leading] / [trailing] then sit right next to it.
  final Widget? search;
  final String semanticLabel;

  /// Height of the toolbar for [context]: 84 (iPhone) / 58 (iPad), more with a bigger bottom safe area.
  static double heightOf(BuildContext context) {
    final regular = IosLayout.isRegular(context);
    return 4 + (regular ? 44 : 48) + _bottomPad(context, regular);
  }

  // Kit: 32 on iPhone (the 34 pt home indicator area minus 2), 10 on iPad.
  static double _bottomPad(BuildContext context, bool regular) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return regular ? math.max(10, inset - 10) : math.max(32, inset - 2);
  }

  @override
  Widget build(BuildContext context) {
    final regular = IosLayout.isRegular(context);
    final m = regular ? _BarMetrics.pt44 : _BarMetrics.pt48;
    Widget row;
    if (search != null) {
      row = Row(
        spacing: 12,
        children: [
          ...leading,
          Expanded(child: search!),
          ...trailing,
        ],
      );
    } else {
      row = Row(
        spacing: 12,
        children: [
          Expanded(child: Row(spacing: 12, children: leading)),
          if (center.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: center),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 12,
              children: trailing,
            ),
          ),
        ],
      );
    }
    return Semantics(
      container: true,
      label: semanticLabel,
      child: _BarScope(
        metrics: m,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            regular ? 10 : 28,
            4,
            regular ? 10 : 28,
            _bottomPad(context, regular),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: m.size),
            child: row,
          ),
        ),
      ),
    );
  }
}

/// Dot sizes of the toolbar page control: up to 6 pages all 8 pt; 7 pages: the dot at the far end is 6 pt;
/// 8+ pages: a window of 8 dots whose outer dots shrink to 6 and 4 pt (kit "_Toolbar page control").
List<({int page, double size})> iosToolbarPageDots(int count, int current) {
  final n = math.max(1, count);
  final c = current.clamp(0, n - 1);
  if (n <= 6) return [for (var i = 0; i < n; i++) (page: i, size: 8.0)];
  if (n == 7) {
    return [
      for (var i = 0; i < 7; i++)
        (page: i, size: (c < 6 ? i == 6 : i == 0) ? 6.0 : 8.0),
    ];
  }
  final atStart = c <= 3;
  final atEnd = c >= n - 3;
  final start = atStart ? 0 : (atEnd ? n - 8 : c - 4);
  return [
    for (var i = 0; i < 8; i++)
      (
        page: start + i,
        size: (!atStart && i == 0) || (!atEnd && i == 7)
            ? 4.0
            : ((!atStart && i == 1) || (!atEnd && i == 6) ? 6.0 : 8.0),
      ),
  ];
}

/// Page dots in a material capsule for the middle of a bottom toolbar (kit "_Toolbar page control": padding 24,
/// 8 pt dots 8 apart; current = primary control label, others tertiary). An indicator: change pages with swipes
/// or toolbar buttons.
///
///     IosToolbar(leading: [...], center: [IosToolbarPageControl(count: 3, current: 1)], trailing: [...])
class IosToolbarPageControl extends StatelessWidget {
  const IosToolbarPageControl({
    super.key,
    required this.count,
    required this.current,
  });

  final int count;

  /// 0-based.
  final int current;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    final m = _BarScope.maybeOf(context)?.metrics ?? _BarMetrics.pt48;
    return Semantics(
      label: 'Page ${current + 1} of $count',
      child: AppleGlass(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SizedBox(
          height: m.size,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              for (final d in iosToolbarPageDots(count, current))
                SizedBox(
                  width: 8,
                  height: 8,
                  child: Center(
                    child: Container(
                      width: d.size,
                      height: d.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d.page == current
                            ? c.labelControlPrimary
                            : c.labelControlTertiary,
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

// ==========================================================================================================
// Scaffold: bars over scrolling content
// ==========================================================================================================

/// How content looks where it passes under a bar (kit "Scroll Edge Effect").
enum IosScrollEdgeStyle {
  /// Content blurs and fades out under the bar (the default).
  soft,

  /// An opaque band (white 85% / black 55% + blur): dense content, iPad apps with pinned headers.
  hard,
}

/// A scrolling screen with an [IosNavigationBar] on top and an optional [IosToolbar] at the bottom. Content
/// scrolls UNDER the bars with the scroll edge effect; a large title scrolls with the content and collapses into
/// the bar. The top/bottom safe areas are handled for you.
///
///     IosBarScaffold(
///       navigationBar: IosNavigationBar(title: 'Inbox', style: IosNavigationBarStyle.large, trailing: [...]),
///       toolbar: IosToolbar(leading: [...], trailing: [...]),
///       children: [ for (final m in messages) MessageRow(m) ],
///     )
class IosBarScaffold extends StatefulWidget {
  const IosBarScaffold({
    super.key,
    this.navigationBar,
    this.toolbar,
    this.children = const [],
    this.slivers,
    this.padding = EdgeInsets.zero,
    this.backgroundColor,
    this.controller,
    this.edgeStyle = IosScrollEdgeStyle.soft,
  });

  final IosNavigationBar? navigationBar;
  final IosToolbar? toolbar;

  /// The content (a column of widgets). Use [slivers] instead for long lists (SliverList.builder).
  final List<Widget> children;
  final List<Widget>? slivers;

  /// Extra padding around [children] (inside the bar insets).
  final EdgeInsets padding;

  /// Screen background. Null = automatic: Grouped Backgrounds/Primary when [children] contain an inset grouped
  /// [IosList] (settings, forms), else Backgrounds/Primary.
  final Color? backgroundColor;
  final ScrollController? controller;
  final IosScrollEdgeStyle edgeStyle;

  @override
  State<IosBarScaffold> createState() => _IosBarScaffoldState();
}

class _IosBarScaffoldState extends State<IosBarScaffold> {
  bool _collapsed = false;

  bool _onScroll(Notification n, double threshold) {
    // Scroll updates, and metrics changes (first layout, initialScrollOffset, content size changes).
    final (depth, metrics) = switch (n) {
      ScrollNotification(:final depth, :final metrics) => (depth, metrics),
      ScrollMetricsNotification(:final depth, :final metrics) => (
        depth,
        metrics,
      ),
      _ => (-1, null),
    };
    if (depth != 0 || metrics == null) return false;
    final collapsed = metrics.pixels >= threshold;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    // automatic → large on the first screen, inline when pushed; iPhone landscape → inline (like iOS).
    final nav = widget.navigationBar?._resolved(context);
    final large =
        nav != null &&
        nav.style == IosNavigationBarStyle.large &&
        nav.title != null;
    final topH = nav == null
        ? MediaQuery.paddingOf(context).top
        : IosNavigationBar.heightOf(context, nav);
    final bottomH = widget.toolbar == null
        ? MediaQuery.paddingOf(context).bottom
        : IosToolbar.heightOf(context);
    final threshold = large
        ? IosLargeTitle.titleBottomOf(context)
        : double.infinity;

    final slivers = <Widget>[
      SliverPadding(padding: EdgeInsets.only(top: topH)),
      if (large)
        SliverToBoxAdapter(
          child: IosLargeTitle(title: nav.title!, subtitle: nav.subtitle),
        ),
      if (widget.slivers != null)
        ...widget.slivers!
      else
        SliverPadding(
          padding: widget.padding,
          sliver: SliverList(
            delegate: SliverChildListDelegate(widget.children),
          ),
        ),
      SliverPadding(padding: EdgeInsets.only(bottom: bottomH)),
    ];

    return ColoredBox(
      color: widget.backgroundColor ??
          (widget.children.any((w) => w is IosList && w.style == IosListStyle.insetGrouped)
              ? theme.ios.groupedBgPrimary
              : theme.ios.bgPrimary),
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<Notification>(
              onNotification: (n) => _onScroll(n, threshold),
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: CustomScrollView(
                  controller: widget.controller,
                  slivers: slivers,
                ),
              ),
            ),
          ),
          if (nav != null) ...[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: topH,
              child: _ScrollEdge(top: true, style: widget.edgeStyle),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IosNavigationBar._row(nav, collapsed: _collapsed),
            ),
          ],
          if (widget.toolbar != null) ...[
            // Kit: the bottom edge effect starts 26 above the iPhone toolbar.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomH + 26,
              child: _ScrollEdge(top: false, style: widget.edgeStyle),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: widget.toolbar!),
          ],
        ],
      ),
    );
  }
}

/// Scroll edge effect behind a bar: progressively less blur away from the screen edge (soft), or an opaque band (hard).
class _ScrollEdge extends StatelessWidget {
  const _ScrollEdge({required this.top, required this.style});
  final bool top;
  final IosScrollEdgeStyle style;

  @override
  Widget build(BuildContext context) {
    final dark = AppleTheme.of(context).isDark;
    if (style == IosScrollEdgeStyle.hard) {
      final line = BorderSide(
        color: dark ? const Color(0x1A000000) : const Color(0x0D000000),
        width: 0.5,
      );
      return ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark ? const Color(0x8C000000) : const Color(0xD9FFFFFF),
              border: top ? Border(bottom: line) : Border(top: line),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }
    // Soft: full blur over the outer 40%, then fading out (kit mask: black 0-40%, transparent at 100%).
    const bands = [(40, 10.0), (15, 7.0), (15, 4.5), (15, 2.5), (15, 1.0)];
    final children = [
      for (final b in bands)
        Expanded(
          flex: b.$1,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: b.$2,
                sigmaY: b.$2,
                tileMode: TileMode.clamp,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
    ];
    return IgnorePointer(
      child: Column(children: top ? children : children.reversed.toList()),
    );
  }
}
