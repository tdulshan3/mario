import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '_chrome.dart';
import 'scroll_views.dart';

/// Sidebar row size (System Settings › Appearance › Sidebar icon size). [medium] is the default.
enum MacSidebarSize {
  /// 24 px rows, 11 px text (the kit's example windows).
  small,

  /// 32 px rows, 13 px text. The default.
  medium,

  /// 36 px rows, 15 px text.
  large,
}

/// Kit "Item", "_Leading", "Section Header" metrics per size.
class _Metrics {
  const _Metrics({
    required this.row,
    required this.font,
    required this.line,
    required this.iconBox,
    required this.iconSize,
    required this.imageSize,
    required this.imageRadius,
    required this.headingSize,
    required this.headingTop,
    required this.headingBottom,
  });
  final double row;
  final double font;
  final double line;
  final double iconBox;
  final double iconSize;
  final double imageSize;
  final double imageRadius;
  final double headingSize;
  final double headingTop;
  final double headingBottom;

  static const small = _Metrics(
    row: 24,
    font: 11,
    line: 14,
    iconBox: 24,
    iconSize: 17,
    imageSize: 14,
    imageRadius: 3,
    headingSize: 11,
    headingTop: 17,
    headingBottom: 8,
  );
  static const medium = _Metrics(
    row: 32,
    font: 13,
    line: 16,
    iconBox: 24,
    iconSize: 19,
    imageSize: 18,
    imageRadius: 4,
    headingSize: 13,
    headingTop: 18,
    headingBottom: 9,
  );
  static const large = _Metrics(
    row: 36,
    font: 15,
    line: 20,
    iconBox: 28,
    iconSize: 22,
    imageSize: 20,
    imageRadius: 4,
    headingSize: 13,
    headingTop: 18,
    headingBottom: 9,
  );

  static _Metrics of(MacSidebarSize s) => switch (s) {
    MacSidebarSize.small => small,
    MacSidebarSize.medium => medium,
    MacSidebarSize.large => large,
  };
}

class _SidebarScope extends InheritedWidget {
  const _SidebarScope({required this.metrics, required super.child});
  final _Metrics metrics;

  static _Metrics of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_SidebarScope>()?.metrics ?? _Metrics.medium;

  @override
  bool updateShouldNotify(_SidebarScope old) => old.metrics != metrics;
}

/// Nesting level and disclosure gutter of the rows in one list (CSS `--mac-sidebar-level` / `--mac-sidebar-gutter`).
class _ListScope extends InheritedWidget {
  const _ListScope({required this.level, required this.gutter, required super.child});
  final int level;
  final bool gutter;

  static _ListScope? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ListScope>();

  @override
  bool updateShouldNotify(_ListScope old) => old.level != level || old.gutter != gutter;
}

/// Marks the first child of the sidebar body (its section header has no space above it).
class _FirstScope extends InheritedWidget {
  const _FirstScope({required this.first, required super.child});
  final bool first;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_FirstScope>()?.first ?? false;

  @override
  bool updateShouldNotify(_FirstScope old) => old.first != first;
}

bool _hasFolder(List<Widget> children) => children.any((w) => w is MacSidebarItem && w.children != null);

Widget _list(List<Widget> children, {required int level, required bool gutter}) => _ListScope(
  level: level,
  gutter: gutter,
  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
);

/// The sidebar: the column on the left of a window that lists the app's places (kit page "Sidebars").
/// 240 px wide, a neutral grey background, a 52 px header row (traffic lights + sidebar button in mockups),
/// then the scrolling list of [MacSidebarSection]s and [MacSidebarItem]s. Put it in `MacWindow(sidebar: …)`.
///
///     MacSidebar(
///       header: [const MacWindowControls(),                        // mockups only; a real app leaves it out
///                MacToolbarButton(icon: AppleIcons.sidebarLeft, label: 'Hide Sidebar', onPressed: hide)],
///       children: [
///         MacSidebarSection(children: [
///           MacSidebarItem(icon: AppleIcons.clock, label: 'Recents', selected: place == 0, onPressed: () => go(0)),
///           MacSidebarItem(icon: AppleIcons.folder, label: 'Shared', selected: place == 1, onPressed: () => go(1)),
///         ]),
///         MacSidebarSection(title: 'Favorites', collapsible: true, children: [
///           MacSidebarItem(icon: AppleIcons.arrowDownCircle, label: 'Downloads', detail: '3',
///                          selected: place == 2, onPressed: () => go(2)),
///         ]),
///       ],
///     )
///
/// No hover effect (macOS sidebars have none). Up/Down move between rows, Home/End jump, Left/Right collapse and
/// expand folders and sections, Return/Space choose. The window's inactive state turns the sidebar grey.
class MacSidebar extends StatefulWidget {
  const MacSidebar({
    super.key,
    required this.children,
    this.size = MacSidebarSize.medium,
    this.width = 240,
    this.header,
    this.background = true,
    this.controller,
    this.semanticLabel = 'Sidebar',
  });

