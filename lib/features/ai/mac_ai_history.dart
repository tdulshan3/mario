part of 'ai_history.dart';

// The saved history, as the desktop inspector draws it.
//
// Same lists, same order, same actions as the Material tiles: a grouped box
// of rows with a hairline between them, each row a disclosure that opens on
// what was answered or done. Delete still asks first — `deleteSavedChat`
// shows the macOS alert on the desktop.

/// Past questions and answers on the Ask tab, or the reason there are none.
class _MacAskHistory extends StatelessWidget {
  const _MacAskHistory({
    required this.bridge,
    required this.history,
    required this.onReplay,
    required this.onPreview,
    required this.onDelete,
  });

  final AiEditorBridge? bridge;
  final AsyncValue<NotebookAiData> history;
  final void Function(AskEntry entry) onReplay;
  final ValueChanged<String> onPreview;
  final ValueChanged<AskEntry> onDelete;

  static const _emptyTitle = 'Ask About This Page';
  static const _emptyMessage =
      'Type /ask or /summary in the editor, or use the box below.';

  @override
  Widget build(BuildContext context) {
    final bridge = this.bridge;
    if (bridge == null) {
      return const MacEmptyState(
        title: 'Open a Page First',
        message: 'The panel reads whichever page is open.',
      );
    }
    return history.when(
      loading: () => const Center(child: MacSpinner(large: true)),
      error: (_, __) =>
          const MacEmptyState(title: _emptyTitle, message: _emptyMessage),
      data: (data) {
        final entries = _askOrder(data, bridge.pageId);
        if (entries.isEmpty) {
          return const MacEmptyState(
              title: _emptyTitle, message: _emptyMessage);
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const MacAiGroupTitle('Earlier Questions'),
            const SizedBox(height: 6),
            _MacHistoryBox(
              children: [
                for (final entry in entries)
                  _MacAskHistoryRow(
                    entry: entry,
                    fromThisPage: entry.pageId == bridge.pageId,
                    onReplay: () => onReplay(entry),
                    onDelete: () => onDelete(entry),
                    onPreview: switch (extractHtmlArtifact(entry.answer)) {
                      final html? => () => onPreview(html),
                      null => null,
                    },
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MacAskHistoryRow extends StatelessWidget {
  const _MacAskHistoryRow({
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
    return _MacHistoryRow(
      title: entry.question,
      meta: [
        if (!fromThisPage) 'another page',
        if (entry.usedWeb) 'web',
        _relative(entry.provenance.createdAt),
      ],
      details: [
        AiMarkdown(entry.answer, fontSize: 12),
        const SizedBox(height: 8),
        _MacHistoryActions(
          actions: [
            MacButton(
              label: 'Ask Again',
              icon: AppleIcons.arrowClockwise,
              onPressed: onReplay,
            ),
            if (onPreview != null)
              MacButton(
                label: 'Preview',
                icon: AppleIcons.eye,
                onPressed: onPreview,
              ),
          ],
          backend: entry.provenance.backend,
          onDelete: onDelete,
        ),
      ],
    );
  }
}

/// Past Do runs under the Do tab's launcher. Nothing at all until something
/// has run.
class _MacDoHistory extends StatelessWidget {
  const _MacDoHistory({
    required this.entries,
    required this.pageId,
    required this.onReplay,
    required this.onDelete,
  });

  final List<DoEntry> entries;
  final String pageId;

  /// Null while a run is in flight.
  final Future<void> Function(String instruction)? onReplay;
  final ValueChanged<DoEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const MacAiGroupTitle('Earlier Instructions'),
        const SizedBox(height: 6),
        _MacHistoryBox(
          children: [
            for (final entry in entries)
              _MacHistoryRow(
                title: entry.instruction,
                meta: [
                  if (entry.pageId != pageId) 'another page',
                  '${entry.applied.length} change(s)',
                  _relative(entry.provenance.createdAt),
                ],
                details: [
                  if (entry.summary.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: MacAiText(entry.summary),
                    ),
                  for (final line in entry.applied)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(AppleIcons.checkmark,
                                size: 11, color: c.accentGreen),
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: MacAiText(line, secondary: true)),
                        ],
                      ),
                    ),
                  if (entry.failed > 0 || entry.dropped > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: MacAiText(
                        [
                          if (entry.dropped > 0)
                            '${entry.dropped} proposed change(s) could not '
                                'be used',
                          if (entry.failed > 0)
                            '${entry.failed} could not be applied',
                        ].join('. '),
                        secondary: true,
                        small: true,
                      ),
                    ),
                  const SizedBox(height: 4),
                  _MacHistoryActions(
                    actions: [
                      MacButton(
                        label: 'Run Again',
                        icon: AppleIcons.arrowClockwise,
                        onPressed: onReplay == null
                            ? null
                            : () => onReplay!(entry.instruction),
                      ),
                    ],
                    backend: entry.provenance.backend,
                    onDelete: () => onDelete(entry),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Saved quizzes on the Quiz tab, with the last score and a way back in.
class _MacQuizHistory extends StatelessWidget {
  const _MacQuizHistory({
    required this.quizzes,
    required this.attempts,
    required this.onReview,
    required this.onRetake,
  });

  final List<Quiz> quizzes;
  final List<QuizAttempt> attempts;
  final void Function(Quiz quiz, QuizAttempt attempt) onReview;
  final ValueChanged<Quiz> onRetake;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const MacAiGroupTitle('Saved Quizzes'),
        const SizedBox(height: 6),
        _MacHistoryBox(
          children: [
            for (final quiz in quizzes)
              _macQuizRow(quiz, [
                for (final a in attempts)
                  if (a.quizId == quiz.id && a.isGraded) a,
              ]),
          ],
        ),
      ],
    );
  }

  Widget _macQuizRow(Quiz quiz, List<QuizAttempt> graded) {
    final last = graded.isEmpty ? null : graded.last;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MacAiText(quiz.title, emphasized: true, maxLines: 1),
                MacAiText(
                  last == null
                      ? '${quiz.items.length} question(s) · not attempted'
                      : '${quiz.items.length} question(s) · last score '
                          '${_trim(last.totalAwarded)}/${last.totalOutOf}',
                  secondary: true,
                  small: true,
                ),
              ],
            ),
          ),
          if (last != null)
            MacAiIconButton(
              icon: AppleIcons.eye,
              label: 'Review marks',
              onPressed: () => onReview(quiz, last),
            ),
          MacAiIconButton(
            icon: AppleIcons.arrowClockwise,
            label: 'Retake',
            onPressed: () => onRetake(quiz),
          ),
        ],
      ),
    );
  }
}

/// A grouped box of history rows with a hairline between them.
class _MacHistoryBox extends StatelessWidget {
  const _MacHistoryBox({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => MacGroupBox(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const MacAiSeparator(),
              children[i],
            ],
          ],
        ),
      );
}

/// One history row: a disclosure, the question or instruction (two lines at
/// most), a grey line of facts under it, and the details when opened.
///
/// The text toggles the row as well as the chevron — the row is the thing
/// people click, as in the Material tile.
class _MacHistoryRow extends StatefulWidget {
  const _MacHistoryRow({
    required this.title,
    required this.meta,
    required this.details,
  });

