part of 'ai_settings_section.dart';

/// The AI settings in the macOS look, for the desktop Settings window.
///
/// Same content as the Material section, laid out the way System Settings
/// lays out an accounts pane:
///
///   Models        one grouped row per backend (kind, model, context, and the
///                 server for the local kinds), "Active" on the one in use and
///                 a Use button on the others, ⓘ to edit; Add a Model… under
///                 the box. Right-click a row for Edit, Use and Remove.
///   Found on this machine
///                 local servers that answered, each a Use button away
///   Ask about a highlight, then Web search (switch, Serper key, Test, Save)
///
/// Adding and editing happen in a sheet (classic "Label:" form) rather than
/// a dialog, and removing — which also deletes the stored API key — now asks
/// first, as macOS does before anything that cannot be undone. The editor,
/// test and save logic is the Material dialog's own: the sheet's state
/// extends it and only draws it differently.
///
/// Every block brings its own gap above it (see mac_settings_widgets.dart),
/// so the Settings pane can put this straight under its header.
class _MacAiSettings extends ConsumerStatefulWidget {
  const _MacAiSettings();

  @override
  ConsumerState<_MacAiSettings> createState() => _MacAiSettingsState();
}

class _MacAiSettingsState extends ConsumerState<_MacAiSettings> {
  Future<void> _edit(LlmProviderConfig? existing) async {
    final saved = await showMacSheet<bool>(
      context: context,
      builder: (_) => _MacBackendSheet(existing: existing),
    );
    if (saved == true && mounted) ref.invalidate(aiConfigsProvider);
  }

  Future<void> _activate(LlmProviderConfig config) async {
    await ref.read(aiBackendsProvider).setActive(config.id);
    if (mounted) ref.invalidate(aiConfigsProvider);
  }

  Future<void> _remove(LlmProviderConfig config) async {
    if (!await _confirmRemoveBackend(context, config)) return;
    if (!mounted) return;
    await ref.read(aiBackendsProvider).remove(config.id);
    if (mounted) ref.invalidate(aiConfigsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(aiConfigsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(child: MacSpinner(semanticLabel: 'Loading AI settings')),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Text(
          'Could not load AI settings: $e',
          style: MacTypography.of(context)
              .body
              .copyWith(color: context.macColors.accentRed),
        ),
      ),
      data: (configs) {
        final backends = ref.watch(aiBackendsProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MacSettingsGroup(
              sections: [
                MacFormSection(
                  title: 'Models',
                  footer: 'Mario can use a local model through Ollama, any '
                      'OpenAI-compatible server on your network, OpenAI, '
                      'Claude, or Gemini. Add as many as you like and switch '
                      'between them.',
                  children: [
                    for (final c in configs)
                      _MacBackendRow(
                        config: c,
                        isActive: backends.activeId == c.id,
                        onActivate: () => _activate(c),
                        onEdit: () => _edit(c),
                        onRemove: () => _remove(c),
                      ),
                    if (configs.isEmpty)
                      const MacFormRow(
                        label: 'No models configured yet.',
                        enabled: false,
                      ),
                  ],
                ),
              ],
            ),
            MacSettingsButtons(
              children: [
                MacButton(label: 'Add a Model…', onPressed: () => _edit(null)),
              ],
            ),
            // Anything already running on this machine, offered as one click.
            _MacDetectedLocalModels(configured: configs),
            const _MacAskOnHighlight(),
            const _MacWebSearchSettings(),
          ],
        );
      },
    );
  }
}

/// Asks before removing a backend. True when the user chose Remove.
Future<bool> _confirmRemoveBackend(
  BuildContext context,
  LlmProviderConfig config,
) =>
    showMacConfirmAlert(
      context,
      title: 'Remove “${config.label}”?',
      message: 'Mario forgets this model and any API key saved for it.',
      confirmLabel: 'Remove',
    );

/// Whether a kind talks to a server whose address the user chose — the ones
/// whose row and editor show a Base URL.
bool _macShowsUrl(LlmProviderKind kind) =>
    kind != LlmProviderKind.openAi &&
    kind != LlmProviderKind.anthropic &&
    kind != LlmProviderKind.gemini;

