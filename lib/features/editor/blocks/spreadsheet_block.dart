/// SpreadsheetBlock — AppFlowy embed wrapping a WorkbookData with import/export hooks.
library;

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../ui/colors.dart';
import '../../spreadsheet/sheet_data.dart';
import '../../spreadsheet/spreadsheet_widget.dart';
import '../../spreadsheet/xlsx_parser.dart';

class SpreadsheetBlockKeys {
  const SpreadsheetBlockKeys._();
  static const String type = 'spreadsheet';
  static const String workbook = 'workbook';
}

afe.Node spreadsheetNode({WorkbookData? workbook}) => afe.Node(
      type: SpreadsheetBlockKeys.type,
      attributes: {
        SpreadsheetBlockKeys.workbook:
            (workbook ?? WorkbookData.blank()).toMap(),
      },
    );

class SpreadsheetBlockComponentBuilder extends afe.BlockComponentBuilder {
  SpreadsheetBlockComponentBuilder({super.configuration});

  @override
  afe.BlockComponentWidget build(afe.BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return SpreadsheetBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
    );
  }

  @override
  bool validate(afe.Node node) =>
      node.attributes[SpreadsheetBlockKeys.workbook] is Map;
}

class SpreadsheetBlockComponentWidget extends afe.BlockComponentStatefulWidget {
  const SpreadsheetBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const afe.BlockComponentConfiguration(),
  });

  @override
  State<SpreadsheetBlockComponentWidget> createState() =>
      _SpreadsheetBlockComponentWidgetState();
}

class _SpreadsheetBlockComponentWidgetState
    extends State<SpreadsheetBlockComponentWidget> {
  late WorkbookData _workbook;

  @override
  void initState() {
    super.initState();
    _workbook = _parse();
  }

  @override
  void didUpdateWidget(covariant SpreadsheetBlockComponentWidget old) {
    super.didUpdateWidget(old);
    _workbook = _parse();
  }

  WorkbookData _parse() {
    final raw = widget.node.attributes[SpreadsheetBlockKeys.workbook];
    if (raw is Map) {
      return WorkbookData.fromMap(Map<String, dynamic>.from(raw));
    }
    return WorkbookData.blank();
  }

  Future<void> _persist(WorkbookData wb) async {
    setState(() => _workbook = wb);
    final editorState = context.read<afe.EditorState>();
    final tx = editorState.transaction
      ..updateNode(widget.node, {SpreadsheetBlockKeys.workbook: wb.toMap()});
    await editorState.apply(tx);
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes ??
        (kIsWeb ? null : await File(result.files.first.path!).readAsBytes());
    if (bytes == null) return;
    try {
      final imported = XlsxParser.decode(bytes);
      await _persist(imported);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _export() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('xlsx export from web not yet implemented'),
      ));
      return;
    }
    try {
      final bytes = XlsxParser.encode(_workbook);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export to xlsx',
        fileName: '${_workbook.sheets.first.name}.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Spreadsheet',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Import .xlsx',
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    onPressed: _import,
                  ),
                  IconButton(
                    tooltip: 'Export .xlsx',
                    icon: const Icon(Icons.download_outlined, size: 16),
                    onPressed: _export,
                  ),
                ],
              ),
            ),
            SpreadsheetWidget(
              workbook: _workbook,
              onChanged: _persist,
            ),
          ],
        ),
      ),
    );
  }
}

afe.SelectionMenuItem spreadsheetSelectionMenuItem = afe.SelectionMenuItem.node(
  getName: () => 'Spreadsheet',
  iconData: Icons.grid_on_outlined,
  keywords: const ['sheet', 'spreadsheet', 'xlsx', 'table', 'grid'],
  nodeBuilder: (editorState, _) => spreadsheetNode(),
  replace: (editorState, node) =>
      node.delta?.toPlainText().isEmpty ?? false,
);
