import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerScrollEvent, kPrimaryButton, kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_panel_support.dart';

// =====================================================================================================
// Look (menus.css): colours, material, metrics
// =====================================================================================================

@immutable
class _MenuColors {
  const _MenuColors({
    required this.label,
    required this.header,
    required this.tertiary,
    required this.separator,
    required this.pill,
    required this.highlight,
    required this.onHighlight,
  });

  /// Light | Dark. Vibrant labels are drawn "plus darker" / "plus lighter" on the material in the kit;
  /// these are the resulting colours, the same as menus.css.
  factory _MenuColors.of(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final dark = theme.isDark;
    return _MenuColors(
      label: c.labelVibrantPrimary, // #1A1A1A · #F5F5F5
      header: dark ? const Color(0xB3FFFFFF) : const Color(0x8C000000), // black 55 % · white 70 %
      tertiary: dark ? const Color(0x54FFFFFF) : const Color(0x40000000), // black 25 % · white 33 %
      separator: c.separator, // black 10 % · white 10 %
      pill: c.fillPrimary, // submenu-open pill
      highlight: menuHighlightColor(theme.accentColor), // accent, 0.07 darker in OKLCH (#0069F9-ish)
      onHighlight: c.labelWhite,
    );
  }

  final Color label;
  final Color header;
  final Color tertiary;
  final Color separator;
  final Color pill;
  final Color highlight;
  final Color onHighlight;
}

final PanelShapeBuilder _menuShape = roundedPanelShape(12);

/// The menu panel (kit "Menu Background"): radius 12, padding 5 top/bottom, on the classic Ultra Thick blur material
/// with a 0.5 px hairline and the kit's drop shadow (0 8 48, black 25 % · 45 %). No inner rims.
Widget _menuPanel(BuildContext context, Widget child) {
  final dark = AppleTheme.of(context).isDark;
  final m = panelMaterial(dark, drop: [panelDropShadow(dark)]);
  return PanelSurface(shape: _menuShape, fill: m.fill, backdrop: m.backdrop, shadows: m.shadows, child: child);
}

/// Menu text line height per size (kit text boxes: 16 · 13 · 12).
double _menuLineHeight(MacSizes s) => s.menuFontSize >= 13 ? 16 : (s.menuFontSize >= 11 ? 13 : 12);

TextStyle _menuText(MacSizes s, Color color, {FontWeight weight = FontWeight.w500}) =>
    panelText(appleFont(size: s.menuFontSize), size: s.menuFontSize, lineHeight: _menuLineHeight(s), weight: weight, color: color);

/// Checkmark column: 16 px at the medium size in the kit render (labels start 24 px further right); menus.css uses
/// Menu/Width - Symbol (12), which puts labels 4 px too far left.
double _checkColumnWidth(MacSizes s) => s.menuWidthSymbol + 4;

// Horizontal geometry: the panel has 12 px side padding; the highlight reaches 7 px past the text column, so items
// are laid out 5 px from the panel edge with 7 px inner padding.
const double _kPanelInset = 5;
const double _kItemPad = 7;

// =====================================================================================================
// Per-item context (which menu level, which index, highlight state, columns)
// =====================================================================================================

@immutable
class _ItemContext {
  const _ItemContext({
    this.session,
    this.level = 0,
    this.index = -1,
    this.highlighted = false,
    this.submenuOpen = false,
    required this.checkColumn,
    required this.iconColumn,
  });
  final _MenuSession? session;
  final int level;
  final int index;
  final bool highlighted;
  final bool submenuOpen;
  final bool checkColumn;
  final bool iconColumn;

  @override
  bool operator ==(Object other) =>
      other is _ItemContext &&
      other.session == session &&
      other.level == level &&
      other.index == index &&
      other.highlighted == highlighted &&
      other.submenuOpen == submenuOpen &&
      other.checkColumn == checkColumn &&
      other.iconColumn == iconColumn;

  @override
  int get hashCode => Object.hash(session, level, index, highlighted, submenuOpen, checkColumn, iconColumn);
}

class _MenuItemScope extends InheritedWidget {
  const _MenuItemScope({required this.data, required super.child});
  final _ItemContext data;
  static _ItemContext? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_MenuItemScope>()?.data;
  @override
  bool updateShouldNotify(_MenuItemScope old) => old.data != data;
}

// =====================================================================================================
// Session: one open menu with its open submenus; keyboard and pointer behaviour (menus.js)
// =====================================================================================================

class _Level {
  _Level(this.items);
  final List<Widget> items;
  int highlight = -1;
  int openSub = -1;
}

class _MenuSession extends ChangeNotifier {
  _MenuSession(List<Widget> items, {required this.onClose, bool highlightFirst = false}) {
    levels.add(_Level(items));
    if (highlightFirst) levels[0].highlight = _firstEnabled(0);
  }

  static const _hoverOpen = Duration(milliseconds: 120); // menus.js HOVER_OPEN_MS
  static const _hoverClose = Duration(milliseconds: 250); // menus.js HOVER_CLOSE_MS

