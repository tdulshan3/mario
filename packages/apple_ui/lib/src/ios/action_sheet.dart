import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/ios_tokens.dart';
import '../core/theme.dart';
import '_presentation_support.dart';

/// Role of an action sheet action.
enum IosActionSheetActionRole {
  none,

  /// Red label: deletes or removes something.
  destructive,

  /// The way out. Always add one: it shows only when the sheet sits at the bottom of an iPhone; next to its button
  /// (and on iPad) it is hidden and a tap outside cancels.
  cancel,
}

/// One button of an [IosActionSheet].
@immutable
class IosActionSheetAction {
  const IosActionSheetAction({required this.label, this.role = IosActionSheetActionRole.none, this.icon, this.onPressed, this.enabled = true});
  final String label;
  final IosActionSheetActionRole role;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool enabled;
}

/// An iOS action sheet (kit page "Action Sheets"): optional title and message, then a column of 48-tall capsule
/// actions on the Thick blur material. Show it with [showIosActionSheet]; this widget alone is the static panel (for
/// mockups).
/// [anchored] = it grows out of a button (300 wide, corners 34, Cancel hidden); otherwise it is the bottom card of
/// an iPhone (full width minus 6, corners 34 / 58, Cancel shown).
///
///     IosActionSheet(
///       title: 'Delete this photo?',
///       actions: [
///         IosActionSheetAction(label: 'Delete Photo', role: IosActionSheetActionRole.destructive, onPressed: delete),
///         const IosActionSheetAction(label: 'Cancel', role: IosActionSheetActionRole.cancel),
///       ],
///     )
class IosActionSheet extends StatelessWidget {
  const IosActionSheet({super.key, this.title, this.message, required this.actions, this.anchored = true, this.sizeClass});

  final String? title;
  final String? message;
  final List<IosActionSheetAction> actions;
  final bool anchored;

  /// Force iPhone (compact) or iPad (regular) looks. Null = from the screen size.
  final IosSizeClass? sizeClass;

  @override
  Widget build(BuildContext context) {
    final regular = sizeClass != null ? sizeClass == IosSizeClass.regular : IosLayout.isRegular(context);
    final popover = anchored || regular;
    final visible = [
      ...actions.where((a) => a.role != IosActionSheetActionRole.cancel),
      if (!popover) ...actions.where((a) => a.role == IosActionSheetActionRole.cancel),
    ];
    final dims = regular ? IosDimensions.ipad : IosDimensions.iphone;
    Widget panel = PresentationGlass(
      radius: popover
          ? BorderRadius.circular(34)
          : BorderRadius.vertical(top: const Radius.circular(34), bottom: Radius.circular(dims.sheetBottomRadius)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || message != null) PresentationTitleBlock(title: title, message: message),
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              PresentationActionButton(
                label: visible[i].label,
                icon: visible[i].icon,
                look: visible[i].role == IosActionSheetActionRole.destructive ? PresentationActionLook.destructive : PresentationActionLook.plain,
                onPressed: visible[i].enabled ? (visible[i].onPressed ?? () {}) : null,
              ),
            ],
          ],
        ),
      ),
    );
    if (popover) panel = SizedBox(width: 300, child: panel);
    return Semantics(scopesRoute: true, namesRoute: true, explicitChildNodes: true, label: title ?? 'Actions', child: panel);
  }
}

/// Shows an [IosActionSheet] and returns the pressed action (the Cancel action for a tap outside or Esc).
/// [anchorKey] = the key of the button that opened it: on iPhone the sheet grows out of it (kit), on iPad it sits
/// next to it like a popover (no dimming). Without it: a bottom card on iPhone, centred on iPad.
///
///     final moreKey = GlobalKey();
///     IosButton(key: moreKey, icon: AppleIcons.ellipsis, semanticLabel: 'More', style: IosButtonStyle.glass,
///         onPressed: () => showIosActionSheet(context, anchorKey: moreKey, title: 'Delete this photo?', actions: [
///               IosActionSheetAction(label: 'Delete Photo', role: IosActionSheetActionRole.destructive, onPressed: delete),
///               const IosActionSheetAction(label: 'Cancel', role: IosActionSheetActionRole.cancel),
///             ]))
Future<IosActionSheetAction?> showIosActionSheet(
  BuildContext context, {
  String? title,
  String? message,
  required List<IosActionSheetAction> actions,
  GlobalKey? anchorKey,
  /// Present on the app's root navigator (default), so it covers the tab bar even from inside a tab's own stack.
  bool useRootNavigator = true,
}) {
  final theme = AppleTheme.of(context);
  final regular = IosLayout.isRegular(context);
  final source = presentationRectOf(anchorKey);
  final cancel = actions.where((a) => a.role == IosActionSheetActionRole.cancel);
  return Navigator.of(context, rootNavigator: useRootNavigator).push(_IosActionSheetRoute(
    title: title,
    message: message,
    actions: actions,
    source: source,
    dim: regular ? const Color(0x00000000) : presentationAlertDim(theme),
    cancel: cancel.isEmpty ? null : cancel.first,
  ));
}

class _IosActionSheetRoute extends PopupRoute<IosActionSheetAction> {
  _IosActionSheetRoute({this.title, this.message, required this.actions, this.source, required this.dim, this.cancel});
  final String? title;
  final String? message;
  final List<IosActionSheetAction> actions;
  final Rect? source;
  final Color dim;
  final IosActionSheetAction? cancel;

  @override
  Color? get barrierColor => dim;
  @override
  bool get barrierDismissible => false; // a tap outside presses Cancel (handled below)
  @override
  String? get barrierLabel => 'Cancel';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  void _press(BuildContext context, IosActionSheetAction? a) {
    Navigator.of(context).pop(a);
    a?.onPressed?.call();
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final regular = IosLayout.isRegular(context);
    final wrapped = [
      for (final a in actions)
        IosActionSheetAction(label: a.label, role: a.role, icon: a.icon, enabled: a.enabled, onPressed: () => _press(context, a)),
    ];
    final sheet = IosActionSheet(title: title, message: message, actions: wrapped, anchored: source != null);
    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): DismissIntent()},
      child: Actions(
        actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => _press(context, cancel))},
        child: Focus(
          autofocus: true,
          child: Stack(children: [
            // A tap outside the sheet = Cancel.
            Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _press(context, cancel))),
            if (source != null)
              CustomSingleChildLayout(delegate: _AnchorLayout(source!, regular), child: sheet)
            else if (regular)
              Center(child: sheet)
            else
              Positioned(left: 6, right: 6, bottom: 6, child: sheet),
          ]),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final curved = CurvedAnimation(parent: animation, curve: const Cubic(0.32, 0.72, 0, 1));
    if (reduceMotion) return FadeTransition(opacity: animation, child: child);
    final regular = IosLayout.isRegular(context);
    final screen = MediaQuery.sizeOf(context);
    // Grow out of the button (or up from the bottom edge).
    final origin = source == null
        ? (regular ? Alignment.center : Alignment.bottomCenter)
        : Alignment((source!.center.dx / screen.width) * 2 - 1, (source!.center.dy / screen.height) * 2 - 1);
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(alignment: origin, scale: Tween(begin: 0.6, end: 1.0).animate(curved), child: child),
    );
  }
}

class _AnchorLayout extends SingleChildLayoutDelegate {
  _AnchorLayout(this.source, this.regular);
  final Rect source;
  final bool regular;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      presentationPlacement(source: source, size: childSize, screen: size, regular: regular);

  @override
  bool shouldRelayout(_AnchorLayout old) => old.source != source || old.regular != regular;
}
