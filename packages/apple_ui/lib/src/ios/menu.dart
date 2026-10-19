import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/glass.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_menu_support.dart';

// =================================================================================================================
// Menu session: what an open menu shares with its rows (close, submenus).
// =================================================================================================================

class _OpenSubmenu {
  _OpenSubmenu(this.item, this.row, this.parent, this.regular, this.depth);
  final IosMenuItem item;
  final Rect row;
  final Rect parent;
  final bool regular;
  final int depth;
}

class _MenuSession extends ChangeNotifier {
  _MenuSession(this.onClose);
  final VoidCallback onClose;
  RenderBox? overlay;
  final List<_OpenSubmenu> submenus = [];

  void close() => onClose();

  void openSubmenu(IosMenuItem item, BuildContext rowContext, int depth) {
    final overlayBox = overlay;
    final panel = _MenuPanelScope.maybeOf(rowContext)?.panelKey.currentContext;
    if (overlayBox == null || panel == null) return;
    submenus.removeWhere((s) => s.depth >= depth);
    submenus.add(_OpenSubmenu(item, menuRectIn(rowContext, overlayBox), menuRectIn(panel, overlayBox),
        MenuMetrics.of(rowContext).regular, depth));
    notifyListeners();
  }

  void closeSubmenu(int depth) {
    submenus.removeWhere((s) => s.depth >= depth);
    notifyListeners();
  }

  void reset() => submenus.clear();
}

class _MenuSessionScope extends InheritedNotifier<_MenuSession> {
  const _MenuSessionScope({required _MenuSession session, required super.child}) : super(notifier: session);
  static _MenuSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MenuSessionScope>()?.notifier;
}

class _MenuPanelScope extends InheritedWidget {
  const _MenuPanelScope({required this.hasSelection, required this.depth, required this.panelKey, required super.child});
  final bool hasSelection;
  final int depth;
  final GlobalKey panelKey;
  static _MenuPanelScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_MenuPanelScope>();
  @override
  bool updateShouldNotify(_MenuPanelScope old) => old.hasSelection != hasSelection || old.depth != depth;
}

class _MenuControlScope extends InheritedWidget {
  const _MenuControlScope({required super.child});
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_MenuControlScope>() != null;
  @override
  bool updateShouldNotify(_MenuControlScope old) => false;
}

