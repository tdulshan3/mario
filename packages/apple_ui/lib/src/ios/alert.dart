import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '../core/typography.dart';
import '_presentation_support.dart';

/// Role of an alert action (kit "_Buttons" Role).
enum IosAlertActionRole {
  /// Grey capsule, primary label.
  none,

  /// Accent-filled capsule, white label: the action people most likely want. At most one per alert.
  defaultAction,

  /// The way out. Always add one when the alert offers a choice. Left when side by side, bottom when stacked.
  cancel,

  /// Grey capsule, red label: deletes or removes something.
  destructive,
}

/// One button of an [IosAlert].
@immutable
class IosAlertAction {
  const IosAlertAction({required this.label, this.role = IosAlertActionRole.none, this.onPressed, this.enabled = true});

  /// A verb in title case ("Delete", "Save") or "Cancel"/"OK".
  final String label;
  final IosAlertActionRole role;

  /// Called when pressed (the alert closes itself in [showIosAlert]).
  final VoidCallback? onPressed;
  final bool enabled;
}

/// A text field of an [IosAlert] (kit "Text Field": 52 tall, Medium 17).
@immutable
class IosAlertTextField {
  const IosAlertTextField({this.placeholder, this.controller, this.obscureText = false, this.keyboardType, this.semanticLabel});
  final String? placeholder;

  /// Read the typed text from here (pass your own controller). Null = an internal one you can't read.
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? semanticLabel;
}

/// How the actions are arranged: [auto] = side by side for 1–2 actions, stacked for 3 or more.
enum IosAlertLayout { auto, sideBySide, stacked }

/// An iOS alert (kit page "Alerts"): a 300-wide panel of Thick blur material, left-aligned title (Semibold 17) and
/// message (Regular 17), optional text fields, and 48-tall capsule actions. Same on iPhone and iPad. Show it with
/// [showIosAlert]; this widget alone is the static card (for mockups).
///
///     IosAlert(
///       title: 'Delete “Trip”?',
///       message: 'This album will be deleted from all your devices.',
///       actions: [
///         IosAlertAction(label: 'Cancel', role: IosAlertActionRole.cancel, onPressed: () {}),
///         IosAlertAction(label: 'Delete', role: IosAlertActionRole.destructive, onPressed: delete),
///       ],
///     )
class IosAlert extends StatelessWidget {
  const IosAlert({
    super.key,
    required this.title,
    this.message,
    required this.actions,
    this.textFields = const [],
    this.layout = IosAlertLayout.auto,
    this.autofocus = false,
  });

  final String title;
  final String? message;
  final List<IosAlertAction> actions;
  final List<IosAlertTextField> textFields;
  final IosAlertLayout layout;

