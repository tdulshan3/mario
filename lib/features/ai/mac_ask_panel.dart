part of 'ask_panel.dart';

/// The Ask tab in the desktop inspector.
///
/// The same view over [askSessionProvider] as the Material tab — the saved
/// history when nothing is running, otherwise the run: its steps, the web
/// search as it happens, the reasoning behind a disclosure, the answer, its
/// sources and what can be done with it. Only the drawing differs: group
/// boxes instead of bordered cards, apple_ui buttons, label colours.
///
/// The answer itself is still the shared Markdown renderer; it is content,
/// and it takes the desktop's colours from the theme.
class _MacAskView extends StatelessWidget {
  const _MacAskView({
    required this.session,
    required this.scroll,
    required this.canInsert,
    required this.inserted,
    required this.onReplay,
    required this.onCancel,
    required this.onInsert,
    required this.onPreview,
    required this.onHistory,
    required this.onClearQuote,
  });

  final AskSession session;
  final ScrollController scroll;
  final bool canInsert;

  /// True once this answer has been written into the page, so the button
  /// says so instead of silently inserting a duplicate.
  final bool inserted;
  final void Function(AskEntry entry) onReplay;
  final VoidCallback onCancel;
  final Future<void> Function(AiRunState state) onInsert;
  final VoidCallback? Function(String answer) onPreview;
  final VoidCallback onHistory;
  final VoidCallback onClearQuote;

  @override
  Widget build(BuildContext context) {
    final run = session.run;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: run == null
              ? AskHistoryList(onReplay: onReplay)
              : ValueListenableBuilder<AiRunState>(
                  valueListenable: run,
                  builder: (context, state, _) => ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(12),
                    children: [
                      AiProgressView(state: state, onCancel: onCancel),
                      if (state.error != null) ...[
                        const SizedBox(height: 10),
                        MacAiErrorNote(
                          message: state.error!,
                          detail: state.errorDetail,
                        ),
                      ],
                      // The search before the answer: that is the order in
                      // which they influence it.
                      if (state.searchQuery != null) ...[
                        const SizedBox(height: 10),
                        _MacWebActivity(
                          query: state.searchQuery!,
                          sources: state.sources,
                          searching: state.steps.any((step) =>
                              step.kind == AiStepKind.searchingWeb &&
                              step.state == AiStepState.active),
                        ),
                      ],
                      if (state.reasoning.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _MacReasoning(text: state.reasoning),
                      ],
                      if (state.hasAnswer) ...[
                        const SizedBox(height: 12),
                        // StreamingMarkdown, for the reason the Material tab
                        // gives: re-rendering the whole answer per token is
                        // quadratic in its length.
                        RepaintBoundary(
                          child: StreamingMarkdown(
                            state.answer,
                            done: state.status != AiRunStatus.running,
                          ),
                        ),
                      ],
                      if (state.sources.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _MacSources(sources: state.sources),
                      ],
                      if (state.backendLabel != null) ...[
                        const SizedBox(height: 12),
                        MacAiText('Answered by ${state.backendLabel}',
                            secondary: true, small: true),
                      ],
                      if (state.status == AiRunStatus.done &&
                          state.hasAnswer) ...[
                        const SizedBox(height: 10),
                        _MacAskActions(
                          busy: session.inserting,
                          canInsert: canInsert,
                          inserted: inserted,
                          error: session.insertError,
                          onInsert: () => onInsert(state),
                          onCopy: () => Clipboard.setData(
                              ClipboardData(text: state.answer)),
                          onPreview: onPreview(state.answer),
                          onHistory: onHistory,
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        if (session.quoted != null)
          _MacQuotedSelection(text: session.quoted!, onClear: onClearQuote),
      ],
    );
  }
}

/// What can be done with a finished answer.
///
/// Insert is tinted rather than prominent: it is the action you probably
/// want, but the panel's one default button is the composer's send.
class _MacAskActions extends StatelessWidget {
  const _MacAskActions({
    required this.busy,
    required this.canInsert,
    required this.inserted,
    required this.error,
    required this.onInsert,
    required this.onCopy,
    required this.onPreview,
    required this.onHistory,
  });

  final bool busy;
  final bool canInsert;
  final bool inserted;
  final String? error;
  final VoidCallback onInsert;
  final VoidCallback onCopy;
  final VoidCallback? onPreview;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            MacButton(
              label: inserted
                  ? 'Inserted'
                  : busy
                      ? 'Inserting…'
                      : 'Insert into Page',
              icon: inserted ? AppleIcons.checkmark : null,
              style: MacButtonStyle.tinted,
              onPressed: busy || !canInsert || inserted ? null : onInsert,
            ),
            MacButton(
                label: 'Copy', icon: AppleIcons.docOnDoc, onPressed: onCopy),
            if (onPreview != null)
              MacButton(
                label: 'Preview HTML',
                icon: AppleIcons.eye,
                onPressed: onPreview,
              ),
            MacButton(
              label: 'History',
              icon: AppleIcons.clock,
              onPressed: onHistory,
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: MacAiText(error!,
                small: true, color: context.macColors.accentRed),
          ),
      ],
    );
  }
}