  final List<_Level> levels = [];
  final FocusNode focusNode = FocusNode(debugLabel: 'MacMenu');
  final VoidCallback onClose;
  int active = 0;
  bool closed = false;
  Timer? _openTimer;
  Timer? _closeTimer;
  Timer? _typeTimer;
  String _typed = '';

  MacMenuItem? itemAt(int level, int index) {
    if (level >= levels.length) return null;
    final items = levels[level].items;
    if (index < 0 || index >= items.length) return null;
    final w = items[index];
    return w is MacMenuItem ? w : null;
  }

  bool _enabledAt(int level, int index) => itemAt(level, index)?._isEnabled ?? false;

  List<int> _enabledIndices(int level) => [
        for (var i = 0; i < levels[level].items.length; i++)
          if (_enabledAt(level, i)) i,
      ];

  int _firstEnabled(int level) {
    final e = _enabledIndices(level);
    return e.isEmpty ? -1 : e.first;
  }

  void _changed() {
    if (!closed) notifyListeners();
  }

  void _cancelTimers() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
  }

  void _closeLevelsAbove(int level) {
    if (level + 1 < levels.length) levels.removeRange(level + 1, levels.length);
    levels[level].openSub = -1;
    if (active > level) active = level;
  }

  // --- pointer ---
  void pointerOver(int level, int index) {
    if (closed || level >= levels.length) return;
    final lvl = levels[level];
    if (!_enabledAt(level, index)) {
      if (lvl.highlight != -1) {
        lvl.highlight = -1;
        _changed();
      }
      return;
    }
    _openTimer?.cancel();
    if (lvl.highlight == index && active == level) return;
    active = level;
    lvl.highlight = index;
    for (var l = 0; l < level; l++) {
      levels[l].highlight = -1; // the parents show the grey "submenu open" pill
    }
    if (lvl.openSub >= 0 && lvl.openSub != index) {
      _closeTimer?.cancel();
      _closeTimer = Timer(_hoverClose, () {
        if (closed || level >= levels.length || levels[level].openSub == levels[level].highlight) return;
        _closeLevelsAbove(level);
        _changed();
      });
    } else if (lvl.openSub == index) {
      _closeTimer?.cancel();
    }
    final item = itemAt(level, index);
    if (item?.submenu != null && lvl.openSub != index) {
      _openTimer = Timer(_hoverOpen, () {
        if (closed || level >= levels.length || levels[level].highlight != index) return;
        openSubmenu(level, index, keyboard: false);
      });
    }
    _changed();
  }

  void pointerLeft(int level) {
    if (closed || level >= levels.length) return;
    _openTimer?.cancel();
    if (levels[level].highlight != -1) {
      levels[level].highlight = -1;
      _changed();
    }
  }

  // --- keyboard ---
  void move(int delta) {
    final lvl = levels[active];
    final enabled = _enabledIndices(active);
    if (enabled.isEmpty) return;
    final i = enabled.indexOf(lvl.highlight);
    int next;
    if (i < 0) {
      next = delta > 0 ? enabled.first : enabled.last;
    } else {
      next = enabled[(i + delta).clamp(0, enabled.length - 1)];
    }
    _setKeyboardHighlight(next);
  }

  void jump(bool end) {
    final enabled = _enabledIndices(active);
    if (enabled.isNotEmpty) _setKeyboardHighlight(end ? enabled.last : enabled.first);
  }

  void _setKeyboardHighlight(int index) {
    _cancelTimers();
    final lvl = levels[active];
    if (lvl.openSub >= 0 && lvl.openSub != index) _closeLevelsAbove(active);
    lvl.highlight = index;
    _changed();
  }

  void activate() {
    final i = levels[active].highlight;
    if (i >= 0) choose(active, i, keyboard: true);
  }

  void openSubmenu(int level, int index, {required bool keyboard}) {
    final item = itemAt(level, index);
    final sub = item?.submenu;
    if (closed || sub == null || !item!._isEnabled) return;
    _cancelTimers();
    if (level + 1 < levels.length) levels.removeRange(level + 1, levels.length);
    levels[level].openSub = index;
    final next = _Level(sub);
    levels.add(next);
    if (keyboard) {
      next.highlight = _firstEnabled(level + 1);
      levels[level].highlight = -1;
      active = level + 1;
    }
    _changed();
  }

  void left(VoidCallback ifRoot) {
    if (active > 0) {
      final parent = active - 1;
      final idx = levels[parent].openSub;
      _closeLevelsAbove(parent);
      active = parent;
      levels[parent].highlight = idx;
      _changed();
    } else {
      ifRoot();
    }
  }

  bool right() {
    final idx = levels[active].highlight;
    if (idx >= 0 && itemAt(active, idx)?.submenu != null) {
      openSubmenu(active, idx, keyboard: true);
      return true;
    }
    return false;
  }

  void typeAhead(String character) {
    _typeTimer?.cancel();
    _typed += character.toLowerCase();
    _typeTimer = Timer(const Duration(milliseconds: 750), () => _typed = '');
    for (final i in _enabledIndices(active)) {
      if (itemAt(active, i)!.label.toLowerCase().startsWith(_typed)) {
        _setKeyboardHighlight(i);
        return;
      }
    }
  }

  // --- choosing and closing ---
  void choose(int level, int index, {bool keyboard = false}) {
    final item = itemAt(level, index);
    if (closed || item == null || !item._isEnabled) return;
    if (item.submenu != null) {
      openSubmenu(level, index, keyboard: keyboard);
      return;
    }
    close();
    item.onSelected?.call();
  }

  void close() {
    if (closed) return;
    _cancelTimers();
    _typeTimer?.cancel();
    onClose();
    closed = true;
  }

  KeyEventResult handleKey(KeyEvent event) {
    if (closed || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      move(-1);
    } else if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.pageUp) {
      jump(false);
    } else if (key == LogicalKeyboardKey.end || key == LogicalKeyboardKey.pageDown) {
      jump(true);
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) activate();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (!right()) return KeyEventResult.ignored; // a menu bar switches to the next menu
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      var handled = true;
      left(() => handled = false);
      if (!handled) return KeyEventResult.ignored; // a menu bar switches to the previous menu
    } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.tab) {
      close();
    } else {
      final ch = event.character;
      final hw = HardwareKeyboard.instance;
      if (ch != null && ch.trim().isNotEmpty && !hw.isMetaPressed && !hw.isControlPressed && !hw.isAltPressed) {
        typeAhead(ch);
      } else {
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _cancelTimers();
    _typeTimer?.cancel();
    focusNode.dispose();
    super.dispose();
  }
}

