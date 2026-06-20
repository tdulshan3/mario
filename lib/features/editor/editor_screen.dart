/// EditorScreen — mounts AppFlowy editor for the selected page with debounced Drive autosave.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_cef/webview_cef.dart';

import '../../core/models/note_page.dart';
import '../../core/services/page_content_repository.dart';
import '../../ui/colors.dart';
import '../drawing/drawing_canvas.dart';
import '../drawing/drawing_toolbar.dart';
import '../drawing/stroke.dart';
import '../math/math_shortcut.dart';
import '../voice/voice_dictation.dart';
import 'blocks/audio_block.dart';
import 'blocks/drawing_block.dart';
import 'blocks/mario_image_block.dart';
import 'blocks/mario_table_block.dart';
import 'blocks/math_block.dart';
import 'blocks/spreadsheet_block.dart';
import 'canvas_drawing_layer.dart';
import 'canvas_toolbar.dart';
import 'page_content_provider.dart';
import 'paste_html_bridge.dart';
import 'word_shortcuts.dart';

/// Single-page editor host — looks up the page by id, shows a loader while the
/// Drive JSON is fetched, then mounts the AppFlowyEditor.
class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key, required this.page});

  final NotePage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileId = page.driveFileId;
    if (fileId == null) {
      return const _UnavailableContent(
        message: 'This page has no Drive content yet.',
      );
    }
    final docAsync = ref.watch(pageContentProvider(fileId));
    return docAsync.when(
      loading: () => const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => _UnavailableContent(message: 'Could not load page: $e'),
      data: (rawJson) => _Editor(
        key: ValueKey(fileId),
        page: page,
        driveFileId: fileId,
        rawJson: rawJson,
      ),
    );
  }
}

class _UnavailableContent extends StatelessWidget {
  const _UnavailableContent({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: muted),
        ),
      ),
    );
  }
}

enum SaveStatus { idle, dirty, saving, saved, error }

/// Key under which the verbatim paste-HTML source is stashed in the page's
/// Drive payload, so the preview-pane override survives page navigation.
const String _rawHtmlOverrideKey = 'rawHtmlOverride';

class _Editor extends ConsumerStatefulWidget {
  const _Editor({
    super.key,
    required this.page,
    required this.driveFileId,
    required this.rawJson,
  });

  final NotePage page;
  final String driveFileId;
  final Map<String, dynamic> rawJson;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late afe.EditorState _editorState;
  late StreamSubscription _txSub;
  Timer? _saveTimer;
  SaveStatus _status = SaveStatus.idle;
  DateTime? _lastSavedAt;
  static const _debounce = Duration(seconds: 2);

  // Zoom — toolbar buttons, Ctrl+0 reset, Ctrl+wheel.
  double _zoom = 1.0;
  static const _zoomMin = 0.5;
  static const _zoomMax = 3.0;
  static const _zoomStep = 0.1;

  // Tracks Ctrl modifier so the canvas can disable scroll-physics during
  // Ctrl+wheel (otherwise both scroll and zoom would fire on the same event).
  bool _ctrlDown = false;

  // Horizontal scroll controller for the outer scrollview (vertical scrolling
  // happens inside AppFlowy's own scroll service, so no _vScroll needed).
  final ScrollController _hScroll = ScrollController();

  // Freehand drawing on the canvas. Strokes persist alongside the document
  // JSON in the page file (top-level `strokes` key) so they round-trip
  // through Drive autosave.
  late DrawingController _drawingController;
  bool _drawMode = false;

  // True while the OS drag carries files over the canvas, so we can paint
  // a drop-zone highlight to confirm the drop will be accepted.
  bool _dragOver = false;

  // HTML preview pane — toggled from the toolbar. _previewHtml is fed by
  // _updatePreview (called on each transaction while preview is on) so the
  // pane re-renders without rebuilding the editor.
  bool _previewMode = false;
  final ValueNotifier<String> _previewHtml = ValueNotifier<String>('');

  static const _imageExtensions = <String>{
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.heif',
  };

