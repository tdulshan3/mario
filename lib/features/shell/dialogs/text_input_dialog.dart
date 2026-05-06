/// Single-field text input dialog (used for sections and pages).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TextInputDialog extends StatefulWidget {
  const TextInputDialog({
    super.key,
    required this.title,
    required this.label,
    required this.submitLabel,
    this.initialValue = '',
  });

  final String title;
  final String label;
  final String submitLabel;
  final String initialValue;

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String submitLabel,
  String initialValue = '',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: title,
        label: label,
        submitLabel: submitLabel,
        initialValue: initialValue,
      ),
    );

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
      content: Text(message, style: GoogleFonts.inter()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: destructive
              ? ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Colors.white,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
