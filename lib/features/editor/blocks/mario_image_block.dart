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
import 'package:flutter/services.dart';
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
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
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

class _MarioImageBlockWidgetState extends State<MarioImageBlockWidget>
    with afe.SelectableMixin, afe.BlockComponentConfigurable {
  bool _ocrRunning = false;
  final GlobalKey _imageKey = GlobalKey();
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  afe.BlockComponentConfiguration get configuration => widget.configuration;

  @override
  afe.Node get node => widget.node;

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

  /// Insert all OCR'd lines as paragraphs immediately after the image, then
  /// dismiss the panel. Single action — no per-line clicking.
  Future<void> _insertAll() async {
    final editorState = context.read<afe.EditorState>();
    final lines = _ocrLines.where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return;
    // insertNodes inserts the whole list at one path in a single op, so we
    // don't have to walk path.next ourselves — the loop version dropped all
    // but the first because each insertNode above the previous shifted the
    // expected target path.
    await safeApply(editorState, (tx) {
      tx.insertNodes(
        widget.node.path.next,
        [for (final line in lines) _paragraphFrom(line)],
      );
      tx.updateNode(widget.node, {MarioImageKeys.ocrDismissed: true});
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

    final editorState = context.read<afe.EditorState>();

    Widget content = Padding(
      key: _imageKey,
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
            Focus(
              autofocus: false,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.tab) {
                  _insertAll();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
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
                              'Detected text (${_ocrLines.length} lines)',
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: Text(
                        _ocrLines.join('\n'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.4,
                          color: muted.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    Container(
                        height: 1,
                        color: border.withValues(alpha: 0.4),
                        margin: const EdgeInsets.symmetric(horizontal: 12)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: _insertAll,
                            icon: const Icon(Icons.keyboard_tab, size: 14),
                            label: Text(
                              'Tab — Insert all',
                              style: GoogleFonts.inter(
                                  fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: MarioColors.primaryPressed,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    // Make the block selectable — the editor's Backspace/Delete handlers
    // remove a node when its block selection is active.
    content = afe.BlockSelectionContainer(
      node: widget.node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [afe.BlockSelectionType.block],
      child: content,
    );

    // Drag handle / + button on hover so the user can move (and delete) the
    // block via the same gutter affordance every other AppFlowy block has.
    if (widget.showActions && widget.actionBuilder != null) {
      content = afe.BlockComponentActionWrapper(
        node: widget.node,
        actionBuilder: widget.actionBuilder!,
        child: content,
      );
    }

    return content;
  }

  // SelectableMixin — minimal implementation that mirrors AppFlowy's stock
  // image block. Each method points the editor at our wrapped image bounds so
  // block-level selection, cursor placement, and "delete this node" all work.

  @override
  afe.Position start() => afe.Position(path: widget.node.path, offset: 0);

  @override
  afe.Position end() => afe.Position(path: widget.node.path, offset: 1);

  @override
  afe.Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  afe.CursorStyle get cursorStyle => afe.CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final box = _imageKey.currentContext?.findRenderObject();
    if (box is RenderBox) return Offset.zero & box.size;
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    afe.Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final box = _renderBox;
    if (box == null) return null;
    return Rect.fromLTWH(-box.size.width / 2, 0, box.size.width, box.size.height);
  }

  @override
  List<Rect> getRectsInSelection(
    afe.Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final box = _renderBox;
    if (box == null) return const [];
    final imageBox = _imageKey.currentContext?.findRenderObject();
    if (imageBox is RenderBox) {
      return [imageBox.localToGlobal(Offset.zero, ancestor: box) & imageBox.size];
    }
    return [Offset.zero & box.size];
  }

  @override
  afe.Selection getSelectionInRange(Offset start, Offset end) =>
      afe.Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox!.localToGlobal(offset);
}

afe.Node _paragraphFrom(String text) => afe.paragraphNode(text: text);