// =====================================================================================================
// The panel (static or live)
// =====================================================================================================

class _MenuPanelView extends StatelessWidget {
  const _MenuPanelView({
    required this.items,
    this.session,
    this.level = 0,
    this.width,
    this.iconColumn = false,
    this.checkmarkColumn,
    this.semanticLabel,
  });

  final List<Widget> items;
  final _MenuSession? session;
  final int level;
  final double? width;
  final bool iconColumn;
  final bool? checkmarkColumn;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final s = session;
    if (s == null) return _build(context);
    return ListenableBuilder(listenable: s, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final s = session;
    final live = s != null && level < s.levels.length;
    final lvl = live ? s.levels[level] : null;
    final checks = checkmarkColumn ?? items.any((w) => w is MacMenuItem && (w.checked != null || w.mixed));
    final children = <Widget>[
      for (var i = 0; i < items.length; i++)
        _MenuItemScope(
          data: _ItemContext(
            session: live ? s : null,
            level: level,
            index: i,
            highlighted: lvl != null && lvl.highlight == i,
            submenuOpen: lvl != null && lvl.openSub == i,
            checkColumn: checks,
            iconColumn: iconColumn,
          ),
          child: items[i],
        ),
    ];
    Widget list = IntrinsicWidth(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
    if (live) list = SingleChildScrollView(child: list);
    Widget body = Padding(padding: const EdgeInsets.symmetric(vertical: 5, horizontal: _kPanelInset), child: list);
    if (live) {
      final session = s;
      body = MouseRegion(onExit: (_) => session.pointerLeft(level), child: body);
    }
    Widget panel = _menuPanel(context, body);
    if (width != null) panel = SizedBox(width: width, child: panel);
    return Semantics(container: true, explicitChildNodes: true, label: semanticLabel, child: panel);
  }
}

/// A menu panel that is always visible, drawn in place: for mockups, documentation and screenshots
/// (CSS `mac-menu mac-menu--static`). Live menus come from [MacMenu] and [MacContextMenu].
///
///     MacMenuPanel(width: 220, items: [
///       MacMenuItem(label: 'Cut', shortcut: '⌘X', onSelected: () {}),
///       MacMenuItem(label: 'Copy', shortcut: '⌘C', highlighted: true, onSelected: () {}),
///       const MacMenuDivider(),
///       MacMenuItem(label: 'Cities', submenu: const [], hovered: true),
///     ])
class MacMenuPanel extends StatelessWidget {
  const MacMenuPanel({
    super.key,
    required this.items,
    this.width,
    this.iconColumn = false,
    this.checkmarkColumn,
    this.semanticLabel,
  });

  /// [MacMenuItem]s, [MacMenuDivider]s and [MacMenuHeader]s.
  final List<Widget> items;

  /// Fixed width. Null = as wide as the longest item.
  final double? width;

  /// Keep an empty icon column on items without an icon, so all labels line up (CSS `mac-menu--icons`).
  final bool iconColumn;

