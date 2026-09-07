/// EditorScreen — mounts AppFlowy editor for the selected page with debounced Drive autosave.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/note_page.dart';
import '../../core/models/section.dart';
import '../../core/services/asset_sync_service.dart';
import '../../core/services/page_content_repository.dart';
import '../../ui/colors.dart';
import '../../ui/theme.dart';
import '../drawing/drawing_canvas.dart';
import '../drawing/drawing_toolbar.dart';
import '../drawing/stroke.dart';
import '../../core/services/sync_service.dart';
import '../ai/agent_executor.dart';
import '../ai/ai_markdown_blocks.dart';
import '../ai/ai_slash_commands.dart';
import '../ai/grammar_check.dart';
import '../ai/ai_state.dart';
import '../ai/inline_ask.dart';
import '../ai/ask_panel.dart';
import '../ai/note_context.dart';
import '../export/export_dialog.dart';
import '../export/markdown_exporter.dart';
import 'editor_typography.dart';
import '../export/pdf_exporter.dart';
import '../math/math_shortcut.dart';
import '../settings/settings_state.dart';
import '../shell/shell_state.dart' as shell;
import '../voice/voice_dictation.dart';
import 'blocks/audio_block.dart';
import 'blocks/code_block.dart';
import 'blocks/drawing_block.dart';
import 'blocks/mario_image_block.dart';
import 'blocks/mario_table_block.dart';
import 'blocks/math_block.dart';
import 'blocks/spreadsheet_block.dart';
import 'asset_sweeper.dart';
import 'canvas_drawing_layer.dart';
import 'canvas_toolbar.dart';
import 'image_asset_resolver.dart';
import 'html_preview.dart';
import 'page_content_provider.dart';
import 'paste_html_bridge.dart';
import 'word_shortcuts.dart';
import '../../ui/widgets/mario_loader.dart';

