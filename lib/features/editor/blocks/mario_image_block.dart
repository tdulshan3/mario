/// MarioImageBlock — drop-in image block with an inline OCR shadow panel.
///
/// Replaces the stock AppFlowy image builder. Trades the resizable image's
/// drag-handles + alignment menu for a lighter wrapper that runs OCR through
/// [OcrService] and shows the detected lines as click-to-insert chips.
library;

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/services/ocr_service.dart';
import '../../../ui/colors.dart';
import '_safe_transaction.dart';

class MarioImageKeys {
  const MarioImageKeys._();
  static const String type = 'image';
  static const String url = 'url';
  static const String width = 'width';
  static const String ocrLines = 'ocr_lines';
  static const String ocrDismissed = 'ocr_dismissed';
}

class MarioImageBlockBuilder extends afe.BlockComponentBuilder {
  MarioImageBlockBuilder({super.configuration});

  @override
  afe.BlockComponentWidget build(afe.BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MarioImageBlockWidget(
      key: node.key,
      node: node,
      configuration: configuration,
    );
  }

  @override
  bool validate(afe.Node node) =>
      node.attributes[MarioImageKeys.url] is String;
}

class MarioImageBlockWidget extends afe.BlockComponentStatefulWidget {
  const MarioImageBlockWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const afe.BlockComponentConfiguration(),
  });

  @override
  State<MarioImageBlockWidget> createState() => _MarioImageBlockWidgetState();
}

class _MarioImageBlockWidgetState extends State<MarioImageBlockWidget> {
  bool _ocrRunning = false;

  String get _src =>
      (widget.node.attributes[MarioImageKeys.url] as String?) ?? '';

  List<String> get _ocrLines {
    final raw = widget.node.attributes[MarioImageKeys.ocrLines];
    if (raw is List) return raw.whereType<String>().toList(growable: false);
    return const [];
  }

  bool get _dismissed =>
      (widget.node.attributes[MarioImageKeys.ocrDismissed] as bool?) ?? false;

  bool get _ocrAlreadyKnown =>
      widget.node.attributes.containsKey(MarioImageKeys.ocrLines);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunOcr());
  }

  Future<void> _maybeRunOcr() async {
    if (!mounted) return;
    if (_ocrAlreadyKnown || _ocrRunning) return;
    final ocr = GetIt.I<OcrService>();
    if (!ocr.isAvailable) return;
    final src = _src;
    if (src.isEmpty) return;
    if (!_isLocalFile(src)) return;

    setState(() => _ocrRunning = true);
    List<String> lines = const [];
    try {
      lines = await ocr.extractText(src);
    } catch (_) {}
    if (!mounted) return;

    final editorState = context.read<afe.EditorState>();
    await safeApply(editorState, (tx) {
      tx.updateNode(widget.node, {
        MarioImageKeys.ocrLines: lines,
        MarioImageKeys.ocrDismissed: false,
      });
    });
    if (!mounted) return;
    setState(() => _ocrRunning = false);
  }

  Future<void> _dismiss() async {
    final editorState = context.read<afe.EditorState>();
    await safeApply(editorState, (tx) {
      tx.updateNode(widget.node, {MarioImageKeys.ocrDismissed: true});
    });
  }

  Future<void> _insertLine(String line) async {
    final editorState = context.read<afe.EditorState>();
    final selection = editorState.selection;
    if (selection != null && selection.isCollapsed) {
      final node = editorState.getNodeAtPath(selection.end.path);
      final delta = node?.delta;
      if (node != null && delta != null) {
        await safeApply(editorState, (tx) {
          tx.insertText(node, selection.end.offset, line);
        });
        return;
      }
    }
    // Fallback: append a new paragraph after the image.
    await safeApply(editorState, (tx) {
      tx.insertNode(widget.node.path.next, _paragraphFrom(line));
    });
  }

  bool _isLocalFile(String src) {
    if (kIsWeb) return false;
    final uri = Uri.tryParse(src);
    if (uri == null) return false;
    if (uri.scheme.isEmpty || uri.scheme == 'file') return File(src).existsSync();
    return false;
  }

  Widget _buildImage() {
    final src = _src;
    if (src.isEmpty) return const SizedBox.shrink();
    if (_isLocalFile(src)) {
      return Image.file(File(src), fit: BoxFit.contain);
    }
    return Image.network(src, fit: BoxFit.contain);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _buildImage(),
          ),
          if (_ocrRunning)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Reading text from image…',
                    style: GoogleFonts.inter(fontSize: 11, color: muted),
                  ),
                ],
              ),
            )
          else if (!_dismissed && _ocrLines.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: MarioColors.primary
                    .withValues(alpha: isDark ? 0.08 : 0.18),
                border: Border(
                    left: BorderSide(color: MarioColors.primary, width: 3)),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Detected text (${_ocrLines.length}) — tap to insert',
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: muted),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss',
                          icon: const Icon(Icons.close, size: 14),
                          onPressed: _dismiss,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              maxHeight: 24, maxWidth: 24),
                        ),
                      ],
                    ),
                  ),
                  for (final line in _ocrLines)
                    InkWell(
                      onTap: () => _insertLine(line),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Text(
                          line,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: muted.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ),
                  Container(
                      height: 1,
                      color: border.withValues(alpha: 0.4),
                      margin: const EdgeInsets.symmetric(vertical: 4)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

afe.Node _paragraphFrom(String text) => afe.paragraphNode(text: text);