  /// Force (true) or hide (false) the checkmark column. Null = automatic: shown when any item has `checked`.
  final bool? checkmarkColumn;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => _MenuPanelView(
        items: items,
        width: width,
        iconColumn: iconColumn,
        checkmarkColumn: checkmarkColumn,
        semanticLabel: semanticLabel,
      );
}

// =====================================================================================================
// Items, separator, header
// =====================================================================================================

/// One command in a macOS menu (kit "Menu Items"): optional checkmark, icon, label, keyboard shortcut or submenu.
///
///     MacMenuItem(label: 'Copy', icon: AppleIcons.docOnDoc, shortcut: '⌘C', onSelected: copy)
///     MacMenuItem(label: 'Show Sidebar', checked: showSidebar, onSelected: () => setState(() => showSidebar = !showSidebar))
///     MacMenuItem(label: 'Paste Style', shortcut: '⌥⌘V', onSelected: null)        // disabled (dimmed)
///     MacMenuItem(label: 'Move To', submenu: [MacMenuItem(label: 'Desktop', onSelected: () {})])
///
/// [onSelected] runs after the menu closes. Null (and no [submenu]) = disabled: dimmed, never highlighted.
/// [shortcut] is only the text on the right, written ⌃ ⌥ ⇧ ⌘ then the key ("⇧⌘S"): register the real key with
/// Flutter's `Shortcuts`/`CallbackShortcuts` (or `PlatformMenuBar` on macOS) yourself.
class MacMenuItem extends StatefulWidget {
  const MacMenuItem({
    super.key,
    required this.label,
    this.onSelected,
    this.icon,
    this.shortcut,
    this.checked,
    this.mixed = false,
    this.submenu,
    this.enabled = true,
    this.highlighted = false,
    this.hovered = false,
    this.semanticLabel,
  });

  /// Title case, "…" when it opens a dialog that asks for more ("Export…").
  final String label;
  final VoidCallback? onSelected;

  /// Optional leading icon (`AppleIcons.*`), only for well-known commands.
  final IconData? icon;

  /// Shortcut text: modifiers in the order ⌃ ⌥ ⇧ ⌘, then the key: '⌘C', '⇧⌘N', '⌥⌘I'.
  final String? shortcut;

  /// Null = a plain command. true/false = an on/off item: the whole menu gets a checkmark column, ✓ when true.
  final bool? checked;

  /// A dash instead of the checkmark (an option that is on for some of the selection).
  final bool mixed;

  /// Items of a submenu (› arrow). One level deep, never a single item.
  final List<Widget>? submenu;

  /// False = dimmed even when it has a [submenu].
  final bool enabled;

  /// Static mockups only (CSS `is-highlighted`): draw the accent highlight. Live menus highlight by themselves.
  final bool highlighted;

  /// Static mockups only (kit State "Hover", CSS `is-hovered`): the grey "submenu open" pill.
  final bool hovered;

  final String? semanticLabel;

  bool get _isEnabled => enabled && (onSelected != null || submenu != null);

  @override
  State<MacMenuItem> createState() => _MacMenuItemState();
}

class _MacMenuItemState extends State<MacMenuItem> {
  final OverlayPortalController _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    // The submenu portal is always "shown"; it draws nothing while the submenu is closed.
    if (widget.submenu != null) _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _MenuItemScope.maybeOf(context);
    final session = scope?.session;
    final sizes = MacControlSizeScope.sizesOf(context);
    final colors = _MenuColors.of(context);
    final enabled = widget._isEnabled;
    final checkColumn = scope?.checkColumn ?? (widget.checked != null || widget.mixed);
    final iconColumn = scope?.iconColumn ?? false;
    final highlighted = enabled && (session != null ? scope!.highlighted : widget.highlighted);
    final pill = !highlighted && (session != null ? scope!.submenuOpen : widget.hovered);
    final fg = !enabled ? colors.tertiary : (highlighted ? colors.onHighlight : colors.label);
    final shortcutColor = highlighted ? colors.onHighlight : colors.tertiary;
    final lh = _menuLineHeight(sizes);
    final symbol = sizes.menuWidthSymbol;

    final row = <Widget>[];
    if (checkColumn) {
      row.add(SizedBox(
        width: _checkColumnWidth(sizes),
        height: lh,
        child: (widget.checked == true || widget.mixed)
            ? CustomPaint(painter: _CheckPainter(fg, (sizes.menuFontSizeSymbol + 3) / 16, mixed: widget.mixed))
            : null,
      ));
      row.add(const SizedBox(width: 8));
    }
    if (widget.icon != null) {
      final glyph = sizes.menuFontSizeSymbol + 1;
      row.add(SizedBox(
        width: symbol,
        height: lh,
        child: OverflowBox(
          minWidth: 0,
          minHeight: 0,
          maxWidth: glyph,
          maxHeight: glyph,
          child: Icon(widget.icon, size: glyph, color: fg),
        ),
      ));
      row.add(const SizedBox(width: 8));
    } else if (iconColumn) {
      row.add(SizedBox(width: symbol + 8));
    }
    row.add(Expanded(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(widget.label, style: _menuText(sizes, fg), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
      ),
    ));
    if (widget.shortcut != null && widget.submenu == null) {
      row.add(const SizedBox(width: 8 + 16));
      row.add(_Shortcut(widget.shortcut!, _menuText(sizes, shortcutColor)));
    }
    if (widget.submenu != null) {
      row.add(const SizedBox(width: 8));
      row.add(SizedBox(width: 12, height: lh, child: CustomPaint(painter: _ChevronPainter(fg, sizes.menuFontSize / 13))));
    }

