import 'package:flutter/foundation.dart' show mergeSort;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '../core/typography.dart';
import '_panel_support.dart';

/// What an alert button does. The alert places the buttons for you: stacked = default on top, destructive,
/// other buttons, Cancel at the bottom; side by side = Cancel left, default right.
enum MacAlertButtonRole {
  /// The accent button: the action people most likely want. Return chooses it. One per alert.
  defaultAction,

  /// Red label on a red wash ("Delete", "Move to Trash").
  destructive,

  /// Solid red default button: only when the destructive action is exactly what people just asked for
  /// ("Empty Trash" after choosing Empty Trash). Return chooses it.
  destructiveDefault,

  /// Escape and ⌘. choose it. Always add one when the alert asks a question.
  cancel,

  /// Any other answer ("Don't Save").
  normal,
}

/// One alert button: a verb in title case that answers the title ("Save", "Delete", "Don't Save").
///
///     const MacAlertButton('Save', role: MacAlertButtonRole.defaultAction)
///     MacAlertButton('Delete', role: MacAlertButtonRole.destructive, onPressed: deleteDraft)
///     const MacAlertButton('Cancel', role: MacAlertButtonRole.cancel)
@immutable
class MacAlertButton {
  const MacAlertButton(this.label, {this.role = MacAlertButtonRole.normal, this.onPressed, this.enabled = true});

  final String label;
  final MacAlertButtonRole role;

  /// Runs when the button is chosen (click, Return for the default, Escape for Cancel), before the alert closes.
  final VoidCallback? onPressed;
  final bool enabled;

  bool get _isDefault => role == MacAlertButtonRole.defaultAction || role == MacAlertButtonRole.destructiveDefault;
}

/// Button layout: [auto] = side by side for two short buttons (12 characters or fewer), otherwise stacked.
enum MacAlertLayout { auto, stacked, sideBySide }

final PanelShapeBuilder _alertShape = roundedPanelShape(34);

List<MacAlertButton> _ordered(List<MacAlertButton> buttons) {
  int rank(MacAlertButton b) => switch (b.role) {
        MacAlertButtonRole.defaultAction || MacAlertButtonRole.destructiveDefault => 0,
        MacAlertButtonRole.destructive => 1,
        MacAlertButtonRole.normal => 2,
        MacAlertButtonRole.cancel => 3,
      };
  final list = [...buttons];
  mergeSort(list, compare: (a, b) => rank(a) - rank(b));
  return list;
}

/// A macOS alert panel (kit "Alert"): Ultra Thick blur material, 260 px wide, radius 34, bold title, optional message,
/// optional app icon and "Don't ask again" checkbox, 1–3 capsule buttons. Usually shown with [showMacAlert];
/// use the widget directly for mockups.
///
///     MacAlert(
///       title: 'Save this message as a draft?',
///       message: 'This message has not been sent and contains unsaved changes.',
///       buttons: [
///         MacAlertButton('Save', role: MacAlertButtonRole.defaultAction, onPressed: save),
///         MacAlertButton('Delete', role: MacAlertButtonRole.destructive, onPressed: delete),
///         MacAlertButton('Cancel', role: MacAlertButtonRole.cancel),
///       ],
///     )
///
/// Keys: Return = the default button, Escape or ⌘. = Cancel, Tab moves between the buttons (focus ring), Space
/// presses the focused one. No hover effects.
class MacAlert extends StatefulWidget {
  const MacAlert({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.buttons = const [MacAlertButton('OK', role: MacAlertButtonRole.defaultAction)],
    this.layout = MacAlertLayout.auto,
    this.suppressionLabel,
    this.suppressed = false,
    this.onSuppressedChanged,
    this.onButtonPressed,
  });

  /// A short question or statement in sentence case ("Delete “Budget.numbers”?").
  final String title;

  /// One or two short sentences with the consequence (optional).
  final String? message;

  /// Optional 64 × 64 app icon (native alerts show it automatically; the kit hides it by default).
  final Widget? icon;

  /// 1 to 3 buttons, in any order: the alert sorts them.
  final List<MacAlertButton> buttons;
  final MacAlertLayout layout;

  /// Shows the suppression checkbox with this text ("Don't ask again").
  final String? suppressionLabel;
  final bool suppressed;
  final ValueChanged<bool>? onSuppressedChanged;

  /// Called after a button's own `onPressed` ([showMacAlert] closes the alert here).
  final ValueChanged<MacAlertButton>? onButtonPressed;

  @override
  State<MacAlert> createState() => _MacAlertState();
}

