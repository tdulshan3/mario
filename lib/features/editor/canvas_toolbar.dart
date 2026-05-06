/// CanvasToolbar — OneNote-style persistent formatting toolbar above the editor.
///
/// Surfaces the rich-text knobs the spec calls for: bold/italic/underline/
/// strikethrough/code, font size, text color, highlight color, and quick
/// inserts for image / drawing / spreadsheet / math.
library;

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/colors.dart';
import 'blocks/drawing_block.dart';
import 'blocks/mario_image_block.dart';
import 'blocks/math_block.dart';
import 'blocks/spreadsheet_block.dart';

const _fontSizes = [10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 36.0, 48.0];

const _palette = <Color>[
  Color(0xFF1A1A1A),
  Color(0xFF6B6B6B),
  Color(0xFFE57373),
  Color(0xFFFFB74D),
  Color(0xFFFFDE7A),
  Color(0xFF81C784),
  Color(0xFF4DB6AC),
  Color(0xFF64B5F6),
  Color(0xFFBA68C8),
  Color(0xFFFFFFFF),
];

class CanvasToolbar extends StatefulWidget {
  const CanvasToolbar({super.key, required this.editorState});

  final afe.EditorState editorState;

  @override
  State<CanvasToolbar> createState() => _CanvasToolbarState();
}

