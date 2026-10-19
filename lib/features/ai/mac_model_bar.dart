part of 'model_bar.dart';

/// The model bar of the desktop inspector.
///
/// The same three facts as the Material bar — which model, how hard it thinks,
/// how much of its window the last request used — as macOS controls: the model
/// and the effort are pop-up buttons (each picks one value from a list), and
/// the context budget is plain secondary text with a small bar, since it is a
/// readout and not something to press.
///
/// Two rows rather than one. At the inspector's narrowest (280) a model name,
/// an effort pop-up and "8.1k / 262k" side by side leave the model name a
/// handful of characters; the budget sits on the second row with the activity
/// line, which is also where the eye goes while a run is in flight.
class _MacModelBar extends StatelessWidget {
  const _MacModelBar({
    required this.configs,
    required this.active,
    required this.run,
    required this.onPick,
    required this.onEffort,
  });

  final List<LlmProviderConfig> configs;
  final LlmProviderConfig active;
  final AiRun? run;
  final ValueChanged<LlmProviderConfig> onPick;
  final ValueChanged<LlmEffort> onEffort;

  /// The model, not the config label — "qwen3.6:latest" is what changes the
  /// answer, where "LAN box" is only where it runs. Two configs serving the
  /// same model are told apart by where they run, or the menu would list the
  /// same name twice.
  String _nameOf(LlmProviderConfig config) {
    String bare(LlmProviderConfig c) => c.model.isEmpty ? c.label : c.model;
    final name = bare(config);
    final clash = configs.where((c) => bare(c) == name).length > 1;
    return clash && config.model.isNotEmpty ? '$name — ${config.label}' : name;
  }

  @override
  Widget build(BuildContext context) {
    final t = MacTypography.of(context);
    final c = context.macColors;

    // With one backend there is nothing to pick, so it reads as a label
    // rather than a menu that would only hold what is already shown.
    final Widget model = configs.length == 1
        ? MacTooltip(
            message: active.label,
            child: Text(
              _nameOf(active),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyEmphasized.copyWith(color: c.labelPrimary),
            ),
          )
        // A tight width, so a long model name truncates instead of pushing
        // the effort pop-up out of the bar.
        : MacPopUpButton<LlmProviderConfig>(
            options: configs,
            value: configs.firstWhere((x) => x.id == active.id,
                orElse: () => active),
            labelOf: _nameOf,
            onChanged: onPick,
            semanticLabel: 'Model',
          );

    final effort = MacTooltip(
      message: 'How hard to think: '
          '${_EffortChip._blurbs[active.effort]!}',
      child: MacPopUpButton<LlmEffort>(
        options: LlmEffort.values,
        value: active.effort,
        labelOf: (e) => _EffortChip._labels[e]!,
        onChanged: onEffort,
        semanticLabel: 'How hard to think',
      ),
    );

    Widget readout(AiRunState? state) => _MacContextReadout(
          contextTokens: state?.contextTokens ??
              active.effectiveCapabilities.contextTokens,
          used: state?.promptTokens,
        );

    // The second row: what the model is doing on the left (only while it is
    // doing something), the context budget on the right.
    Widget secondRow(AiRunState? state) => Row(
          children: [
            Expanded(
              child: state == null
                  ? const SizedBox.shrink()
                  : _MacActivityLine(state: state),
            ),
            const SizedBox(width: 8),
            readout(state),
          ],
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: model),
                  const SizedBox(width: 8),
                  effort,
                ],
              ),
              const SizedBox(height: 6),
              if (run == null)
                secondRow(null)
              else
                ValueListenableBuilder<AiRunState>(
                  valueListenable: run!,
                  builder: (context, state, _) => secondRow(state),
                ),
            ],
          ),
        ),
        const MacAiSeparator(),
      ],
    );
  }
}

/// The context window, and how much of it the last request used, as
/// secondary text — red once it is close to full.
class _MacContextReadout extends StatelessWidget {
  const _MacContextReadout({required this.contextTokens, this.used});

  final int contextTokens;

  /// Reported by the server. Null on a backend that does not say, in which
  /// case only the window is shown — a made-up estimate presented as a
  /// measurement would be worse than no number.
  final int? used;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final t = MacTypography.of(context);
    final fraction =
        used == null || contextTokens <= 0 ? null : used! / contextTokens;
    // Past about three-quarters, the next question in the same page is the
    // one that gets truncated.
    final tight = fraction != null && fraction > 0.75;

    return MacTooltip(
      message: used == null
          ? 'Context window: ${_formatTokens(contextTokens)}'
          : 'Last request used ${_formatTokens(used!)} of '
              '${_formatTokens(contextTokens)}'
              '${tight ? ' — close to full, so longer notes may be cut' : ''}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fraction != null) ...[
            MacProgressBar(
              value: fraction.clamp(0, 1).toDouble(),
              size: MacControlSize.small,
              width: 32,
              semanticLabel: 'Context used',
            ),
            const SizedBox(width: 6),
          ],
          Text(
            used == null
                ? '${_formatTokens(contextTokens)} context'
                : '${_formatTokens(used!)} / ${_formatTokens(contextTokens)}',
            style: t.subheadline.copyWith(
              color: tight ? c.accentRed : c.labelSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The live "what is it doing" line, in the inspector's type: a spinner, the
/// running step and its detail, and how long it has been at it. Silent when
/// nothing is running, red when the run failed.
class _MacActivityLine extends StatelessWidget {
  const _MacActivityLine({required this.state});

  final AiRunState state;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final t = MacTypography.of(context);

    if (state.status == AiRunStatus.failed) {
      return _line(
        t,
        icon: Icon(AppleIcons.exclamationmarkTriangle,
            size: 12, color: c.accentRed),
        text: state.error ?? 'Failed',
        colour: c.accentRed,
        elapsedColour: c.labelTertiary,
      );
    }
    if (state.status != AiRunStatus.running) return const SizedBox.shrink();

    AiStep? active;
    for (final s in state.steps) {
      if (s.state == AiStepState.active) {
        active = s;
        break;
      }
    }
    // Running, but between steps — say so rather than going blank and
    // looking like nothing is happening.
    final label = active?.kind.label ?? 'Working';
    final detail = active?.detail;

    return _line(
      t,
      icon: const MacSpinner(semanticLabel: 'Working'),
      text: detail == null || detail.isEmpty ? label : '$label · $detail',
      colour: c.labelSecondary,
      elapsedColour: c.labelTertiary,
      trailing: active?.elapsed,
    );
  }

  Widget _line(
    MacTypography t, {
    required Widget icon,
    required String text,
    required Color colour,
    required Color elapsedColour,
    Duration? trailing,
  }) {
    return Row(
      children: [
        SizedBox.square(dimension: 16, child: Center(child: icon)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.subheadline.copyWith(color: colour),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Text(
            ModelActivityLine._elapsedLabel(trailing),
            style: t.subheadline.copyWith(
              color: elapsedColour,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}