/// The row's icon square: a computer for a server on this machine or the
/// network, a cloud for a hosted API, each kind in its own colour so two
/// rows of the same model on different backends still read apart.
MacFormIcon _macKindIcon(MacColors c, LlmProviderKind kind) => switch (kind) {
      LlmProviderKind.ollama =>
        MacFormIcon(AppleIcons.desktop, color: c.gray, large: true),
      LlmProviderKind.openAiCompatible =>
        MacFormIcon(AppleIcons.desktop, color: c.accentTeal, large: true),
      LlmProviderKind.openAi =>
        MacFormIcon(AppleIcons.cloud, color: c.accentGreen, large: true),
      LlmProviderKind.anthropic =>
        MacFormIcon(AppleIcons.cloud, color: c.accentOrange, large: true),
      LlmProviderKind.gemini =>
        MacFormIcon(AppleIcons.cloud, color: c.accentBlue, large: true),
    };

/// One configured backend.
class _MacBackendRow extends StatelessWidget {
  const _MacBackendRow({
    required this.config,
    required this.isActive,
    required this.onActivate,
    required this.onEdit,
    required this.onRemove,
  });

  final LlmProviderConfig config;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final detail = [
      '${config.kind.label} · '
          '${config.model.isEmpty ? 'no model set' : config.model} · '
          '${formatContextWindow(config.effectiveCapabilities.contextTokens)} '
          'context',
      if (_macShowsUrl(config.kind)) config.baseUrl,
    ].join('\n');

