import 'package:flutter/gestures.dart' show GestureBinding, PointerDownEvent, PointerEvent, PointerHoverEvent;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/icons.dart';
import '../core/mac_support.dart' show MacGlassStyle;
import '../core/theme.dart';
import '../core/typography.dart';
import '_panel_support.dart';
import 'menus.dart';

// =====================================================================================================
// Menu bar (MOCKUPS ONLY)
// =====================================================================================================

/// The colour of the menu bar text: it follows the WALLPAPER under the transparent bar, not Light/Dark Mode.
enum MacMenuBarForeground {
  /// Follow Light/Dark Mode (black 85 % in Light, white in Dark).
  auto,

  /// White text over a dark wallpaper (kit "Over Dark").
  overDark,

  /// Black 85 % text over a light wallpaper (kit "Over Light").
  overLight,
}

/// One menu of a [MacMenuBar]: its title and its items ([MacMenuItem], [MacMenuDivider], [MacMenuHeader]).
///
///     MacMenuBarMenu('File', items: [MacMenuItem(label: 'New Note', shortcut: '⌘N', onSelected: newNote)])
@immutable
class MacMenuBarMenu {
  const MacMenuBarMenu(this.title, {this.items = const []});
  final String title;
  final List<Widget> items;
}

/// A status item (menu bar extra) at the right of a [MacMenuBar]: a template icon and its accessible name.
///
///     const MacMenuBarExtra(icon: AppleIcons.wifi, semanticLabel: 'Wi-Fi')
@immutable
class MacMenuBarExtra {
  const MacMenuBarExtra({required this.icon, required this.semanticLabel, this.items});
  final IconData icon;
  final String semanticLabel;

  /// Optional menu it opens.
  final List<Widget>? items;
}

/// A MOCKUP of the macOS menu bar (kit "Menu Bar", 34 px, transparent over the wallpaper): a placeholder system
/// slot (never the Apple logo), the app name in bold, the menu titles, status items and the clock.
/// Real apps never draw the menu bar: on macOS use Flutter's `PlatformMenuBar` (the native menu bar).
///
///     MacMenuBar(
///       appName: 'Notes',
///       foreground: MacMenuBarForeground.overDark,     // white text over a dark wallpaper
///       appMenu: [MacMenuItem(label: 'About Notes', onSelected: () {})],
///       menus: [
///         MacMenuBarMenu('File', items: [MacMenuItem(label: 'New Note', shortcut: '⌘N', onSelected: newNote)]),
///         MacMenuBarMenu('Edit', items: [MacMenuItem(label: 'Copy', shortcut: '⌘C', onSelected: copy)]),
///         const MacMenuBarMenu('View'),
///       ],
///       extras: const [
///         MacMenuBarExtra(icon: AppleIcons.wifi, semanticLabel: 'Wi-Fi'),
///         MacMenuBarExtra(icon: AppleIcons.magnifyingglass, semanticLabel: 'Spotlight'),
///       ],
///       date: 'Wed Apr 1',
///       time: '9:41 AM',
///     )
///
/// Click a title to open its menu; while one is open, moving the pointer to another title switches menus and
/// ← → switch from the keyboard. An open title gets a soft capsule. No hover effects.
class MacMenuBar extends StatefulWidget {
  const MacMenuBar({
    super.key,
    required this.appName,
    this.appMenu = const [],
    this.menus = const [],
    this.extras = const [],
    this.date,
    this.time,
    this.foreground = MacMenuBarForeground.auto,
    this.systemIcon = AppleIcons.app,
    this.selected,
  });

  final String appName;

  /// Items of the app menu (About, Settings… ⌘,, Quit ⌘Q). Empty = the app name opens nothing.
  final List<Widget> appMenu;
  final List<MacMenuBarMenu> menus;
  final List<MacMenuBarExtra> extras;

  /// Clock text: "Wed Apr 1" and "9:41 AM" (8 px apart).
  final String? date;
  final String? time;
  final MacMenuBarForeground foreground;

  /// Neutral placeholder for the system menu slot. Never the Apple logo.
  final IconData systemIcon;

  /// Static mockups: draw this title (index into [menus]) as open (kit "Selected").
  final int? selected;

  @override
  State<MacMenuBar> createState() => _MacMenuBarState();
}

class _MacMenuBarState extends State<MacMenuBar> {
  // Index 0 = the app menu, 1… = widget.menus.
  final List<MacMenuController> _controllers = [];
  final List<GlobalKey> _keys = [];
  int _open = -1;
  int _justClosed = -1;
  bool _routing = false;

  List<List<Widget>> get _allMenus => [widget.appMenu, for (final m in widget.menus) m.items];

  void _sync() {
    final n = widget.menus.length + 1;
    while (_controllers.length < n) {
      _controllers.add(MacMenuController());
      _keys.add(GlobalKey());
    }
  }

  @override
  void dispose() {
    _route(false);
    super.dispose();
  }

