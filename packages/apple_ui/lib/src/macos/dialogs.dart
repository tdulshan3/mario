import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '../core/typography.dart';
import '_panel_support.dart';

/// One labelled row of a [MacOpenSavePanel]: a right-aligned label ending with ":" and its control.
///
///     MacOpenSavePanelField(label: 'Save As:', child: MacTextField(value: name, onChanged: setName, autofocus: true))
@immutable
class MacOpenSavePanelField {
  const MacOpenSavePanelField({required this.label, required this.child});

  /// "Save As:", "Tags:", "File Format:", "Where:" (ends with a colon).
  final String label;

  /// The control: a text field, a pop-up button, or a Row of a pop-up + disclosure button (8 px apart).
  final Widget child;
}

final PanelShapeBuilder _panelShape = roundedPanelShape(16);
const _panelShadows = [
  PanelShadow(0, 0, 1, 0, Color(0xCC000000)), // 0 0 1 px black 80 %
  PanelShadow(0, 18, 54, 0, Color(0x4D000000)), // 0 18 54 px black 30 %
];

/// A save (or open) panel MOCKUP (kit page "Dialogs": "Small" = compact, "Large" = [expanded] with a sidebar and
/// a file browser). Native apps never draw this: they call the system panel (`file_selector` / `NSSavePanel`).
/// Use it for prototypes and web/desktop apps that need to show a save step. Show it attached to the window with
/// `showMacSheet`.
///
///     MacOpenSavePanel(
///       title: 'Do you want to keep this new document “Untitled”?',
///       message: 'You can choose to save your changes, or delete this document immediately.',
///       fields: [
///         MacOpenSavePanelField(label: 'Save As:', child: MacTextField(value: name, onChanged: setName, autofocus: true)),
///         MacOpenSavePanelField(label: 'Tags:', child: MacTextField(value: tags, onChanged: setTags)),
///       ],
///       leading: [MacButton(label: 'Delete', style: MacButtonStyle.destructive, onPressed: delete)],
///       actions: [
///         MacButton(label: 'Cancel', onPressed: cancel),
///         MacButton(label: 'Save', style: MacButtonStyle.prominent, onPressed: save),
///       ],
///       onSubmit: save,
///       onCancel: cancel,
///     )
///
/// Compact: 390 px wide, fields padded 20 · 40 · 10, labels 81 px + 6 px gap + 223 px controls, rows 12 px apart.
/// Expanded: 1000 × 448, a 210 px [sidebar], fields on three columns (229 px controls), a browser toolbar row
/// ([navigation] · [location] · [search]) and the [browser] (file list) between hairlines. Buttons: [leading] at
/// the bottom left, [actions] at the bottom right (each at least 74 px wide). Return = [onSubmit],
/// Escape / ⌘. = [onCancel]. No hover effects.
class MacOpenSavePanel extends StatelessWidget {
  const MacOpenSavePanel({
    super.key,
    this.title,
    this.message,
    required this.fields,
    this.actions = const [],
    this.leading = const [],
    this.expanded = false,
    this.sidebar,
    this.navigation,
    this.location,
    this.search,
    this.browser,
    this.onSubmit,
    this.onCancel,
    this.semanticLabel,
  });

  /// Bold 13 px question above the fields (compact panel only; optional).
  final String? title;

  /// Regular 11 px text under the title (optional).
  final String? message;
  final List<MacOpenSavePanelField> fields;

  /// Bottom-right buttons: Cancel, then the default button ("Save", "Open", "Choose").
  final List<Widget> actions;

  /// Bottom-left buttons: "New Folder", a destructive "Delete".
  final List<Widget> leading;

  /// The kit "Large" panel: sidebar + file browser.
  final bool expanded;

  /// Expanded: the 210 px sidebar (Recents, Favorites, Locations, Tags), for example a small `MacSidebar`.
  final Widget? sidebar;

  /// Expanded: back/forward + view options, at the left of the browser toolbar row.
  final Widget? navigation;

  /// Expanded: the location pop-up (+ disclosure button), in the control column.
  final Widget? location;

  /// Expanded: the search field at the right.
  final Widget? search;

  /// Expanded: the file list (for example a `MacTable` with Name, Date Modified, Size, Kind).
  final Widget? browser;

  final VoidCallback? onSubmit;
  final VoidCallback? onCancel;
  final String? semanticLabel;

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
    final labelStyle = panelText(appleFont(size: 13), size: 13, lineHeight: 24, weight: FontWeight.w500, color: c.labelSecondary);

    Widget label(String text) => Text(text, style: labelStyle, textAlign: TextAlign.right, maxLines: 1, softWrap: false);

    final buttons = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Row(
        children: [
          for (var i = 0; i < leading.length; i++) ...[if (i > 0) const SizedBox(width: 8), leading[i]],
          const Spacer(),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            ConstrainedBox(constraints: const BoxConstraints(minWidth: 74), child: actions[i]),
          ],
        ],
      ),
    );

    Widget panel;
    if (!expanded) {
      final rows = <Widget>[];
      if (title != null || message != null) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 81 + 6, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Semantics(header: true, child: Text(title!, style: type.body.copyWith(fontWeight: FontWeight.w700))),
              if (title != null && message != null) const SizedBox(height: 6),
              if (message != null)
                Text(message!, style: panelText(appleFont(size: 11), size: 11, lineHeight: 14, color: c.labelPrimary)),
            ],
          ),
        ));
      }
      for (final f in fields) {
        rows.add(Row(
          children: [
            SizedBox(width: 81, child: Align(alignment: AlignmentDirectional.centerEnd, child: label(f.label))),
            const SizedBox(width: 6),
            SizedBox(width: 223, child: f.child),
          ],
        ));
      }
      panel = SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 20, 40, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 12), rows[i]],
                ],
              ),
            ),
            buttons,
          ],
        ),
      );
    } else {
      Widget threeColumns(Widget? a, Widget? b, Widget? cc, {bool labelColumn = false}) => Row(
            children: [
              Expanded(
                child: Align(
                  alignment: labelColumn ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                  child: labelColumn ? Transform.translate(offset: const Offset(1, 0), child: a) : a,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 229, child: b),
              const SizedBox(width: 8),
              Expanded(child: Align(alignment: AlignmentDirectional.centerEnd, child: cc)),
            ],
          );
      final formRows = <Widget>[
        for (final f in fields) threeColumns(label(f.label), f.child, null, labelColumn: true),
        if (navigation != null || location != null || search != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: threeColumns(navigation, location, search)),
      ];
      final main = ColoredBox(
        color: c.windowBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < formRows.length; i++) ...[if (i > 0) const SizedBox(height: 13), formRows[i]],
                ],
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.symmetric(horizontal: BorderSide(color: c.separator)),
                ),
                child: browser ?? const SizedBox.expand(),
              ),
            ),
            buttons,
          ],
        ),
      );
      panel = SizedBox(
        width: 1000,
        height: 448,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sidebar != null) SizedBox(width: 210, child: sidebar),
            Expanded(child: main),
          ],
        ),
      );
    }

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: semanticLabel ?? title ?? 'Save',
      child: FocusScope(
        autofocus: true,
        onKeyEvent: _onKey,
        child: DefaultTextStyle(
          style: type.body,
          child: PanelSurface(shape: _panelShape, fill: c.windowBg, shadows: _panelShadows, child: panel),
        ),
      ),
    );
  }
}