    return MacContextMenu(
      items: [
        MacMenuItem(label: 'Edit…', onSelected: onEdit),
        MacMenuItem(
          label: 'Use This Model',
          enabled: !isActive,
          onSelected: onActivate,
        ),
        const MacMenuDivider(),
        MacMenuItem(label: 'Remove…', onSelected: onRemove),
      ],
      child: MacFormRow(
        label: config.label,
        subtitle: detail,
        icon: _macKindIcon(context.macColors, config.kind),
        value: isActive ? 'Active' : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            if (!isActive)
              MacTooltip(
                message: 'Use this one',
                child: MacButton(label: 'Use', onPressed: onActivate),
              ),
            MacTooltip(
              message: 'Edit',
              child: MacFormIconButton.info(
                semanticLabel: 'Edit ${config.label}',
                onPressed: onEdit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds or edits a backend: [_BackendDialog]'s fields and buttons as a sheet.
///
/// Return saves and Escape cancels (the sheet binds both). The form scrolls
/// inside the sheet, because with the server's model list and a test result
/// showing it is taller than an 800 × 600 window.
class _MacBackendSheet extends _BackendDialog {
  const _MacBackendSheet({super.existing});

  @override
  ConsumerState<_BackendDialog> createState() => _MacBackendSheetState();
}

class _MacBackendSheetState extends _BackendDialogState {
  /// The context-window presets the Material dialog offers as chips.
  static final _contextPresets = [
    'Auto',
    for (final tokens in const [8192, 32768, 65536, 131072, 262144, 1048576])
      formatContextWindow(tokens),
  ];

  void _cancel() => Navigator.of(context).pop(false);

  Future<void> _remove() async {
    final existing = widget.existing;
    if (existing == null) return;
    if (!await _confirmRemoveBackend(context, existing)) return;
    if (!mounted) return;
    await ref.read(aiBackendsProvider).remove(existing.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// Typed text and a picked preset both land here. "Auto" means no override,
  /// which is an empty field — the field's placeholder then says what Auto is.
  void _onContextWindowChanged(String value) {
    if (value == 'Auto') _contextWindow.clear();
    if (_contextWindowError != null) {
      setState(() => _contextWindowError = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final probe = _probe;
    final localServer = _kind == LlmProviderKind.ollama ||
        _kind == LlmProviderKind.openAiCompatible;
    final modelHint = switch (_kind) {
      LlmProviderKind.anthropic => kDefaultAnthropicModel,
      LlmProviderKind.gemini => kDefaultGeminiModel,
      LlmProviderKind.ollama => 'qwen3:4b',
      _ => 'model name',
    };

    return MacSheet(
      title: widget.existing == null ? 'Add a Model' : 'Edit Model',
      width: 520,
      onSubmit: _save,
      onCancel: _cancel,
      leading: [
        if (widget.existing != null)
          MacButton(
            label: 'Remove…',
            style: MacButtonStyle.destructive,
            onPressed: _remove,
          ),
      ],
      actions: [
        if (_testing) const MacSpinner(semanticLabel: 'Testing'),
        MacTooltip(
          message: 'Check that Mario can reach this model',
          child: MacButton(label: 'Test', onPressed: _testing ? null : _test),
        ),
        MacButton(label: 'Cancel', onPressed: _cancel),
        MacButton(
          label: 'Save',
          style: MacButtonStyle.prominent,
          onPressed: _save,
        ),
      ],
      // Flexible: a direct child of the sheet's column, so the form scrolls
      // within the window's height instead of running off its bottom.
      child: Flexible(
        child: SingleChildScrollView(
          child: MacForm(
            columns: true,
            children: [
              MacFormRow(
                label: 'Kind:',
                // As wide as the fields under it (one width per column), and
                // so able to shorten a long kind rather than overflow.
                child: SizedBox(
                  width: double.infinity,
                  child: MacPopUpButton<LlmProviderKind>(
                    options: LlmProviderKind.values,
                    value: _kind,
                    labelOf: (k) => k.label,
                    onChanged: _onKindChanged,
                    semanticLabel: 'Kind',
                  ),
                ),
              ),
              if (_macShowsUrl(_kind))
                MacFormRow(
                  label: 'Base URL:',
                  note: 'The /v1 is added for you if you leave it off.',
                  child: MacTextField(
                    controller: _baseUrl,
                    placeholder: 'http://192.168.1.50:8080/v1',
                    keyboardType: TextInputType.url,
                    semanticLabel: 'Base URL',
                  ),
                ),
              MacFormRow(
                label: 'Model:',
                note: _models.isEmpty
                    ? null
                    : 'Pick one the server lists, or type a name.',
                // The server's own list once a test has fetched it: a combo
                // box, because a model it does not list can still be typed.
                child: _models.isEmpty
                    ? MacTextField(
                        controller: _model,
                        placeholder: modelHint,
                        semanticLabel: 'Model',
                      )
                    : MacComboBox(
                        controller: _model,
                        items: _models.take(12).toList(),
                        placeholder: modelHint,
                        semanticLabel: 'Model',
                      ),
              ),
              MacFormRow(
                label: 'Context Window:',
                note: _contextWindowError ??
                    (localServer
                        ? 'Tokens. Sets how much Mario sends and the local '
                            'server’s num_ctx. Larger windows use more RAM or '
                            'VRAM.'
                        : 'Tokens. Limits how much Mario sends. Leave empty '
                            'to use the model default.'),
                noteIsError: _contextWindowError != null,
                child: MacComboBox(
                  key: const ValueKey('ai-context-window'),
                  controller: _contextWindow,
                  items: _contextPresets,
                  width: 160,
                  placeholder: 'Auto · '
                      '${formatContextWindow(_kind.assumedCapabilities.contextTokens)}',
                  onChanged: _onContextWindowChanged,
                  semanticLabel: 'Context window (tokens)',
                ),
              ),
              MacFormRow(
                label: 'API Key:',
                note: _kind.requiresApiKey
                    ? null
                    : 'Usually blank for a local or LAN server.',
                child: MacTextField(
                  controller: _apiKey,
                  obscureText: true,
                  placeholder: _keyLoaded ? 'saved — type to replace' : null,
                  semanticLabel: 'API key',
                ),
              ),
              MacFormRow(
                label: 'Embedding Model:',
                note: 'Optional. Only needed for retrieval over large '
                    'sections.',
                child: MacTextField(
                  controller: _embedModel,
                  semanticLabel: 'Embedding model',
                ),
              ),
              MacFormRow(
                label: 'Name:',
                note: 'Shown next to every answer this model gives.',
                child: MacTextField(
                  controller: _label,
                  placeholder: _defaultLabel(),
                  semanticLabel: 'Name',
                ),
              ),
              if (probe != null)
                MacStatusLine(
                  ok: probe.ok,
                  message: probe.latency == null
                      ? probe.message
                      : '${probe.message} '
                          '(${probe.latency!.inMilliseconds}ms)',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Model servers found running on this machine, each addable in one click.
///
/// Like the Material version, shown only when something was found; while
/// it is still looking, one row says so.
class _MacDetectedLocalModels extends _DetectedLocalModels {
  const _MacDetectedLocalModels({required super.configured});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.macColors;
    final found = ref.watch(localModelsProvider);

    return found.maybeWhen(
      loading: () => const MacSettingsGroup(
        sections: [
          MacFormSection(
            children: [
              MacFormRow(
                label: 'Looking for a local model server…',
                child: MacSpinner(semanticLabel: 'Looking'),
              ),
            ],
          ),
        ],
      ),
      data: (endpoints) {
        final rows = _unconfigured(endpoints);
        if (rows.isEmpty) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MacSettingsGroup(
              sections: [
                MacFormSection(
                  title: 'Found on this machine',
                  children: [
                    for (final row in rows.take(12))
                      MacFormRow(
                        label: row.model.name,
                        subtitle: [
                          row.endpoint.serverName,
                          if (row.model.parameters != null)
                            row.model.parameters!,
                          if (row.model.sizeLabel.isNotEmpty)
                            row.model.sizeLabel,
                        ].join(' · '),
                        icon: Icon(
                          AppleIcons.desktop,
                          size: 15,
                          color: c.labelSecondary,
                        ),
                        child: MacTooltip(
                          message: 'Add it and use it',
                          child: MacButton(
                            label: 'Use',
                            icon: AppleIcons.plus,
                            onPressed: () => _add(ref, row.endpoint, row.model),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            MacSettingsButtons(
              children: [
                MacTooltip(
                  message: 'Look again',
                  child: MacButton(
                    label: 'Look Again',
                    icon: AppleIcons.arrowClockwise,
                    onPressed: () => ref.invalidate(localModelsProvider),
                  ),
                ),
              ],
            ),
          ],
        );
      },
      orElse: SizedBox.shrink.call,
    );
  }
}

/// Whether highlighting a passage opens the panel to ask about it.
class _MacAskOnHighlight extends ConsumerWidget {
  const _MacAskOnHighlight();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    return MacSettingsGroup(
      sections: [
        MacFormSection(
          footer: 'Highlighting a passage opens the AI panel ready to answer '
              'about it. Turn off if you select text mostly to edit it.',
          children: [
            MacFormRow(
              label: 'Ask about a highlight',
              enabled: settings != null,
              child: MacSwitch(
                value: settings?.askOnHighlight ?? true,
                onChanged: settings == null
                    ? null
                    : (v) => ref
                        .read(settingsProvider.notifier)
                        .change((s) => s.copyWith(askOnHighlight: v)),
                semanticLabel: 'Ask about a highlight',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The Serper key and the web search switch: [_WebSearchSettings]'s state,
/// drawn as a settings section with its buttons under it.
class _MacWebSearchSettings extends _WebSearchSettings {
  const _MacWebSearchSettings();

  @override
  ConsumerState<_WebSearchSettings> createState() =>
      _MacWebSearchSettingsState();
}

class _MacWebSearchSettingsState extends _WebSearchSettingsState {
  /// Removing the key also turns search off (see [_forget]); it asks first,
  /// because the key is gone for good.
  Future<void> _confirmForget() async {
    final remove = await showMacConfirmAlert(
      context,
      title: 'Remove the Serper key?',
      message: 'Web search turns off until you save a key again.',
      confirmLabel: 'Remove',
    );
    if (remove && mounted) await _forget();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(webSearchProvider);
    final result = _testResult;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MacSettingsGroup(
          sections: [
            MacFormSection(
              title: 'Web search',
              footer: 'With a Serper key, /ask can look things up online. '
                  'The question is what gets sent — never the note itself — '
                  'and you can turn it off per question in the panel.',
              children: [
                MacFormRow(
                  label: 'Allow web search',
                  subtitle: _hasKey
                      ? '$_remaining of ${WebSearchService.dailyLimit} '
                          'searches left today'
                      : 'Save a key below and this turns on',
                  enabled: _hasKey,
                  child: MacSwitch(
                    value: _enabled && _hasKey,
                    onChanged: _hasKey
                        ? (v) async {
                            await service.setEnabled(v);
                            if (mounted) setState(() => _enabled = v);
                          }
                        : null,
                    semanticLabel: 'Allow web search',
                  ),
                ),
                MacFormRow(
                  label: 'Serper API key',
                  child: MacTextField(
                    controller: _key,
                    obscureText: true,
                    width: 220,
                    placeholder:
                        _hasKey ? 'saved — type to replace' : 'from serper.dev',
                    // Return saves, as in the Material field.
                    onSubmitted: (_) => _save(),
                    semanticLabel: 'Serper API key',
                  ),
                ),
                if (result != null)
                  MacFormRow(
                    label: result.message,
                    icon: macStatusSymbol(context, ok: result.ok),
                  ),
              ],
            ),
          ],
        ),
        MacSettingsButtons(
          children: [
            if (_hasKey)
              MacButton(
                label: 'Remove Key…',
                style: MacButtonStyle.destructive,
                onPressed: _confirmForget,
              ),
            if (_testing) const MacSpinner(semanticLabel: 'Testing search'),
            MacButton(
              label: 'Test Search',
              onPressed: _testing ? null : _test,
            ),
            // Saving is the main action here; it waits for a typed key, so
            // an accidental press cannot replace the saved one with nothing.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _key,
              builder: (context, value, _) => MacButton(
                label: 'Save Key',
                onPressed: value.text.trim().isEmpty ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