  /// [MacSidebarSection]s (or [MacSidebarItem]s directly).
  final List<Widget> children;
  final MacSidebarSize size;

  /// Default 240 (kit). 180–320 is a good range.
  final double width;

  /// The 52 px header row: traffic lights at the left, the sidebar button at the right (XL toolbar size).
  /// Null = no header (a page app: the list starts 14 px from the top).
  final List<Widget>? header;

  /// Draw the sidebar background (default true). False only for a source list inside a sheet or popover.
  final bool background;
  final ScrollController? controller;
  final String semanticLabel;

  @override
  State<MacSidebar> createState() => _MacSidebarState();
}

class _MacSidebarState extends State<MacSidebar> {
  // Home / End: first / last row. (Set on the node: a Focus widget ignores onKeyEvent for an external node.)
  late final _bodyNode = FocusNode(skipTraversal: true, canRequestFocus: false, onKeyEvent: _onKey);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.home || event.logicalKey == LogicalKeyboardKey.end) {
      _jump(event.logicalKey == LogicalKeyboardKey.end);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _bodyNode.dispose();
    super.dispose();
  }

  void _jump(bool last) {
    // Focus tree order is attachment order (rows of a folder opened later come last): sort by position.
    final nodes = _bodyNode.traversalDescendants.where((n) => n.canRequestFocus).toList()..sort((a, b) => a.rect.top.compareTo(b.rect.top));
    if (nodes.isEmpty) return;
    (last ? nodes.last : nodes.first).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final dark = theme.isDark;
    final inactive = MacWindowState.isInactive(context);
    final m = _Metrics.of(widget.size);
    // Kit "BG": the Sidebar-BG colour with luminosity blend, 85% desaturated = a neutral grey of the same lightness.
    final bg = inactive
        ? (dark ? const Color(0xFF131313) : const Color(0xFFF3F3F3))
        : (dark ? const Color(0xFF151515) : const Color(0xFFE4E4E4));
    final label = inactive && !dark ? theme.mac.sidebarLabelInactive : theme.mac.labelVibrantPrimary;

    final body = FocusTraversalGroup(
      child: Focus(
        focusNode: _bodyNode,
        child: MacScrollView(
          controller: widget.controller,
          fillViewport: false,
          padding: EdgeInsets.fromLTRB(10, widget.header == null ? 14 : 0, 10, 10),
          child: _list(
            [for (var i = 0; i < widget.children.length; i++) _FirstScope(first: i == 0, child: widget.children[i])],
            level: 0,
            gutter: _hasFolder(widget.children),
          ),
        ),
      ),
    );

    Widget sidebar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != null)
          MacControlSizeScope(
            size: MacControlSize.xl,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(19, 0, 8, 0),
                child: Row(
                  mainAxisAlignment: widget.header!.length > 1 ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                  // Flexible (loose): each child keeps its own size but gets a bounded width, so anything placed here
                  // by mistake (a sidebar row) lays out instead of failing.
                  children: [for (final w in widget.header!) Flexible(child: w)],
                ),
              ),
            ),
          ),
        Expanded(child: body),
      ],
    );
    sidebar = DefaultTextStyle(
      style: macChromeText(m.font, m.line, label, weight: FontWeight.w500),
      child: _SidebarScope(metrics: m, child: sidebar),
    );
    if (widget.background) sidebar = ColoredBox(color: bg, child: sidebar);
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      explicitChildNodes: true,
      child: SizedBox(width: widget.width, child: sidebar),
    );
  }
}

/// A group of sidebar rows with an optional header (kit "Section Header"): Bold, grey, not selectable.
/// [collapsible] adds a chevron at the right that hides and shows the rows.
///
///     MacSidebarSection(children: [recents, shared])                          // first, untitled group
///     MacSidebarSection(title: 'Favorites', collapsible: true, children: [desktop, documents])
///     MacSidebarSection(title: 'Tags', detail: '12', children: [ … ])
class MacSidebarSection extends StatefulWidget {
  const MacSidebarSection({
    super.key,
    this.title,
    this.detail,
    this.collapsible = false,
    this.expanded,
    this.initiallyExpanded = true,
    this.onExpandedChanged,
    required this.children,
  });

  /// Header text ("Favorites", "Locations"). Leave it out for the first, untitled group.
  final String? title;