  /// Focus the first text field (and show the keyboard) when the alert appears.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final stacked = layout == IosAlertLayout.stacked || (layout == IosAlertLayout.auto && actions.length > 2);
    final ordered = [...actions];
    final cancel = ordered.where((a) => a.role == IosAlertActionRole.cancel).toList();
    ordered.removeWhere((a) => a.role == IosAlertActionRole.cancel);
    // Cancel goes left when side by side and to the bottom when stacked.
    final list = stacked ? [...ordered, ...cancel] : [...cancel, ...ordered];
    Widget button(IosAlertAction a) => PresentationActionButton(
          label: a.label,
          look: switch (a.role) {
            IosAlertActionRole.defaultAction => PresentationActionLook.prominent,
            IosAlertActionRole.destructive => PresentationActionLook.destructive,
            _ => PresentationActionLook.plain,
          },
          onPressed: a.enabled ? (a.onPressed ?? () {}) : null,
        );
    final buttons = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < list.length; i++) ...[if (i > 0) const SizedBox(height: 8), button(list[i])],
            ],
          )
        : Row(children: [
            for (var i = 0; i < list.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: button(list[i]))],
          ]);

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: SizedBox(
        width: 300,
        child: PresentationGlass(
          radius: BorderRadius.circular(34),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PresentationTitleBlock(title: title, message: message),
                if (textFields.isNotEmpty) ...[
                  _AlertFields(fields: textFields, autofocus: autofocus, onSubmit: () {
                    final def = actions.where((a) => a.role == IosAlertActionRole.defaultAction && a.enabled);
                    if (def.isNotEmpty) def.first.onPressed?.call();
                  }),
                  const SizedBox(height: 19),
                ],
                buttons,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertFields extends StatefulWidget {
  const _AlertFields({required this.fields, required this.autofocus, required this.onSubmit});
  final List<IosAlertTextField> fields;
  final bool autofocus;
  final VoidCallback onSubmit;

  @override
  State<_AlertFields> createState() => _AlertFieldsState();
}

class _AlertFieldsState extends State<_AlertFields> {
  late final List<TextEditingController> _own = [for (final _ in widget.fields) TextEditingController()];

  @override
  void dispose() {
    for (final c in _own) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final t = IosTypography.of(context);
    final text = t.body.copyWith(fontWeight: FontWeight.w500);
    // Kit "_Text Field Background": Fills/Secondary (Light), Fills/Tertiary (Dark), corner 26.
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(26),
      child: ColoredBox(
        color: theme.isDark ? c.fillTertiary : c.fillSecondary,
        child: Column(
          children: [
            for (var i = 0; i < widget.fields.length; i++)
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  // A separator between fields, inset 16 like the text.
                  decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.separator))),
                  child: Container(
                    height: 52,
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      textField: true,
                      label: widget.fields[i].semanticLabel ?? widget.fields[i].placeholder,
                      child: CupertinoTextField.borderless(
                        controller: widget.fields[i].controller ?? _own[i],
                        placeholder: widget.fields[i].placeholder,
                        placeholderStyle: text.copyWith(color: c.labelTertiary),
                        style: text,
                        cursorColor: theme.accentColor,
                        obscureText: widget.fields[i].obscureText,
                        keyboardType: widget.fields[i].keyboardType,
                        autofocus: widget.autofocus && i == 0,
                        padding: EdgeInsets.zero,
                        textInputAction: i == widget.fields.length - 1 ? TextInputAction.done : TextInputAction.next,
                        onSubmitted: (_) => i == widget.fields.length - 1 ? widget.onSubmit() : FocusScope.of(context).nextFocus(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows an [IosAlert] over a dimmed page (kit "Overlay - Alerts") and returns the pressed action
/// (null if the route was popped another way). A tap outside does nothing; Esc presses Cancel.
///
///     final name = TextEditingController(text: 'Trip to Rome');
///     final action = await showIosAlert(context,
///       title: 'Rename Album',
///       textFields: [IosAlertTextField(placeholder: 'Name', controller: name)],
///       actions: [
///         const IosAlertAction(label: 'Cancel', role: IosAlertActionRole.cancel),
///         IosAlertAction(label: 'Save', role: IosAlertActionRole.defaultAction, onPressed: () => rename(name.text)),
///       ],
///     );
Future<IosAlertAction?> showIosAlert(
  BuildContext context, {
  required String title,
  String? message,
  required List<IosAlertAction> actions,
  List<IosAlertTextField> textFields = const [],
  IosAlertLayout layout = IosAlertLayout.auto,
}) {
  final theme = AppleTheme.of(context);
  return showGeneralDialog<IosAlertAction>(
    context: context,
    barrierDismissible: false,
    barrierLabel: title,
    barrierColor: presentationAlertDim(theme),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondary) {
      IosAlertAction wrap(IosAlertAction a) => IosAlertAction(
            label: a.label,
            role: a.role,
            enabled: a.enabled,
            onPressed: () {
              Navigator.of(context).pop(a);
              a.onPressed?.call();
            },
          );
      final cancel = actions.where((a) => a.role == IosAlertActionRole.cancel);
      return SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: Shortcuts(
              shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): DismissIntent()},
              child: Actions(
                actions: {
                  DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
                    if (cancel.isNotEmpty) wrap(cancel.first).onPressed!();
                    return null;
                  }),
                },
                child: Focus(
                  autofocus: textFields.isEmpty,
                  child: IosAlert(
                    title: title,
                    message: message,
                    actions: [for (final a in actions) wrap(a)],
                    textFields: textFields,
                    layout: layout,
                    autofocus: textFields.isNotEmpty,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondary, child) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final curved = CurvedAnimation(parent: animation, curve: const Cubic(0.32, 0.72, 0, 1));
      return FadeTransition(
        opacity: animation,
        child: reduceMotion ? child : ScaleTransition(scale: Tween(begin: 1.12, end: 1.0).animate(curved), child: child),
      );
    },
  );
}
