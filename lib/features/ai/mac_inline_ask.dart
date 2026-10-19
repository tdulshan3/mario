part of 'inline_ask.dart';

/// The in-page answer, as the desktop draws it.
///
/// The same block as the Material one — an accent bar down its leading edge,
/// a one-line attribution, the answer, what can be done with it — with
/// apple_ui buttons for the actions and the system accent for the bar. Its
/// constructor matches [_Answer]'s, so the state builds either one from the
/// same values.
class _MacAnswer extends StatelessWidget {
  const _MacAnswer({
    required this.state,
    required this.question,
    required this.quoted,
    required this.busy,
    required this.error,
    required this.onInsert,
    required this.onReplace,
    required this.onAskAgain,
    required this.onPreview,
    required this.onDiscard,
    required this.onStop,
  });

  final AiRunState state;
  final String question;
  final bool quoted;
  final bool busy;
  final String? error;
  final VoidCallback onInsert;
  final VoidCallback onReplace;
  final VoidCallback onAskAgain;
  final VoidCallback? onPreview;
  final VoidCallback onDiscard;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final t = MacTypography.of(context);
    final accent = context.accent;
    final running = state.isRunning;

    // "Qwen 3.5:0.8b · read this page": which backend, and what it read.
    final backend = state.backendLabel;
    final scope = quoted ? 'read your selection' : 'read this page';
    final attribution = backend == null ? scope : '$backend · $scope';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 0, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.sparkles, size: 14, color: accent),
                const SizedBox(width: 6),
                Text('Mario',
                    style: t.bodyEmphasized.copyWith(color: c.labelPrimary)),
                const SizedBox(width: 8),
                Flexible(
                  child: MacAiText(attribution,
                      secondary: true, small: true, maxLines: 1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.error != null)
              MacAiText(state.error!, color: c.accentRed)
            else if (state.answer.isEmpty && running)
              const MacAiText('Thinking…', secondary: true)
            else
              // Rendered, not raw, and streamed in settled pieces — the
              // reasons are in the Material block above.
              StreamingMarkdown(
                state.answer,
                done: !running,
                fontSize: 14.5,
              ),
            if (error != null) ...[
              const SizedBox(height: 6),
              MacAiText(error!, small: true, color: c.accentRed),
            ],
            const SizedBox(height: 10),
            // While a run is live the only honest action is to stop it.
            if (running)
              MacButton(label: 'Stop', icon: AppleIcons.stop, onPressed: onStop)
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  MacButton(
                    label: busy ? 'Inserting…' : 'Insert Below',
                    style: MacButtonStyle.tinted,
                    onPressed: busy ? null : onInsert,
                  ),
                  MacButton(
                    label: 'Replace Selection',
                    onPressed: busy ? null : onReplace,
                  ),
                  MacButton(
                    label: 'Ask Again',
                    onPressed: busy ? null : onAskAgain,
                  ),
                  if (onPreview != null)
                    MacButton(label: 'Preview HTML', onPressed: onPreview),
                  MacButton(
                    label: 'Discard',
                    style: MacButtonStyle.borderless,
                    onPressed: busy ? null : onDiscard,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The in-page composer on the desktop: a macOS text field. Return sends,
/// Escape closes — the editor owns both keys everywhere else on the page, so
/// the composer claims them here.
class _MacInlineComposer extends StatelessWidget {
  const _MacInlineComposer({
    required this.controller,
    required this.focus,
    required this.onSubmit,
    required this.onDismiss,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSubmit;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onDismiss,
      },
      child: Row(
        children: [
          Expanded(
            child: MacTextField(
              controller: controller,
              focusNode: focus,
              size: MacControlSize.medium,
              placeholder: 'Ask Mario about this page, or type / for blocks',
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              semanticLabel: 'Ask Mario',
            ),
          ),
          const SizedBox(width: 8),
          MacAiText('⏎', secondary: true, small: true),
        ],
      ),
    );
  }
}
