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
import 'ai_markdown.dart';
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
        // about the page you are looking at is the one you want back.
        final entries = [
          ...data.asks.where((a) => a.pageId == bridge.pageId),
          ...data.asks.where((a) => a.pageId != bridge.pageId),
        ].reversed.toList();

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
            return _AskHistoryTile(
              entry: entry,
              fromThisPage: entry.pageId == bridge.pageId,
              onReplay: () => onReplay(entry),
            );
          },
        );
      },
    );
  }
}

class _AskHistoryTile extends StatelessWidget {
  const _AskHistoryTile({
    required this.entry,
    required this.fromThisPage,
    required this.onReplay,
  });

  final AskEntry entry;
  final bool fromThisPage;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
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
                const Spacer(),
                Text(
                  entry.provenance.backend,
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ],
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
            icon: Icon(Icons.replay, size: 16, color: MarioColors.primaryPressed),
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