    Widget content = Container(
      height: sizes.menuHeight,
      padding: const EdgeInsets.symmetric(horizontal: _kItemPad),
      decoration: (highlighted || pill)
          ? ShapeDecoration(
              color: highlighted ? colors.highlight : colors.pill,
              shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(8)),
            )
          : null,
      child: Row(children: row),
    );

    if (session != null) {
      final level = scope!.level;
      final index = scope.index;
      content = MouseRegion(
        cursor: SystemMouseCursors.basic,
        onEnter: (_) => session.pointerOver(level, index),
        onHover: (_) => session.pointerOver(level, index),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => session.choose(level, index) : null,
          child: content,
        ),
      );
      if (widget.submenu != null) {
        final open = scope.submenuOpen && level + 1 < session.levels.length;
        content = OverlayPortal.overlayChildLayoutBuilder(
          controller: _portal,
          overlayLocation: OverlayChildLocation.rootOverlay,
          overlayChildBuilder: (context, info) {
            if (!open) return const SizedBox.shrink();
            final rect = MatrixUtils.transformRect(info.childPaintTransform, Offset.zero & info.childSize);
            return CustomSingleChildLayout(
              delegate: _SubmenuLayout(rect),
              child: _MenuPanelView(items: widget.submenu!, session: session, level: level + 1, semanticLabel: widget.label),
            );
          },
          child: content,
        );
      }
    }

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      checked: widget.checked,
      mixed: widget.mixed ? true : null,
      selected: highlighted,
      label: widget.semanticLabel ?? widget.label,
      hint: widget.shortcut,
      excludeSemantics: true,
      onTap: enabled && session != null ? () => session.choose(scope!.level, scope.index) : null,
      child: content,
    );
  }
}

/// Keyboard shortcut (kit "_Shortcuts"): every modifier symbol in its own 12 px cell, 1 px apart, then the key.
class _Shortcut extends StatelessWidget {
  const _Shortcut(this.text, this.style);
  final String text;
  final TextStyle style;

  static const _modifiers = '⌃⌥⇧⌘';

  @override
  Widget build(BuildContext context) {
    final cells = <String>[];
    var rest = text;
    while (rest.isNotEmpty && _modifiers.contains(rest.characters.first)) {
      cells.add(rest.characters.first);
      rest = rest.characters.skip(1).toString();
    }
    if (rest.isNotEmpty) cells.add(rest);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 12),
            child: Text(cells[i], style: style, textAlign: TextAlign.center, maxLines: 1, softWrap: false),
          ),
        ],
      ],
    );
  }
}

/// Checkmark of the checkmark column (bold, round ends; ~9.3 × 8.9 px at the medium size) or the mixed dash.
class _CheckPainter extends CustomPainter {
  _CheckPainter(this.color, this.scale, {this.mixed = false});
  final Color color;
  final double scale;
  final bool mixed;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = 9.31 * scale, h = 8.93 * scale;
    final o = Offset(size.width - w, (size.height - h) / 2); // kit: the glyph ends at the column's right edge
    if (mixed) {
      canvas.drawLine(o + Offset(1 * scale, h / 2), o + Offset(w - 1 * scale, h / 2), paint);
      return;
    }
    final p = Path()
      ..moveTo(o.dx + 0.9 * scale, o.dy + 4.75 * scale)
      ..lineTo(o.dx + 3.65 * scale, o.dy + 8.05 * scale)
      ..lineTo(o.dx + 8.4 * scale, o.dy + 0.9 * scale);
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color || old.scale != scale || old.mixed != mixed;
}

/// Submenu arrow: a bold chevron › (kit "Chevron"), ~5.6 × 8.8 px at 13 px text.
class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color, this.scale);
  final Color color;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    final w = 5.6 * scale, h = 8.8 * scale, sw = 1.9 * scale;
    final o = Offset(size.width - 2.5 * scale - w, (size.height - h) / 2); // kit: 2.5 px from the column's right edge
    final p = Path()
      ..moveTo(o.dx + sw / 2, o.dy + sw / 2)
      ..lineTo(o.dx + w - sw / 2, o.dy + h / 2)
      ..lineTo(o.dx + sw / 2, o.dy + h - sw / 2);
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color || old.scale != scale;
}

/// A line between groups of menu items (kit "Separators": 11 px tall, 1 px line in the middle).
///
///     const MacMenuDivider()
class MacMenuDivider extends StatelessWidget {
  const MacMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = _MenuColors.of(context);
    return Semantics(
      container: true,
      child: Padding(
        // 1 px wider than the text column on each side (text column = 7 px inside the item box).
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: _kItemPad - 1),
        child: SizedBox(height: 1, child: ColoredBox(color: colors.separator)),
      ),
    );
  }
}

/// A bold, secondary-colour title above a group of menu items (kit "Headers"). Not clickable.
///
///     const MacMenuHeader('Sort By')
///
/// [inset] null = automatic: lines up with the labels when the menu has a checkmark or icon column (kit "Inset").
class MacMenuHeader extends StatelessWidget {
  const MacMenuHeader(this.text, {super.key, this.inset});

