import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/widgets.dart';

import '../core/glass.dart';
import '../core/icons.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import 'app_shell.dart';
import 'window.dart';

/// One row of an [IosSidebar] (kit "Sidebar Row").
///
///     const IosSidebarItem(id: 'inbox', label: 'Inbox', icon: AppleIcons.tray, detail: '12')
///     IosSidebarItem(id: 'projects', label: 'Projects', icon: AppleIcons.folder, children: [ … ])   // expandable
@immutable
class IosSidebarItem {
  const IosSidebarItem({
    required this.id,
    required this.label,
    this.icon,
    this.image,
    this.subtitle,
    this.detail,
    this.accessory,
    this.enabled = true,
    this.children = const [],
    this.initiallyExpanded = true,
  });

  /// Identifies the row ([IosSidebar.selectedId]).
  final String id;
  final String label;

  /// Leading symbol, drawn in the accent colour.
  final IconData? icon;

  /// Leading picture instead of a symbol (28 × 28, radius 6).
  final ImageProvider? image;

  /// Second line (footnote, secondary colour).
  final String? subtitle;

  /// Trailing text: a count or a value.
  final String? detail;

  /// Trailing widget after the detail (a checkmark Icon, an IosToggle…).
  final Widget? accessory;
  final bool enabled;

  /// Nested rows: this row expands and collapses with a chevron (kit State = Disclosable).
  final List<IosSidebarItem> children;
  final bool initiallyExpanded;
}

/// A group of rows with an optional header (kit "Section Header"). A section without [title] is a plain list.
@immutable
class IosSidebarSection {
  const IosSidebarSection({this.title, required this.items, this.detail, this.collapsible = true, this.initiallyExpanded = true});
  final String? title;
  final List<IosSidebarItem> items;

  /// Optional text at the end of the header.
  final String? detail;

  /// The header collapses the section (chevron). Default true.
  final bool collapsible;
  final bool initiallyExpanded;
}

// Kit colours that are not tokens (plus darker / plus lighter blends written as normal fills).
Color _material(bool dark, bool inactive) => inactive
    ? (dark ? const Color(0xF7131414) : const Color(0xF7F3F3F3))
    : (dark ? const Color(0xEB131415) : const Color(0xEBE4E4E4));
Color _selection(bool dark) => dark ? const Color(0x21FFFFFF) : const Color(0x12000000);
Color _secondary(bool dark) => dark ? const Color(0x8FFFFFFF) : const Color(0x8F000000);
Color _field(bool dark) => dark ? const Color(0x29FFFFFF) : const Color(0x16000000);

Widget _symbol(IconData icon, double size, Color color) => SizedBox(
      width: size,
      height: size,
      child: OverflowBox(maxWidth: size * 1.2, maxHeight: size * 1.2, child: Icon(icon, size: size * 1.2, color: color)),
    );

/// The iPad sidebar (kit "Sidebar"): toolbar row, search field, rows and collapsible sections on the sidebar
/// material. Give it to [IosAppShell] / [IosSplitView] / [IosTabView] as `sidebar`: on iPad it is the 320 pt left
/// column, on iPhone it is hidden (tab apps) or the full-screen first page (sidebar apps; then give it a [title]).
///
///     IosSidebar(
///       title: 'Mail',
///       sections: [
///         IosSidebarSection(items: [IosSidebarItem(id: 'inbox', label: 'Inbox', icon: AppleIcons.tray, detail: '12')]),
///         IosSidebarSection(title: 'Folders', items: [IosSidebarItem(id: 'work', label: 'Work', icon: AppleIcons.folder)]),
///       ],
///       selectedId: selected,
///       onSelected: (id) => setState(() => selected = id),
///       toolbar: [IosBarButton(label: 'Edit', onPressed: edit)],
///       onSearchChanged: (text) => setState(() => query = text),
///     )
class IosSidebar extends StatefulWidget {
  const IosSidebar({
    super.key,
    required this.sections,
    this.selectedId,
    this.onSelected,
    this.title,
    this.toolbar = const [],
    this.toolbarTrailing = const [],
    this.showToggleButton = true,
    this.searchController,
    this.onSearchChanged,
    this.searchPlaceholder = 'Search',
    this.dictation = false,
    this.inactive = false,
  });

  final List<IosSidebarSection> sections;

  /// The selected row's id. Null = nothing selected.
  final String? selectedId;
  final ValueChanged<String>? onSelected;

  /// Large title at the top of the list (Bold 34). Give it when the sidebar is the iPhone first page.
  final String? title;

  /// Bar buttons at the start of the 44 pt toolbar row (e.g. `IosBarButton(label: 'Edit', …)`).
  final List<Widget> toolbar;

  /// Bar buttons at the end of the toolbar row.
  final List<Widget> toolbarTrailing;

  /// iPad: a "Hide Sidebar" button at the end of the toolbar row (only inside an IosAppShell / IosSplitView).
  final bool showToggleButton;

  /// Shows the search field when set (or when [onSearchChanged] is set).
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final String searchPlaceholder;

  /// Microphone symbol at the end of the search field.
  final bool dictation;