  final String title;
  final List<String> meta;
  final List<Widget> details;

  @override
  State<_MacHistoryRow> createState() => _MacHistoryRowState();
}

class _MacHistoryRowState extends State<_MacHistoryRow> {
  bool _open = false;

  void _toggle(bool open) => setState(() => _open = open);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MacDisclosure(
                open: _open,
                onToggle: _toggle,
                semanticLabel: widget.title,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggle(!_open),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MacAiText(widget.title, maxLines: 2),
                      MacAiText(widget.meta.join(' · '),
                          secondary: true, small: true, maxLines: 1),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.details,
              ),
            ),
        ],
      ),
    );
  }
}

/// The foot of an opened row: its actions, which backend answered, and
/// delete at the far end.
class _MacHistoryActions extends StatelessWidget {
  const _MacHistoryActions({
    required this.actions,
    required this.backend,
    required this.onDelete,
  });

  final List<Widget> actions;
  final String backend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final a in actions) ...[a, const SizedBox(width: 8)],
        Expanded(
          child: MacAiText(backend,
              secondary: true,
              small: true,
              maxLines: 1,
              textAlign: TextAlign.end),
        ),
        MacAiIconButton(
          icon: AppleIcons.trash,
          label: 'Delete this chat',
          onPressed: onDelete,
        ),
      ],
    );
  }
}
