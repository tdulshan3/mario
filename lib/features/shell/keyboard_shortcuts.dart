/// Global keyboard shortcuts wrapping the shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/models/section.dart';
import '../../ui/mac/mac_look.dart';
import '../auth/auth_notifier.dart';
import '../search/global_search.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'mac_shortcuts_help.dart';
import 'shell_state.dart';

/// What the help (Ctrl+/) lists, in its order: the keys, then what they do.
/// One list for both looks, so the Material dialog and the macOS sheet
/// cannot disagree about the shortcuts.
const List<({String keys, String label})> kShortcutHelp = [
  (keys: 'Ctrl+N', label: 'New notebook'),
  (keys: 'Ctrl+Shift+N', label: 'New quick note'),
  (keys: 'Ctrl+T', label: 'New section'),
  (keys: 'Ctrl+Alt+N', label: 'New page'),
  (keys: 'Ctrl+F', label: 'Find in page'),
  (keys: 'Ctrl+Shift+F', label: 'Global search'),
  (keys: 'Ctrl+S', label: 'Save now'),
  (keys: 'Ctrl+,', label: 'Settings'),
  (keys: 'Ctrl+\\', label: 'Collapse / expand the sidebar'),
  (keys: 'Ctrl+/', label: 'Show this dialog'),
];

class GlobalShortcuts extends ConsumerWidget {
  const GlobalShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _newNotebook(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyN,
            control: true, shift: true): () => _quickNote(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
            _newSection(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyN,
            control: true, alt: true): () => _newPage(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyF,
            control: true, shift: true): () => showGlobalSearch(context),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            context.push('/settings'),
        const SingleActivator(LogicalKeyboardKey.slash, control: true): () =>
            _showHelp(context),
        // The sidebar's own header has no collapse control — the design gives
        // it a filter and a create button and nothing else — so this is the
        // way in. Clicking the collapsed strip is the way back out.
        const SingleActivator(LogicalKeyboardKey.backslash, control: true):
            () => ref.read(sidebarCollapsedProvider.notifier).update((c) => !c),
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  Future<void> _newNotebook(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final result = await showNotebookDialog(
      context,
      title: 'New notebook',
      submitLabel: 'Create',
    );
    if (result == null) return;
    final now = DateTime.now();
    final id = await ref.read(syncServiceProvider).createNotebook(Notebook(
          id: '',
          name: result.name,
          ownerId: user.uid,
          colorIndex: result.colorIndex,
          createdAt: now,
          updatedAt: now,
        ));
    ref.read(selectionProvider.notifier).selectNotebook(id);
  }

  Future<void> _quickNote(BuildContext context, WidgetRef ref) async {
    final title = await showTextInputDialog(
      context,
      title: 'Quick note',
      label: 'Title',
      submitLabel: 'Create',
    );
    if (title == null) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    var notebooks = ref.read(notebooksStreamProvider).valueOrNull ?? [];
    var quick = notebooks.where((n) => n.name == 'Quick Notes').firstOrNull;
    quick ??= await _createQuickNotesNotebook(ref, user.uid);

    final sections =
        ref.read(sectionsStreamProvider(quick.id)).valueOrNull ?? [];
    var section = sections.firstOrNull;
    section ??= await _createDefaultSection(ref, quick.id);

    final pages = ref
            .read(pagesStreamProvider(
                (notebookId: quick.id, sectionId: section.id)))
            .valueOrNull ??
        [];
    final order = pages.length;
    final now = DateTime.now();
    final pageId = await ref.read(syncServiceProvider).createPage(NotePage(
          id: '',
          sectionId: section.id,
          notebookId: quick.id,
          title: title,
          order: order,
          createdAt: now,
          updatedAt: now,
        ));
    ref.read(selectionProvider.notifier).selectNotebook(quick.id);
    ref.read(selectionProvider.notifier).selectSection(section.id);
    ref.read(selectionProvider.notifier).selectPage(pageId);
  }

  Future<Notebook> _createQuickNotesNotebook(WidgetRef ref, String uid) async {
    final now = DateTime.now();
    final id = await ref.read(syncServiceProvider).createNotebook(Notebook(
          id: '',
          name: 'Quick Notes',
          ownerId: uid,
          colorIndex: 2,
          createdAt: now,
          updatedAt: now,
        ));
    return Notebook(
      id: id,
      name: 'Quick Notes',
      ownerId: uid,
      colorIndex: 2,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Section> _createDefaultSection(
      WidgetRef ref, String notebookId) async {
    final id = await ref.read(syncServiceProvider).createSection(Section(
          id: '',
          notebookId: notebookId,
          name: 'Notes',
          colorIndex: 2,
          order: 0,
        ));
    return Section(
        id: id, notebookId: notebookId, name: 'Notes', colorIndex: 2, order: 0);
  }

  Future<void> _newSection(BuildContext context, WidgetRef ref) async {
    final selection = ref.read(selectionProvider);
    final notebookId = selection.notebookId;
    if (notebookId == null) return;
    final result = await showNotebookDialog(
      context,
      title: 'New section',
      submitLabel: 'Create',
    );
    if (result == null) return;
    final sections =
        ref.read(sectionsStreamProvider(notebookId)).valueOrNull ?? [];
    final id = await ref.read(syncServiceProvider).createSection(Section(
          id: '',
          notebookId: notebookId,
          name: result.name,
          colorIndex: result.colorIndex,
          order: sections.length,
        ));
    ref.read(selectionProvider.notifier).selectSection(id);
  }

  Future<void> _newPage(BuildContext context, WidgetRef ref) async {
    final selection = ref.read(selectionProvider);
    final notebookId = selection.notebookId;
    final sectionId = selection.sectionId;
    if (notebookId == null || sectionId == null) return;
    final title = await showTextInputDialog(
      context,
      title: 'New page',
      label: 'Title',
      submitLabel: 'Create',
    );
    if (title == null) return;
    final pages = ref
            .read(pagesStreamProvider(
                (notebookId: notebookId, sectionId: sectionId)))
            .valueOrNull ??
        [];
    final now = DateTime.now();
    final id = await ref.read(syncServiceProvider).createPage(NotePage(
          id: '',
          sectionId: sectionId,
          notebookId: notebookId,
          title: title,
          order: pages.length,
          createdAt: now,
          updatedAt: now,
        ));
    ref.read(selectionProvider.notifier).selectPage(id);
  }

  void _showHelp(BuildContext context) {
    if (useMacLook) {
      showMacShortcutsHelp(context);
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Keyboard shortcuts',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in kShortcutHelp) _ShortcutRow(s.keys, s.label),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.keys, this.label);
  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(keys,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 13))),
        ],
      ),
    );
  }
}
