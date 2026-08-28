/// The Ask tab — where `/ask` and `/summary` land.
///
/// A view over [askSessionProvider]. Nothing that matters lives in this
/// widget's `State`, because the panel destroys the widget whenever you switch
/// tabs — the run, the draft question and the web preference all outlive it.
///
/// With no run in flight it shows the saved question history instead of an
/// empty box. The answer is deliberately *not* written to the page
/// automatically: it arrives here first so the user can read it, decide it is
/// right, and only then commit it to their own notes.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/ai/ai_artifacts.dart';
import '../../ui/colors.dart';
import 'ai_history.dart';
import 'ai_markdown.dart';
import 'ai_progress.dart';
import 'ai_progress_view.dart';
import 'ai_session_state.dart';
import 'ai_state.dart';
import 'ai_tasks.dart';

/// Sentinel the `/summary` command puts in the pending-question slot, to mean
/// "summarise the note above the cursor" rather than a literal question.
///
/// A shape nobody types by accident. It was briefly a leading control
/// character, which worked but made git treat this whole file as binary — no
/// diffs, no review, no merge.
const String kSummaryRequest = '__mario_summary__';

class AskPanel extends ConsumerStatefulWidget {
  const AskPanel({super.key});

  @override
  ConsumerState<AskPanel> createState() => _AskPanelState();
}

