part of 'ai_side_panel.dart';

/// The AI panel as the desktop window's inspector.
///
/// It looks like apple_ui's `MacInspector` — the window background, the
/// separator down its left edge — but is not one. `MacInspector` puts its
/// child in a scroll view, and this panel has a header and a composer that
/// must stay put while each tab scrolls its own list (an answer streaming in,
/// a quiz paper, the step list of a run). So the frame borrows the look and
/// leaves the scrolling to the tabs.
///
/// The left edge can be dragged, as an inspector's can: an invisible 5 px
/// handle with the column-resize pointer, and no coloured line of its own —
/// the separator is the edge. The width range is the Material panel's.
class _MacInspectorFrame extends StatefulWidget {
  const _MacInspectorFrame({required this.child});

  final Widget child;

  @override
  State<_MacInspectorFrame> createState() => _MacInspectorFrameState();
}

class _MacInspectorFrameState extends State<_MacInspectorFrame> {
  double _width = _kPanelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    return SizedBox(
      width: _width,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.windowBg,
                border: Border(left: BorderSide(color: c.separator)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 1),
                // Transparent, so the content still drawn with Material
                // widgets — the Markdown renderer, the HTML preview — has a
                // surface to sit on without painting one.
                child: Material(
                  type: MaterialType.transparency,
                  child: widget.child,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 5,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                // Docked on the right, so dragging left widens it.
                onHorizontalDragUpdate: (d) => setState(() {
                  _width = (_width - d.delta.dx)
                      .clamp(_kPanelMinWidth, _kPanelMaxWidth);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Header, model bar, the tab, and the composer, top to bottom.
///
/// Small controls throughout, as an inspector has them; the composer is the
/// one exception (see [_MacComposerView]). The composer is DOCKED under a
/// separator rather than floating over the tab the way the Material one
/// does: a macOS pane stops at a hairline, and blur material belongs to bars
/// and menus, not to a text field. With nothing floating over the tabs there
/// is nothing for them to reserve, hence the zero [ComposerReserve].
class _MacPanelLayout extends StatelessWidget {
  const _MacPanelLayout({
    required this.tab,
    required this.onTab,
    required this.onClose,
    required this.modelBar,
    required this.body,
    required this.composer,
  });

  final AiPanelTab tab;
  final ValueChanged<AiPanelTab> onTab;
  final VoidCallback onClose;
  final Widget modelBar;
  final Widget body;

  /// Null until a backend exists.
  final Widget? composer;

  @override
  Widget build(BuildContext context) {
    return MacControlSizeScope(
      size: MacControlSize.small,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MacHeader(tab: tab, onTab: onTab, onClose: onClose),
          const MacAiSeparator(),
          // Which model is answering applies to every tab, so it sits above
          // them; it draws its own separator underneath.
          modelBar,
          Expanded(child: ComposerReserve(height: 0, child: body)),
          if (composer != null) ...[
            const MacAiSeparator(),
            composer!,
          ],
        ],
      ),
    );
  }
}

/// The tabs as a segmented control, and Close.
///
/// Labels rather than icons: "Do" and "Writing" have no symbol that says
/// them. The control stretches across the header with equal segments, as an
/// inspector's pane switcher does; at the narrowest width, small segments
/// still fit "Writing" whole.
class _MacHeader extends StatelessWidget {
  const _MacHeader({
    required this.tab,
    required this.onTab,
    required this.onClose,
  });

  final AiPanelTab tab;
  final ValueChanged<AiPanelTab> onTab;
  final VoidCallback onClose;

  /// The design's order and wording; the fourth reads "Do" and selects
  /// [AiPanelTab.agent], as in the Material header.
  static const _segments = [
    MacSegment(value: AiPanelTab.ask, label: 'Ask'),
    MacSegment(value: AiPanelTab.quiz, label: 'Quiz'),
    MacSegment(value: AiPanelTab.writing, label: 'Writing'),
    MacSegment(value: AiPanelTab.agent, label: 'Do'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: MacSegmentedControl<AiPanelTab>(
              segments: _segments,
              value: tab,
              equal: true,
              onChanged: onTab,
              semanticLabel: 'Mario',
            ),
          ),
          const SizedBox(width: 8),
          MacAiIconButton(
            icon: AppleIcons.xmark,
            label: 'Close',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// The composer, docked at the foot of every tab.
///
/// Two rows. The question field and the send button share the first, so the
/// field gets the panel's whole width to type in — the Material composer's
/// single row had to measure its web chip and give up its wording to keep
/// the field readable at 280, and two rows make that budgeting unnecessary.
/// The question's options (web search, summarise) sit on the second, as small
/// controls like the rest of the inspector, and wrap rather than overflow if
/// a wider face than Inter or SF Pro ever makes them not fit.
///
/// The first row is medium, unlike the rest of the inspector: this is where
/// people type, and the field reads at body size.
class _MacComposerView extends StatelessWidget {
  const _MacComposerView({
    required this.controller,
    required this.focusNode,
    required this.isAgent,
    required this.enabled,
    required this.hint,
    required this.useWeb,
    required this.onWeb,
    required this.onChanged,
    required this.onSubmit,
    required this.onSummarise,
    required this.summariseTip,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isAgent;
  final bool enabled;
  final String hint;
  final bool? useWeb;
  final ValueChanged<bool?> onWeb;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  /// Null on Do (summarising is a question, not an edit) and with no page.
  final VoidCallback? onSummarise;
  final String summariseTip;

  static String _webLabel(bool? value) => switch (value) {
        true => 'Web: On',
        false => 'Web: Off',
        null => 'Web: Auto',
      };

  @override
  Widget build(BuildContext context) {
    final sendLabel = isAgent ? 'Run' : 'Ask';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MacControlSizeScope(
            size: MacControlSize.medium,
            child: Row(
              children: [
                Expanded(
                  child: MacTextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    placeholder: hint,
                    textInputAction: TextInputAction.send,
                    onChanged: onChanged,
                    onSubmitted: (_) => onSubmit(),
                    semanticLabel: isAgent ? 'Instruction' : 'Question',
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => MacTooltip(
                    message: sendLabel,
                    child: MacButton(
                      icon: AppleIcons.arrowUp,
                      semanticLabel: sendLabel,
                      style: MacButtonStyle.prominent,
                      onPressed: enabled && value.text.trim().isNotEmpty
                          ? onSubmit
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              // Web search is on both Ask and Do — "add a section on the
              // current rules" is an edit that cannot be written from a page
              // which says nothing about them. Three values, so a pop-up,
              // with the full meaning of the current one in its tooltip.
              MacTooltip(
                message: _WebChip._face(useWeb).$3,
                child: MacPopUpButton<bool?>(
                  options: const [null, true, false],
                  value: useWeb,
                  labelOf: _webLabel,
                  onChanged: onWeb,
                  semanticLabel: 'Web search',
                ),
              ),
              if (!isAgent)
                MacTooltip(
                  message: summariseTip,
                  child: MacButton(
                    label: 'Summarise',
                    icon: CupertinoIcons.text_quote,
                    onPressed: onSummarise,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// First run on the desktop: nothing configured yet.
///
/// The same offer as the Material panel — a model server already running on
/// this machine, one click from a working panel — in the kit's empty-pane
/// type, with the detected models as buttons and Settings as the default.
class _MacNeedsSetup extends StatelessWidget {
  const _MacNeedsSetup({
    required this.message,
    required this.searching,
    required this.best,
    required this.onUse,
    required this.onSettings,
  });

  /// Set when the settings could not be read, instead of the introduction.
  final String? message;
  final bool searching;
  final DiscoveredEndpoint? best;
  final ValueChanged<String> onUse;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final best = this.best;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MacEmptyState(
              title: message == null
                  ? 'No Model Set Up'
                  : 'AI Settings Unavailable',
              message: message ??
                  'Mario can use a local model through Ollama, any '
                      'OpenAI-compatible server on your network, OpenAI, '
                      'or Claude.',
            ),
            if (searching)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MacSpinner(semanticLabel: 'Looking'),
                  const SizedBox(width: 6),
                  MacAiText('Looking for a local model server…',
                      secondary: true, small: true),
                ],
              ),
            // The detected models as rows of a group, each with its own Use
            // button: a model name is often long ("qwen3.5:4b-instruct-
            // q4_K_M"), and a row's label wraps where a button's cannot.
            if (best != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: MacForm(
                  children: [
                    MacFormSection(
                      title: '${best.serverName} is running here with '
                          '${best.models.length} model'
                          '${best.models.length == 1 ? '' : 's'}',
                      children: [
                        for (final m in best.models.take(4))
                          MacFormRow(
                            label: m.name,
                            subtitle: m.sizeLabel.isEmpty ? null : m.sizeLabel,
                            child: MacButton(
                              label: 'Use',
                              onPressed: () => onUse(m.name),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // The default action of an empty panel; with a server found, the
            // models above are the quicker way and this is the long way round.
            MacButton(
              label: best == null ? 'Set Up a Model…' : 'More Options…',
              style: best == null
                  ? MacButtonStyle.prominent
                  : MacButtonStyle.bordered,
              onPressed: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}