  final String text;
  final bool? inset;

  @override
  Widget build(BuildContext context) {
    final scope = _MenuItemScope.maybeOf(context);
    final sizes = MacControlSizeScope.sizesOf(context);
    final colors = _MenuColors.of(context);
    // Automatic inset: line up with the labels (checkmark column + 8, icon column + 8).
    final auto = ((scope?.checkColumn ?? false) ? _checkColumnWidth(sizes) + 8 : 0.0) +
        ((scope?.iconColumn ?? false) ? sizes.menuInsetLeftHeader : 0.0);
    final left = switch (inset) {
      true => auto > 0 ? auto : sizes.menuInsetLeftHeader,
      false => 0.0,
      null => auto,
    };
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(_kItemPad + left, sizes.menuInsetTopHeader, _kItemPad, sizes.menuInsetBottomHeader),
        child: Text(text, style: _menuText(sizes, colors.header, weight: FontWeight.w700), maxLines: 1, softWrap: false),
      ),
    );
  }
}

// =====================================================================================================
// Placement (menus.js placeMenu)
// =====================================================================================================

const double _kEdge = 8; // keep menus this far from the window edges
const double _kGap = 6; // button → menu

class _RootMenuLayout extends SingleChildLayoutDelegate {
  _RootMenuLayout({required this.anchor, this.point, required this.minWidth});
  final Rect anchor;
  final Offset? point;
  final double minWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxW = math.max(0.0, constraints.maxWidth - 2 * _kEdge);
    return BoxConstraints(
      minWidth: math.min(minWidth, maxW),
      maxWidth: maxW,
      maxHeight: math.max(0.0, constraints.maxHeight - 2 * _kEdge),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final w = child.width, h = child.height;
    double x, y;
    final p = point;
    if (p != null) {
      // Context menu: top-left corner at the pointer; to the left / upwards when there is no room.
      x = p.dx;
      y = p.dy;
      if (x + w > size.width - _kEdge) x -= w;
      if (y + h > size.height - _kEdge) y = math.max(_kEdge, y - h);
    } else {
      // Under the button, left edges aligned; above it when there is more room there.
      final below = size.height - _kEdge - (anchor.bottom + _kGap);
      final above = anchor.top - _kGap - _kEdge;
      x = anchor.left;
      y = (h <= below || below >= above) ? anchor.bottom + _kGap : anchor.top - _kGap - h;
    }
    if (y + h > size.height - _kEdge) y = size.height - _kEdge - h;
    x = x.clamp(_kEdge, math.max(_kEdge, size.width - _kEdge - w));
    y = math.max(_kEdge, y);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_RootMenuLayout old) => old.anchor != anchor || old.point != point || old.minWidth != minWidth;
}

/// Submenu: starts 5 px inside the parent menu's right edge, its first item level with the parent item.
class _SubmenuLayout extends SingleChildLayoutDelegate {
  _SubmenuLayout(this.item);
  final Rect item; // the parent item (5 px inside the parent panel)

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
        maxWidth: math.max(0.0, constraints.maxWidth - 2 * _kEdge),
        maxHeight: math.max(0.0, constraints.maxHeight - 2 * _kEdge),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = item.right; // parent right edge − 5
    if (x + child.width > size.width - _kEdge) x = item.left - child.width; // parent left edge + 5 − width
    var y = item.top - 5; // the submenu's 5 px top padding
    if (y + child.height > size.height - _kEdge) y = size.height - _kEdge - child.height;
    return Offset(x.clamp(_kEdge, math.max(_kEdge, size.width - _kEdge - child.width)), math.max(_kEdge, y));
  }

  @override
  bool shouldRelayout(_SubmenuLayout old) => old.item != item;
}

// =====================================================================================================
// The live menu: anchor (button or right-click) + overlay
// =====================================================================================================

/// Opens and closes a [MacMenu] from code, for example from a button's `onPressed` (keyboard Return/Space).
///
///     final _actions = MacMenuController();
///     MacMenu(controller: _actions, trigger: MacButton(label: 'Actions', onPressed: () => _actions.open()), items: […])
class MacMenuController {
  _MenuAnchorState? _anchor;

  /// Whether the menu is open.
  bool get isOpen => _anchor?._session != null;

  /// Opens the menu. [highlightFirst] highlights the first item (use it when opened with the keyboard).
  void open({bool highlightFirst = false}) => _anchor?._open(highlightFirst: highlightFirst);

  void close() => _anchor?._close();

  void toggle({bool highlightFirst = false}) => isOpen ? close() : open(highlightFirst: highlightFirst);
}

class _TriggerScope extends InheritedWidget {
  const _TriggerScope({required this.controller, required this.open, required super.child});
  final MacMenuController controller;
  final bool open;
  @override
  bool updateShouldNotify(_TriggerScope old) => old.open != open || old.controller != controller;
}