  void _route(bool on) {
    if (on == _routing) return;
    _routing = on;
    if (on) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    } else {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    }
  }

  int _titleAt(Offset global) {
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final local = box.globalToLocal(global);
      if ((Offset.zero & box.size).contains(local)) return i;
    }
    return -1;
  }

  void _onPointer(PointerEvent e) {
    if (e is! PointerHoverEvent && e is! PointerDownEvent) return;
    final i = _titleAt(e.position);
    if (i < 0 || _allMenus[i].isEmpty) return;
    if (e is PointerDownEvent) {
      if (i == _justClosed) return; // this click closed it
      _switchTo(i, keyboard: false);
    } else if (_open >= 0 && i != _open) {
      _switchTo(i, keyboard: false);
    }
  }

  void _switchTo(int i, {required bool keyboard}) {
    if (_open >= 0 && _open != i) _controllers[_open].close();
    _controllers[i].open(highlightFirst: keyboard);
  }

  void _openChanged(int i, bool open) {
    if (open) {
      _open = i;
      _route(true);
    } else if (_open == i) {
      _open = -1;
      _justClosed = i;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _justClosed = -1;
        if (_open < 0) _route(false);
      });
    }
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(int i, KeyEvent e) {
    if (e is! KeyDownEvent || _open != i) return KeyEventResult.ignored;
    final dir = e.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : (e.logicalKey == LogicalKeyboardKey.arrowLeft ? -1 : 0);
    if (dir == 0) return KeyEventResult.ignored;
    final menus = _allMenus;
    var j = i;
    for (var step = 0; step < menus.length; step++) {
      j = (j + dir) % menus.length;
      if (j < 0) j += menus.length;
      if (menus[j].isNotEmpty) break;
    }
    if (j != i) _switchTo(j, keyboard: true);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final theme = AppleTheme.of(context);
    final over = switch (widget.foreground) {
      MacMenuBarForeground.overDark => true,
      MacMenuBarForeground.overLight => false,
      MacMenuBarForeground.auto => theme.isDark,
    };
    final label = over ? const Color(0xFFFFFFFF) : const Color(0xD9000000);
    final capsule = over ? const Color(0x14FFFFFF) : const Color(0x14000000);
    final text = panelText(appleFont(size: 13), size: 13, lineHeight: 16, weight: FontWeight.w600, color: label);

    Widget title(int i, String t, {bool app = false}) {
      final items = _allMenus[i];
      final selected = _open == i || (widget.selected != null && widget.selected == i - 1);
      Widget w = _BarItem(
        key: _keys[i],
        selected: selected,
        capsule: capsule,
        padding: EdgeInsets.fromLTRB(app ? 11 : 9, 4, 9, 4),
        child: Text(t, style: app ? text.copyWith(fontWeight: FontWeight.w800) : text, maxLines: 1, softWrap: false),
      );
      w = Semantics(button: true, label: t, excludeSemantics: true, child: w);
      if (items.isEmpty) return w;
      return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, e) => _onKey(i, e),
        child: MacMenu(
          controller: _controllers[i],
          matchTriggerWidth: false,
          onOpenChanged: (open) => _openChanged(i, open),
          items: items,
          semanticLabel: t,
          trigger: w,
        ),
      );
    }

    Widget extra(MacMenuBarExtra x) {
      Widget w = _BarItem(
        selected: false,
        capsule: capsule,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Icon(x.icon, size: 16, color: label),
      );
      w = Semantics(label: x.semanticLabel, image: x.items == null, button: x.items != null, excludeSemantics: true, child: w);
      if (x.items == null) return w;
      return MacMenu(matchTriggerWidth: false, items: x.items!, semanticLabel: x.semanticLabel, trigger: w);
    }

    return Semantics(
      container: true,
      label: 'Menu bar',
      explicitChildNodes: true,
      child: SizedBox(
        height: 34,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 20, 5),
          child: Row(
            children: [
              // System menu slot, 33 × 24: a neutral placeholder (the real system draws the Apple logo).
              ExcludeSemantics(
                child: SizedBox(width: 33, height: 24, child: Center(child: Icon(widget.systemIcon, size: 16, color: label))),
              ),
              title(0, widget.appName, app: true),
              for (var i = 0; i < widget.menus.length; i++) title(i + 1, widget.menus[i].title),
              const Spacer(),
              const SizedBox(width: 16),
              for (final x in widget.extras) extra(x),
              if (widget.date != null || widget.time != null)
                Padding(
                  padding: const EdgeInsets.only(left: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.date != null) Text(widget.date!, style: text, maxLines: 1, softWrap: false),
                      if (widget.date != null && widget.time != null) const SizedBox(width: 8),
                      if (widget.time != null) Text(widget.time!, style: text, maxLines: 1, softWrap: false),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A menu-bar title or status item: 24 px tall; when open, a soft capsule 4 px wider on each side and 1 px
/// taller at the top (kit "Selected"). No hover effect.
class _BarItem extends StatelessWidget {
  const _BarItem({super.key, required this.selected, required this.capsule, required this.padding, required this.child});
  final bool selected;
  final Color capsule;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final open = selected || MacMenu.isOpenOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: SizedBox(
        height: 24,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (open)
              Positioned(
                left: -4,
                right: -4,
                top: -1,
                bottom: 0,
                child: DecoratedBox(decoration: ShapeDecoration(color: capsule, shape: const StadiumBorder())),
              ),
            Padding(padding: padding, child: Center(widthFactor: 1, child: child)),
          ],
        ),
      ),
    );
  }
}