  /// The window is not focused (kit BG Active = False): lighter material.
  final bool inactive;

  @override
  State<IosSidebar> createState() => _IosSidebarState();
}

class _IosSidebarState extends State<IosSidebar> {
  final Map<String, bool> _expanded = {};

  bool _isExpanded(String key, bool initial) => _expanded[key] ?? initial;
  void _toggle(String key, bool initial) => setState(() => _expanded[key] = !_isExpanded(key, initial));

  void _select(IosSidebarItem item) {
    widget.onSelected?.call(item.id);
    // iPhone: choosing a row on the full-screen sidebar page opens the main column.
    final shell = IosAppShellScope.maybeOf(context);
    if (shell != null && !shell.isRegular && shell.sidebarVisible) shell.setSidebarVisible(false);
  }

  List<Widget> _rows(List<IosSidebarItem> items, int level, bool pageMode) {
    final out = <Widget>[];
    for (final item in items) {
      final key = 'item:${item.id}';
      final expandable = item.children.isNotEmpty;
      final open = expandable && _isExpanded(key, item.initiallyExpanded);
      out.add(IosSidebarRow(
        item: item,
        level: level,
        selected: !pageMode && !expandable && item.id == widget.selectedId,
        expanded: expandable ? open : null,
        onTap: !item.enabled ? null : (expandable ? () => _toggle(key, item.initiallyExpanded) : () => _select(item)),
      ));
      if (open) out.addAll(_rows(item.children, level + 1, pageMode));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final shell = IosAppShellScope.maybeOf(context);
    final window = IosWindowScope.maybeOf(context);
    // iPhone first page of a sidebar app: plain background, no remembered selection.
    final pageMode = shell != null && !shell.isRegular;
    final topInset = window != null ? 10.0 : (MediaQuery.paddingOf(context).top > 0 ? MediaQuery.paddingOf(context).top : 10.0);
    final showToggle = widget.showToggleButton && shell != null && shell.hasSidebar && shell.isRegular;
    final showControls = window != null && window.showControls;
    final hasToolbar = widget.toolbar.isNotEmpty || widget.toolbarTrailing.isNotEmpty || showToggle || showControls;
    final hasSearch = widget.searchController != null || widget.onSearchChanged != null;
    final t = IosTypography.of(context);

    final children = <Widget>[
      if (widget.title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Text(widget.title!, style: t.largeTitleEmphasized),
        ),
      if (hasSearch)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: _SidebarSearchField(
            controller: widget.searchController,
            onChanged: widget.onSearchChanged,
            placeholder: widget.searchPlaceholder,
            dictation: widget.dictation,
          ),
        ),
      for (var s = 0; s < widget.sections.length; s++) ...[
        if (widget.sections[s].title != null)
          _SidebarHeader(
            section: widget.sections[s],
            expanded: _isExpanded('section:$s', widget.sections[s].initiallyExpanded),
            onTap: widget.sections[s].collapsible ? () => _toggle('section:$s', widget.sections[s].initiallyExpanded) : null,
          ),
        if (widget.sections[s].title == null || !widget.sections[s].collapsible || _isExpanded('section:$s', widget.sections[s].initiallyExpanded))
          ..._rows(widget.sections[s].items, 0, pageMode),
      ],
    ];

    final pad = MediaQuery.paddingOf(context);
    Widget body = Padding(
      padding: EdgeInsets.only(top: topInset, left: 10, right: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (hasToolbar)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              height: 44,
              child: Row(children: [
                if (showControls) ...[const SizedBox(width: 11), IosWindowControls(active: window.active), const SizedBox(width: 12)],
                for (var i = 0; i < widget.toolbar.length; i++) ...[if (i > 0) const SizedBox(width: 12), widget.toolbar[i]],
                const Spacer(),
                for (var i = 0; i < widget.toolbarTrailing.length; i++) ...[if (i > 0) const SizedBox(width: 12), widget.toolbarTrailing[i]],
                if (showToggle) ...[
                  if (widget.toolbarTrailing.isNotEmpty) const SizedBox(width: 12),
                  _SidebarToggleButton(visible: shell.sidebarVisible, onPressed: shell.toggleSidebar),
                ],
              ]),
            ),
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: ListView(padding: EdgeInsets.only(bottom: 10 + pad.bottom), children: children),
          ),
        ),
      ]),
    );

    if (pageMode) return ColoredBox(color: theme.ios.bgPrimary, child: body);
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(outer: ui.ColorFilter.matrix(_desaturate(0.15)), inner: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20)),
        child: ColoredBox(color: _material(theme.isDark, widget.inactive), child: body),
      ),
    );
  }
}