class _MacAlertState extends State<MacAlert> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'MacAlert');

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  void _press(MacAlertButton b) {
    if (!b.enabled) return;
    b.onPressed?.call();
    widget.onButtonPressed?.call(b);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final hw = HardwareKeyboard.instance;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      for (final b in widget.buttons) {
        if (b._isDefault) {
          _press(b);
          return KeyEventResult.handled;
        }
      }
    } else if (k == LogicalKeyboardKey.escape || (k == LogicalKeyboardKey.period && hw.isMetaPressed)) {
      for (final b in widget.buttons) {
        if (b.role == MacAlertButtonRole.cancel) {
          _press(b);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    // The classic Ultra Thick blur material: 0.5 px hairline + the kit's 0 18 48 drop shadow, no rims.
    final material = panelMaterial(theme.isDark);
    final ordered = _ordered(widget.buttons);
    final sideBySide = widget.layout == MacAlertLayout.sideBySide ||
        (widget.layout == MacAlertLayout.auto && ordered.length == 2 && ordered.every((b) => b.label.characters.length <= 12));
    final base = appleFont(size: 13);
    final title = panelText(base, size: 13, lineHeight: 16, weight: FontWeight.w700, color: c.labelPrimary);
    final small = panelText(appleFont(size: 11), size: 11, lineHeight: 14, color: c.labelPrimary);

    Widget buttons;
    if (sideBySide) {
      buttons = Row(
        children: [
          for (var i = ordered.length - 1; i >= 0; i--) ...[
            Expanded(child: _AlertButton(button: ordered[i], height: 32, onPressed: () => _press(ordered[i]))),
            if (i > 0) const SizedBox(width: 8),
          ],
        ],
      );
    } else {
      buttons = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < ordered.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _AlertButton(button: ordered[i], height: 28, onPressed: () => _press(ordered[i])),
          ],
        ],
      );
    }

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.icon != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
              child: Align(alignment: AlignmentDirectional.centerStart, child: SizedBox(width: 64, height: 64, child: widget.icon)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Semantics(header: true, child: Text(widget.title, style: title)),
          ),
          if (widget.message != null)
            Padding(padding: const EdgeInsets.fromLTRB(6, 10, 6, 0), child: Text(widget.message!, style: small)),
          if (widget.suppressionLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
              child: _SuppressionCheckbox(
                label: widget.suppressionLabel!,
                value: widget.suppressed,
                style: small,
                onChanged: widget.onSuppressedChanged,
              ),
            ),
          const SizedBox(height: 16),
          buttons,
        ],
      ),
    );

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: widget.title,
      child: FocusScope(
        node: _scope,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SizedBox(
          width: 260,
          child: PanelSurface(
            shape: _alertShape,
            fill: material.fill,
            backdrop: material.backdrop,
            shadows: material.shadows,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// The alert's capsule buttons (kit "Alerts/_Buttons"): 28 px stacked, 32 px side by side, 13 px Medium.
class _AlertButton extends StatefulWidget {
  const _AlertButton({required this.button, required this.height, required this.onPressed});
  final MacAlertButton button;
  final double height;
  final VoidCallback onPressed;

  @override
  State<_AlertButton> createState() => _AlertButtonState();
}

class _AlertButtonState extends State<_AlertButton> {
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final dark = theme.isDark;
    final b = widget.button;
    final enabled = b.enabled;
    final accent = theme.accentColor;
    final red = c.accentVibrantRed;
    const white = Color(0xFFFFFFFF);
    Color fill, pressed, disabledFill, label, disabledLabel;
    switch (b.role) {
      case MacAlertButtonRole.defaultAction:
        fill = accent;
        pressed = dark ? mixColor(accent, white, 0.88) : mixColor(accent, const Color(0xFF000000), 0.88);
        disabledFill = accent.withValues(alpha: accent.a * 0.4);
        label = white;
        disabledLabel = const Color(0x80FFFFFF);
      case MacAlertButtonRole.destructiveDefault:
        final r = c.accentRed;
        fill = r;
        pressed = dark ? mixColor(r, white, 0.88) : mixColor(r, const Color(0xFF000000), 0.88);
        disabledFill = r.withValues(alpha: 0.4);
        label = white;
        disabledLabel = const Color(0x80FFFFFF);
      case MacAlertButtonRole.destructive:
        final wash = dark ? mixColor(red, white, 0.9) : mixColor(red, const Color(0xFF000000), 0.92);
        fill = wash.withValues(alpha: dark ? 0.25 : 0.23);
        pressed = wash.withValues(alpha: dark ? 0.35 : 0.33);
        disabledFill = red.withValues(alpha: 0.1);
        label = red;
        disabledLabel = red.withValues(alpha: 0.4);
      case MacAlertButtonRole.cancel || MacAlertButtonRole.normal:
        fill = dark ? const Color(0x17FFFFFF) : const Color(0x1A000000); // white 9 % · black 10 %
        pressed = dark ? const Color(0x2BFFFFFF) : const Color(0x2E000000); // white 17 % · black 18 %
        disabledFill = dark ? const Color(0x0DFFFFFF) : const Color(0x0D000000);
        label = c.labelPrimary;
        disabledLabel = c.labelTertiary;
    }
    final bg = !enabled ? disabledFill : (_pressed ? pressed : fill);
    final fg = enabled ? label : disabledLabel;
    final shape = roundedPanelShape(widget.height / 2);

    Widget box = Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Text(
        b.label,
        style: panelText(appleFont(size: 13), size: 13, lineHeight: 16, weight: FontWeight.w500, color: fg),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
    if (_focused) {
      box = CustomPaint(foregroundPainter: FocusRingPainter(shape, accent.withValues(alpha: 0.55)), child: box);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: b.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed())},
        mouseCursor: SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: enabled ? widget.onPressed : null,
          child: box,
        ),
      ),
    );
  }
}