/// The model's reasoning, closed by default.
class _MacReasoning extends StatefulWidget {
  const _MacReasoning({required this.text});
  final String text;

  @override
  State<_MacReasoning> createState() => _MacReasoningState();
}

class _MacReasoningState extends State<_MacReasoning> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => MacDisclosure(
        title: "Model's Reasoning",
        open: _open,
        onToggle: (v) => setState(() => _open = v),
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          // Rendered, not raw: a model reasons in the same Markdown it
          // answers in.
          child: AiMarkdown(widget.text.trim(), fontSize: 11),
        ),
      );
}

/// The sites the answer was written from, numbered to match its `[n]`
/// markers, each leading with its domain. The whole row opens the page.
class _MacSources extends StatelessWidget {
  const _MacSources({required this.sources});
  final List<AiSource> sources;

  @override
  Widget build(BuildContext context) {
    return MacGroupBox(
      title: 'Answered Using ${sources.length} Web '
          'Source${sources.length == 1 ? '' : 's'}',
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sources.length; i++)
            _MacSourceRow(index: i + 1, source: sources[i]),
        ],
      ),
    );
  }
}

class _MacSourceRow extends StatelessWidget {
  const _MacSourceRow({required this.index, required this.source});

  final int index;
  final AiSource source;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final t = MacTypography.of(context);
    final host = Uri.tryParse(source.url)?.host.replaceFirst('www.', '') ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MacAiLinkRow(
        onTap: source.url.isEmpty
            ? null
            : () => launchUrl(Uri.parse(source.url),
                mode: LaunchMode.externalApplication),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The marker the answer's [n] refers to.
            SizedBox(
              width: 18,
              child: Text('$index.',
                  style: t
                      .emphasized(MacTextSpecs.subheadline)
                      .copyWith(color: c.labelTertiary)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (host.isNotEmpty)
                    Text(host,
                        style: t
                            .emphasized(MacTextSpecs.subheadline)
                            .copyWith(color: context.accent)),
                  Text(
                    source.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.subheadline.copyWith(color: c.labelSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The search as it happens: the query that left the machine, then the sites
/// that answered.
class _MacWebActivity extends StatelessWidget {
  const _MacWebActivity({
    required this.query,
    required this.sources,
    required this.searching,
  });

  final String query;
  final List<AiSource> sources;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final t = MacTypography.of(context);
    final hosts = <String>[];
    for (final s in sources) {
      final host = Uri.tryParse(s.url)?.host.replaceFirst('www.', '');
      if (host != null && host.isNotEmpty && !hosts.contains(host)) {
        hosts.add(host);
      }
    }

    return MacGroupBox(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 16,
                child: Center(
                  child: searching
                      ? const MacSpinner(semanticLabel: 'Searching')
                      : Icon(AppleIcons.globe,
                          size: 13, color: c.labelSecondary),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: MacAiText(
                  searching
                      ? 'Searching the web'
                      : hosts.isEmpty
                          ? 'Searched the web — no results'
                          : 'Read ${hosts.length} site'
                              '${hosts.length == 1 ? '' : 's'}',
                  emphasized: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // The query itself: it is what actually left the machine, and the
          // user is entitled to see it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 16,
                child: Icon(AppleIcons.magnifyingglass,
                    size: 11, color: c.labelSecondary),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  query,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.subheadline.copyWith(
                    color: c.labelSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          if (hosts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                for (var i = 0; i < hosts.length; i++)
                  Text('${i + 1}. ${hosts[i]}',
                      style: t.subheadline.copyWith(color: c.labelSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The highlighted passage the question is about, above the composer, with a
/// way back to asking about the whole page.
class _MacQuotedSelection extends StatelessWidget {
  const _MacQuotedSelection({required this.text, required this.onClear});

  final String text;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: c.fillQuaternary,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The accent bar is a child, not a one-coloured side of a
                // rounded border, which Flutter refuses to paint.
                SizedBox(width: 3, child: ColoredBox(color: context.accent)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 7, 4, 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const MacAiGroupTitle(
                                  'Asking About Your Highlight'),
                              const SizedBox(height: 2),
                              MacAiText(oneLine, maxLines: 2),
                            ],
                          ),
                        ),
                        MacAiIconButton(
                          icon: AppleIcons.xmark,
                          label: 'Ask about the whole page instead',
                          onPressed: onClear,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
