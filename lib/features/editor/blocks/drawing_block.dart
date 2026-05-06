/// DrawingBlock — AppFlowy embed wrapping the Mario drawing surface.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../../ui/colors.dart';
import '../../drawing/drawing_canvas.dart';
import '../../drawing/drawing_toolbar.dart';
import '../../drawing/stroke.dart';
import '../../drawing/stroke_painter.dart';
import '_safe_transaction.dart';

class DrawingBlockKeys {
  const DrawingBlockKeys._();
  static const String type = 'drawing';
  static const String strokes = 'strokes';
  static const String width = 'width';
  static const String height = 'height';
}

afe.Node drawingNode({
  List<Stroke> strokes = const [],
  double width = 600,
  double height = 400,
}) =>
    afe.Node(
      type: DrawingBlockKeys.type,
      attributes: {
        DrawingBlockKeys.strokes: strokesToJson(strokes),
        DrawingBlockKeys.width: width,
        DrawingBlockKeys.height: height,
      },
    );

class DrawingBlockComponentBuilder extends afe.BlockComponentBuilder {
  DrawingBlockComponentBuilder({super.configuration});

  @override
  afe.BlockComponentWidget build(afe.BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return DrawingBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
    );
  }

  @override
  bool validate(afe.Node node) =>
      node.attributes[DrawingBlockKeys.strokes] is List;
}

class DrawingBlockComponentWidget extends afe.BlockComponentStatefulWidget {
  const DrawingBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const afe.BlockComponentConfiguration(),
  });

  @override
  State<DrawingBlockComponentWidget> createState() =>
      _DrawingBlockComponentWidgetState();
}

class _DrawingBlockComponentWidgetState
    extends State<DrawingBlockComponentWidget> {
  late DrawingController _controller;
  bool _expanded = false;
  final GlobalKey _boundary = GlobalKey();

  Size get _size {
    final w = (widget.node.attributes[DrawingBlockKeys.width] as num?)
            ?.toDouble() ??
        600;
    final h = (widget.node.attributes[DrawingBlockKeys.height] as num?)
            ?.toDouble() ??
        400;
    return Size(w, h);
  }

  List<Stroke> get _persistedStrokes =>
      strokesFromJson(widget.node.attributes[DrawingBlockKeys.strokes] as List?);

  @override
  void initState() {
    super.initState();
    final initial = _persistedStrokes;
    _controller = DrawingController(initial: initial);
    _expanded = initial.isEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final editorState = context.read<afe.EditorState>();
    await safeApply(editorState, (tx) {
      tx.updateNode(widget.node, {
        DrawingBlockKeys.strokes: strokesToJson(_controller.snapshot()),
      });
    });
    if (!mounted) return;
    setState(() => _expanded = false);
  }

  Future<void> _exportPng() async {
    final boundary =
        _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();
    await _writePng(bytes);
  }

  Future<void> _writePng(Uint8List bytes) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (kIsWeb) {
      messenger?.showSnackBar(const SnackBar(
        content: Text('PNG export from web not yet implemented'),
      ));
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save drawing',
      fileName: 'mario-drawing.png',
      type: FileType.image,
      allowedExtensions: const ['png'],
    );
    if (path == null) return;
    final file = File(path);
    await file.writeAsBytes(bytes);
    messenger?.showSnackBar(SnackBar(content: Text('Saved to $path')));
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
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
            DrawingToolbar(
              controller: _controller,
              collapsed: !_expanded,
              onCollapse: _toggleExpanded,
              onExport: _exportPng,
              onSave: _save,
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: DrawingCanvas(
                    controller: _controller,
                    size: _size,
                    boundaryKey: _boundary,
                  ),
                ),
              )
            else
              _CollapsedPreview(
                strokes: _controller.snapshot(),
                size: _size,
                onTap: _toggleExpanded,
                muted: muted,
              ),
          ],
        ),
      ),
    );
  }
}

class _CollapsedPreview extends StatelessWidget {
  const _CollapsedPreview({
    required this.strokes,
    required this.size,
    required this.onTap,
    required this.muted,
  });

  final List<Stroke> strokes;
  final Size size;
  final VoidCallback onTap;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF101010) : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Container(
            width: size.width,
            height: size.height,
            color: bg,
            child: strokes.isEmpty
                ? Center(
                    child: Text('Tap to draw',
                        style: TextStyle(color: muted, fontSize: 12)),
                  )
                : FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: CustomPaint(
                        painter: StrokePainter(strokes: strokes, background: bg),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

afe.SelectionMenuItem drawingSelectionMenuItem = afe.SelectionMenuItem.node(
  getName: () => 'Drawing',
  iconData: Icons.draw_outlined,
  keywords: const ['draw', 'sketch', 'ink', 'whiteboard'],
  nodeBuilder: (editorState, _) => drawingNode(),
  replace: (editorState, node) =>
      node.delta?.toPlainText().isEmpty ?? false,
);