class _AskPanelState extends ConsumerState<AskPanel> {
  // Controllers and scroll offset are the only genuinely view-local things
  // here; the text they hold is mirrored into the session so it survives a
  // tab switch.
  late final TextEditingController _controller;
  final _focus = FocusNode();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: ref.read(askSessionProvider).draft);
    // A question handed over by the slash command runs as soon as we mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(aiPanelProvider.notifier).takePendingQuestion();
      if (pending == null) {
        _focus.requestFocus();
      } else if (pending == kSummaryRequest) {
        _runSummary();
      } else {
        _controller.text = pending;
        _submit();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  AiTaskContext? _buildContext({required bool aboveCursorOnly}) {
    final bridge = ref.read(aiEditorBridgeProvider);
    if (bridge == null) return null;
    final note = aboveCursorOnly ? bridge.readAboveCursor() : bridge.readPage();
    return AiTaskContext(
      notebookId: bridge.notebookId,
      pageId: bridge.pageId,
      note: note,
    );
  }

  void _submit() {
    final question = _controller.text.trim();
    if (question.isEmpty) return;
    final ctx = _buildContext(aboveCursorOnly: false);
    if (ctx == null) return;

    final run = ref.read(aiTasksProvider).ask(
          question: question,
          ctx: ctx,
          useWeb: ref.read(askSessionProvider).useWeb,
        );
    ref.read(askSessionProvider.notifier).startRun(run, question: question);
    _saveWhenDone(run, question: question, ctx: ctx);
  }

  void _runSummary() {
    final bridge = ref.read(aiEditorBridgeProvider);
    final ctx = _buildContext(aboveCursorOnly: true);
    if (bridge == null || ctx == null) return;
    const label = 'Summary of the notes above';
    final run = ref.read(aiTasksProvider).summarize(ctx);
    ref.read(askSessionProvider.notifier).startRun(run, question: label);
    _saveWhenDone(run, question: label, ctx: ctx);

    // A summary doubles as the cached context that makes later questions and
    // section-wide quizzes cheap — but only when it actually covers the whole
    // page. `/summary` with the caret halfway down summarises just the part
    // above it, and caching that as *the* page summary would later hand a
    // quiz generator half a page while telling it the summary was current.
    final wholePage = bridge.readPage();
    if (ctx.note.render() == wholePage.render()) {
      _cacheSummaryWhenDone(run, ctx);
    }
  }

  /// Persists a finished run to Drive.
  ///
  /// Listens rather than awaits: the run is what the UI already rebuilds on,
  /// and saving must never delay the answer appearing.
  ///
  /// The store is captured *now*, while `ref` is valid, rather than read inside
  /// the callback. The run outlives this widget — a local model can still be
  /// generating when the user closes the panel or switches tab — and reading
  /// `ref` from a listener that fires after disposal throws
  /// "Cannot use ref after the widget was disposed". Guarding on `mounted`
  /// instead would compile, but it would silently discard the answer the user
  /// waited thirty seconds for, which is worse than the crash.
  void _saveWhenDone(
    AiRun run, {
    required String question,
    required AiTaskContext ctx,
  }) {
    final store = ref.read(aiArtifactStoreProvider);
    void listener() {
      final s = run.value;
      if (s.status != AiRunStatus.done || !s.hasAnswer) return;
      run.removeListener(listener);
      final entry = AskEntry(
        id: 'ask-${DateTime.now().microsecondsSinceEpoch}',
        pageId: ctx.pageId,
        question: question,
        answer: s.answer,
        sources: s.sources,
        usedWeb: s.sources.isNotEmpty,
        provenance: AiProvenance(
          backend: s.backendLabel ?? 'unknown',
          model: '',
          createdAt: DateTime.now(),
        ),
      );
      // Best-effort: the answer is on screen either way, and the store keeps a
      // local copy when Drive is unreachable.
      store.addAsk(ctx.notebookId, entry).ignore();
    }

    run.addListener(listener);
  }

  void _cacheSummaryWhenDone(AiRun run, AiTaskContext ctx) {
    // Captured for the same reason as in [_saveWhenDone].
    final store = ref.read(aiArtifactStoreProvider);
    void listener() {
      final s = run.value;
      if (s.status != AiRunStatus.done || !s.hasAnswer) return;
      run.removeListener(listener);
      store
          .putSummary(
            ctx.notebookId,
            NoteSummary(
              pageId: ctx.pageId,
              sourceHash: sourceHashOf(ctx.note.render()),
              summary: s.answer,
              provenance: AiProvenance(
                backend: s.backendLabel ?? 'unknown',
                model: '',
                createdAt: DateTime.now(),
              ),
            ),
          )
          .ignore();
    }

    run.addListener(listener);
  }

  Future<void> _insert(AiRunState state) async {
    final bridge = ref.read(aiEditorBridgeProvider);
    final session = ref.read(askSessionProvider);
    if (bridge == null) return;
    final notifier = ref.read(askSessionProvider.notifier)..setInserting(true);
    final entry = AskEntry(
      id: 'inline',
      pageId: bridge.pageId,
      question: session.lastQuestion.isEmpty ? 'Summary' : session.lastQuestion,
      answer: state.answer,
      sources: state.sources,
      usedWeb: state.sources.isNotEmpty,
      provenance: AiProvenance(
        backend: state.backendLabel ?? 'unknown',
        model: '',
        createdAt: DateTime.now(),
      ),
    );
    final ok = await bridge.insertMarkdown(renderAskForPage(entry));
    notifier.insertFinished(
        error: ok ? null : 'Could not insert — the page was closed.');
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(aiEditorBridgeProvider);
    final session = ref.watch(askSessionProvider);
    final run = session.run;

    // Keep the field in step when the session changed the draft from elsewhere
    // — a slash command, or a rebuild after a tab switch.
    //
    // Safe to do inline because the draft is written back from the TextField's
    // `onChanged`, which fires only on real user input. A controller *listener*
    // would also fire on this programmatic assignment, write to the provider
    // mid-build, and throw "Tried to modify a provider while the widget tree
    // was building".
    if (_controller.text != session.draft) {
      _controller.value = TextEditingValue(
        text: session.draft,
        selection: TextSelection.collapsed(offset: session.draft.length),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: run == null
              ? AskHistoryList(onReplay: (entry) {
                  _controller.text = entry.question;
                  _submit();
                })
              : ValueListenableBuilder<AiRunState>(
                  valueListenable: run,
                  builder: (context, state, _) => ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    children: [
                      AiProgressView(
                        state: state,
                        onCancel: ref.read(askSessionProvider.notifier).stop,
                      ),
                      if (state.error != null) ...[
                        const SizedBox(height: 10),
                        _ErrorBox(
                          message: state.error!,
                          detail: state.errorDetail,
                        ),
                      ],
                      if (state.reasoning.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ReasoningDisclosure(text: state.reasoning),
                      ],
                      if (state.hasAnswer) ...[
                        const SizedBox(height: 12),
                        // Models answer in Markdown; showing it raw makes the
                        // reader parse the punctuation instead of the meaning.
                        AiMarkdown(state.answer),
                      ],
                      if (state.sources.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _Sources(sources: state.sources),
                      ],
                      if (state.backendLabel != null) ...[
                        const SizedBox(height: 12),
                        _BackendFooter(label: state.backendLabel!),
                      ],
                      if (state.status == AiRunStatus.done &&
                          state.hasAnswer) ...[
                        const SizedBox(height: 10),
                        _Actions(
                          busy: session.inserting,
                          canInsert: bridge != null,
                          inserted: ref
                              .read(askSessionProvider.notifier)
                              .alreadyInserted(run),
                          error: session.insertError,
                          onInsert: () => _insert(state),
                          onCopy: () => Clipboard.setData(
                              ClipboardData(text: state.answer)),
                          onHistory:
                              ref.read(askSessionProvider.notifier).clear,
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        const Divider(height: 1),
        _Composer(
          controller: _controller,
          focusNode: _focus,
          enabled: bridge != null,
          useWeb: session.useWeb,
          onWebChanged: ref.read(askSessionProvider.notifier).cycleWeb,
          onDraftChanged: ref.read(askSessionProvider.notifier).setDraft,
          onSubmit: _submit,
          onSummarize: _runSummary,
        ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.useWeb,
    required this.onWebChanged,
    required this.onDraftChanged,
    required this.onSubmit,
    required this.onSummarize,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool? useWeb;
  final VoidCallback onWebChanged;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onSubmit;
  final VoidCallback onSummarize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _WebToggle(value: useWeb, onChanged: onWebChanged),
              const Spacer(),
              TextButton.icon(
                onPressed: enabled ? onSummarize : null,
                icon: const Icon(Icons.subject, size: 15),
                label: const Text('Summarise'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: GoogleFonts.inter(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.send,
            onChanged: onDraftChanged,
            onSubmitted: (_) => onSubmit(),
            style: GoogleFonts.inter(fontSize: 13),
            decoration: InputDecoration(
              hintText: enabled
                  ? 'Ask about this page...'
                  : 'Open a page to ask about it',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: scheme.outlineVariant),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_upward, size: 16),
                onPressed: enabled ? onSubmit : null,
                tooltip: 'Ask',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Auto / on / off for the web.
///
/// Three states rather than a plain switch because "off" is a real
/// requirement, not a preference: a search sends a question derived from
/// private notes to a third party, and some notes should never leave the
/// machine.
class _WebToggle extends StatelessWidget {
  const _WebToggle({required this.value, required this.onChanged});

  final bool? value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = switch (value) {
      true => (Icons.public, 'Web: on'),
      false => (Icons.public_off, 'Web: off'),
      null => (Icons.auto_awesome, 'Web: auto'),
    };
    return TextButton.icon(
      onPressed: onChanged,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: value == true
            ? MarioColors.primaryPressed
            : scheme.onSurfaceVariant,
        textStyle: GoogleFonts.inter(fontSize: 12),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.busy,
    required this.canInsert,
    required this.inserted,
    required this.error,
    required this.onInsert,
    required this.onCopy,
    required this.onHistory,
  });

  final bool busy;
  final bool canInsert;

  /// True once this answer has been written into the page, so the button says
  /// so instead of silently inserting a duplicate.
  final bool inserted;

  final String? error;
  final VoidCallback onInsert;
  final VoidCallback onCopy;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: busy || !canInsert || inserted ? null : onInsert,
              icon: busy
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(inserted ? Icons.check : Icons.playlist_add, size: 16),
              label: Text(inserted ? 'Inserted' : 'Insert into page'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 15),
              label: const Text('Copy'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: GoogleFonts.inter(fontSize: 12),
              ),
            ),
            TextButton.icon(
              onPressed: onHistory,
              icon: const Icon(Icons.history, size: 15),
              label: const Text('History'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: GoogleFonts.inter(fontSize: 12),
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error!,
              style: GoogleFonts.inter(
                  fontSize: 11, color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _ReasoningDisclosure extends StatelessWidget {
  const _ReasoningDisclosure({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          "Model's reasoning",
          style:
              GoogleFonts.inter(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        children: [
          SelectableText(
            text.trim(),
            style: GoogleFonts.inter(
              fontSize: 11,
              height: 1.4,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sites the answer was written from.
///
/// Numbered to match the `[1]`, `[2]` markers in the answer, and each row leads
/// with the **domain** rather than the page title — "wikipedia.org" tells you
/// whether to trust a sentence; "Cell (biology) - Wikipedia" mostly tells you
/// what you already read. The whole row opens the page.
class _Sources extends StatelessWidget {
  const _Sources({required this.sources});
  final List<AiSource> sources;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 12, color: scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                'ANSWERED USING ${sources.length} WEB SOURCE'
                '${sources.length == 1 ? '' : 'S'}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < sources.length; i++)
            _SourceRow(index: i + 1, source: sources[i]),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.index, required this.source});

  final int index;
  final AiSource source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(source.url)?.host.replaceFirst('www.', '') ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: source.url.isEmpty
            ? null
            : () => launchUrl(Uri.parse(source.url),
                mode: LaunchMode.externalApplication),
        borderRadius: BorderRadius.circular(4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The marker the answer's [n] refers to.
            Container(
              margin: const EdgeInsets.only(top: 1),
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('$index',
                  style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (host.isNotEmpty)
                    Text(
                      host,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: MarioColors.primaryPressed,
                      ),
                    ),
                  Text(
                    source.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      height: 1.3,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new,
                size: 11,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _BackendFooter extends StatelessWidget {
  const _BackendFooter({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.memory, size: 12, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Answered by $label',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, this.detail});
  final String message;

  /// What the model actually said. Behind a disclosure because it is
  /// diagnostic, not an answer — but present, because with a local model it is
  /// usually the fastest way to tell a rambling reply from a truncated one.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final raw = detail?.trim();
    // Material, not a coloured Container: the disclosure below is a ListTile,
    // and a ListTile paints its ink onto the nearest Material ancestor.
    return Material(
      color: scheme.errorContainer.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: GoogleFonts.inter(
                  fontSize: 12, height: 1.4, color: scheme.onErrorContainer),
            ),
            if (raw != null && raw.isNotEmpty) ...[
              const SizedBox(height: 4),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  dense: true,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 6),
                  title: Text(
                    'What the model actually said',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: scheme.onErrorContainer),
                  ),
                  children: [
                    SelectableText(
                      // Capped: a runaway model can return a wall of text, and
                      // the first part is always the diagnostic part.
                      raw.length > 1200
                          ? '${raw.substring(0, 1200)}\n…(truncated)'
                          : raw,
                      style: GoogleFonts.robotoMono(
                        fontSize: 10.5,
                        height: 1.35,
                        color: scheme.onErrorContainer.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