  bool _isImagePath(String p) {
    final dot = p.lastIndexOf('.');
    if (dot < 0) return false;
    return _imageExtensions.contains(p.substring(dot).toLowerCase());
  }

  Future<void> _onFilesDropped(List<String> paths) async {
    final imagePaths = <String>[];
    for (final p in paths) {
      if (!_isImagePath(p)) continue;
      if (!await File(p).exists()) continue;
      // Copy into the persistent image dir so the Drive reference survives
      // the user moving / deleting / renaming the original file.
      try {
        imagePaths.add(await persistImageFile(p));
      } catch (_) {
        imagePaths.add(p);
      }
    }
    if (imagePaths.isEmpty || _editorState.isDisposed) return;
    final selection = _editorState.selection;
    final basePath = selection?.end.path ??
        _editorState.document.root.children.last.path;
    final tx = _editorState.transaction
      ..insertNodes(
        basePath.next,
        [
          for (final p in imagePaths)
            afe.Node(
              type: MarioImageKeys.type,
              attributes: {MarioImageKeys.url: p},
            ),
        ],
      );
    await _editorState.apply(tx);
  }

  @override
  void initState() {
    super.initState();
    _editorState = afe.EditorState(document: afe.Document.fromJson(widget.rawJson));
    _txSub = _editorState.transactionStream.listen(_onTransaction);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _drawingController = DrawingController(
      initial: strokesFromJson(widget.rawJson['strokes'] as List?),
    );
    // Listen to committed changes (a finished stroke / undo / erase), not the
    // per-point live notifications — autosave once per change, not per pixel.
    _drawingController.committed.addListener(_onStrokesChanged);
    // Restore this page's stashed paste-HTML override (or clear if the page
    // has none — would otherwise leak from the previously-mounted editor).
    // Then watch the bridge so paste-detected full HTML auto-routes into the
    // preview pane (and pops the pane open if it was closed).
    final savedOverride = widget.rawJson[_rawHtmlOverrideKey] as String?;
    rawHtmlOverride.value =
        (savedOverride != null && savedOverride.isNotEmpty) ? savedOverride : null;
    rawHtmlOverride.addListener(_onRawHtmlOverrideChanged);
    if (rawHtmlOverride.value != null) {
      // Auto-open preview on a page that has a stashed override — same UX as
      // the immediate-paste flow, just rehydrated from Drive.
      _previewMode = true;
      _previewHtml.value = rawHtmlOverride.value!;
    }
  }

  @override
  void dispose() {
    final hadPendingSave = _saveTimer?.isActive ?? false;
    _saveTimer?.cancel();
    _txSub.cancel();
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _drawingController.committed.removeListener(_onStrokesChanged);
    _drawingController.dispose();
    _hScroll.dispose();
    _previewHtml.dispose();
    rawHtmlOverride.removeListener(_onRawHtmlOverrideChanged);
    final state = _editorState;
    // Flush a pending debounced save so paste-then-quick-switch doesn't drop
    // unsaved work. We snapshot the doc + override *now* (while the state is
    // alive) and fire off the Drive write without awaiting it — dispose has
    // to stay synchronous, so the save happens as a detached task.
    if (hadPendingSave && !state.isDisposed) {
      _flushFinalSave(state);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => state.dispose());
    super.dispose();
  }

  /// Fire-and-forget Drive save using a snapshot taken before dispose. Runs
  /// outside the widget's mounted lifecycle, so it must NOT touch context,
  /// setState, or any State fields — only the snapshot is safe.
  void _flushFinalSave(afe.EditorState state) {
    final snapshot = <String, dynamic>{
      ...state.document.toJson(),
      'title': widget.page.title,
      'updatedAt': DateTime.now().toIso8601String(),
      'strokes': strokesToJson(_drawingController.snapshot()),
      if (rawHtmlOverride.value != null && rawHtmlOverride.value!.isNotEmpty)
        _rawHtmlOverrideKey: rawHtmlOverride.value,
    };
    final fileId = widget.driveFileId;
    unawaited(
        GetIt.I<PageContentRepository>().save(fileId, snapshot).catchError((_) {
      // Silent: the user has already navigated away; surfacing an error
      // through a no-longer-mounted ScaffoldMessenger isn't useful.
    }));
  }