List<double> _desaturate(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  return [
    r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0,
    r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0,
    r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// One sidebar row (kit "Sidebar Row"): 44 tall, padding 10 (+20 per level) / 8, symbol 17 in a 34 box, 4 before the
/// Body title, detail in the secondary colour; selected = grey capsule; disabled = 50%. [IosSidebar] builds these;
/// use it directly only for a custom sidebar.
class IosSidebarRow extends StatefulWidget {
  const IosSidebarRow({super.key, required this.item, this.level = 0, this.selected = false, this.expanded, required this.onTap});
  final IosSidebarItem item;

  /// Indent level 0, 1 or 2.
  final int level;
  final bool selected;

  /// Non-null for an expandable row: true = chevron down, false = chevron forward.
  final bool? expanded;
  final VoidCallback? onTap;

  @override
  State<IosSidebarRow> createState() => _IosSidebarRowState();
}

class _IosSidebarRowState extends State<IosSidebarRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final t = IosTypography.of(context);
    final item = widget.item;
    final secondary = _secondary(theme.isDark);
    final leading = item.image != null
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(6),
              child: Image(image: item.image!, width: 28, height: 28, fit: BoxFit.cover),
            ),
          )
        : item.icon != null
            ? SizedBox(width: 34, child: Center(child: _symbol(item.icon!, t.body.fontSize ?? 17, theme.accentColor)))
            : null;
    final title = Text(item.label, style: t.body, maxLines: 1, overflow: TextOverflow.ellipsis);
    final text = item.subtitle == null
        ? title
        : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            title,
            Transform.translate(
              offset: const Offset(0, -2),
              child: Text(item.subtitle!, style: t.footnote.copyWith(color: c.labelSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]);
    Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: EdgeInsets.only(left: 10.0 + 20 * widget.level.clamp(0, 2), right: 8),
        child: Row(children: [
          if (leading != null) ...[leading, const SizedBox(width: 4)],
          Expanded(child: text),
          if (item.detail != null) ...[
            const SizedBox(width: 8),
            Text(item.detail!, style: t.body.copyWith(color: secondary), maxLines: 1),
            if (widget.expanded == null && item.accessory == null) const SizedBox(width: 8),
          ],
          if (item.accessory != null) ...[const SizedBox(width: 8), item.accessory!],
          if (widget.expanded != null) ...[
            const SizedBox(width: 4),
            SizedBox(
              width: 18,
              height: 18,
              child: Center(child: Icon(widget.expanded! ? AppleIcons.chevronDown : AppleIcons.forward, size: 15, color: secondary)),
            ),
            const SizedBox(width: 4),
          ],
        ]),
      ),
    );
    final fill = widget.selected || (_pressed && widget.onTap != null) ? _selection(theme.isDark) : const Color(0x00000000);
    row = DecoratedBox(decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()), child: row);
    if (!item.enabled) row = Opacity(opacity: 0.5, child: row);
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.onTap != null,
      expanded: widget.expanded,
      label: [item.label, if (item.detail != null) item.detail!].join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
        onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
        onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: row,
      ),
    );
  }
}

// Section header (kit "Section Header"): 54 tall, padding 21 / 12 / 11, Body in the secondary label colour,
// chevron (primary colour) when the section collapses.
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.section, required this.expanded, required this.onTap});
  final IosSidebarSection section;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final t = IosTypography.of(context);
    final style = t.body.copyWith(color: theme.ios.labelSecondary);
    return Semantics(
      header: true,
      button: onTap != null,
      expanded: onTap != null ? expanded : null,
      label: section.title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 21, 12, 11),
            child: Row(children: [
              Expanded(child: Text(section.title!, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (section.detail != null) ...[const SizedBox(width: 8), Text(section.detail!, style: style)],
              if (onTap != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Center(
                    child: Icon(expanded ? AppleIcons.chevronDown : AppleIcons.forward, size: 15, color: theme.ios.labelVibrantPrimary),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// Search field (kit "Sidebar Search Field"): 44 capsule, padding 11, symbol + Body text, gap 8.
class _SidebarSearchField extends StatelessWidget {
  const _SidebarSearchField({required this.controller, required this.onChanged, required this.placeholder, required this.dictation});
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String placeholder;
  final bool dictation;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final t = IosTypography.of(context);
    final secondary = _secondary(theme.isDark);
    final size = t.body.fontSize ?? 17;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: ShapeDecoration(color: _field(theme.isDark), shape: const StadiumBorder()),
      child: Row(children: [
        _symbol(AppleIcons.magnifyingglass, size, secondary),
        const SizedBox(width: 8),
        Expanded(
          child: CupertinoTextField.borderless(
            controller: controller,
            onChanged: onChanged,
            placeholder: placeholder,
            padding: EdgeInsets.zero,
            style: t.body,
            placeholderStyle: t.body.copyWith(color: secondary),
            cursorColor: theme.accentColor,
          ),
        ),
        if (dictation) ...[const SizedBox(width: 8), _symbol(AppleIcons.mic, size, secondary)],
      ]),
    );
  }
}

// The sidebar's own "Hide Sidebar" bar button (a 44 circle of Regular blur material, symbol Medium 17).
class _SidebarToggleButton extends StatelessWidget {
  const _SidebarToggleButton({required this.visible, required this.onPressed});
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    return Semantics(
      button: true,
      expanded: visible,
      label: visible ? 'Hide Sidebar' : 'Show Sidebar',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: AppleGlass(
          child: SizedBox(width: 44, height: 44, child: Center(child: _symbol(AppleIcons.sidebarLeft, 17, theme.ios.labelControlPrimary))),
        ),
      ),
    );
  }
}