  /// Grey text at the right of the header.
  final String? detail;

  /// The header gets a chevron and hides/shows the rows (remember the state).
  final bool collapsible;

  /// Controlled open state. Null = the section keeps its own state, starting at [initiallyExpanded].
  final bool? expanded;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  /// [MacSidebarItem]s.
  final List<Widget> children;

  @override
  State<MacSidebarSection> createState() => _MacSidebarSectionState();
}

class _MacSidebarSectionState extends State<MacSidebarSection> {
  late bool _open = widget.initiallyExpanded;

  bool get _expanded => !widget.collapsible || (widget.expanded ?? _open);

  void _set(bool v) {
    if (widget.expanded == null) setState(() => _open = v);
    widget.onExpandedChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final m = _SidebarScope.of(context);
    final inactive = MacWindowState.isInactive(context);
    final first = _FirstScope.of(context);
    final headingColor = inactive ? c.labelTertiary : c.labelSecondary;
    final chevronColor = c.labelTertiary;

    Widget? heading;
    if (widget.title != null) {
      final style = macChromeText(m.headingSize, m.headingSize + 3, headingColor, weight: FontWeight.w700);
      Widget row(bool focused) => MacFocusRing(
        show: focused,
        radius: 6,
        offset: -2,
        child: Padding(
          padding: EdgeInsets.fromLTRB(4, first ? 0 : m.headingTop, 4, m.headingBottom),
          child: Row(
            children: [
              Flexible(
                child: Text(widget.title!, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: style),
              ),
              const Spacer(),
              if (widget.detail != null)
                Text(widget.detail!, maxLines: 1, softWrap: false, style: style.copyWith(fontWeight: FontWeight.w500)),
              if (widget.collapsible) ...[
                if (widget.detail != null) const SizedBox(width: 4),
                SizedBox(
                  width: 24,
                  height: 14,
                  child: Center(
                    child: MacChevron(expanded: _expanded, color: chevronColor),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      heading = widget.collapsible
          ? MacPressable(
              onPressed: () => _set(!_expanded),
              semanticLabel: widget.title,
              toggled: _expanded,
              keys: {macArrowLeft: () => _set(false), macArrowRight: () => _set(true)},
              builder: (context, s) => row(s.focused),
            )
          : Semantics(header: true, child: row(false));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ?heading,
        if (_expanded) _list(widget.children, level: 0, gutter: _hasFolder(widget.children)),
      ],
    );
  }
}

/// One sidebar row (kit "Item"): a symbol in the accent colour, a short name (1–3 words), an optional grey count
/// on the right. The selected row gets a neutral grey rounded highlight. Exactly one row is selected.
/// With [children] it is a folder with a disclosure triangle (nested rows indent 12 px per level, up to 4).
///
///     MacSidebarItem(icon: AppleIcons.clock, label: 'Recents', selected: true, onPressed: () => go(0))
///     MacSidebarItem(icon: AppleIcons.tray, label: 'Inbox', detail: '12', onPressed: () => go(1))
///     MacSidebarItem(icon: AppleIcons.globe, label: 'Network', onPressed: null)            // disabled
///     MacSidebarItem(icon: AppleIcons.folder, label: 'Work', onPressed: () => go(2), children: [
///       MacSidebarItem(icon: AppleIcons.doc, label: 'Invoices', onPressed: () => go(3)),
///     ])
/// [onPressed] null = disabled (grey name, faded symbol). No hover effect.
class MacSidebarItem extends StatefulWidget {
  const MacSidebarItem({
    super.key,
    this.icon,
    this.image,
    required this.label,
    this.detail,
    this.selected = false,
    required this.onPressed,
    this.children,
    this.expanded,
    this.initiallyExpanded = false,
    this.onExpandedChanged,
    this.level,
    this.semanticLabel,
  });

  /// Outline symbol, drawn in the accent colour.
  final IconData? icon;

  /// A full-colour image instead of a symbol (album cover, avatar): 14 · 18 · 20 px, rounded 3 · 4 · 4.
  final Widget? image;
  final String label;

  /// Count or short text on the right ("3"), plain grey. Not a coloured pill.
  final String? detail;

  /// The current place: grey rounded highlight.
  final bool selected;
  final VoidCallback? onPressed;

  /// Child rows: makes this row a folder with a disclosure triangle. An empty list = a folder without children yet.
  final List<Widget>? children;

  /// Controlled open state of a folder. Null = the row keeps its own state, starting at [initiallyExpanded].
  final bool? expanded;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  /// Indent level 0–4 (12 px each). Null = automatic from the nesting. Set it when you render a tree as a flat list.
  final int? level;

  /// Accessible name (default: [label] + [detail]).
  final String? semanticLabel;

  @override
  State<MacSidebarItem> createState() => _MacSidebarItemState();
}

class _MacSidebarItemState extends State<MacSidebarItem> {
  late bool _open = widget.initiallyExpanded;

  bool get _folder => widget.children != null;
  bool get _expanded => widget.expanded ?? _open;

  void _set(bool v) {
    if (!_folder) return;
    if (widget.expanded == null) setState(() => _open = v);
    widget.onExpandedChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final dark = theme.isDark;
    final m = _SidebarScope.of(context);
    final scope = _ListScope.of(context);
    final level = (widget.level ?? scope?.level ?? 0).clamp(0, 4);
    final gutter = _folder || (scope?.gutter ?? false);
    final inactive = MacWindowState.isInactive(context);
    final enabled = widget.onPressed != null;

    // Kit "_Leading" / "_Detail" / "_Selection" colours (vibrant colours pre-blended), Active = True / False.
    final labelColor = !enabled ? c.sidebarLabelInactive : (inactive && !dark ? c.sidebarLabelInactive : c.labelVibrantPrimary);
    final iconColor = inactive || !enabled ? c.sidebarLabelInactive : macAccentVibrant(context);
    final detailColor = inactive ? (dark ? const Color(0x29FFFFFF) : const Color(0x29000000)) : c.labelTertiary;
    // Kit "_Selection": Light #F2F2F2 plus darker (= black 5%; inactive 2%), Dark #0D0D0D plus lighter (= +5%;
    // inactive +2%). Dark uses the real "plus" blend, so the highlight is right on any background.
    final selection = dark ? (inactive ? const Color(0xFF050505) : const Color(0xFF0D0D0D)) : (inactive ? c.fillQuinary : c.fillTertiary);
    final indent = level * 12.0 + (gutter ? 16 : 0);

    Widget leading = const SizedBox.shrink();
    if (widget.image != null) {
      leading = SizedBox(
        width: m.iconBox,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(m.imageRadius),
            child: SizedBox.square(
              dimension: m.imageSize,
              child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: widget.image),
            ),
          ),
        ),
      );
    } else if (widget.icon != null) {
      leading = SizedBox(
        width: m.iconBox,
        height: m.iconSize,
        child: OverflowBox(
          minWidth: 0,
          minHeight: 0,
          maxWidth: m.iconSize * 1.3,
          maxHeight: m.iconSize * 1.3,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Icon(widget.icon, size: m.iconSize * 1.05, color: iconColor),
          ),
        ),
      );
    }

    final row = MacPressable(
      onPressed: widget.onPressed,
      semanticLabel: widget.semanticLabel ?? (widget.detail == null ? widget.label : '${widget.label}, ${widget.detail}'),
      selected: widget.selected,
      keys: _folder ? {macArrowLeft: () => _set(false), macArrowRight: () => _set(true)} : const {},
      builder: (context, s) {
        Widget content = ConstrainedBox(
          constraints: BoxConstraints(minHeight: m.row),
          child: Padding(
            padding: EdgeInsets.fromLTRB(4 + indent, 0, 6, 0),
            child: Row(
              spacing: 4,
              children: [
                if (widget.image != null || widget.icon != null) leading,
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: macChromeText(m.font, m.line, labelColor, weight: FontWeight.w500),
                  ),
                ),
                if (widget.detail != null)
                  Text(
                    widget.detail!,
                    maxLines: 1,
                    softWrap: false,
                    style: macChromeText(m.font, m.line, detailColor, weight: FontWeight.w500, tabular: true),
                  ),
              ],
            ),
          ),
        );
        if (_folder) {
          // Kit "_Disclosure - Folder": 12 px column at 4 + level × 12, SF Bold 11 chevron, label tertiary.
          content = Stack(
            children: [
              content,
              Positioned(
                left: 4 + level * 12.0,
                top: 0,
                bottom: 0,
                width: 12,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _set(!_expanded),
                  child: Center(
                    child: MacChevron(expanded: _expanded, color: c.labelTertiary),
                  ),
                ),
              ),
            ],
          );
        }
        return MacFocusRing(
          show: s.focused,
          radius: 8,
          offset: -2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.selected ? selection : null,
              backgroundBlendMode: widget.selected && dark ? BlendMode.plus : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: content,
          ),
        );
      },
    );

    if (!_folder) return row;
    // Same tree when collapsed and expanded, so the row keeps keyboard focus while it opens.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        if (_expanded && widget.children!.isNotEmpty) _list(widget.children!, level: level + 1, gutter: true),
      ],
    );
  }
}