// =====================================================================================================
// Dock (MOCKUPS ONLY)
// =====================================================================================================

final PanelShapeBuilder _dockShape = roundedPanelShape(15);

/// A MOCKUP of the Dock (kit "Dock"): a shelf of the classic Thin blur material (0.5 px hairline, soft shadow, no
/// rims or inner highlights), 55 px tall, radius 15, 36 px icons 9 px apart.
/// Real apps never draw the Dock (they set a Dock badge or menu). Centre it 4 px above the bottom of a
/// desktop mockup.
///
///     MacDock(children: [
///       MacDockItem(label: 'Notes', running: true, icon: MacDockIcon(icon: AppleIcons.squareAndPencil, color: c.accentYellow)),
///       MacDockItem(label: 'Mail', icon: MacDockIcon(icon: AppleIcons.paperplane, color: c.accentBlue)),
///       const MacDockSeparator(),
///       MacDockItem(label: 'Trash', icon: MacDockIcon(icon: AppleIcons.trash, color: c.gray)),
///     ])
class MacDock extends StatelessWidget {
  const MacDock({super.key, required this.children, this.semanticLabel = 'Dock'});

  /// [MacDockItem]s and [MacDockSeparator]s.
  final List<Widget> children;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final material = panelMaterial(AppleTheme.of(context).isDark, style: MacGlassStyle.control);
    return Semantics(
      container: true,
      label: semanticLabel,
      explicitChildNodes: true,
      child: SizedBox(
        height: 55,
        child: IntrinsicWidth(
          child: PanelSurface(
            shape: _dockShape,
            fill: material.fill,
            backdrop: material.backdrop,
            shadows: material.shadows,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 9), children[i]],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One app in a [MacDock] (kit "Dock Icon", 36 × 47): the 36 px icon and, when [running], a 4 px dot 3 px under it.
///
///     MacDockItem(label: 'Mail', running: true, icon: MacDockIcon(icon: AppleIcons.paperplane, color: c.accentBlue))
///     MacDockItem(label: 'My App', icon: Image.asset('assets/app_icon.png'))
class MacDockItem extends StatelessWidget {
  const MacDockItem({super.key, required this.label, required this.icon, this.running = false, this.onPressed});

  /// The app name (accessible name).
  final String label;

  /// A 36 × 36 icon: your app's icon image, or a [MacDockIcon] placeholder. Never Apple's app icons.
  final Widget icon;
  final bool running;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          child: SizedBox(
            width: 36,
            height: 47,
            child: Column(
              children: [
                SizedBox(width: 36, height: 36, child: icon),
                const SizedBox(height: 3),
                if (running)
                  const SizedBox(
                    width: 4,
                    height: 4,
                    child: DecoratedBox(decoration: ShapeDecoration(color: Color(0xA6FFFFFF), shape: CircleBorder())),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The line between apps and folders/Trash in a [MacDock]: 1 × 36 px in an 11 px slot.
///
///     const MacDockSeparator()
class MacDockSeparator extends StatelessWidget {
  const MacDockSeparator({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 5),
        child: SizedBox(width: 1, height: 36, child: ColoredBox(color: Color(0x73FFFFFF))), // white 45 %
      );
}

/// A placeholder app icon for mockups: a rounded square (corners 22.5 %) with a gradient of [color] and a
/// white glyph. Use your own app's icon when you have one; never copy Apple's.
///
///     MacDockIcon(icon: AppleIcons.paperplane, color: context.macColors.accentBlue)
class MacDockIcon extends StatelessWidget {
  const MacDockIcon({super.key, required this.icon, this.color});

  final IconData icon;

  /// Null = the accent colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppleTheme.of(context).accentColor;
    final shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(36 * 0.225));
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [mixColor(tint, const Color(0xFFFFFFFF), 0.72), tint],
        ),
        shadows: const [BoxShadow(color: Color(0x2E000000), offset: Offset(0, 1), blurRadius: 2)],
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(36 * 0.225),
            side: const BorderSide(color: Color(0x1F000000), width: 0.5),
          ),
        ),
        child: Center(child: Icon(icon, size: 20, color: const Color(0xFFFFFFFF))),
      ),
    );
  }
}
