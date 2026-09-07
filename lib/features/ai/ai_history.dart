/// Browsing what the AI features have already produced.
///
/// Every answer, quiz and marked attempt has been saved to Drive since the
/// first version — it just had nowhere to be seen. These lists are that
/// missing half: the Ask tab opens on past questions instead of an empty box,
/// and the Quiz tab offers to retake or review a quiz rather than only ever
/// generating a new one.
///
/// Scoped to the open notebook, newest first, and read through the same
/// local-first store the rest of the AI layer uses, so it works offline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/ai/ai_artifacts.dart';
import '../../ui/colors.dart';
import '../shell/dialogs/text_input_dialog.dart';
import 'ai_markdown.dart';
import 'html_artifact.dart';
import 'ai_session_state.dart';
import 'ai_state.dart';
import '../../ui/widgets/mario_loader.dart';

/// The notebook's saved artifacts, or empty when no page is open.
final aiHistoryProvider = FutureProvider<NotebookAiData>((ref) async {
  final bridge = ref.watch(aiEditorBridgeProvider);
  if (bridge == null) return const NotebookAiData();
  return ref.watch(aiArtifactStoreProvider).load(bridge.notebookId);
});

/// Past questions and answers, newest first.
class AskHistoryList extends ConsumerWidget {
  const AskHistoryList({super.key, required this.onReplay});

  /// Ask the same question again — useful when the notes have moved on.
  final void Function(AskEntry entry) onReplay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bridge = ref.watch(aiEditorBridgeProvider);
    final history = ref.watch(aiHistoryProvider);

    if (bridge == null) {
      return const _Empty(
        icon: Icons.auto_awesome_outlined,
        title: 'Open a page first',
        detail: 'The panel reads whichever page is open.',
      );
    }

    return history.when(
      loading: () => const _Loading(),
      error: (e, _) => _Empty(
        icon: Icons.auto_awesome_outlined,
        title: 'Ask about this page',
        detail: 'Type /ask or /summary in the editor, or use the box below.',
      ),
      data: (data) {
        // This page first, then the rest of the notebook — a question asked
        // about the page you are looking at is the one you want back — and
        // newest first within each. (Reversing the two groups as one list
        // used to put the rest of the notebook on top.)
        final entries = [
          ...data.asks
              .where((a) => a.pageId == bridge.pageId)
              .toList()
              .reversed,
          ...data.asks
              .where((a) => a.pageId != bridge.pageId)
              .toList()
              .reversed,
        ];

        if (entries.isEmpty) {
          return const _Empty(
            icon: Icons.auto_awesome_outlined,
            title: 'Ask about this page',
            detail:
                'Type /ask or /summary in the editor, or use the box below.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          itemCount: entries.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Earlier questions',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            final entry = entries[i - 1];
            final html = extractHtmlArtifact(entry.answer);
            return _AskHistoryTile(
              entry: entry,
              fromThisPage: entry.pageId == bridge.pageId,
              onReplay: () => onReplay(entry),
              onDelete: () => deleteSavedChat(context, ref,
                  notebookId: bridge.notebookId, id: entry.id),
              onPreview: html == null
                  ? null
                  : () {
                      ref
                          .read(agentSessionProvider.notifier)
                          .previewArtifact(html);
                      ref
                          .read(aiPanelProvider.notifier)
                          .showTab(AiPanelTab.agent);
                    },
            );
          },
        );
      },
    );
  }
}

/// Deletes one saved chat, after asking.
///
/// Asks, because it is final: the entry goes from the notebook's file on
/// Drive, and the id is remembered so a copy on another device cannot bring
/// it back. The list is refreshed afterwards through the same provider the
/// quiz tab invalidates after a mutation.
Future<void> deleteSavedChat(
  BuildContext context,
  WidgetRef ref, {
  required String notebookId,
  required String id,
}) async {
  final ok = await showConfirmDialog(
    context,
    title: 'Delete this chat?',
    message: 'It is removed from this notebook\'s history on every device. '
        'The page itself is not changed.',
  );
  // The tile can be gone by the time the dialog closes, and `ref` with it.
  if (!ok || !context.mounted) return;
  await ref.read(aiArtifactStoreProvider).removeEntry(notebookId, id);
  if (!context.mounted) return;
  ref.invalidate(aiHistoryProvider);
}

/// A small trailing delete control, the same in every history tile.
class _DeleteChatButton extends StatelessWidget {
  const _DeleteChatButton({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Delete this chat',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.delete_outline,
            size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        onPressed: onDelete,
      );
}

class _AskHistoryTile extends StatelessWidget {
  const _AskHistoryTile({
    required this.entry,
    required this.fromThisPage,
    required this.onReplay,
    required this.onDelete,
    required this.onPreview,
  });