/// A button that opens a menu of commands (pull-down menu): the menu appears 6 px under [trigger], left edges
/// aligned, at least as wide as the trigger, and flips above when there is no room (kit "Menu").
///
///     MacMenu(
///       trigger: MacButton(label: 'Actions', onPressed: () {}),
///       items: [
///         MacMenuItem(label: 'Duplicate', shortcut: '⌘D', onSelected: duplicate),
///         MacMenuItem(label: 'Rename…', onSelected: rename),
///         const MacMenuDivider(),
///         const MacMenuHeader('Share'),
///         MacMenuItem(label: 'Copy Link', icon: AppleIcons.link, onSelected: copyLink),
///         MacMenuItem(label: 'Move To', submenu: [
///           MacMenuItem(label: 'Desktop', onSelected: () {}),
///           MacMenuItem(label: 'Documents', onSelected: () {}),
///         ]),
///       ],
///     )
///
/// It opens when the mouse button goes down on [trigger] (like macOS), and with ↓ / Return / Space when the
/// trigger has keyboard focus and doesn't use those keys itself; a trigger that does (a button) calls
/// `MacMenu.maybeOf(context)?.open(highlightFirst: true)` or a [controller]. In the menu: ↑ ↓ Home End move,
/// Return/Space choose, → ← open/close submenus, Escape and Tab close, typing jumps to an item.
/// Clicking outside closes it. The highlight is the only hover effect.
class MacMenu extends StatelessWidget {
  const MacMenu({
    super.key,
    required this.trigger,
    required this.items,
    this.controller,
    this.enabled = true,
    this.iconColumn = false,
    this.checkmarkColumn,
    this.matchTriggerWidth = true,
    this.onOpenChanged,
    this.semanticLabel,
  });

  /// The widget the menu opens from (usually a pull-down button or a toolbar button).
  final Widget trigger;

  /// [MacMenuItem]s, [MacMenuDivider]s and [MacMenuHeader]s.
  final List<Widget> items;
  final MacMenuController? controller;

  /// False = the trigger doesn't open the menu.
  final bool enabled;

  /// Keep an icon column on items without an icon so labels line up (CSS `mac-menu--icons`).
  final bool iconColumn;

  /// Null = automatic checkmark column (any item with `checked`).
  final bool? checkmarkColumn;

  /// The menu is at least as wide as the trigger (macos.js does this for button menus).
  final bool matchTriggerWidth;
  final ValueChanged<bool>? onOpenChanged;

  /// Accessible name of the menu (defaults to nothing; the trigger names it).
  final String? semanticLabel;

  /// The controller of the nearest [MacMenu] above [context] (for a trigger that opens its menu itself).
  static MacMenuController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TriggerScope>()?.controller;

  /// Whether the nearest [MacMenu] above [context] is open (a trigger can draw its pressed look).
  static bool isOpenOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_TriggerScope>()?.open ?? false;

  @override
  Widget build(BuildContext context) => _MenuAnchor(
        items: items,
        controller: controller,
        enabled: enabled,
        iconColumn: iconColumn,
        checkmarkColumn: checkmarkColumn,
        matchTriggerWidth: matchTriggerWidth,
        onOpenChanged: onOpenChanged,
        semanticLabel: semanticLabel,
        context: false,
        child: trigger,
      );
}

/// A right-click (Control-click) menu for [child], opened at the pointer (kit "Menu"; CSS `mac-context-menu`).
/// Shift-F10 or the Menu key opens it under the focused child. Leave out items that don't apply, and don't show
/// shortcuts in context menus. Every command in it must also be in the menu bar, a toolbar or a shortcut.
///
///     MacContextMenu(
///       items: [
///         MacMenuItem(label: 'Open', onSelected: open),
///         MacMenuItem(label: 'Get Info', onSelected: getInfo),
///         const MacMenuDivider(),
///         MacMenuItem(label: 'Move to Trash', onSelected: trash),
///       ],
///       child: const FileTile(name: 'Report.pdf'),
///     )
class MacContextMenu extends StatelessWidget {
  const MacContextMenu({
    super.key,
    required this.items,
    required this.child,
    this.enabled = true,
    this.iconColumn = false,
    this.controller,
    this.onOpenChanged,
    this.semanticLabel,
  });

  final List<Widget> items;
  final Widget child;
  final bool enabled;
  final bool iconColumn;
  final MacMenuController? controller;
  final ValueChanged<bool>? onOpenChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => _MenuAnchor(
        items: items,
        controller: controller,
        enabled: enabled,
        iconColumn: iconColumn,
        matchTriggerWidth: false,
        onOpenChanged: onOpenChanged,
        semanticLabel: semanticLabel,
        context: true,
        child: child,
      );
}

class _MenuAnchor extends StatefulWidget {
  const _MenuAnchor({
    required this.items,
    required this.child,
    required this.context,
    this.controller,
    this.enabled = true,
    this.iconColumn = false,
    this.checkmarkColumn,
    this.matchTriggerWidth = true,
    this.onOpenChanged,
    this.semanticLabel,
  });