/// The overlay layers of an open menu: a tap-outside barrier, the root panel, and the open submenus.
Widget _menuLayers(BuildContext context, _MenuSession session, Widget root, {Color barrier = const Color(0x00000000)}) {
  return Actions(
    actions: <Type, Action<Intent>>{
      DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
        if (session.submenus.isNotEmpty) {
          session.closeSubmenu(session.submenus.last.depth);
        } else {
          session.close();
        }
        return null;
      }),
    },
    child: FocusScope(
      autofocus: true,
      child: _MenuSessionScope(
        session: session,
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => SizedBox.expand(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => session.close(),
                    onSecondaryTapDown: (_) => session.close(),
                    child: ColoredBox(color: barrier),
                  ),
                ),
                Positioned.fill(child: root),
                for (final s in session.submenus) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => session.closeSubmenu(s.depth),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomSingleChildLayout(
                      delegate: SubmenuPlacementDelegate(parent: s.parent, row: s.row, regular: s.regular),
                      child: MenuAppear(
                        alignment: Alignment.topLeft,
                        child: IosMenuPanel(
                          width: s.parent.width,
                          depth: s.depth,
                          semanticLabel: s.item.label,
                          children: [
                            // iPhone: the row is repeated at the top of the submenu, open; tapping it goes back.
                            if (!s.regular)
                              IosMenuItem(
                                label: s.item.label,
                                icon: s.item.icon,
                                subtitle: s.item.subtitle,
                                open: true,
                                keepsMenuOpen: true,
                                onPressed: () => session.closeSubmenu(s.depth),
                              ),
                            ...s.item.children,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

bool _isCheckable(Widget w) =>
    (w is IosMenuItem && w.checked != null) || (w is IosMenuSection && w.children.any((c) => c is IosMenuItem && c.checked != null));

// =================================================================================================================
// IosMenuPanel — the material panel (static); IosMenu shows it next to a trigger.
// =================================================================================================================

/// The menu panel itself (kit "Menu"): Thick blur material, 250 wide, r=34, 10 above and below the rows.
/// [IosMenu], [IosContextMenu], [IosPopUpButton] and [IosPullDownButton] show it for you; use it directly only to
/// draw a menu in place (a mockup, a kit sheet).
///
///     IosMenuPanel(children: [
///       IosMenuControlGroup(children: [IosMenuItem(label: 'Copy', icon: AppleIcons.docOnDoc, onPressed: copy), …]),
///       IosMenuItem(label: 'Rename', icon: AppleIcons.pencil, onPressed: rename),
///       IosMenuSection(title: 'Sort By', children: [...]),
///       IosMenuItem(label: 'Delete', icon: AppleIcons.trash, destructive: true, onPressed: delete),
///     ])
class IosMenuPanel extends StatefulWidget {
  const IosMenuPanel({
    super.key,
    required this.children,
    this.width = 250,
    this.hasSelection,
    this.semanticLabel,
    this.depth = 0,
    this.background = true,
  });

  /// [IosMenuControlGroup] (first), [IosMenuItem], [IosMenuSection], [IosMenuDivider].
  final List<Widget> children;

  /// false = the rows only, without the material panel (to put menu rows on your own surface).
  final bool background;

  /// Kit: 250 (238 on the component sheet).
  final double width;

  /// Indent every row for checkmarks. Null = automatic (true when a row has `checked`).
  final bool? hasSelection;
  final String? semanticLabel;

  /// 0 for a menu, 1+ for submenus (set by the menu).
  final int depth;

  @override
  State<IosMenuPanel> createState() => _IosMenuPanelState();
}

class _IosMenuPanelState extends State<IosMenuPanel> {
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final m = MenuMetrics.of(context);
    final colors = MenuColors.of(context);
    final padX = m.dims.menuItemPaddingX;
    Widget separator() => Padding(
          // Kit: 10 above and below on iPhone AND iPad (its iPad menus draw 21-tall separators, not the 8 / 9 tokens).
          padding: EdgeInsets.fromLTRB(padX + 8, 10, padX + 8, 10),
          child: SizedBox(height: 1, child: ColoredBox(color: colors.separator)),
        );
    // Separators: under the control group, above every section (unless first), for each divider (never doubled,
    // never first or last).
    final rows = <Widget>[];
    var lastWasSeparator = true;
    final kids = widget.children;
    for (var i = 0; i < kids.length; i++) {
      final c = kids[i];
      final isLast = i == kids.length - 1;
      if (c is IosMenuDivider) {
        if (!lastWasSeparator && !isLast) {
          rows.add(separator());
          lastWasSeparator = true;
        }
        continue;
      }
      if (c is IosMenuSection && !lastWasSeparator) rows.add(separator());
      if (c is IosMenuControlGroup) {
        rows.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: c));
        if (!isLast) {
          rows.add(separator());
          lastWasSeparator = true;
          continue;
        }
      } else {
        rows.add(Padding(padding: EdgeInsets.symmetric(horizontal: padX), child: c));
      }
      lastWasSeparator = false;
    }
    final hasSelection = widget.hasSelection ?? kids.any(_isCheckable);
    final content = _MenuPanelScope(
      hasSelection: hasSelection,
      depth: widget.depth,
      panelKey: _key,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
    return Semantics(
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: SizedBox(
        key: _key,
        width: widget.width,
        child: widget.background ? AppleGlass(style: AppleGlassStyle.panel, radius: 34, child: content) : content,
      ),
    );
  }
}

// =================================================================================================================
// IosMenuItem
// =================================================================================================================

/// One menu row (kit "Menu Items"): symbol + label (+ subtitle) (+ shortcut), 40 tall.
/// Inside [IosMenuControlGroup] it draws as an icon button. With [children] it is a SUBMENU row (chevron.right):
/// on iPhone the submenu covers its row, on iPad it opens beside the menu.
///
///     IosMenuItem(label: 'Rename', icon: AppleIcons.pencil, onPressed: rename)
///     IosMenuItem(label: 'Delete', icon: AppleIcons.trash, destructive: true, onPressed: delete)
///     IosMenuItem(label: 'Show Hidden Files', checked: showHidden, onPressed: toggleHidden)   // checkmark
///     IosMenuItem(label: 'Sort By', icon: AppleIcons.arrowUpArrowDown, children: [ … IosMenuItem … ])   // submenu
/// [onPressed] null (and no [children]) = disabled. Choosing an item closes the menu (unless [keepsMenuOpen]).
class IosMenuItem extends StatefulWidget {
  const IosMenuItem({
    super.key,
    required this.label,
    this.subtitle,
    this.icon,
    this.shortcut,
    this.onPressed,
    this.destructive = false,
    this.checked,
    this.keepsMenuOpen = false,
    this.enabled = true,
    this.open = false,
    this.children = const [],
  });

  /// The title: a verb for actions ("Rename", "Delete").
  final String label;

  /// A second line in secondary grey.
  final String? subtitle;
  final IconData? icon;

  /// Keyboard shortcut at the trailing edge (iPad with a keyboard): '⌘R', '⇧⌘N'.
  final String? shortcut;
  final VoidCallback? onPressed;

  /// Red: deletes or removes something.
  final bool destructive;

  /// null = a plain action. true / false = a checkable row (a checkmark in front when true).
  final bool? checked;

  /// Keep the menu open after choosing (on/off options flipped several times).
  final bool keepsMenuOpen;

  /// false = disabled even with [onPressed] or [children].
  final bool enabled;

  /// Draws a submenu row open (chevron.down on a highlight). The menu sets it on the row repeated at the top of an
  /// open submenu; you don't need it.
  final bool open;

  /// Submenu items. Non-empty = this row opens a submenu.
  final List<Widget> children;

  @override
  State<IosMenuItem> createState() => _IosMenuItemState();
}

class _IosMenuItemState extends State<IosMenuItem> {
  bool _pressed = false;
  bool _focused = false;
  bool _hovered = false;

  bool get _isSubmenu => widget.children.isNotEmpty;
  bool get _enabled => widget.enabled && (widget.onPressed != null || _isSubmenu);

  void _activate() {
    if (!_enabled) return;
    final session = _MenuSessionScope.maybeOf(context);
    if (_isSubmenu) {
      final depth = (_MenuPanelScope.maybeOf(context)?.depth ?? 0) + 1;
      if (session != null && session.submenus.any((s) => s.item == widget)) {
        session.closeSubmenu(depth);
      } else {
        session?.openSubmenu(widget, context, depth);
      }
      return;
    }
    HapticFeedback.selectionClick();
    widget.onPressed?.call();
    if (!widget.keepsMenuOpen) session?.close();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MenuColors.of(context);
    final inControls = _MenuControlScope.of(context);
    final color = !_enabled ? colors.tertiary : (widget.destructive ? colors.destructive : colors.label);
    final session = _MenuSessionScope.maybeOf(context);
    final isOpen = widget.open || (session?.submenus.any((s) => s.item == widget) ?? false);
    final highlighted = _enabled && (_pressed || _focused || _hovered);

    Widget body = inControls ? _buildControl(context, color, highlighted, colors) : _buildRow(context, color, highlighted || isOpen, isOpen, colors);

    return Semantics(
      button: true,
      enabled: _enabled,
      checked: widget.checked,
      label: widget.subtitle == null ? widget.label : '${widget.label}, ${widget.subtitle}',
      hint: _isSubmenu ? 'Opens a submenu' : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _enabled,
        mouseCursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _activate();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onTap: _enabled ? _activate : null,
          child: body,
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, Color color, bool fill, bool isOpen, MenuColors colors) {
    final m = MenuMetrics.of(context);
    final hasSelection = _MenuPanelScope.maybeOf(context)?.hasSelection ?? widget.checked != null;
    // Kit: iPhone Size/Body (17) on a 20 line, iPad 15 on 18; subtitle Regular 13 on 18 / 16.
    final base = appleFont(size: m.fontSize).copyWith(
      fontSize: m.fontSize,
      height: m.lineHeight / m.fontSize,
      letterSpacing: m.tracking,
      decoration: TextDecoration.none,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final title = base.copyWith(color: color);
    final sub = appleFont(size: 13).copyWith(
      fontSize: 13,
      height: m.dims.menuItemSubtitleLeading / 13,
      letterSpacing: -0.08,
      color: _enabled ? colors.secondary : colors.quaternary,
      decoration: TextDecoration.none,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final shortcut = appleFont(size: 15).copyWith(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.5,
      color: _enabled ? colors.secondary : colors.quaternary,
      decoration: TextDecoration.none,
    );
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          SizedBox(width: 28, height: 20, child: Center(child: Icon(widget.icon, size: m.fontSize, color: color))),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: m.dims.menuItemPaddingY, horizontal: m.dims.menuItemLabelIndent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.label, style: title),
                if (widget.subtitle != null) ...[const SizedBox(height: 2), Text(widget.subtitle!, style: sub)],
              ],
            ),
          ),
        ),
        if (widget.shortcut != null) ...[const SizedBox(width: 6), Text(widget.shortcut!, style: shortcut, maxLines: 1)],
        if (_isSubmenu || widget.open) ...[
          const SizedBox(width: 6),
          MenuGlyph(isOpen ? MenuGlyphKind.chevronDown : MenuGlyphKind.chevronRight,
              color: color, size: isOpen ? 15 : 17, width: 14, height: 20),
        ],
      ],
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: EdgeInsets.only(left: hasSelection ? 36 : 6, right: 8),
      decoration: fill
          ? ShapeDecoration(
              color: isOpen && !(_pressed || _focused || _hovered) ? colors.openFill : colors.highlight,
              shape: const StadiumBorder())
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          row,
          if (widget.checked == true)
            Positioned(
              left: -30,
              top: 0,
              bottom: 0,
              child: Center(child: MenuGlyph(MenuGlyphKind.checkmark, color: colors.label, size: 17, width: 24, height: 22)),
            ),
        ],
      ),
    );
  }

  Widget _buildControl(BuildContext context, Color color, bool highlighted, MenuColors colors) {
    final m = MenuMetrics.of(context);
    final symbol = m.dims.menuControlGroupSymbol;
    return Container(
      height: 56,
      padding: EdgeInsets.fromLTRB(4, m.dims.menuControlGroupTop, 4, 0),
      decoration: highlighted ? ShapeDecoration(color: colors.highlight, shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(20))) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: symbol, child: Center(child: Icon(widget.icon, size: symbol - 3, color: color))),
          SizedBox(height: m.dims.menuControlGroupSpacing),
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appleFont(size: 12).copyWith(
              fontSize: 12,
              height: 18 / 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
              color: color,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================================================================
// Sections, dividers, control group, edit menu
// =================================================================================================================

/// A group of rows with a separator above it (unless it is first) and an optional small grey title (kit "Section Title").
///
///     IosMenuSection(title: 'Sort By', children: [IosMenuItem(label: 'Name', checked: true, onPressed: …), …])
class IosMenuSection extends StatelessWidget {
  const IosMenuSection({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final m = MenuMetrics.of(context);
    final colors = MenuColors.of(context);
    final size = m.dims.menuSectionTitleSize;
    return Semantics(
      container: true,
      label: title,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(8, m.dims.menuSectionTitleTop, 8, m.dims.menuSectionTitleBottom),
              child: ExcludeSemantics(
                child: Text(
                  title!,
                  style: appleFont(size: size).copyWith(
                    fontSize: size,
                    height: 15 / size,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    color: colors.tertiary,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// A separator between groups of rows (kit "Separator"): 1 pt, 10 above and below. Put it between the top-level
/// entries of a menu (inside an [IosMenuSection], start a new section instead). [IosMenuPanel] never shows two in a
/// row, or one at the ends.
class IosMenuDivider extends StatelessWidget {
  const IosMenuDivider({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink(); // drawn by IosMenuPanel
}

/// The row of 3–4 icon buttons at the top of a menu (kit "Control Group" of "Quick Action"s): the most common actions.
///
///     IosMenuControlGroup(children: [
///       IosMenuItem(label: 'Copy', icon: AppleIcons.docOnDoc, onPressed: copy),
///       IosMenuItem(label: 'Share', icon: AppleIcons.squareAndArrowUp, onPressed: share),
///       IosMenuItem(label: 'Delete', icon: AppleIcons.trash, destructive: true, onPressed: delete),
///     ])
class IosMenuControlGroup extends StatelessWidget {
  const IosMenuControlGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _MenuControlScope(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// The edit menu over a text selection (kit "Edit Menu"): a 44-tall material capsule of text actions + a round "more"
/// button.
/// Text fields show the system one by themselves; use this only for your own selectable content.
///
///     IosEditMenu(actions: {'Cut': cut, 'Copy': copy, 'Paste': paste}, onMore: showMore)
class IosEditMenu extends StatelessWidget {
  const IosEditMenu({super.key, required this.actions, this.onMore});

  /// Label → callback (null = disabled), in order.
  final Map<String, VoidCallback?> actions;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final colors = MenuColors.of(context);
    final entries = actions.entries.toList();
    final style = appleFont(size: 15).copyWith(
      fontSize: 15,
      height: 18 / 15,
      letterSpacing: -0.23,
      decoration: TextDecoration.none,
    );
    return SizedBox(
      height: 44,
      child: AppleGlass(
        style: AppleGlassStyle.panel,
        radius: 22,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) SizedBox(width: 1, height: 18, child: ColoredBox(color: colors.editSeparator)),
                Semantics(
                  button: true,
                  enabled: entries[i].value != null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: entries[i].value,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: Text(entries[i].key,
                              style: style.copyWith(color: entries[i].value == null ? colors.tertiary : colors.label)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (onMore != null)
                Semantics(
                  button: true,
                  label: 'More',
                  child: GestureDetector(
                    onTap: onMore,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: ShapeDecoration(color: colors.highlight, shape: const CircleBorder()),
                      child: Center(child: MenuGlyph(MenuGlyphKind.chevronRight, color: colors.label, size: 18)),
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

// =================================================================================================================
// IosMenu — a menu that opens from ANY trigger
// =================================================================================================================

/// Builds the control that opens a menu or popover; call [open] from its onPressed.
typedef IosMenuTriggerBuilder = Widget Function(BuildContext context, VoidCallback open);

/// An iOS menu that opens from any trigger, 8 below it (above when there is no room), aligned to its leading edge
/// (trailing edge in the right half of the screen). A tap outside or Esc closes it; choosing an item closes it.
///
///     IosMenu(
///       semanticLabel: 'More',
///       trigger: (context, open) => IosButton(icon: AppleIcons.ellipsis, semanticLabel: 'More', onPressed: open),
///       children: [
///         IosMenuItem(label: 'Rename', icon: AppleIcons.pencil, onPressed: rename),
///         IosMenuItem(label: 'Delete', icon: AppleIcons.trash, destructive: true, onPressed: delete),
///       ],
///     )
class IosMenu extends StatefulWidget {
  const IosMenu({
    super.key,
    required this.trigger,
    required this.children,
    this.semanticLabel,
    this.width = 250,
    this.hasSelection,
    this.onOpenChanged,
  });

  final IosMenuTriggerBuilder trigger;

  /// [IosMenuControlGroup] (first), [IosMenuItem], [IosMenuSection], [IosMenuDivider].
  final List<Widget> children;
  final String? semanticLabel;
  final double width;
  final bool? hasSelection;
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<IosMenu> createState() => _IosMenuState();
}

class _IosMenuState extends State<IosMenu> {
  final _portal = OverlayPortalController();
  final _anchorKey = GlobalKey();
  late final _session = _MenuSession(_close);
  Rect _anchor = Rect.zero;

  void _open() {
    final anchor = _anchorKey.currentContext;
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null || _portal.isShowing) return;
    _session
      ..overlay = overlay
      ..reset();
    setState(() => _anchor = menuRectIn(anchor, overlay));
    _portal.show();
    widget.onOpenChanged?.call(true);
  }

  void _close() {
    if (!_portal.isShowing) return;
    _session.reset();
    _portal.hide();
    if (mounted) setState(() {});
    widget.onOpenChanged?.call(false);
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        final m = MenuMetrics.of(context);
        final alignRight = _anchor.center.dx >= MediaQuery.sizeOf(context).width / 2;
        return _menuLayers(
          context,
          _session,
          CustomSingleChildLayout(
            delegate: MenuPlacementDelegate(anchor: _anchor, margin: m.dims.margin),
            child: MenuAppear(
              alignment: alignRight ? Alignment.topRight : Alignment.topLeft,
              child: IosMenuPanel(
                width: widget.width,
                hasSelection: widget.hasSelection,
                semanticLabel: widget.semanticLabel,
                children: widget.children,
              ),
            ),
          ),
        );
      },
      child: KeyedSubtree(key: _anchorKey, child: widget.trigger(context, _open)),
    );
  }
}

// =================================================================================================================
// IosContextMenu
// =================================================================================================================

/// The lifted preview of a context menu (kit "Content Area"): r=30, Backgrounds/Primary - Elevated, shadow 0 0 32
/// black 20%. [IosContextMenu] uses it; use it yourself for a custom preview.
class IosContextMenuPreview extends StatelessWidget {
  const IosContextMenuPreview({super.key, required this.child, this.radius = 30});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppleTheme.of(context).ios.bgPrimaryElevated,
        shape: shape,
        shadows: const [BoxShadow(color: Color(0x33000000), blurRadius: 32)],
      ),
      child: ClipPath(clipper: ShapeBorderClipper(shape: shape), child: child),
    );
  }
}

/// Touch-and-hold (or a secondary click) on [child] lifts a preview of it over a dimmed page (black 23%) and shows a
/// menu next to it: below (aligned to the leading or trailing edge), above when there is no room, beside on iPad.
///
///     IosContextMenu(
///       items: [
///         IosMenuItem(label: 'Copy', icon: AppleIcons.docOnDoc, onPressed: copy),
///         IosMenuItem(label: 'Delete', icon: AppleIcons.trash, destructive: true, onPressed: delete),
///       ],
///       child: PhotoCard(photo),
///     )
class IosContextMenu extends StatefulWidget {
  const IosContextMenu({super.key, required this.child, required this.items, this.preview, this.semanticLabel, this.onOpenChanged});

  /// The content (also lifted as the preview unless [preview] is given).
  final Widget child;

  /// [IosMenuControlGroup], [IosMenuItem], [IosMenuSection], [IosMenuDivider].
  final List<Widget> items;

  /// A different (usually bigger) preview: an image, a link preview.
  final Widget? preview;
  final String? semanticLabel;
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<IosContextMenu> createState() => _IosContextMenuState();
}

class _IosContextMenuState extends State<IosContextMenu> {
  final _portal = OverlayPortalController();
  final _targetKey = GlobalKey();
  late final _session = _MenuSession(_close);
  Rect _target = Rect.zero;
  bool _pressed = false;

  void _open() {
    final target = _targetKey.currentContext;
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (target == null || overlay == null || _portal.isShowing) return;
    HapticFeedback.mediumImpact();
    _session
      ..overlay = overlay
      ..reset();
    setState(() {
      _pressed = false;
      _target = menuRectIn(target, overlay);
    });
    _portal.show();
    widget.onOpenChanged?.call(true);
  }

  void _close() {
    if (!_portal.isShowing) return;
    _session.reset();
    _portal.hide();
    if (mounted) setState(() {});
    widget.onOpenChanged?.call(false);
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        final m = MenuMetrics.of(context);
        return _menuLayers(
          context,
          _session,
          barrier: const Color(0x3B000000),                // kit "Context Menu - Dimming Overlay": black 23%
          CustomMultiChildLayout(
            delegate: _ContextMenuLayout(target: _target, margin: m.dims.margin, regular: m.regular),
            children: [
              LayoutId(
                id: _ContextSlot.preview,
                child: GestureDetector(
                  onTap: _close,
                  child: IosContextMenuPreview(child: IgnorePointer(child: widget.preview ?? widget.child)),
                ),
              ),
              LayoutId(
                id: _ContextSlot.menu,
                child: MenuAppear(
                  from: 0.5,
                  child: IosMenuPanel(semanticLabel: widget.semanticLabel, children: widget.items),
                ),
              ),
            ],
          ),
        );
      },
      child: Semantics(
        onLongPressHint: 'Show menu',
        child: GestureDetector(
          onLongPressDown: (_) => setState(() => _pressed = true),
          onLongPressCancel: () => setState(() => _pressed = false),
          onLongPressStart: (_) => _open(),
          onSecondaryTapUp: (_) => _open(),
          child: AnimatedScale(
            scale: _pressed && !reduceMotion ? 0.97 : 1,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            child: KeyedSubtree(key: _targetKey, child: widget.child),
          ),
        ),
      ),
    );
  }
}

enum _ContextSlot { preview, menu }

/// Preview over the content; menu 16 below it (aligned leading / trailing), above it when there is no room,
/// beside it on iPad, or the preview moved up so the menu fits below (kit "Context Menu" Alignment × Side).
class _ContextMenuLayout extends MultiChildLayoutDelegate {
  _ContextMenuLayout({required this.target, required this.margin, required this.regular});
  final Rect target;
  final double margin;
  final bool regular;

  @override
  void performLayout(Size size) {
    final m = margin;
    final pv = target.size;
    final avail = math.max(120.0, size.height - 2 * m - pv.height - 16);
    layoutChild(_ContextSlot.preview, BoxConstraints.tight(pv));
    final menu = layoutChild(_ContextSlot.menu, BoxConstraints(maxWidth: size.width - 2 * m, maxHeight: avail));
    final trailing = target.center.dx > size.width / 2;
    var previewPos = target.topLeft;
    Offset menuPos;
    if (target.bottom + 16 + menu.height <= size.height - m) {
      menuPos = Offset(trailing ? target.right - menu.width : target.left, target.bottom + 16);
    } else if (target.top - 16 - menu.height >= m) {
      menuPos = Offset(trailing ? target.right - menu.width : target.left, target.top - 16 - menu.height);
    } else if (regular && (target.right + 16 + menu.width <= size.width - m || target.left - 16 - menu.width >= m)) {
      final onLeading = target.right + 16 + menu.width > size.width - m;
      final top = math.min(target.top, size.height - m - math.max(pv.height, menu.height));
      previewPos = Offset(target.left, top);
      menuPos = Offset(onLeading ? target.left - 16 - menu.width : target.right + 16, top);
    } else {
      final top = math.max(m, size.height - m - pv.height - 16 - menu.height);
      previewPos = Offset(target.left, top);
      menuPos = Offset(trailing ? target.right - menu.width : target.left, top + pv.height + 16);
    }
    final minX = math.min(m, target.left);
    final maxX = size.width - math.min(m, size.width - target.right);
    double clampX(double x, double w) => x.clamp(minX, math.max(minX, maxX - w));
    positionChild(_ContextSlot.preview, Offset(clampX(previewPos.dx, pv.width), previewPos.dy));
    positionChild(_ContextSlot.menu, Offset(clampX(menuPos.dx, menu.width), menuPos.dy));
  }

  @override
  bool shouldRelayout(_ContextMenuLayout old) => old.target != target || old.margin != margin || old.regular != regular;
}

// =================================================================================================================
// IosPopUpButton / IosPullDownButton
// =================================================================================================================

class _PopUpFace extends StatefulWidget {
  const _PopUpFace({required this.label, required this.glyph, required this.onTap, this.icon, this.semanticLabel});
  final String label;
  final MenuGlyphKind glyph;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? semanticLabel;

  @override
  State<_PopUpFace> createState() => _PopUpFaceState();
}

class _PopUpFaceState extends State<_PopUpFace> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final enabled = widget.onTap != null;
    final color = enabled ? theme.accentColor : theme.ios.labelTertiary;
    // Kit "Popup Button": 44 tall (13 above and below an 18 line), Semibold 18, 3 to a 14 × 18 chevron.
    final face = Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[Icon(widget.icon, size: 20, color: color), const SizedBox(width: 2)],
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appleFont(size: 18).copyWith(
              fontSize: 18,
              height: 1,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.45,
              color: color,
              decoration: TextDecoration.none,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
          const SizedBox(width: 3),
          MenuGlyph(widget.glyph, color: color, size: widget.glyph == MenuGlyphKind.chevronDown ? 15 : 17, width: 14, height: 18),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel == null ? widget.label : '${widget.semanticLabel}, ${widget.label}',
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onTap,
          child: Opacity(opacity: _pressed ? 0.35 : 1, child: face),
        ),
      ),
    );
  }
}

/// A pop-up button (kit "Popup Button"): shows the CURRENT choice + chevron.up.chevron.down; a tap opens a menu of
/// mutually exclusive choices with a checkmark on the current one.
///
///     IosPopUpButton<String>(
///       semanticLabel: 'Sort By',
///       value: sort,
///       options: const {'name': 'Name', 'date': 'Date', 'size': 'Size'},
///       onChanged: (v) => setState(() => sort = v),
///     )
/// [onChanged] null = disabled.
class IosPopUpButton<T> extends StatelessWidget {
  const IosPopUpButton({super.key, required this.value, required this.options, required this.onChanged, this.semanticLabel});

  final T value;

  /// value → label, in menu order.
  final Map<T, String> options;
  final ValueChanged<T>? onChanged;

  /// What is being chosen ("Sort By"): the menu's name, read before the current choice.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return IosMenu(
      semanticLabel: semanticLabel,
      hasSelection: true,
      trigger: (context, open) => _PopUpFace(
        label: options[value] ?? '',
        glyph: MenuGlyphKind.chevronUpDown,
        semanticLabel: semanticLabel,
        onTap: onChanged == null ? null : open,
      ),
      children: [
        for (final e in options.entries)
          IosMenuItem(label: e.value, checked: e.key == value, onPressed: onChanged == null ? null : () => onChanged!(e.key)),
      ],
    );
  }
}

/// A pull-down button: a FIXED label (+ chevron.down) that opens a menu of actions related to it.
///
///     IosPullDownButton(label: 'Add', icon: AppleIcons.plus, items: [
///       IosMenuItem(label: 'New Document', icon: AppleIcons.doc, onPressed: newDocument),
///       IosMenuItem(label: 'New Folder', icon: AppleIcons.folder, onPressed: newFolder),
///     ])
class IosPullDownButton extends StatelessWidget {
  const IosPullDownButton({super.key, required this.label, required this.items, this.icon, this.enabled = true});

  final String label;
  final IconData? icon;

  /// [IosMenuItem], [IosMenuSection], [IosMenuDivider].
  final List<Widget> items;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IosMenu(
      semanticLabel: label,
      trigger: (context, open) => _PopUpFace(label: label, icon: icon, glyph: MenuGlyphKind.chevronDown, onTap: enabled ? open : null),
      children: items,
    );
  }
}