  final AskEntry entry;
  final bool fromThisPage;
  final VoidCallback onReplay;
  final VoidCallback onDelete;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The surface colour lives on a Material, not on the Container.
    // ExpansionTile is a ListTile, and a ListTile paints its background and ink
    // splashes onto the nearest Material ancestor — a coloured DecoratedBox in
    // between hides both, which Flutter asserts about in debug.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: scheme.surface,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            title: Text(
              entry.question,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            subtitle: Row(
              children: [
                if (!fromThisPage) ...[
                  Icon(Icons.description_outlined,
                      size: 11, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text('another page',
                      style: GoogleFonts.inter(
                          fontSize: 10, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                ],
                if (entry.usedWeb) ...[
                  Icon(Icons.public, size: 11, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 3),
                ],
                Expanded(
                  child: Text(
                    _relative(entry.provenance.createdAt),
                    style: GoogleFonts.inter(
                        fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            children: [
              AiMarkdown(entry.answer, fontSize: 12),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onReplay,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Ask again'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: GoogleFonts.inter(fontSize: 11.5),
                    ),
                  ),
                  if (onPreview != null)
                    TextButton.icon(
                      onPressed: onPreview,
                      icon: const Icon(Icons.preview_outlined, size: 14),
                      label: const Text('Preview'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: GoogleFonts.inter(fontSize: 11.5),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    entry.provenance.backend,
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
                  _DeleteChatButton(onDelete: onDelete),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Past Do runs — what was asked, and what it did — newest first.
///
/// A column rather than a list, because it sits under the Do tab's launcher
/// in a ListView of its own, and is empty (and invisible) until something
/// has been run.
class DoHistoryList extends ConsumerWidget {
  const DoHistoryList({super.key, required this.onReplay});

  /// Run the same instruction again. Null while a run is in flight.
  final Future<void> Function(String instruction)? onReplay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bridge = ref.watch(aiEditorBridgeProvider);
    final history = ref.watch(aiHistoryProvider);
    if (bridge == null) return const SizedBox.shrink();

    return history.maybeWhen(
      data: (data) {
        if (data.dos.isEmpty) return const SizedBox.shrink();
        // This page first, then the rest of the notebook, newest first within
        // each — same order as the Ask history, for the same reason.
        final entries = [
          ...data.dos.where((d) => d.pageId == bridge.pageId).toList().reversed,
          ...data.dos.where((d) => d.pageId != bridge.pageId).toList().reversed,
        ].take(30).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Earlier instructions',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final entry in entries)
              _DoHistoryTile(
                entry: entry,
                fromThisPage: entry.pageId == bridge.pageId,
                onReplay: onReplay == null
                    ? null
                    : () => onReplay!(entry.instruction),
                onDelete: () => deleteSavedChat(context, ref,
                    notebookId: bridge.notebookId, id: entry.id),
              ),
          ],
        );
      },
      orElse: SizedBox.shrink.call,
    );
  }
}

class _DoHistoryTile extends StatelessWidget {
  const _DoHistoryTile({
    required this.entry,
    required this.fromThisPage,
    required this.onReplay,
    required this.onDelete,
  });

  final DoEntry entry;
  final bool fromThisPage;
  final VoidCallback? onReplay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted =
        GoogleFonts.inter(fontSize: 10, color: scheme.onSurfaceVariant);
    // Same Material-under-the-tile arrangement as the Ask tile, for the same
    // reason: a ListTile paints onto the nearest Material.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: scheme.surface,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            title: Text(
              entry.instruction,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            subtitle: Row(
              children: [
                if (!fromThisPage) ...[
                  Icon(Icons.description_outlined,
                      size: 11, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text('another page', style: muted),
                  const SizedBox(width: 8),
                ],
                Text(
                  '${entry.applied.length} change(s)',
                  style: muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      Text(_relative(entry.provenance.createdAt), style: muted),
                ),
              ],
            ),
            children: [
              if (entry.summary.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    entry.summary,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.4,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              for (final line in entry.applied)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check,
                          size: 12, color: MarioColors.labelGreen),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(line,
                            style: GoogleFonts.inter(
                                fontSize: 11.5,
                                height: 1.35,
                                color: scheme.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
              if (entry.failed > 0 || entry.dropped > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Text(
                    [
                      if (entry.dropped > 0)
                        '${entry.dropped} proposed change(s) could not be used',
                      if (entry.failed > 0)
                        '${entry.failed} could not be applied',
                    ].join('. '),
                    style: GoogleFonts.inter(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onReplay,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Run again'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: GoogleFonts.inter(fontSize: 11.5),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    entry.provenance.backend,
                    style: GoogleFonts.inter(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
                  _DeleteChatButton(onDelete: onDelete),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saved quizzes, with the best score so far and a way back in.
class QuizHistoryList extends ConsumerWidget {
  const QuizHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final history = ref.watch(aiHistoryProvider);

    return history.maybeWhen(
      data: (data) {
        if (data.quizzes.isEmpty) return const SizedBox.shrink();
        final quizzes = data.quizzes.reversed.take(10).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Text(
              'Saved quizzes',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            for (final quiz in quizzes)
              _QuizHistoryTile(
                quiz: quiz,
                attempts: [
                  for (final a in data.attempts)
                    if (a.quizId == quiz.id) a,
                ],
              ),
          ],
        );
      },
      orElse: SizedBox.shrink.call,
    );
  }
}

class _QuizHistoryTile extends ConsumerWidget {
  const _QuizHistoryTile({required this.quiz, required this.attempts});

  final Quiz quiz;
  final List<QuizAttempt> attempts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final graded = [
      for (final a in attempts)
        if (a.isGraded) a,
    ];
    final last = graded.isEmpty ? null : graded.last;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quiz.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  last == null
                      ? '${quiz.items.length} question(s) · not attempted'
                      : '${quiz.items.length} question(s) · last score '
                          '${_trim(last.totalAwarded)}/${last.totalOutOf}',
                  style: GoogleFonts.inter(
                      fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (last != null)
            IconButton(
              tooltip: 'Review marks',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.fact_check_outlined, size: 16),
              onPressed: () =>
                  ref.read(quizSessionProvider.notifier).review(quiz, last),
            ),
          IconButton(
            tooltip: 'Retake',
            visualDensity: VisualDensity.compact,
            icon:
                Icon(Icons.replay, size: 16, color: MarioColors.primaryPressed),
            onPressed: () =>
                ref.read(quizSessionProvider.notifier).retake(quiz),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) =>
      const Center(child: MarioLoader(size: 28));
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              title,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

String _relative(DateTime when) {
  final d = DateTime.now().difference(when);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${when.year}-${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
