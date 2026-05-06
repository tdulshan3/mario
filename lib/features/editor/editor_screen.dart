/// EditorScreen — mounts AppFlowy editor for the selected page with debounced Drive autosave.
library;

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/note_page.dart';
import '../../core/services/drive_service.dart';
import '../../ui/colors.dart';
import '../math/math_shortcut.dart';
import '../voice/voice_dictation.dart';
import 'blocks/audio_block.dart';
import 'blocks/drawing_block.dart';
import 'blocks/mario_image_block.dart';
import 'blocks/math_block.dart';
import 'blocks/spreadsheet_block.dart';
import 'canvas_toolbar.dart';
import 'page_content_provider.dart';
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

  // Independent controllers so vertical and horizontal scrollbars can be
  // attached without sharing state with AppFlowy's internal scroller.
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _editorState = afe.EditorState(document: afe.Document.fromJson(widget.rawJson));
    _txSub = _editorState.transactionStream.listen(_onTransaction);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _txSub.cancel();
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _vScroll.dispose();
    _hScroll.dispose();
    final state = _editorState;
    WidgetsBinding.instance.addPostFrameCallback((_) => state.dispose());
    super.dispose();
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
    if (!HardwareKeyboard.instance.isControlPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final dy = (e as PointerScrollEvent).scrollDelta.dy;
      if (dy < 0) {
        _zoomIn();
      } else if (dy > 0) {
        _zoomOut();
      }
    });
  }

  void _onTransaction((afe.TransactionTime, afe.Transaction) event) {
    if (event.$1 != afe.TransactionTime.after) return;
    if (!mounted) return;
    setState(() => _status = SaveStatus.dirty);
    _saveTimer?.cancel();
    _saveTimer = Timer(_debounce, _save);
  }

  Future<void> _save() async {
    if (!mounted) return;
    setState(() => _status = SaveStatus.saving);
    final drive = GetIt.I<DriveService>();
    try {
      final json = _editorState.document.toJson();
      final payload = <String, dynamic>{
        ...json,
        'title': widget.page.title,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await drive.updatePageFile(widget.driveFileId, payload);
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
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    final canvasBg =
        isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE9E9E9);
    final paper = isDark ? const Color(0xFF242424) : Colors.white;

    final style = isDark
        ? afe.EditorStyle.desktop(
            cursorColor: MarioColors.primary,
            selectionColor: MarioColors.primary.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 24),
            textStyleConfiguration: afe.TextStyleConfiguration(
              text: GoogleFonts.inter(
                  fontSize: 14, color: MarioColors.onSurfaceDark, height: 1.35),
            ),
          )
        : afe.EditorStyle.desktop(
            cursorColor: MarioColors.primaryPressed,
            selectionColor: MarioColors.primary.withValues(alpha: 0.35),
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 24),
            textStyleConfiguration: afe.TextStyleConfiguration(
              text: GoogleFonts.inter(
                  fontSize: 14, color: MarioColors.onSurface, height: 1.35),
            ),
          );

    final blockBuilders = <String, afe.BlockComponentBuilder>{
      ...afe.standardBlockComponentBuilderMap,
      MarioImageKeys.type: MarioImageBlockBuilder(),
      MathBlockKeys.type: MathBlockComponentBuilder(),
      DrawingBlockKeys.type: DrawingBlockComponentBuilder(),
      SpreadsheetBlockKeys.type: SpreadsheetBlockComponentBuilder(),
      AudioBlockKeys.type: AudioBlockComponentBuilder(),
    };

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

    final scrollPhysics = _ctrlDown
        ? const NeverScrollableScrollPhysics()
        : const BouncingScrollPhysics();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveNow,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            _zoomReset,
      },
      child: Focus(
        autofocus: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CanvasToolbar(
              editorState: _editorState,
              zoom: _zoom,
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onZoomReset: _zoomReset,
              trailing: VoiceDictationButton(editorState: _editorState),
            ),
            Expanded(
              child: Container(
                color: canvasBg,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const cardWidth = 820.0;
                    final scaledWidth = cardWidth * _zoom;
                    final viewport = constraints.maxWidth;
                    // When the scaled card is narrower than the viewport, pad
                    // the inner row so the centred card has elbow room. When
                    // wider, the row matches the scaled width and the
                    // horizontal scrollview moves it.
                    final innerWidth =
                        scaledWidth < viewport ? viewport : scaledWidth + 32;
                    return Listener(
                      onPointerSignal: _onPointerSignal,
                      child: Scrollbar(
                        controller: _vScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _vScroll,
                          physics: scrollPhysics,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Scrollbar(
                            controller: _hScroll,
                            thumbVisibility: scaledWidth > viewport,
                            notificationPredicate: (n) => n.depth == 1,
                            child: SingleChildScrollView(
                              controller: _hScroll,
                              scrollDirection: Axis.horizontal,
                              physics: scrollPhysics,
                              child: SizedBox(
                                width: innerWidth,
                                child: Center(
                                  child: SizedBox(
                                    width: scaledWidth,
                                    child: FittedBox(
                                      fit: BoxFit.fitWidth,
                                      alignment: Alignment.topCenter,
                                      child: SizedBox(
                                        width: cardWidth,
                                        child: Material(
                                          color: paper,
                                          elevation: isDark ? 0 : 2,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              _PageHeader(page: widget.page),
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                        minHeight: 600),
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
                                                  shrinkWrap: true,
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
                      ),
                    );
                  },
                ),
              ),
            ),
            _StatusBar(
                status: _status, lastSavedAt: _lastSavedAt, muted: muted),
          ],
        ),
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