  void _onRawHtmlOverrideChanged() {
    if (!mounted) return;
    final hasOverride = rawHtmlOverride.value != null;
    // Auto-pop the preview pane open when paste sets an override — the user
    // pasted a styled doc clearly intending to *see* it.
    if (hasOverride && !_previewMode) {
      setState(() => _previewMode = true);
    } else if (mounted) {
      // Override cleared (or replaced) — refresh preview content if it's open.
      setState(() {});
    }
    if (_previewMode) _updatePreview();
    // Persist the override change to Drive. Without this, paste-HTML lives
    // only in memory and disappears on page switch (the page reloads from
    // Drive, which never saw the paste).
    setState(() => _status = SaveStatus.dirty);
    _saveTimer?.cancel();
    _saveTimer = Timer(_debounce, _save);
  }

  void _onStrokesChanged() {
    if (!mounted) return;
    setState(() => _status = SaveStatus.dirty);
    _saveTimer?.cancel();
    _saveTimer = Timer(_debounce, _save);
  }

  void _toggleDraw() {
    setState(() => _drawMode = !_drawMode);
  }

  bool _onHardwareKey(KeyEvent event) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl != _ctrlDown && mounted) {
      // Schedule outside the key-event callback to avoid setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _ctrlDown = ctrl);
      });
    }
    return false; // never consume — let editor see the keys.
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    // In draw mode the canvas Listener swallows hit-tests, so the editor's
    // own Scrollable never sees the wheel event — we forward it manually.
    if (!ctrl && !_drawMode) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final dy = (e as PointerScrollEvent).scrollDelta.dy;
      if (ctrl) {
        if (dy < 0) {
          _zoomIn();
        } else if (dy > 0) {
          _zoomOut();
        }
        return;
      }
      final scrollController =
          _editorState.service.scrollService?.scrollController;
      if (scrollController == null || !scrollController.hasClients) return;
      final pos = scrollController.position;
      final next =
          (pos.pixels + dy).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      pos.jumpTo(next);
    });
  }

  void _onTransaction((afe.TransactionTime, afe.Transaction) event) {
    if (event.$1 != afe.TransactionTime.after) return;
    if (!mounted) return;
    setState(() => _status = SaveStatus.dirty);
    _saveTimer?.cancel();
    _saveTimer = Timer(_debounce, _save);
    if (_previewMode) _updatePreview();
  }

  void _updatePreview() {
    try {
      // Pasted-HTML override wins — render the user's verbatim source so
      // sticky/grid/JS/animations all survive. Otherwise fall back to the
      // round-tripped doc HTML.
      final override = rawHtmlOverride.value;
      if (override != null && override.isNotEmpty) {
        _previewHtml.value = override;
      } else {
        _previewHtml.value = afe.documentToHTML(_editorState.document);
      }
    } catch (e) {
      _previewHtml.value = '<!-- preview error: $e -->';
    }
  }

  void _togglePreview() {
    setState(() => _previewMode = !_previewMode);
    if (_previewMode) _updatePreview();
  }

  Future<void> _save() async {
    if (!mounted) return;
    setState(() => _status = SaveStatus.saving);
    try {
      final json = _editorState.document.toJson();
      final payload = <String, dynamic>{
        ...json,
        'title': widget.page.title,
        'updatedAt': DateTime.now().toIso8601String(),
        'strokes': strokesToJson(_drawingController.snapshot()),
        if (rawHtmlOverride.value != null && rawHtmlOverride.value!.isNotEmpty)
          _rawHtmlOverrideKey: rawHtmlOverride.value,
      };
      await GetIt.I<PageContentRepository>().save(widget.driveFileId, payload);
      if (!mounted) return;
      setState(() {
        _status = SaveStatus.saved;
        _lastSavedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = SaveStatus.error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _save();
  }

  void _zoomIn() {
    setState(() => _zoom = (_zoom + _zoomStep).clamp(_zoomMin, _zoomMax));
  }

  void _zoomOut() {
    setState(() => _zoom = (_zoom - _zoomStep).clamp(_zoomMin, _zoomMax));
  }

  void _zoomReset() {
    setState(() => _zoom = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    // Canvas behind the paper card: surfaceContainerHighest is the panel-bg
    // token (slightly tinted from the base surface), which gives the Book
    // theme its sepia surround without affecting Light/Dark.
    final canvasBg = scheme.surfaceContainerHighest;
    // Paper is the elevated/raised surface — pure white in Light, near-black
    // in Dark, light cream in Book.
    final paper = scheme.surfaceContainerHigh;

    // AppFlowy applies editorStyle.padding to EVERY block (page_block_component
    // wraps each item in `Padding(padding: editorStyle.padding)`), so any
    // vertical value here doubles up between adjacent blocks. Keep it 0 and
    // get top/bottom breathing room from the editor's header/footer slots.
    final style = isDark
        ? afe.EditorStyle.desktop(
            cursorColor: MarioColors.primary,
            selectionColor: MarioColors.primary.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 8),
            textStyleConfiguration: afe.TextStyleConfiguration(
              text: GoogleFonts.inter(
                  fontSize: 14, color: MarioColors.onSurfaceDark, height: 1.2),
              lineHeight: 1.2,
            ),
            cursorWidth: 2.0,
          )
        : afe.EditorStyle.desktop(
            cursorColor: MarioColors.primaryPressed,
            selectionColor: MarioColors.primary.withValues(alpha: 0.35),
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 8),
            textStyleConfiguration: afe.TextStyleConfiguration(
              text: GoogleFonts.inter(
                  fontSize: 14, color: MarioColors.onSurface, height: 1.2),
              lineHeight: 1.2,
            ),
            cursorWidth: 2.0,
          );

    // Drop AppFlowy's default 4px vertical block padding to zero so the gap
    // between adjacent paragraphs matches wrapped-line spacing inside one
    // paragraph (otherwise 2px of padding shows up only between blocks).
    final tightConfig = afe.BlockComponentConfiguration(
      padding: (_) => EdgeInsets.symmetric(vertical: 1),
    );

    final blockBuilders = <String, afe.BlockComponentBuilder>{
      ...afe.standardBlockComponentBuilderMap,
      // Override the stock table with our wrapper that adds a whole-table
      // corner resize handle (keeps AppFlowy's table for editing/cells).
      afe.TableBlockKeys.type: MarioTableBlockComponentBuilder(),
      MarioImageKeys.type: MarioImageBlockBuilder(),
      MathBlockKeys.type: MathBlockComponentBuilder(),
      DrawingBlockKeys.type: DrawingBlockComponentBuilder(),
      SpreadsheetBlockKeys.type: SpreadsheetBlockComponentBuilder(),
      AudioBlockKeys.type: AudioBlockComponentBuilder(),
    };
    // Apply tight padding to every standard block builder (paragraphs, lists,
    // headings, quotes…). The custom Mario blocks own their own padding so we
    // leave them alone.
    for (final entry in afe.standardBlockComponentBuilderMap.entries) {
      blockBuilders[entry.key]?.configuration = tightConfig;
    }

    final standardSpaceHandlers = afe.standardCharacterShortcutEvents
        .where((e) => e.character != '/');
    final shortcutEvents = <afe.CharacterShortcutEvent>[
      marioMathShortcut,
      ...standardSpaceHandlers,
      afe.customSlashCommand(
        [
          ...afe.standardSelectionMenuItems,
          mathSelectionMenuItem,
          drawingSelectionMenuItem,
          spreadsheetSelectionMenuItem,
          audioSelectionMenuItem,
        ],
        style: isDark
            ? afe.SelectionMenuStyle.dark
            : afe.SelectionMenuStyle.light,
      ),
    ];

    // Word-style shortcuts win over AppFlowy defaults where keys collide
    // (Ctrl+E especially: AppFlowy used it for inline-code; Word uses it for
    // align-center).
    final commandShortcuts = <afe.CommandShortcutEvent>[
      ...wordCommandShortcuts(),
      ...afe.standardCommandShortcutEvents.where(
        (e) => !_overriddenShortcutKeys.contains(e.key),
      ),
      ...afe.findAndReplaceCommands(context: context),
    ];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveNow,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            _zoomReset,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CanvasToolbar(
            editorState: _editorState,
            zoom: _zoom,
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onZoomReset: _zoomReset,
            drawMode: _drawMode,
            onToggleDraw: _toggleDraw,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _previewMode ? Icons.code_off : Icons.code,
                    color: _previewMode ? MarioColors.primary : null,
                  ),
                  tooltip: _previewMode
                      ? 'Hide HTML preview'
                      : 'Show HTML preview',
                  onPressed: _togglePreview,
                ),
                VoiceDictationButton(editorState: _editorState),
              ],
            ),
          ),
          if (_drawMode)
            DrawingToolbar(
              controller: _drawingController,
              onCollapse: _toggleDraw,
              onExport: () {},
              onSave: _toggleDraw,
              collapsed: false,
            ),
          Expanded(
            child: _previewMode
                ? _HtmlPreviewPane(
                    html: _previewHtml,
                    isDark: isDark,
                  )
                : DropTarget(
              onDragEntered: (_) => setState(() => _dragOver = true),
              onDragExited: (_) => setState(() => _dragOver = false),
              onDragDone: (details) {
                setState(() => _dragOver = false);
                _onFilesDropped(
                    [for (final f in details.files) f.path]);
              },
              child: Container(
                color: canvasBg,
                foregroundDecoration: _dragOver
                    ? BoxDecoration(
                        border: Border.all(
                            color: MarioColors.primary, width: 3),
                        color: MarioColors.primary.withValues(alpha: 0.08),
                      )
                    : null,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                  const cardWidth = 820.0;
                  final scaledWidth = cardWidth * _zoom;
                  final viewportW = constraints.maxWidth;
                  final viewportH = constraints.maxHeight;
                  final outerWidth =
                      math.max(scaledWidth + 32, viewportW);
                  final cardHeight = viewportH - 16;
                  // Outer scroll only does work when the scaled card overflows
                  // horizontally. Otherwise it'd intercept stray dx deltas
                  // from trackpads and block AppFlowy's vertical scroll.
                  final hasHorizontalOverflow = scaledWidth > viewportW;
                  final outerPhysics = hasHorizontalOverflow
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics();
                  return Listener(
                    onPointerSignal: _onPointerSignal,
                    child: Scrollbar(
                      controller: _hScroll,
                      thumbVisibility: hasHorizontalOverflow,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      child: SingleChildScrollView(
                        controller: _hScroll,
                        scrollDirection: Axis.horizontal,
                        physics: outerPhysics,
                        child: SizedBox(
                          width: outerWidth,
                          height: viewportH,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              // Outer SizedBox is the *post-scale* width so
                              // the parent's hit-test region covers the whole
                              // visually-zoomed card. OverflowBox then hands
                              // the unscaled child its natural cardWidth
                              // constraints inside that wider region.
                              child: SizedBox(
                                width: scaledWidth,
                                height: cardHeight,
                                child: OverflowBox(
                                  minWidth: 0,
                                  maxWidth: cardWidth,
                                  minHeight: 0,
                                  maxHeight: cardHeight,
                                  alignment: Alignment.topCenter,
                                  child: Transform.scale(
                                    scale: _zoom,
                                    alignment: Alignment.topCenter,
                                    child: SizedBox(
                                      width: cardWidth,
                                      height: cardHeight,
                                      child: Stack(
                                        children: [
                                          Material(
                                            color: paper,
                                            elevation: isDark ? 0 : 2,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                            clipBehavior: Clip.antiAlias,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                _PageHeader(page: widget.page),
                                                Expanded(
                                                  child: afe.AppFlowyEditor(
                                                    editorState: _editorState,
                                                    editorStyle: style,
                                                    blockComponentBuilders:
                                                        blockBuilders,
                                                    characterShortcutEvents:
                                                        shortcutEvents,
                                                    commandShortcutEvents:
                                                        commandShortcuts,
                                                    autoFocus: true,
                                                    header: const SizedBox(
                                                        height: 16),
                                                    footer: const SizedBox(
                                                        height: 24),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Drawing surface on top — strokes
                                          // always visible; pointer capture
                                          // only when draw mode is on.
                                          Positioned.fill(
                                            child: CanvasDrawingLayer(
                                              controller: _drawingController,
                                              active: _drawMode,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              ),
            ),
          ),
          _StatusBar(
              status: _status, lastSavedAt: _lastSavedAt, muted: muted),
        ],
      ),
    );
  }
}

/// AppFlowy command keys whose shortcuts collide with Word equivalents we
/// install via [wordCommandShortcuts].
const _overriddenShortcutKeys = <String>{
  'toggle code', // Ctrl+E — AppFlowy uses for code; Word uses for align-center
  'paste the content', // Ctrl+V — replaced by smart paste (image+markdown+rich)
};

/// One-time CEF init — `WebviewManager().initialize()` is safe to await
/// repeatedly but we cache the future so concurrent preview opens don't race.
Future<void>? _cefInit;
Future<void> _ensureCef() {
  return _cefInit ??= WebviewManager().initialize();
}

/// Wraps documentToHTML output in a full HTML5 doc with default styling so
/// the webview has something to render (otherwise it'd inherit no margins,
/// no font, etc.). The body content is the AppFlowy-emitted HTML.
String _wrapPreviewHtml(String body, {required bool isDark}) {
  final bg = isDark ? '#1f1f1f' : '#ffffff';
  final fg = isDark ? '#e6e6e6' : '#1a1a18';
  return '''<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<style>
  html, body { margin: 0; padding: 0; }
  body {
    background: $bg;
    color: $fg;
    font-family: -apple-system, system-ui, "Segoe UI", Roboto, sans-serif;
    font-size: 15px;
    line-height: 1.6;
    padding: 24px 32px;
    max-width: 820px;
    margin: 0 auto;
  }
  h1, h2, h3, h4 { font-weight: 600; line-height: 1.25; margin-top: 1.4em; }
  p { margin: 0.5em 0; }
  ul, ol { padding-left: 1.5em; }
  blockquote { border-left: 3px solid #888; margin: 0.5em 0; padding-left: 1em; color: #888; }
  code { font-family: ui-monospace, "Fira Code", monospace; background: rgba(127,127,127,0.15); padding: 1px 4px; border-radius: 3px; font-size: 0.92em; }
  pre { background: rgba(127,127,127,0.1); padding: 12px; border-radius: 6px; overflow-x: auto; }
  img { max-width: 100%; height: auto; }
  table { border-collapse: collapse; }
  th, td { border: 1px solid rgba(127,127,127,0.4); padding: 4px 8px; }
  a { color: #5fa8e9; }
</style>
</head><body>$body</body></html>''';
}

class _HtmlPreviewPane extends StatefulWidget {
  const _HtmlPreviewPane({required this.html, required this.isDark});

  final ValueListenable<String> html;
  final bool isDark;

  @override
  State<_HtmlPreviewPane> createState() => _HtmlPreviewPaneState();
}

class _HtmlPreviewPaneState extends State<_HtmlPreviewPane> {
  WebViewController? _controller;
  String? _error;
  File? _tempFile;

  @override
  void initState() {
    super.initState();
    widget.html.addListener(_onHtmlChanged);
    _setup();
  }

  @override
  void dispose() {
    widget.html.removeListener(_onHtmlChanged);
    _controller?.dispose();
    final f = _tempFile;
    if (f != null) {
      // Fire-and-forget — file deletion is best-effort; an OS cleanup will
      // sweep stragglers eventually.
      f.delete().catchError((_) => f);
    }
    super.dispose();
  }

  // Set by _onHtmlChanged when the listener fires before _controller is ready,
  // so _setup can catch up after init with the latest value.
  bool _dirtyDuringInit = false;

  Future<void> _setup() async {
    try {
      await _ensureCef().timeout(const Duration(seconds: 15));
      final c = WebviewManager().createWebView(
        loading: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
      final url = await _writeTempFile(widget.html.value);
      await c.initialize(url);
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
      if (_dirtyDuringInit) {
        _dirtyDuringInit = false;
        final url2 = await _writeTempFile(widget.html.value);
        if (!mounted) return;
        await c.loadUrl(url2);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _onHtmlChanged() async {
    final c = _controller;
    if (c == null) {
      // Controller not ready yet — flag for _setup to catch up post-init.
      _dirtyDuringInit = true;
      return;
    }
    final url = await _writeTempFile(widget.html.value);
    if (!mounted) return;
    c.loadUrl(url);
  }

  /// Writing to disk avoids the size & cross-origin headaches of base64
  /// data: URIs. Per-State unique filename so two preview panes (sequential
  /// after a page switch, or briefly overlapping during dispose) never share
  /// a path — same-URL reuse triggered stale renders from CEF's cache layer.
  ///
  /// If `body` is already a full HTML document (DOCTYPE or `<html>` root),
  /// it's written verbatim — wrapping it again would nest two `<html>` trees
  /// and most of the user's CSS would never apply.
  Future<String> _writeTempFile(String body) async {
    final t = body.trimLeft().toLowerCase();
    final isFullDoc = t.startsWith('<!doctype') || t.startsWith('<html');
    final content =
        isFullDoc ? body : _wrapPreviewHtml(body, isDark: widget.isDark);
    var f = _tempFile;
    if (f == null) {
      final dir = Directory.systemTemp;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      f = File('${dir.path}/mario_preview_$stamp.html');
      _tempFile = f;
    }
    await f.writeAsString(content);
    return Uri.file(f.path).toString();
  }

  Future<void> _openInBrowser() async {
    final url = await _writeTempFile(widget.html.value);
    final path = Uri.parse(url).toFilePath();
    try {
      if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [path]);
      } else if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path]);
      }
    } catch (_) {
      // ignore — user can copy the path manually
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF7F7F7);
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    final border = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFDADADA);
    final controller = _controller;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        border: Border(left: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: ValueListenableBuilder<String?>(
              valueListenable: rawHtmlOverride,
              builder: (context, override, _) {
                final pinned = override != null && override.isNotEmpty;
                return Row(
                  children: [
                    Text(
                      pinned ? 'HTML preview · pinned source' : 'HTML preview',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: pinned ? MarioColors.primary : muted,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    if (pinned)
                      TextButton.icon(
                        onPressed: () => rawHtmlOverride.value = null,
                        icon: const Icon(Icons.close, size: 14),
                        label: const Text('Unpin'),
                        style: TextButton.styleFrom(
                          foregroundColor: muted,
                          textStyle: GoogleFonts.inter(fontSize: 11),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 28),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: _openInBrowser,
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('Open in browser'),
                      style: TextButton.styleFrom(
                        foregroundColor: muted,
                        textStyle: GoogleFonts.inter(fontSize: 11),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Divider(height: 1, color: border),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Preview unavailable: $_error\n\nClick "Open in '
                        'browser" above to render in your default browser.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12, color: muted),
                      ),
                    ),
                  )
                : controller == null
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : ValueListenableBuilder<bool>(
                        valueListenable: controller,
                        builder: (context, ready, _) => SizedBox.expand(
                          child: ready
                              ? controller.webviewWidget
                              : controller.loadingWidget,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.page});
  final NotePage page;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 16, 64, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            page.title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Last edited ${_formatTime(page.updatedAt)}',
            style: GoogleFonts.inter(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.status,
    required this.lastSavedAt,
    required this.muted,
  });

  final SaveStatus status;
  final DateTime? lastSavedAt;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final (text, icon) = switch (status) {
      SaveStatus.idle => (lastSavedAt == null ? '' : 'Saved', Icons.check_circle_outline),
      SaveStatus.dirty => ('Edited', Icons.edit_note),
      SaveStatus.saving => ('Saving…', Icons.cloud_upload_outlined),
      SaveStatus.saved => ('Saved', Icons.cloud_done_outlined),
      SaveStatus.error => ('Save failed', Icons.error_outline),
    };
    final isError = status == SaveStatus.error;
    final color = isError ? Theme.of(context).colorScheme.error : muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: GoogleFonts.inter(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

