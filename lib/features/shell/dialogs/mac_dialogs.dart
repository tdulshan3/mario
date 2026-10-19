/// The macOS versions of the shell's three dialogs: a sheet with one text
/// field, a sheet with a name and a label colour, and a confirmation alert.
///
/// `showTextInputDialog`, `showNotebookDialog` and `showConfirmDialog` route
/// here on the desktop builds, so every call site gets the macOS look without
/// knowing about it.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/widgets.dart';

import 'notebook_dialog.dart' show NotebookDialogResult;

/// The label colours, by name, in [MarioColors.labelPalette] order.
const List<String> kLabelColorNames = [
  'Red',
  'Orange',
  'Yellow',
  'Green',
  'Teal',
  'Purple',
];

/// A sheet with one text field. Returns the trimmed text, or null.
Future<String?> showMacTextInputSheet(
  BuildContext context, {
  required String title,
  required String label,
  required String submitLabel,
  String initialValue = '',
}) =>
    showMacSheet<String>(
      context: context,
      builder: (_) => _TextInputSheet(
        title: title,
        label: label,
        submitLabel: submitLabel,
        initialValue: initialValue,
      ),
    );

class _TextInputSheet extends StatefulWidget {
  const _TextInputSheet({
    required this.title,
    required this.label,
    required this.submitLabel,
    required this.initialValue,
  });

  final String title;
  final String label;
  final String submitLabel;
  final String initialValue;

  @override
  State<_TextInputSheet> createState() => _TextInputSheetState();
}

class _TextInputSheetState extends State<_TextInputSheet> {
  late final _controller = TextEditingController(text: widget.initialValue)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return MacSheet(
      title: widget.title,
      width: 380,
      onSubmit: _submit,
      onCancel: _cancel,
      actions: [
        MacButton(label: 'Cancel', onPressed: _cancel),
        MacButton(
          label: widget.submitLabel,
          style: MacButtonStyle.prominent,
          onPressed: _valid ? _submit : null,
        ),
      ],
      child: MacForm(
        columns: true,
        children: [
          MacFormRow(
            label: '${widget.label}:',
            child: MacTextField(
              controller: _controller,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              semanticLabel: widget.label,
            ),
          ),
        ],
      ),
    );
  }
}

/// A sheet for a notebook or section: its name and its label colour.
Future<NotebookDialogResult?> showMacNotebookSheet(
  BuildContext context, {
  required String title,
  required String submitLabel,
  String initialName = '',
  int initialColorIndex = 2,
}) =>
    showMacSheet<NotebookDialogResult>(
      context: context,
      builder: (_) => _NotebookSheet(
        title: title,
        submitLabel: submitLabel,
        initialName: initialName,
        initialColorIndex: initialColorIndex,
      ),
    );

class _NotebookSheet extends StatefulWidget {
  const _NotebookSheet({
    required this.title,
    required this.submitLabel,
    required this.initialName,
    required this.initialColorIndex,
  });

  final String title;
  final String submitLabel;
  final String initialName;
  final int initialColorIndex;

  @override
  State<_NotebookSheet> createState() => _NotebookSheetState();
}

class _NotebookSheetState extends State<_NotebookSheet> {
  late final _name = TextEditingController(text: widget.initialName)
    ..addListener(() => setState(() {}));
  late int _color =
      widget.initialColorIndex.clamp(0, kLabelColorNames.length - 1);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(NotebookDialogResult(_name.text.trim(), _color));
  }

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return MacSheet(
      title: widget.title,
      width: 380,
      onSubmit: _submit,
      onCancel: _cancel,
      actions: [
        MacButton(label: 'Cancel', onPressed: _cancel),
        MacButton(
          label: widget.submitLabel,
          style: MacButtonStyle.prominent,
          onPressed: _valid ? _submit : null,
        ),
      ],
      child: MacForm(
        columns: true,
        children: [
          MacFormRow(
            label: 'Name:',
            child: MacTextField(
              controller: _name,
              autofocus: true,
              placeholder: 'My notebook',
              onSubmitted: (_) => _submit(),
              semanticLabel: 'Name',
            ),
          ),
          MacFormRow(
            label: 'Color:',
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: MacPopUpButton<int>(
                options: [for (var i = 0; i < kLabelColorNames.length; i++) i],
                value: _color,
                labelOf: (i) => kLabelColorNames[i],
                onChanged: (i) => setState(() => _color = i),
                semanticLabel: 'Color',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A confirmation alert. True when the confirming button was chosen.
Future<bool> showMacConfirmAlert(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final choice = await showMacAlert(
    context,
    title: title,
    message: message,
    buttons: [
      MacAlertButton(
        confirmLabel,
        role: destructive
            ? MacAlertButtonRole.destructive
            : MacAlertButtonRole.defaultAction,
      ),
      const MacAlertButton('Cancel', role: MacAlertButtonRole.cancel),
    ],
  );
  return choice == confirmLabel;
}