/// Single-page editor host — looks up the page by id, shows a loader while the
/// content is fetched, then mounts the AppFlowyEditor.
///
/// A page with no Drive file yet — created while Drive was out of reach, or
/// before the sync outbox existed — opens under its local content key rather
/// than as a dead end; the outbox promotes it to a Drive file when it can.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.page});

  final NotePage page;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  /// The key the content was loaded under, fixed for the life of this
  /// screen. When a page opened under its local key is promoted mid-edit,
  /// the page arrives with a Drive id; loading afresh under it would tear
  /// the editor down and put it back up. Saves use the current id, and the
  /// repository forwards the local key to the promoted one anyway.
  late final String _loadKey = _contentKey(widget.page);

  static String _contentKey(NotePage page) =>
      page.driveFileId ?? PageContentRepository.localKeyFor(page.id);

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final docAsync = ref.watch(pageContentProvider(_loadKey));
    return docAsync.when(
      loading: () => const Center(child: MarioLoader(size: 30)),
      error: (e, _) => _UnavailableContent(message: 'Could not load page: $e'),
      data: (rawJson) => _Editor(
        key: ValueKey(page.id),
        page: page,
        driveFileId: _contentKey(page),
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

/// The editor's horizontal inset.
///
/// Applied inside [afe.EditorStyle] rather than as a `Padding` around the
/// editor — `getNodeInOffset` resolves a tap to the NEAREST node, so margin
/// inside the editor still places the caret on the adjacent line, whereas
/// wrapping the editor shrinks its gesture box and those taps hit dead space.
///
/// Named here because the page heading has to match it to share the body's
/// left edge, and the column has to be this much wider than the text measure.
const double kEditorInset = 52;

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

  /// The canvas Stack, so a global caret rect can be brought into its space.
  final GlobalKey _canvasKey = GlobalKey();

  /// ONE executor for the life of this editor, not one per action.
  ///
  /// It remembers where a run's deleted blocks sat, so a rewrite that deletes
  /// the old text and inserts the new can put the replacement in the gap
  /// rather than at the end of the page. A fresh executor per action forgot
  /// that immediately, and every replacement landed at the bottom.
  ///
  /// Lazy, because [_editorState] is not built until initState.
  late final AgentExecutor _agent = AgentExecutor(_editorState);
  late StreamSubscription _txSub;
  Timer? _saveTimer;
  SaveStatus _status = SaveStatus.idle;
  DateTime? _lastSavedAt;
  static const _debounce = Duration(seconds: 2);

  // Zoom — toolbar buttons, Ctrl+0 reset, Ctrl+wheel.
  double _zoom = 1.0;

  /// The TEXT measure, from the Page width setting — the design's `--pw`.
  double get _pageWidth =>
      ref.watch(settingsProvider).valueOrNull?.canvasWidth.pageWidth ??
      CanvasWidth.medium.pageWidth;

  /// The column the document is laid out in.
  ///
  /// Wider than the text measure by the editor's own inset on each side.
  /// That inset lives inside `EditorStyle` rather than in a `Padding` around
  /// the editor (see [kEditorInset]), so it eats into the column: a 720px
  /// column would set 616px of text. Both the heading and the document go
  /// through this, which is what puts them on one left edge — they were
  /// 52px apart before, because the heading carried no inset.
  double get _columnWidth => _pageWidth + kEditorInset * 2;
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

  // Pushes this page's images to Drive. Page-level rather than block-level
  // because the editor's lazy list never builds blocks below the fold — see
  // AssetSweeper's header for why that matters.
  late AssetSweeper _assetSweeper;

  // Captured in initState so dispose() can clear the AI bridge without
  // touching `ref`, which is already invalid by then.
  StateController<AiEditorBridge?>? _bridgeController;

  // Publishes what the user has highlighted, for the Ask panel.
  StateController<String?>? _selectionController;
  Timer? _selectionDebounce;

  /// How long a selection must hold still before it counts as deliberate.
  ///
  /// Selecting text is constant, incidental editing: every drag to delete a
  /// phrase, every double-click on a word. Reacting to each one would pop the
  /// panel open while someone is trying to write. Waiting for the selection to
  /// settle separates "I dragged across this" from "I am looking at this".
  static const _selectionSettleDelay = Duration(milliseconds: 500);

  /// Below this, a highlight is a cursor placement or a stray double-click
  /// rather than a passage worth asking about.
  static const _minQuotableLength = 12;

  // HTML preview pane — toggled from the toolbar. _previewHtml is fed by
  // _updatePreview (called on each transaction while preview is on) so the
  // pane re-renders without rebuilding the editor.
  bool _previewMode = false;

  final ValueNotifier<String> _previewHtml = ValueNotifier<String>('');

  static const _imageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.heif',
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
    final basePath =
        selection?.end.path ?? _editorState.document.root.children.last.path;
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
    _editorState =
        afe.EditorState(document: afe.Document.fromJson(widget.rawJson));
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
    rawHtmlOverride.value = (savedOverride != null && savedOverride.isNotEmpty)
        ? savedOverride
        : null;
    rawHtmlOverride.addListener(_onRawHtmlOverrideChanged);
    if (rawHtmlOverride.value != null) {
      // Auto-open preview on a page that has a stashed override — same UX as
      // the immediate-paste flow, just rehydrated from Drive.
      _previewMode = true;
      _previewHtml.value = rawHtmlOverride.value!;
    }
    // Heal pages that were saved empty by the older delete-last-block bug, so
    // they don't open to a frozen, untypeable canvas.
    _ensureNonEmptyDocument();

    // Hand the AI panel a way to read this page and write back into it. Done
    // after the first frame because publishing to a provider during initState
    // would mutate state while the tree is still building. The controller is
    // grabbed now, synchronously, because dispose() cannot use `ref` — see
    // [_withdrawAiBridge].
    _bridgeController = ref.read(aiEditorBridgeProvider.notifier);
    _selectionController = ref.read(editorSelectionProvider.notifier);
    _editorState.selectionNotifier.addListener(_onSelectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishAiBridge());

    _assetSweeper = AssetSweeper(_editorState, GetIt.I<AssetSyncService>());
    // One pass on open covers images this device inserted while offline and
    // notes written before image sync existed. Later passes ride on _save.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_assetSweeper.sweep()));
  }

  @override
  void dispose() {
    _selectionDebounce?.cancel();
    _editorState.selectionNotifier.removeListener(_onSelectionChanged);
    _withdrawAiBridge();
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
    // After the flush — assetIds() reads the document the flush also snapshots.
    _assetSweeper.dispose();
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
      'assetIds': _assetSweeper.assetIds(),
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
    _ensureNonEmptyDocument();
    setState(() => _status = SaveStatus.dirty);
    _saveTimer?.cancel();
    _saveTimer = Timer(_debounce, _save);
    if (_previewMode) _updatePreview();
  }

  /// Deleting the last top-level block (e.g. a code/drawing/table/image block
  /// that was the only line) leaves the document with zero children — the
  /// canvas then has nothing to focus, so it can't be typed in or clicked.
  /// Restore an empty paragraph and put the cursor in it. Deferred to the next
  /// frame so we never apply a transaction reentrantly from the stream callback.
  void _ensureNonEmptyDocument() {
    final state = _editorState;
    if (state.isDisposed || state.document.root.children.isNotEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (state.isDisposed || state.document.root.children.isNotEmpty) return;
      final tx = state.transaction..insertNode([0], afe.paragraphNode());
      await state.apply(tx);
      if (state.isDisposed) return;
      state.selection = afe.Selection.collapsed(afe.Position(path: [0]));
    });
  }

  /// Memo for the preview's image-path substitutions, keyed by the set of
  /// asset ids in the document. Resolving stats one file per image, and the
  /// preview regenerates on every keystroke — without this, a page with thirty
  /// pictures would do thirty syscalls per character typed. The ids only
  /// change when an image is added, removed, or finishes uploading.
  String _previewSubsKey = '';
  Map<String, String> _previewSubs = const {};

  Future<void> _updatePreview() async {
    try {
      // Pasted-HTML override wins — render the user's verbatim source so
      // sticky/grid/JS/animations all survive. Otherwise fall back to the
      // round-tripped doc HTML.
      final override = rawHtmlOverride.value;
      if (override != null && override.isNotEmpty) {
        _previewHtml.value = override;
        return;
      }
      // The HTML encoder emits each image node's `url`, which is the path on
      // the device that inserted it — repoint those at this device's copies.
      // `fetchMissing: false` on purpose: the preview must never touch the
      // network. An image the editor has already downloaded is a cache hit
      // here anyway.
      final ids = _assetSweeper.assetIds().join(',');
      if (ids != _previewSubsKey) {
        _previewSubs = await resolveImageSources(
            _editorState.document, GetIt.I<AssetSyncService>());
        _previewSubsKey = ids;
        if (!mounted) return;
      }
      _previewHtml.value = rewriteHtmlImageSources(
          afe.documentToHTML(_editorState.document), _previewSubs);
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
        // Which Drive assets this page still references. Nothing reads it
        // today; it exists so a later cleanup pass can tell a live image from
        // an orphan. Deleting a page destroys its JSON, so if the ids aren't
        // recorded before that happens they're unrecoverable.
        'assetIds': _assetSweeper.assetIds(),
        if (rawHtmlOverride.value != null && rawHtmlOverride.value!.isNotEmpty)
          _rawHtmlOverrideKey: rawHtmlOverride.value,
      };
      await GetIt.I<PageContentRepository>().save(widget.driveFileId, payload);
      if (!mounted) return;
      setState(() {
        _status = SaveStatus.saved;
        _lastSavedAt = DateTime.now();
      });
      // Push any images that still lack a Drive id. Riding on the save keeps
      // the retry cadence tied to real activity — a paste is swept within a
      // couple of seconds, an idle page costs nothing.
      unawaited(_assetSweeper.sweep());
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

  // ---------------------------------------------------------------- AI panel

  /// Publishes the handle the AI side panel uses to read this page and insert
  /// answers into it. See [AiEditorBridge] for why the panel cannot reach the
  /// EditorState directly.
  void _publishAiBridge() {
    if (!mounted) return;
    ref.read(aiEditorBridgeProvider.notifier).state = AiEditorBridge(
      pageId: widget.page.id,
      notebookId: widget.page.notebookId,
      sectionId: widget.page.sectionId,
      pageTitle: widget.page.title,
      readPage: _readPageText,
      readAboveCursor: _readTextAboveCursor,
      readDocument: () => _editorState.document,
      readHtmlArtifact: () => rawHtmlOverride.value,
      insertMarkdown: (markdown) =>
          insertMarkdownIntoDocument(_editorState, markdown),
      replaceSelection: (markdown) =>
          replaceSelectionWithMarkdown(_editorState, markdown),
      applyGrammar: (suggestion) =>
          applyGrammarSuggestion(_editorState, suggestion),
      snapshot: () => _agent.snapshot(
        widget.page.title,
        htmlArtifact: rawHtmlOverride.value,
      ),
      restore: (snapshot) async {
        final ok = await _agent.restore(snapshot);
        // The title lives on the index entry, not in the document, so it has
        // to be put back separately.
        if (ok && snapshot.title != widget.page.title) {
          await _renamePage(snapshot.title);
        }
        if (ok) rawHtmlOverride.value = snapshot.htmlArtifact;
        return ok;
      },
      applyAgentAction: (action) => _agent.apply(action),
      renamePage: _renamePage,
      createPage: _createPage,
      createSection: _createSection,
      renameSection: _renameSection,
      setHtmlArtifact: (html) async {
        if (!mounted || html.trim().isEmpty) return false;
        rawHtmlOverride.value = html;
        return true;
      },
    );
  }

  /// Clears the bridge, but only if it is still ours.
  ///
  /// Switching pages disposes the outgoing editor *after* the incoming one has
  /// mounted and published its own bridge; clearing unconditionally would wipe
  /// the new page's handle and leave the panel thinking no page is open.
  ///
  /// Two things make this awkward from `dispose()`, and both are why it goes
  /// through a captured controller and a microtask rather than `ref`:
  ///
  ///  * `ref` is dead by then. Flutter marks the element inactive *before*
  ///    calling `State.dispose`, so Riverpod throws
  ///    "Cannot use ref after the widget was disposed". Hence
  ///    [_bridgeController], captured in initState while `ref` is still valid.
  ///  * Writing provider state synchronously during teardown rebuilds any
  ///    widget listening to it in the middle of the tree being dismantled.
  ///    Deferring to a microtask sidesteps that, and the page-id guard is what
  ///    keeps the deferral safe — by the time it runs the next editor may
  ///    already have published, and then this is a no-op.
  void _withdrawAiBridge() {
    final controller = _bridgeController;
    if (controller == null) return;
    final pageId = widget.page.id;
    scheduleMicrotask(() {
      try {
        if (controller.state?.pageId == pageId) controller.state = null;
      } catch (_) {
        // The whole ProviderScope went away with us (app shutdown). Nothing
        // left to withdraw from.
      }
    });
  }

  /// Publishes a settled, substantial highlight so the Ask panel can offer to
  /// answer about it.
  ///
  /// Debounced rather than immediate: the listener fires on every character of
  /// a drag, and acting on each would mean the panel opening and closing under
  /// the user's hand.
  void _onSelectionChanged() {
    _selectionDebounce?.cancel();
    final selection = _editorState.selection;
    if (selection == null || selection.isCollapsed) {
      // Clearing is immediate. Leaving a stale quote attached after the user
      // has clicked away would scope their next question to a passage they are
      // no longer looking at.
      _selectionController?.state = null;
      return;
    }
    _selectionDebounce = Timer(_selectionSettleDelay, () {
      if (!mounted || _editorState.isDisposed) return;
      final current = _editorState.selection;
      if (current == null || current.isCollapsed) return;
      final text = _editorState.getTextInSelection(current).join('\n').trim();
      _selectionController?.state =
          text.length >= _minQuotableLength ? text : null;
    });
  }

  /// Renames the page.
  ///
  /// Writes the index entry rather than the document: the title is Firestore
  /// metadata that the nav tree and the page header both read, and the Drive
  /// payload picks it up on the next autosave.
  Future<bool> _renamePage(String title) async {
    final clean = title.trim();
    if (clean.isEmpty || clean == widget.page.title) return false;
    try {
      await GetIt.I<SyncService>().updatePage(
        widget.page.copyWith(title: clean, updatedAt: DateTime.now()),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sections an agent run created here, by lower-cased name.
  ///
  /// A plan that creates a section and then a page in it looks the section up
  /// before the Firestore stream has delivered it; this is what lets the
  /// second action find what the first one made.
  final _createdSections = <String, String>{};

  /// The id of the section called [name], or this page's own section when
  /// no name is given. Null when the name matches nothing.
  String? _sectionIdNamed(String? name) {
    if (name == null || name.trim().isEmpty) return widget.page.sectionId;
    final wanted = name.trim().toLowerCase();
    final made = _createdSections[wanted];
    if (made != null) return made;
    final sections = ref
            .read(shell.sectionsStreamProvider(widget.page.notebookId))
            .valueOrNull ??
        const <Section>[];
    for (final s in sections) {
      if (s.name.trim().toLowerCase() == wanted) return s.id;
    }
    return null;
  }

  /// Creates a page beside this one, for the agent.
  ///
  /// The new page is not opened: the run that asked for it is still editing
  /// this page through this editor, and switching pages would dispose it
  /// mid-plan. A section the model named that does not exist falls back to
  /// this one — the page is the point, and it is still there to be found.
  Future<bool> _createPage(
    String title, {
    String? section,
    String markdown = '',
  }) async {
    if (!mounted) return false;
    final clean = title.trim();
    if (clean.isEmpty) return false;
    final nid = widget.page.notebookId;
    final sectionId = _sectionIdNamed(section) ?? widget.page.sectionId;
    final pages = ref
        .read(
            shell.pagesStreamProvider((notebookId: nid, sectionId: sectionId)))
        .valueOrNull;

    afe.Document? document;
    if (markdown.trim().isNotEmpty) {
      final nodes = marioMarkdownToNodes(markdown);
      if (nodes.isNotEmpty) {
        document = afe.Document(root: afe.pageNode(children: nodes));
      }
    }

    final now = DateTime.now();
    try {
      await GetIt.I<SyncService>().createPage(
        NotePage(
          id: '',
          sectionId: sectionId,
          notebookId: nid,
          title: clean,
          order: pages?.length ?? 0,
          createdAt: now,
          updatedAt: now,
        ),
        document: document,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Creates a section in this notebook, for the agent.
  Future<bool> _createSection(String name) async {
    if (!mounted) return false;
    final clean = name.trim();
    if (clean.isEmpty) return false;
    final nid = widget.page.notebookId;
    final sections =
        ref.read(shell.sectionsStreamProvider(nid)).valueOrNull ?? const [];
    try {
      final id = await GetIt.I<SyncService>().createSection(Section(
        id: '',
        notebookId: nid,
        name: clean,
        colorIndex: 2,
        order: sections.length,
      ));
      _createdSections[clean.toLowerCase()] = id;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Renames the named section, or this page's own, for the agent. A name
  /// that matches no section is refused rather than guessed at.
  Future<bool> _renameSection(String name, {String? section}) async {
    if (!mounted) return false;
    final clean = name.trim();
    if (clean.isEmpty) return false;
    final id = _sectionIdNamed(section);
    if (id == null) return false;
    final sections = ref
            .read(shell.sectionsStreamProvider(widget.page.notebookId))
            .valueOrNull ??
        const <Section>[];
    final target = sections.where((s) => s.id == id).firstOrNull;
    if (target == null || target.name == clean) return false;
    try {
      await GetIt.I<SyncService>().updateSection(target.copyWith(name: clean));
      return true;
    } catch (_) {
      return false;
    }
  }

  NoteText _readPageText() =>
      extractNoteText(_editorState.document, title: widget.page.title);

  /// Everything above the caret — what `/summary` means by "the note above".
  /// With no caret (the panel was used without clicking into the page first)
  /// the whole page is the sensible reading.
  NoteText _readTextAboveCursor() {
    final full = _readPageText();
    final selection = _editorState.selection;
    if (selection == null) return full;
    return full.above(List<int>.from(selection.start.path));
  }

  /// `/ask` opens the composer ON THE PAGE, not the side panel.
  ///
  /// That is the whole reason the composer is summoned rather than permanent:
  /// asking is something you do at a moment, in a place, so the control
  /// appears where the caret already is. `/ask what is a monad` carries the
  /// question straight through and runs it.
  ///
  /// Both the WHERE and the WHAT are taken now, while the caret still exists.
  /// The composer takes focus the instant it appears, and the editor then has
  /// no selection to read — so a submit that asked "what is above the cursor?"
  /// at send time would find no cursor and fall back to the whole page.
  ///
  /// The side panel is still the home of Write, Quiz and Do, and of the
  /// question history — the top bar's Ask button opens it.
  void _onAskCommand(String question) =>
      ref.read(inlineAskProvider.notifier).openWith(
            question,
            anchor: _caretInCanvas(),
            above: _readTextAboveCursor(),
          );

  /// The caret, in the canvas Stack's coordinates.
  ///
  /// `selectionRects` reports in global space; `globalToLocal` walks back down
  /// through the zoom transform and the scroll view, so the result is where
  /// the caret actually sits on screen whatever the zoom.
  Offset? _caretInCanvas() {
    final rects = _editorState.selectionRects();
    if (rects.isEmpty) return null;
    final box = _canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    // The BOTTOM of the caret: the composer hangs below the line it was
    // summoned from, rather than covering it.
    return box.globalToLocal(rects.first.bottomLeft);
  }

  void _onSummaryCommand() =>
      ref.read(aiPanelProvider.notifier).askQuestion(kSummaryRequest);

  void _onQuizCommand() =>
      ref.read(aiPanelProvider.notifier).showTab(AiPanelTab.quiz);

  /// Ask what to export, then export it through the same exporters the nav
  /// tree's page menu uses.
  ///
  /// The flush stays where it was — after the choice, before the export. A
  /// pending debounced save has to land first: both exporters read the page
  /// back from Drive, so without this the file would be the last autosave
  /// rather than what is on screen.
  Future<void> _export() async {
    final request = await showExportDialog(context, page: widget.page);
    if (request == null || !mounted) return;
    if (_status == SaveStatus.dirty) {
      _saveTimer?.cancel();
      await _save();
      if (!mounted) return;
    }
    final content = GetIt.I<PageContentRepository>();
    final assets = GetIt.I<AssetSyncService>();
    switch (request.format) {
      case ExportFormat.markdown:
        await MarkdownExporter(content, assets)
            .exportPageToFile(context, widget.page);
      case ExportFormat.pdf:
        await PdfExporter(content, assets)
            .exportPageToFile(context, widget.page, paper: request.paper);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    // Ground behind the paper. The header above it and the composer below it
    // sit on the same `surface`, so the three read as one page with the paper
    // floating on top rather than as three stacked bands.
    // One continuous writing surface. The remodel drops the floating-card
    // metaphor: there is no ground showing around the page any more, so the
    // pane and the paper are the same colour and the "card" is only a width
    // constraint on the column of text.
    // The ground the writing column sits ON. The artboard makes the whole
    // pane paper, which reads as one continuous sheet — and on a wide display
    // that leaves nothing to tell you where the page you are writing on
    // begins. The column keeps `paper`; the pane around it is the ground.
    final canvasBg = scheme.surface;

    // Paper is the design's writing surface — surfaceContainerHigh on all
    // four grounds.
    final paper = scheme.surfaceContainerHigh;

    // AppFlowy applies editorStyle.padding to EVERY block (page_block_component
    // wraps each item in `Padding(padding: editorStyle.padding)`), so any
    // vertical value here lands between each line and the next — 8px here was
    // 16px between every two lines of a page. It is 0; the top and bottom
    // breathing room comes from the header and footer slots, and the line box
    // and block spacing are set in editor_typography.dart.
    final style = afe.EditorStyle.desktop(
      cursorColor: isDark ? MarioColors.primary : MarioColors.primaryPressed,
      selectionColor:
          MarioColors.primary.withValues(alpha: isDark ? 0.25 : 0.35),
      // Horizontal inset lives HERE, not in a Padding around the editor:
      // getNodeInOffset resolves a tap to the NEAREST node, so margin inside
      // the editor still places the caret on the adjacent line. Wrapping the
      // editor instead shrinks its gesture box and those taps hit dead space.
      padding: const EdgeInsets.symmetric(horizontal: kEditorInset),
      textStyleConfiguration: editorTextStyles(
        context,
        ink: isDark ? MarioColors.onSurfaceDark : MarioColors.onSurface,
      ),
      cursorWidth: 2.0,
    );

    final blockBuilders = <String, afe.BlockComponentBuilder>{
      ...afe.standardBlockComponentBuilderMap,
      // Headings and dividers with the preview's type, rules and spacing.
      ...editorTypographyBuilders(context),
      // Override the stock table with our wrapper that adds a whole-table
      // corner resize handle (keeps AppFlowy's table for editing/cells).
      afe.TableBlockKeys.type: MarioTableBlockComponentBuilder(),
      MarioImageKeys.type: MarioImageBlockBuilder(),
      MathBlockKeys.type: MathBlockComponentBuilder(),
      CodeBlockKeys.type: CodeBlockComponentBuilder(),
      DrawingBlockKeys.type: DrawingBlockComponentBuilder(),
      SpreadsheetBlockKeys.type: SpreadsheetBlockComponentBuilder(),
      AudioBlockKeys.type: AudioBlockComponentBuilder(),
    };
    // Every standard block (paragraphs, lists, headings, quotes…) takes its
    // padding from one place, editorBlockPadding — zero for text, so a page
    // written a line per block reads like a paragraph that wraps. The custom
    // Mario blocks own their own padding and are left alone.
    for (final entry in afe.standardBlockComponentBuilderMap.entries) {
      blockBuilders[entry.key]?.configuration = editorBlockConfiguration;
    }

    final standardSpaceHandlers =
        afe.standardCharacterShortcutEvents.where((e) => e.character != '/');
    final shortcutEvents = <afe.CharacterShortcutEvent>[
      marioMathShortcut,
      marioEmojiShortcut,
      ...standardSpaceHandlers,
      afe.customSlashCommand(
        [
          ...aiSelectionMenuItems(
            onAsk: _onAskCommand,
            onSummary: _onSummaryCommand,
            onQuiz: _onQuizCommand,
          ),
          ...afe.standardSelectionMenuItems,
          mathSelectionMenuItem,
          codeSelectionMenuItem,
          drawingSelectionMenuItem,
          spreadsheetSelectionMenuItem,
          audioSelectionMenuItem,
        ],
        style:
            isDark ? afe.SelectionMenuStyle.dark : afe.SelectionMenuStyle.light,
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
            trailing: ValueListenableBuilder<int>(
              valueListenable: _assetSweeper.pendingCount,
              builder: (context, pendingImages, _) =>
                  ValueListenableBuilder<int>(
                valueListenable: GetIt.I<SyncService>().pendingChanges,
                builder: (context, pendingChanges, _) => _PageActions(
                  pendingChanges: pendingChanges,
                  dictate: IconButtonTheme(
                    data: IconButtonThemeData(
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(5),
                        minimumSize: const Size(28, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                    ),
                    child: VoiceDictationButton(editorState: _editorState),
                  ),
                  status: _status,
                  lastSavedAt: _lastSavedAt,
                  pendingImages: pendingImages,
                  drawMode: _drawMode,
                  previewMode: _previewMode,
                  onExport: _export,
                  onToggleDraw: _toggleDraw,
                  onTogglePreview: _togglePreview,
                  onSaveNow: _saveNow,
                ),
              ),
            ),
          ),
          if (_drawMode)
            DrawingToolbar(
              controller: _drawingController,
              onCollapse: _toggleDraw,
              // No PNG export here: _exportPng captures a RenderRepaintBoundary
              // and the full-page canvas has none. The button hides rather
              // than pretending.
              onExport: null,
              onSave: _toggleDraw,
              collapsed: false,
            ),
          Expanded(
            child: _previewMode
                ? ValueListenableBuilder<String>(
                    valueListenable: _previewHtml,
                    builder: (context, html, _) {
                      final pinned = rawHtmlOverride.value?.isNotEmpty == true;
                      return HtmlPreviewPane(
                        html: html,
                        isDark: isDark,
                        title: pinned
                            ? 'HTML preview · pinned source'
                            : 'HTML preview',
                        primaryActionLabel: pinned ? 'Unpin' : null,
                        onPrimaryAction:
                            pinned ? () => rawHtmlOverride.value = null : null,
                      );
                    },
                  )
                : DropTarget(
                    onDragEntered: (_) => setState(() => _dragOver = true),
                    onDragExited: (_) => setState(() => _dragOver = false),
                    onDragDone: (details) {
                      setState(() => _dragOver = false);
                      _onFilesDropped([for (final f in details.files) f.path]);
                    },
                    child: Container(
                      color: canvasBg,
                      foregroundDecoration: _dragOver
                          ? BoxDecoration(
                              border: Border.all(
                                  color: MarioColors.primary, width: 3),
                              color:
                                  MarioColors.primary.withValues(alpha: 0.08),
                            )
                          : null,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = _columnWidth;
                          final scaledWidth = cardWidth * _zoom;
                          final viewportW = constraints.maxWidth;
                          final viewportH = constraints.maxHeight;
                          final outerWidth =
                              math.max<double>(scaledWidth, viewportW);

                          // The editor's LOGICAL height, chosen so that the
                          // scale transform lands it exactly on the viewport.
                          //
                          // Handing it the viewport height directly is what
                          // made the bottom of a zoomed page unreachable: at
                          // 1.2x, a viewport-tall editor renders 1.2 viewports
                          // tall, so its own scroll view thought it had
                          // already shown everything while the last fifth of
                          // it hung below the clip. Dividing gives the editor
                          // a shorter box whose scrollable content still
                          // covers the whole document.
                          final cardHeight = viewportH / _zoom;
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
                                  // TOP-aligned, not centred. The box here is
                                  // the editor at its UNSCALED height, and the
                                  // transform below grows it from its own top
                                  // edge — so centring it first pushed the
                                  // bottom of a zoomed page clean out of the
                                  // viewport, and the last stretch of a long
                                  // document could not be scrolled to at any
                                  // zoom but 100%. Horizontal centring is
                                  // still wanted, hence topCenter rather than
                                  // topLeft.
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    // Outer SizedBox is the *post-scale* width
                                    // so the parent's hit-test region covers
                                    // the whole visually-zoomed card.
                                    // OverflowBox then hands the unscaled
                                    // child its natural cardWidth constraints
                                    // inside that wider region.
                                    child: SizedBox(
                                      // BOTH dimensions post-scale. A
                                      // RenderBox only hit-tests inside its
                                      // own size, and Transform paints outside
                                      // it — so with the pre-scale height here
                                      // the bottom of a zoomed page was
                                      // visible but dead to the pointer: you
                                      // could read it and not click into it.
                                      // The width was already correct; the
                                      // height had been missed.
                                      width: scaledWidth,
                                      height: cardHeight * _zoom,
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
                                              key: _canvasKey,
                                              children: [
                                                // The paper. Soft-cornered, lifted
                                                // off the ground by the system's
                                                // own shadow (which is nothing at
                                                // all on the black ground).
                                                Positioned.fill(
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      color: paper,
                                                      // Hairline sides, so
                                                      // the column reads as
                                                      // a page on a ground
                                                      // rather than as an
                                                      // area of the pane.
                                                      // On Light the two
                                                      // tones are half a
                                                      // step apart and the
                                                      // edge is what
                                                      // actually carries it.
                                                      border: Border(
                                                        left: BorderSide(
                                                            color: scheme
                                                                .outlineVariant),
                                                        right: BorderSide(
                                                            color: scheme
                                                                .outlineVariant),
                                                      ),
                                                    ),
                                                    child: Material(
                                                      type: MaterialType
                                                          .transparency,
                                                      child: afe.AppFlowyEditor(
                                                        editorState:
                                                            _editorState,
                                                        editorStyle: style,
                                                        blockComponentBuilders:
                                                            blockBuilders,
                                                        characterShortcutEvents:
                                                            shortcutEvents,
                                                        commandShortcutEvents:
                                                            commandShortcuts,
                                                        autoFocus: true,
                                                        // The page's own
                                                        // heading, INSIDE
                                                        // the document.
                                                        // As a band above
                                                        // the canvas it
                                                        // neither scrolled
                                                        // nor scaled with
                                                        // the page, so at
                                                        // any zoom but 100%
                                                        // its column was a
                                                        // different width
                                                        // from the one
                                                        // below it and the
                                                        // two edges stepped
                                                        // apart. The
                                                        // artboard has it
                                                        // in the content
                                                        // anyway.
                                                        header: _PageHeader(
                                                          page: widget.page,
                                                        ),
                                                        // Breathing room
                                                        // under the last
                                                        // block. The ask
                                                        // composer used to
                                                        // live here, which
                                                        // pinned it to the
                                                        // foot of the page
                                                        // however far that
                                                        // was from what you
                                                        // were writing.
                                                        footer: const SizedBox(
                                                          height: 40,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                // Drawing surface on top — strokes
                                                // always visible; pointer capture
                                                // only when draw mode is on.
                                                Positioned.fill(
                                                  child: CanvasDrawingLayer(
                                                    controller:
                                                        _drawingController,
                                                    active: _drawMode,
                                                  ),
                                                ),
                                                // The ask composer, at the
                                                // caret. In the Stack rather
                                                // than in the document, so it
                                                // can sit where the cursor is
                                                // instead of at the foot of
                                                // the page. Renders nothing
                                                // until `/ask` opens it.
                                                const Positioned.fill(
                                                  child: InlineAsk(
                                                    inset: kEditorInset,
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
                          );
                        },
                      ),
                    ),
                  ),
          ),
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

/// The header overflow menu: the page-level actions the design's three
/// buttons have no room for. Both are real actions this screen owns.
enum _PageMenuAction { preview, saveNow }

/// Trims a name to null when there is nothing real in it, so a breadcrumb tag
/// is omitted rather than rendered blank.
String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// The page's own heading — breadcrumb over title, in the document.
///
/// The remodel moves this ONTO the writing surface and strips it back to two
/// lines. It used to be a band above the paper carrying breadcrumb tags, a
/// save dot, a 30px title and a row of four pill buttons; the artboard puts a
/// 12px section name over a 31px title and nothing else. The actions it used
/// to hold now sit at the right end of the format row — see [_PageActions].
///
/// It mounts in the editor's `header` slot, so it scrolls and scales with the
/// page. AppFlowy pads every BLOCK by `editorStyle.padding` and hands the
/// header through unpadded, exactly as it does the footer — hence the inset
/// here, which is what puts the title on the body's left edge.
class _PageHeader extends ConsumerWidget {
  const _PageHeader({required this.page});

  final NotePage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = marioTokens(context);
    final textTheme = Theme.of(context).textTheme;

    // Breadcrumb names come from the live index. A name that hasn't arrived
    // yet — or a section that has gone away — drops the line instead of
    // printing a stand-in.
    String? crumb;
    if (page.notebookId.isNotEmpty && page.sectionId.isNotEmpty) {
      final sections =
          ref.watch(shell.sectionsStreamProvider(page.notebookId)).valueOrNull;
      for (final s in sections ?? const []) {
        if (s.id == page.sectionId) crumb = _nonEmpty(s.name);
      }
    }
    if (crumb == null && page.notebookId.isNotEmpty) {
      final notebooks = ref.watch(shell.notebooksStreamProvider).valueOrNull;
      for (final n in notebooks ?? const []) {
        if (n.id == page.notebookId) crumb = _nonEmpty(n.name);
      }
    }

    final title = _nonEmpty(page.title);

    // The header is the top of the writing column, not a band across the pane
    // — so it paints the ground either side of itself and carries the same
    // paper, width and hairline edges the canvas below it does. Without that
    // the page began as a full-width white stripe and then narrowed.
    return Padding(
      // 40 above the breadcrumb and 26 below the title, as the artboard sets
      // them. The 26 was the SizedBox this replaced.
      padding: const EdgeInsets.fromLTRB(kEditorInset, 40, kEditorInset, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (crumb != null) ...[
            Text(
              crumb,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.2, color: t.mut),
            ),
            const SizedBox(height: 10),
          ],
          if (title != null)
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.displayLarge,
            ),
        ],
      ),
    );
  }
}

/// The page-level actions, at the right end of the format row.
///
/// The artboard draws "Saved", a share glyph and an overflow glyph there.
/// Dictate and Draw ride alongside them: they are page-level too, they were
/// in the header this replaces, and neither has another entry point.
class _PageActions extends StatelessWidget {
  const _PageActions({
    required this.status,
    required this.lastSavedAt,
    required this.pendingImages,
    required this.pendingChanges,
    required this.drawMode,
    required this.previewMode,
    required this.onExport,
    required this.onToggleDraw,
    required this.onTogglePreview,
    required this.onSaveNow,
    required this.dictate,
  });

  final SaveStatus status;
  final DateTime? lastSavedAt;

  /// Images in this page that haven't reached Drive yet. The save line is
  /// otherwise about the page JSON only, and "Saved" while a picture is still
  /// local-only would promise something the other devices won't see.
  final int pendingImages;

  /// Pages, sections and notebooks made, renamed or deleted on this device
  /// that the server has not heard about yet — the sync outbox. Same
  /// promise: "Saved" is true here, and not yet anywhere else.
  final int pendingChanges;

  final bool drawMode;
  final bool previewMode;
  final VoidCallback onExport;
  final VoidCallback onToggleDraw;
  final VoidCallback onTogglePreview;
  final VoidCallback onSaveNow;

  /// The app's single dictation control. One instance only: two would fight
  /// over the same VoiceService session.
  final Widget dictate;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);

    // The real save state, not a promise. `idle` means nothing has been typed
    // since the page was loaded from Drive, so there is genuinely nothing
    // outstanding either way.
    var saveLabel = switch (status) {
      SaveStatus.idle => lastSavedAt == null ? 'No changes' : 'Saved',
      SaveStatus.dirty => 'Unsaved',
      SaveStatus.saving => 'Saving…',
      SaveStatus.saved => 'Saved',
      SaveStatus.error => 'Save failed',
    };
    if (pendingImages > 0 && status != SaveStatus.error) {
      saveLabel = '$saveLabel · $pendingImages '
          'image${pendingImages == 1 ? '' : 's'} not synced';
    }
    if (pendingChanges > 0) {
      saveLabel = '$saveLabel · $pendingChanges '
          'change${pendingChanges == 1 ? '' : 's'} waiting to sync';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: pendingImages > 0
              ? '$pendingImages image(s) still uploading'
              : saveLabel,
          child: Text(
            saveLabel,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              color: status == SaveStatus.error
                  ? Theme.of(context).colorScheme.error
                  : t.mut,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _PageActionIcon(
          icon: Icons.ios_share,
          tooltip: 'Export this page',
          onTap: onExport,
        ),
        dictate,
        _PageActionIcon(
          icon: Icons.draw_outlined,
          tooltip: drawMode ? 'Exit drawing mode' : 'Draw on this page',
          active: drawMode,
          onTap: onToggleDraw,
        ),
        PopupMenuButton<_PageMenuAction>(
          tooltip: 'More',
          position: PopupMenuPosition.under,
          onSelected: (action) => switch (action) {
            _PageMenuAction.preview => onTogglePreview(),
            _PageMenuAction.saveNow => onSaveNow(),
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _PageMenuAction.preview,
              child:
                  Text(previewMode ? 'Hide HTML preview' : 'Show HTML preview'),
            ),
            const PopupMenuItem(
              value: _PageMenuAction.saveNow,
              child: Text('Save now  (Ctrl+S)'),
            ),
          ],
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(Icons.more_horiz, size: 18, color: t.sec),
          ),
        ),
      ],
    );
  }
}

/// One 18px glyph in the page-action row.
class _PageActionIcon extends StatelessWidget {
  const _PageActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            icon,
            size: 18,
            color: active ? t.accentText : t.sec,
          ),
        ),
      ),
    );
  }
}
