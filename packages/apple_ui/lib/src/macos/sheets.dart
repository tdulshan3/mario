import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '../core/typography.dart';
import '_panel_support.dart';

final PanelShapeBuilder _sheetShape = roundedPanelShape(16);

List<PanelShadow> _sheetShadows(bool dark) => [
      if (dark) const PanelShadow(0, 0, 0, 1, Color(0x33FFFFFF), inset: true), // Dark: 1 px white 20 % inner edge
      const PanelShadow(0, 0, 1, 0, Color(0xCC000000)), // 0 0 1 px black 80 %
      PanelShadow(0, 18, 54, 0, dark ? const Color(0x91000000) : const Color(0x4D000000)), // black 30 % · 57 %
    ];

/// A sheet panel (kit "Sheet"): window background, radius 16, 20 px padding, window shadow; an optional bold
/// title, your content, and a button row at the bottom right (Cancel, then the default button on the far right;
/// [leading] buttons such as "Help" go to the far left). Show it with [showMacSheet].
///
///     MacSheet(
///       title: 'Rename Project',
///       onSubmit: rename,                          // Return (also in a text field)
///       onCancel: () => Navigator.pop(context),    // Escape and ⌘.
///       actions: [
///         MacButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
///         MacButton(label: 'Rename', style: MacButtonStyle.prominent, onPressed: rename),
///       ],
///       child: MacTextField(value: name, onChanged: (v) => setState(() => name = v), autofocus: true),
///     )
///
/// The buttons are your own widgets ([MacSheet] only places them, 8 px apart). No hover effects.
class MacSheet extends StatelessWidget {
  const MacSheet({
    super.key,
    this.title,
    required this.child,
    this.actions = const [],
    this.leading = const [],
    this.onSubmit,
    this.onCancel,
    this.width,
    this.minWidth = 300,
  });

  /// Bold 13 px title at the top left ("Rename Project"). Optional.
  final String? title;

  /// The sheet's content (fields, text). The 20 px padding comes from the sheet.
  final Widget child;

  /// Buttons at the bottom right, in order: Cancel first, the default (prominent) button last.
  final List<Widget> actions;

  /// Extra buttons at the bottom left ("Help", "Delete").
  final List<Widget> leading;

  /// Return runs this (the default button's action).
  final VoidCallback? onSubmit;

  /// Escape and ⌘. run this (Cancel). Null = [showMacSheet] closes the sheet with null.
  final VoidCallback? onCancel;

  /// Fixed width; null = fits the content, at least [minWidth].
  final double? width;
  final double minWidth;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && onSubmit != null) {
      onSubmit!();
      return KeyEventResult.handled;
    }
    final cmdPeriod = k == LogicalKeyboardKey.period && HardwareKeyboard.instance.isMetaPressed;
    if ((k == LogicalKeyboardKey.escape || cmdPeriod) && onCancel != null) {
      onCancel!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final type = MacTypography.of(context);
    final hasButtons = actions.isNotEmpty || leading.isNotEmpty;
    Widget body = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(header: true, child: Text(title!, style: type.bodyEmphasized.copyWith(fontWeight: FontWeight.w700))),
            ),
          child,
          if (hasButtons)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Row(
                children: [
                  for (var i = 0; i < leading.length; i++) ...[if (i > 0) const SizedBox(width: 8), leading[i]],
                  const Spacer(),
                  for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), actions[i]],
                ],
              ),
            ),
        ],
      ),
    );
    body = DefaultTextStyle(style: type.body, child: body);
    Widget panel = PanelSurface(shape: _sheetShape, fill: c.windowBg, shadows: _sheetShadows(theme.isDark), child: body);
    panel = width != null
        ? SizedBox(width: width, child: panel)
        : ConstrainedBox(constraints: BoxConstraints(minWidth: minWidth), child: IntrinsicWidth(child: panel));
    return Semantics(
      scopesRoute: true,
      namesRoute: title != null,
      explicitChildNodes: true,
      label: title,
      // A scope with autofocus: a field inside with autofocus still gets the focus; otherwise the sheet has it,
      // so Return and Escape work at once.
      child: FocusScope(autofocus: true, onKeyEvent: _onKey, child: panel),
    );
  }
}

/// Shows a sheet attached to the top centre of the window: it slides down from the top edge (0.3 s, none with
/// reduced motion), the window behind is dimmed (black 20 %) and blocked until it closes. Returns what the sheet
/// passes to `Navigator.pop(context, value)`. Escape closes it with null (unless the [MacSheet] has `onCancel`).
///
///     final name = await showMacSheet<String>(
///       context: context,
///       builder: (context) => RenameSheet(initial: project.name),   // a widget that returns a MacSheet
///     );
///
/// [top] = gap from the top of the window (default 8; below a 52 px toolbar use 60).
Future<T?> showMacSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double top = 8,
}) {
  final theme = AppleTheme.of(context);
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0x33000000), // kit "Dialogs/Overlay": black 20 %
    barrierLabel: 'Sheet',
    transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
    pageBuilder: (dialogContext, animation, secondary) {
      final curve = CurvedAnimation(parent: animation, curve: const Cubic(0.2, 0.8, 0.2, 1));
      return AppleTheme(
        data: theme,
        child: FocusScope(
          autofocus: true,
          onKeyEvent: (node, e) {
            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(dialogContext).maybePop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, top, 16, 16),
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedBuilder(
                  animation: curve,
                  // Slides down from the top edge of the window (CSS: translateY(-100% - top) → 0).
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, -(1 - curve.value) * top),
                    child: FractionalTranslation(translation: Offset(0, curve.value - 1), child: child),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: math.max(0.0, constraints.maxHeight)),
                    child: Builder(builder: builder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondary, child) => child,
  );
}
