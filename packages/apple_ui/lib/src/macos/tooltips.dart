import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show GestureBinding, PointerDeviceKind, PointerDownEvent, PointerSignalEvent;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_panel_support.dart';

final PanelShapeBuilder _square = roundedPanelShape(0);
final _tooltipBlur = cssBackdrop(blur: 10);

/// The tooltip box on its own (kit "Tooltip"; CSS `mac-tooltip`): Ultra Thick material, square corners,
/// 11 px SF Pro Medium, padding 3 · 6 · 2 · 6 (18 px tall for one line), wraps at 320 px. For mockups;
/// real tooltips come from [MacTooltip].
///
///     const MacTooltipBox('Tooltip')
class MacTooltipBox extends StatelessWidget {
  const MacTooltipBox(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final dark = theme.isDark;
    final c = theme.mac;
    final style = panelText(appleFont(size: 11), size: 11, lineHeight: 13, weight: FontWeight.w500, color: c.labelVibrantPrimary);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: PanelSurface(
        shape: _square,
        fill: dark ? MacMaterials.ultrathickDark : MacMaterials.ultrathickLight, // #ECECEC 88 % · black 50 %
        backdrop: _tooltipBlur,
        shadows: [
          PanelShadow(0, 0, 0, 0.6, c.tooltipInnerStroke, inset: true), // white 0 % · 15 %
          const PanelShadow(0, 2, 8, 0, Color(0x33000000)),
          const PanelShadow(0, 0, 2, 0, Color(0x66000000)),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 3, 6, 2),
          child: Text(message, style: style),
        ),
      ),
    );
  }
}

/// A macOS tooltip (kit "Tooltips"): after the pointer rests on [child] for about 1 second, a small box with
/// [message] appears 20 px below the pointer (above it when there is no room, kept 8 px inside the window).
/// It hides when the pointer leaves, on a click, a key press or scrolling. Moving straight to another control
/// with a tooltip shows the next one at once (0.6 s "warm" time). Never on keyboard focus (macOS).
///
///     MacTooltip(
///       message: 'Share',                        // the same words as the control's accessible name
///       child: MacButton(icon: AppleIcons.squareAndArrowUp, semanticLabel: 'Share', onPressed: share),
///     )
///
/// Every icon-only control needs one. Keep it short ("Add Folder", "Shows hidden files too"); never put
/// essential information only in a tooltip. Screen readers get [message] as a hint.
class MacTooltip extends StatefulWidget {
  const MacTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<MacTooltip> createState() => _MacTooltipState();
}

const _kDelay = Duration(milliseconds: 1000); // rest time before the first tooltip
const _kWarm = Duration(milliseconds: 600); // the next one shows at once within this time
DateTime _warmUntil = DateTime.fromMillisecondsSinceEpoch(0);
_MacTooltipState? _shown;

class _MacTooltipState extends State<MacTooltip> {
  final OverlayPortalController _portal = OverlayPortalController();
  Timer? _timer;
  Offset _pointer = Offset.zero; // in the child's coordinates
  bool _visible = false;
  bool _listening = false;

  @override
  void dispose() {
    _timer?.cancel();
    _stopListening();
    if (_shown == this) _shown = null;
    super.dispose();
  }

  void _startListening() {
    if (_listening) return;
    _listening = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
  }

  void _stopListening() {
    if (!_listening) return;
    _listening = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
  }

  bool _onKey(KeyEvent e) {
    _hide();
    return false;
  }

  void _onGlobalPointer(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerSignalEvent) _hide(); // click or scroll
  }

  void _show() {
    if (!mounted || _visible) return;
    if (_shown != null && _shown != this) _shown!._hide();
    _shown = this;
    setState(() => _visible = true);
    _portal.show();
  }

  void _hide() {
    _timer?.cancel();
    _stopListening();
    if (!_visible) return;
    if (_shown == this) _shown = null;
    _warmUntil = DateTime.now().add(_kWarm);
    if (mounted) setState(() => _visible = false);
    _portal.hide();
  }

  void _onEnter(PointerEnterEvent e) {
    if (e.kind == PointerDeviceKind.touch) return; // touch never shows tooltips
    _pointer = e.localPosition;
    _startListening();
    _timer?.cancel();
    if (DateTime.now().isBefore(_warmUntil) || (_shown != null && _shown != this)) {
      _show();
    } else {
      _timer = Timer(_kDelay, _show);
    }
  }

  void _onHover(PointerHoverEvent e) {
    if (_visible) return; // macOS tooltips don't follow the pointer
    _pointer = e.localPosition;
    if (_listening && !DateTime.now().isBefore(_warmUntil)) {
      _timer?.cancel();
      _timer = Timer(_kDelay, _show); // it appears when the pointer RESTS
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hint: widget.message,
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayLocation: OverlayChildLocation.rootOverlay,
        overlayChildBuilder: (context, info) {
          final at = MatrixUtils.transformPoint(info.childPaintTransform, _pointer);
          return CustomSingleChildLayout(
            delegate: _TooltipLayout(at),
            child: IgnorePointer(child: ExcludeSemantics(child: MacTooltipBox(widget.message))),
          );
        },
        child: MouseRegion(
          opaque: false,
          hitTestBehavior: HitTestBehavior.deferToChild,
          onEnter: _onEnter,
          onHover: _onHover,
          onExit: (_) => _hide(),
          child: widget.child,
        ),
      ),
    );
  }
}

/// tooltips.js: 20 px below the pointer, above it when there is no room, 8 px from the window edges.
class _TooltipLayout extends SingleChildLayoutDelegate {
  _TooltipLayout(this.pointer);
  final Offset pointer;
  static const _below = 20.0;
  static const _edge = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
        maxWidth: math.max(0.0, constraints.maxWidth - 2 * _edge),
        maxHeight: math.max(0.0, constraints.maxHeight - 2 * _edge),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = pointer.dx;
    var y = pointer.dy + _below;
    if (y + child.height > size.height - _edge) y = pointer.dy - child.height - 4;
    x = x.clamp(_edge, math.max(_edge, size.width - _edge - child.width));
    y = y.clamp(_edge, math.max(_edge, size.height - _edge - child.height));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_TooltipLayout old) => old.pointer != pointer;
}