/// "Don't ask again": a small macOS checkbox (14 px, radius 4.5) + 11 px label, placed like NSAlert's.
class _SuppressionCheckbox extends StatefulWidget {
  const _SuppressionCheckbox({required this.label, required this.value, required this.style, this.onChanged});
  final String label;
  final bool value;
  final TextStyle style;
  final ValueChanged<bool>? onChanged;

  @override
  State<_SuppressionCheckbox> createState() => _SuppressionCheckboxState();
}

class _SuppressionCheckboxState extends State<_SuppressionCheckbox> {
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final dark = theme.isDark;
    final accent = theme.accentColor;
    final enabled = widget.onChanged != null;
    final on = widget.value;
    Color bg;
    if (on) {
      bg = dark ? mixColor(accent, const Color(0xFFFFFFFF), 0.95) : accent;
      if (_pressed) bg = dark ? mixColor(accent, const Color(0xFFFFFFFF), 0.92) : mixColor(accent, const Color(0xFF000000), 0.9);
    } else {
      bg = _pressed ? (dark ? const Color(0x30FFFFFF) : const Color(0x30000000)) : (dark ? const Color(0x1AFFFFFF) : const Color(0x1A000000));
    }
    final shape = roundedPanelShape(4.5);
    Widget box = Container(
      width: 14,
      height: 14,
      decoration: ShapeDecoration(color: bg, shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(4.5))),
      child: on ? CustomPaint(painter: _CheckGlyph(const Color(0xFFFFFFFF))) : null,
    );
    if (_focused) box = CustomPaint(foregroundPainter: FocusRingPainter(shape, accent.withValues(alpha: 0.55)), child: box);
    void toggle() => widget.onChanged?.call(!widget.value);
    return Semantics(
      checked: on,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => toggle())},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: enabled ? toggle : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [box, const SizedBox(width: 6), Flexible(child: Text(widget.label, style: widget.style))],
          ),
        ),
      ),
    );
  }
}

class _CheckGlyph extends CustomPainter {
  _CheckGlyph(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const s = 7.78 / 9.31; // small checkbox checkmark (7.78 × 7.55)
    final o = Offset((size.width - 7.78) / 2, (size.height - 7.55) / 2);
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + 0.9 * s, o.dy + 4.75 * s)
        ..lineTo(o.dx + 3.65 * s, o.dy + 8.05 * s)
        ..lineTo(o.dx + 8.4 * s, o.dy + 0.9 * s),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckGlyph old) => old.color != color;
}

/// Shows a modal macOS alert in the middle of the window, dims everything behind it (kit "Alerts/Overlay") and
/// returns the label of the button people chose (Escape/⌘. = the Cancel button's label; null if it closed
/// another way).
///
///     final choice = await showMacAlert(
///       context,
///       title: 'Move “Report.pdf” to the Trash?',
///       message: 'You can restore it from the Trash until you empty it.',
///       suppressionLabel: "Don't ask again",
///       onSuppressionChanged: (v) => dontAskAgain = v,
///       buttons: const [
///         MacAlertButton('Move to Trash', role: MacAlertButtonRole.defaultAction),
///         MacAlertButton('Cancel', role: MacAlertButtonRole.cancel),
///       ],
///     );
///     if (choice == 'Move to Trash') moveToTrash();
Future<String?> showMacAlert(
  BuildContext context, {
  required String title,
  String? message,
  Widget? icon,
  List<MacAlertButton> buttons = const [MacAlertButton('OK', role: MacAlertButtonRole.defaultAction)],
  MacAlertLayout layout = MacAlertLayout.auto,
  String? suppressionLabel,
  bool suppressed = false,
  ValueChanged<bool>? onSuppressionChanged,
}) {
  final theme = AppleTheme.of(context);
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierColor: theme.mac.overlay, // #ABABAB 60 % · #171717 62 %
    barrierLabel: title,
    transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
    transitionBuilder: (context, animation, secondary, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
    pageBuilder: (dialogContext, animation, secondary) {
      var value = suppressed;
      return AppleTheme(
        data: theme,
        child: Center(
          child: StatefulBuilder(
            builder: (context, setState) => MacAlert(
              title: title,
              message: message,
              icon: icon,
              buttons: buttons,
              layout: layout,
              suppressionLabel: suppressionLabel,
              suppressed: value,
              onSuppressedChanged: (v) {
                setState(() => value = v);
                onSuppressionChanged?.call(v);
              },
              onButtonPressed: (b) => Navigator.of(dialogContext).pop(b.label),
            ),
          ),
        ),
      );
    },
  );
}