  final List<Widget> items;
  final Widget child;
  final bool context;
  final MacMenuController? controller;
  final bool enabled;
  final bool iconColumn;
  final bool? checkmarkColumn;
  final bool matchTriggerWidth;
  final ValueChanged<bool>? onOpenChanged;
  final String? semanticLabel;

  @override
  State<_MenuAnchor> createState() => _MenuAnchorState();
}

class _MenuAnchorState extends State<_MenuAnchor> {
  final OverlayPortalController _portal = OverlayPortalController();
  late MacMenuController _controller;
  _MenuSession? _session;
  Offset? _point; // context menu: where it opens, in the child's coordinates
  FocusNode? _restoreFocus;
  bool _openedByPointer = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MacMenuController();
    _controller._anchor = this;
  }

  @override
  void didUpdateWidget(_MenuAnchor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (_controller._anchor == this) _controller._anchor = null;
      _controller = widget.controller ?? MacMenuController();
      _controller._anchor = this;
    }
    if (!widget.enabled) _close();
  }

  @override
  void dispose() {
    if (_controller._anchor == this) _controller._anchor = null;
    final s = _session;
    _session = null;
    if (s != null) {
      s.closed = true;
      s.dispose();
    }
    super.dispose();
  }

  void _open({bool highlightFirst = false, Offset? point}) {
    if (!widget.enabled || !mounted) return;
    final current = _session;
    if (current != null) {
      // Already open (for example a trigger button that also calls open() when the click ends).
      if (point == null || !widget.context) {
        // A click that opened the menu on mouse-down also ends in the trigger's onPressed: no highlight then.
        final fromSameClick = _openedByPointer;
        _openedByPointer = false;
        if (highlightFirst && !fromSameClick && current.levels.first.highlight < 0) current.move(1);
        return;
      }
      _close();
    }
    _restoreFocus = FocusManager.instance.primaryFocus;
    late final _MenuSession session;
    session = _MenuSession(widget.items, highlightFirst: highlightFirst, onClose: () => _onSessionClosed(session));
    setState(() {
      _session = session;
      _point = point;
    });
    _portal.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_session == session && !session.closed) session.focusNode.requestFocus();
    });
    widget.onOpenChanged?.call(true);
  }

  void _close() => _session?.close();

  void _onSessionClosed(_MenuSession session) {
    if (_session != session) return;
    _openedByPointer = false;
    final hadFocus = session.focusNode.hasFocus || FocusManager.instance.primaryFocus == null;
    if (mounted) {
      setState(() => _session = null);
      _portal.hide();
    } else {
      _session = null;
    }
    if (hadFocus && _restoreFocus?.context != null) _restoreFocus!.requestFocus();
    _restoreFocus = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => session.dispose());
    widget.onOpenChanged?.call(false);
  }

  void _onPointerDown(PointerDownEvent e) {
    if (!widget.enabled) return;
    if (widget.context) {
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      if (e.buttons == kSecondaryButton || (e.buttons == kPrimaryButton && ctrl)) _open(point: e.localPosition);
    } else if (e.buttons == kPrimaryButton) {
      if (_session == null) {
        _open();
        _openedByPointer = true;
      } else {
        _close();
      }
    }
  }

  KeyEventResult _onTriggerKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || !widget.enabled) return KeyEventResult.ignored;
    _openedByPointer = false;
    final k = e.logicalKey;
    if (widget.context) {
      final menuKey = k == LogicalKeyboardKey.contextMenu || (k == LogicalKeyboardKey.f10 && HardwareKeyboard.instance.isShiftPressed);
      if (!menuKey) return KeyEventResult.ignored;
      final box = context.findRenderObject() as RenderBox?;
      _open(highlightFirst: true, point: Offset(0, box?.size.height ?? 0));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space) {
      _open(highlightFirst: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final trigger = _TriggerScope(
      controller: _controller,
      open: _session != null,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onTriggerKey,
        child: Listener(onPointerDown: _onPointerDown, child: widget.child),
      ),
    );
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context, info) {
        final session = _session;
        if (session == null) return const SizedBox.shrink();
        final anchor = MatrixUtils.transformRect(info.childPaintTransform, Offset.zero & info.childSize);
        final point = _point == null ? null : MatrixUtils.transformPoint(info.childPaintTransform, _point!);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Clicking (or scrolling) anywhere else closes the menu; nothing under it reacts to hover meanwhile.
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => session.close(),
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) session.close();
              },
              child: const MouseRegion(cursor: SystemMouseCursors.basic, child: SizedBox.expand()),
            ),
            CustomSingleChildLayout(
              delegate: _RootMenuLayout(
                anchor: anchor,
                point: point,
                minWidth: widget.matchTriggerWidth && point == null ? anchor.width : 0,
              ),
              child: Focus(
                focusNode: session.focusNode,
                onKeyEvent: (node, event) => session.handleKey(event),
                child: _MenuPanelView(
                  items: widget.items,
                  session: session,
                  iconColumn: widget.iconColumn,
                  checkmarkColumn: widget.checkmarkColumn,
                  semanticLabel: widget.semanticLabel,
                ),
              ),
            ),
          ],
        );
      },
      child: trigger,
    );
  }
}
