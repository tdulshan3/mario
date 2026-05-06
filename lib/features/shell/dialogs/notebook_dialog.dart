/// Notebook create / rename / recolor dialog with the 6-color label palette.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../ui/colors.dart';

class NotebookDialogResult {
  final String name;
  final int colorIndex;
  const NotebookDialogResult(this.name, this.colorIndex);
}

class NotebookDialog extends StatefulWidget {
  const NotebookDialog({
    super.key,
    this.initialName = '',
    this.initialColorIndex = 2,
    required this.title,
    required this.submitLabel,
  });

  final String initialName;
  final int initialColorIndex;
  final String title;
  final String submitLabel;

  @override
  State<NotebookDialog> createState() => _NotebookDialogState();
}

class _NotebookDialogState extends State<NotebookDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  late int _colorIndex = widget.initialColorIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(NotebookDialogResult(name, _colorIndex));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'My notebook',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            Text('Color',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < MarioColors.labelPalette.length; i++)
                  _ColorDot(
                    color: MarioColors.labelPalette[i],
                    selected: i == _colorIndex,
                    onTap: () => setState(() => _colorIndex = i),
                  ),
              ],
            ),
          ],
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

class _ColorDot extends StatelessWidget {
  const _ColorDot(
      {required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? MarioColors.onSurface : Colors.transparent,
            width: 2,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.black87)
            : null,
      ),
    );
  }
}

Future<NotebookDialogResult?> showNotebookDialog(
  BuildContext context, {
  String initialName = '',
  int initialColorIndex = 2,
  required String title,
  required String submitLabel,
}) =>
    showDialog<NotebookDialogResult>(
      context: context,
      builder: (_) => NotebookDialog(
        initialName: initialName,
        initialColorIndex: initialColorIndex,
        title: title,
        submitLabel: submitLabel,
      ),
    );
