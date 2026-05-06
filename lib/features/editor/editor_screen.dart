/// EditorScreen — mounts AppFlowy editor for the selected page with debounced Drive autosave.
library;

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/note_page.dart';
import '../../core/services/drive_service.dart';
import '../../ui/colors.dart';
import '../math/math_shortcut.dart';
import 'blocks/drawing_block.dart';
import 'blocks/math_block.dart';
import 'page_content_provider.dart';

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
      data: (document) => _Editor(
        key: ValueKey(fileId),
        page: page,
        driveFileId: fileId,
        initialDocument: document,
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
    required this.initialDocument,
  });

  final NotePage page;
  final String driveFileId;
  final afe.Document initialDocument;

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

  @override
  void initState() {
    super.initState();
    _editorState = afe.EditorState(document: widget.initialDocument);
    _txSub = _editorState.transactionStream.listen(_onTransaction);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _txSub.cancel();
    _editorState.dispose();
    super.dispose();
  }

  void _onTransaction((afe.TransactionTime, afe.Transaction) event) {
    // Only react after a transaction has been applied.
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;

    final style = isDark
        ? afe.EditorStyle.desktop(
            cursorColor: MarioColors.primary,
            selectionColor: MarioColors.primary.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 24),
            textStyleConfiguration: afe.TextStyleConfiguration(
              text: GoogleFonts.inter(
                  fontSize: 15, color: MarioColors.onSurfaceDark, height: 1.6),
            ),
          )
        : afe.EditorStyle.desktop(
            cursorColor: MarioColors.primaryPressed,
            selectionColor: MarioColors.primary.withValues(alpha: 0.35),
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 24),
            textStyleConfiguration: afe.TextStyleConfiguration(
              text: GoogleFonts.inter(
                  fontSize: 15, color: MarioColors.onSurface, height: 1.6),
            ),
          );

    final blockBuilders = <String, afe.BlockComponentBuilder>{
      ...afe.standardBlockComponentBuilderMap,
      MathBlockKeys.type: MathBlockComponentBuilder(),
      DrawingBlockKeys.type: DrawingBlockComponentBuilder(),
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
        ],
        style: isDark
            ? afe.SelectionMenuStyle.dark
            : afe.SelectionMenuStyle.light,
      ),
    ];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveNow,
      },
      child: Focus(
        autofocus: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PageHeader(page: widget.page),
            Expanded(
              child: afe.AppFlowyEditor(
                editorState: _editorState,
                editorStyle: style,
                blockComponentBuilders: blockBuilders,
                characterShortcutEvents: shortcutEvents,
                autoFocus: true,
              ),
            ),
            _StatusBar(status: _status, lastSavedAt: _lastSavedAt, muted: muted),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(64, 32, 64, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            page.title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Last edited ${_formatTime(page.updatedAt)}',
            style: GoogleFonts.inter(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: GoogleFonts.inter(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