class _CanvasToolbarState extends State<CanvasToolbar> {
  @override
  void initState() {
    super.initState();
    widget.editorState.selectionNotifier.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    widget.editorState.selectionNotifier.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// True when every text run in the current selection has the given key set.
  bool _isAttributeOn(String key) {
    final selection = widget.editorState.selection;
    if (selection == null) return false;
    final nodes = widget.editorState.getNodesInSelection(selection);
    if (nodes.isEmpty) return false;
    return nodes.allSatisfyInSelection(selection, (delta) {
      return delta.everyAttributes((attrs) => attrs[key] == true);
    });
  }

  Future<void> _toggle(String key) =>
      widget.editorState.toggleAttribute(key);

  Future<void> _formatColor(String key, Color? color) async {
    final selection = widget.editorState.selection;
    if (selection == null || selection.isCollapsed) return;
    await widget.editorState.formatDelta(
      selection,
      {key: color == null ? null : '0x${color.toARGB32().toRadixString(16)}'},
    );
  }

  Future<void> _setFontSize(double size) async {
    final selection = widget.editorState.selection;
    if (selection == null || selection.isCollapsed) return;
    await widget.editorState.formatDelta(
      selection,
      {afe.AppFlowyRichTextKeys.fontSize: size},
    );
  }

  Future<void> _insertNode(afe.Node node) async {
    if (widget.editorState.isDisposed) return;
    final selection = widget.editorState.selection;
    final path = selection?.end.path ?? widget.editorState.document.root.children.last.path;
    final tx = widget.editorState.transaction..insertNode(path.next, node);
    await widget.editorState.apply(tx);
  }

  Future<void> _pickAndInsertImage() async {
    if (kIsWeb) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    if (!await File(path).exists()) return;
    await _insertNode(afe.Node(
      type: MarioImageKeys.type,
      attributes: {MarioImageKeys.url: path},
    ));
  }

  Future<void> _insertTable() async {
    // AppFlowy's standard table block ships in stableBlockComponentBuilderMap.
    final tableNode = afe.Node(
      type: 'table',
      attributes: const {
        'colsLen': 3,
        'rowsLen': 3,
        'colDefaultWidth': 80.0,
        'rowDefaultHeight': 40.0,
      },
    );
    await _insertNode(tableNode);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;
    final hasSelection = widget.editorState.selection != null &&
        !widget.editorState.selection!.isCollapsed;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToggleButton(
              icon: Icons.format_bold,
              tooltip: 'Bold (Ctrl+B)',
              active: _isAttributeOn(afe.AppFlowyRichTextKeys.bold),
              onPressed: () => _toggle(afe.AppFlowyRichTextKeys.bold),
            ),
            _ToggleButton(
              icon: Icons.format_italic,
              tooltip: 'Italic (Ctrl+I)',
              active: _isAttributeOn(afe.AppFlowyRichTextKeys.italic),
              onPressed: () => _toggle(afe.AppFlowyRichTextKeys.italic),
            ),
            _ToggleButton(
              icon: Icons.format_underline,
              tooltip: 'Underline (Ctrl+U)',
              active: _isAttributeOn(afe.AppFlowyRichTextKeys.underline),
              onPressed: () => _toggle(afe.AppFlowyRichTextKeys.underline),
            ),
            _ToggleButton(
              icon: Icons.format_strikethrough,
              tooltip: 'Strikethrough',
              active: _isAttributeOn(afe.AppFlowyRichTextKeys.strikethrough),
              onPressed: () =>
                  _toggle(afe.AppFlowyRichTextKeys.strikethrough),
            ),
            _ToggleButton(
              icon: Icons.code,
              tooltip: 'Inline code',
              active: _isAttributeOn(afe.AppFlowyRichTextKeys.code),
              onPressed: () => _toggle(afe.AppFlowyRichTextKeys.code),
            ),
            const _Divider(),
            _FontSizeDropdown(
              enabled: hasSelection,
              onChanged: _setFontSize,
            ),
            const _Divider(),
            _ColorButton(
              icon: Icons.format_color_text,
              tooltip: 'Text color',
              enabled: hasSelection,
              onPicked: (c) =>
                  _formatColor(afe.AppFlowyRichTextKeys.textColor, c),
            ),
            _ColorButton(
              icon: Icons.format_color_fill,
              tooltip: 'Highlight',
              enabled: hasSelection,
              defaultColor: MarioColors.primary,
              onPicked: (c) =>
                  _formatColor(afe.AppFlowyRichTextKeys.backgroundColor, c),
            ),
            const _Divider(),
            _IconAction(
              icon: Icons.image_outlined,
              tooltip: 'Insert image',
              onPressed: _pickAndInsertImage,
            ),
            _IconAction(
              icon: Icons.table_chart_outlined,
              tooltip: 'Insert table',
              onPressed: _insertTable,
            ),
            _IconAction(
              icon: Icons.draw_outlined,
              tooltip: 'Insert drawing',
              onPressed: () => _insertNode(drawingNode()),
            ),
            _IconAction(
              icon: Icons.grid_on_outlined,
              tooltip: 'Insert spreadsheet',
              onPressed: () => _insertNode(spreadsheetNode()),
            ),
            _IconAction(
              icon: Icons.functions,
              tooltip: 'Insert math equation',
              onPressed: () => _insertNode(mathEquationNode()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? MarioColors.primary.withValues(alpha: isDark ? 0.18 : 0.32)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        visualDensity: VisualDensity.compact,
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 1,
      height: 18,
      color: isDark ? MarioColors.borderDark : MarioColors.border,
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

class _FontSizeDropdown extends StatelessWidget {
  const _FontSizeDropdown({required this.enabled, required this.onChanged});
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: DropdownButton<double>(
        isDense: true,
        underline: const SizedBox.shrink(),
        hint: Text('Size',
            style: GoogleFonts.inter(fontSize: 11)),
        items: [
          for (final s in _fontSizes)
            DropdownMenuItem(
              value: s,
              child: Text(s.toStringAsFixed(0),
                  style: GoogleFonts.inter(fontSize: 12)),
            ),
        ],
        onChanged: enabled ? (v) {
          if (v != null) onChanged(v);
        } : null,
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPicked,
    this.defaultColor,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final ValueChanged<Color?> onPicked;
  final Color? defaultColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PopupMenuButton<Color?>(
        enabled: enabled,
        position: PopupMenuPosition.under,
        tooltip: '',
        offset: const Offset(0, 4),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: null,
            child: Row(children: [
              Icon(Icons.format_color_reset,
                  size: 14, color: Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 8),
              const Text('None'),
            ]),
          ),
          PopupMenuItem(
            enabled: false,
            height: 8,
            child: Container(),
          ),
          ..._chunked(_palette, 5).map(
            (row) => PopupMenuItem(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in row)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        onPicked(c);
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: c,
                          border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                              width: 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: enabled
                ? (defaultColor ?? Theme.of(context).colorScheme.onSurface)
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  static Iterable<List<T>> _chunked<T>(List<T> list, int n) sync* {
    for (var i = 0; i < list.length; i += n) {
      yield list.sublist(i, i + n > list.length ? list.length : i + n);
    }
  }
}
