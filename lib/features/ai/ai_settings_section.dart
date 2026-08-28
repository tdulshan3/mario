/// Settings for the AI backends — the screen where the user points Mario at
/// whatever they actually run.
///
/// A list of configured backends with one marked active, an editor for each,
/// and a Test button that says something specific when it fails. That last
/// part matters more than it sounds: "connection refused" and "the API key was
/// rejected" and "reachable, but this server doesn't list models" are three
/// completely different problems, and a single red "failed" would leave the
/// user guessing which.
///
/// Testing also *learns*. Probing an unknown OpenAI-compatible endpoint is how
/// Mario finds out whether it can do strict JSON schemas, which decides
/// whether quiz generation gets constrained decoding or the repair path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/ai/anthropic_provider.dart';
import '../../core/services/ai/llm_provider.dart';
import '../../core/services/ai/llm_provider_config.dart';
import '../../core/services/ai/local_model_discovery.dart';
import '../../ui/colors.dart';
import 'ai_state.dart';
import '../../ui/widgets/mario_loader.dart';
import '../../core/services/ai/openai_compatible_provider.dart';

class AiSettingsSection extends ConsumerStatefulWidget {
  const AiSettingsSection({super.key});

  @override
  ConsumerState<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends ConsumerState<AiSettingsSection> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(aiConfigsProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: MarioLoader(size: 26),
      ),
      error: (e, _) => Text('Could not load AI settings: $e',
          style: GoogleFonts.inter(fontSize: 12, color: scheme.error)),
      data: (configs) {
        final backends = ref.watch(aiBackendsProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Mario can use a local model through Ollama, any '
                'OpenAI-compatible server on your network, OpenAI, or Claude. '
                'Add as many as you like and switch between them.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.45,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            for (final c in configs)
              _BackendTile(
                config: c,
                isActive: backends.activeId == c.id,
                onActivate: () async {
                  await backends.setActive(c.id);
                  ref.invalidate(aiConfigsProvider);
                },
                onEdit: () => _edit(c),
                onDelete: () async {
                  await backends.remove(c.id);
                  ref.invalidate(aiConfigsProvider);
                },
              ),
            if (configs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('No models configured yet.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add a model'),
              ),
            ),
            // Anything already running on this machine, offered as one tap.
            _DetectedLocalModels(configured: configs),
            const SizedBox(height: 18),
            const _WebSearchSettings(),
          ],
        );
      },
    );
  }

  Future<void> _edit(LlmProviderConfig? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BackendDialog(existing: existing),
    );
    if (saved == true) ref.invalidate(aiConfigsProvider);
  }
}

class _BackendTile extends StatelessWidget {
  const _BackendTile({
    required this.config,
    required this.isActive,
    required this.onActivate,
    required this.onEdit,
    required this.onDelete,
  });

  final LlmProviderConfig config;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? MarioColors.primary : scheme.outlineVariant,
          width: isActive ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: isActive ? 'Active' : 'Use this one',
            onPressed: isActive ? null : onActivate,
            icon: Icon(
              isActive
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: isActive
                  ? MarioColors.primaryPressed
                  : scheme.onSurfaceVariant,
            ),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(config.label,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                const SizedBox(height: 1),
                Text(
                  '${config.kind.label} · ${config.model.isEmpty ? 'no model set' : config.model}',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                if (config.kind != LlmProviderKind.anthropic &&
                    config.kind != LlmProviderKind.openAi)
                  Text(
                    config.baseUrl,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 16),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _BackendDialog extends ConsumerStatefulWidget {
  const _BackendDialog({this.existing});
  final LlmProviderConfig? existing;

  @override
  ConsumerState<_BackendDialog> createState() => _BackendDialogState();
}

class _BackendDialogState extends ConsumerState<_BackendDialog> {
  late LlmProviderKind _kind =
      widget.existing?.kind ?? LlmProviderKind.openAiCompatible;
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final _baseUrl = TextEditingController(
      text: widget.existing?.baseUrl ?? _kind.defaultBaseUrl);
  late final _model = TextEditingController(text: widget.existing?.model ?? '');
  late final _embedModel =
      TextEditingController(text: widget.existing?.embeddingModel ?? '');
  final _apiKey = TextEditingController();

  bool _keyLoaded = false;
  bool _testing = false;
  LlmProbeResult? _probe;
  List<String> _models = const [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null && existing.hasApiKey) {
      // Never show the stored secret. An empty box with a "key saved" hint
      // means "leave it alone"; typing replaces it.
      _keyLoaded = true;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _embedModel.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _onKindChanged(LlmProviderKind kind) {
    setState(() {
      // Only overwrite a URL the user has not customised, so switching kinds
      // to compare options does not silently discard their LAN address.
      final wasDefault = _baseUrl.text.trim().isEmpty ||
          LlmProviderKind.values.any((k) => k.defaultBaseUrl == _baseUrl.text);
      _kind = kind;
      if (wasDefault) _baseUrl.text = kind.defaultBaseUrl;
      if (kind == LlmProviderKind.anthropic && _model.text.trim().isEmpty) {
        _model.text = kDefaultAnthropicModel;
      }
      _probe = null;
      _models = const [];
    });
  }

  LlmProviderConfig _buildConfig() {
    final id =
        widget.existing?.id ?? 'llm-${DateTime.now().microsecondsSinceEpoch}';
    return LlmProviderConfig(
      id: id,
      label: _label.text.trim().isEmpty ? _defaultLabel() : _label.text.trim(),
      kind: _kind,
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      embeddingModel:
          _embedModel.text.trim().isEmpty ? null : _embedModel.text.trim(),
      hasApiKey: _apiKey.text.trim().isNotEmpty || _keyLoaded,
      capabilities: widget.existing?.capabilities ?? _probe?.capabilities,
    );
  }

  String _defaultLabel() => switch (_kind) {
        LlmProviderKind.anthropic => 'Claude',
        LlmProviderKind.openAi => 'OpenAI',
        LlmProviderKind.ollama => 'Ollama',
        LlmProviderKind.openAiCompatible =>
          _hostOf(_baseUrl.text) ?? 'Local server',
      };

  static String? _hostOf(String url) {
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'http://$url');
    return uri?.host.isEmpty ?? true ? null : uri!.host;
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _probe = null;
    });
    final config = _buildConfig();
    final provider = config.build(
      apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
    );
    final result = await provider.probe();
    provider.dispose();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _probe = result;
      _models = result.models;
      // Offer the first model when the endpoint advertises some and the user
      // has not typed one — the common case for a fresh Ollama install.
      if (_model.text.trim().isEmpty && result.models.isNotEmpty) {
        _model.text = result.models.first;
      }
    });
  }

  Future<void> _save() async {
    final backends = ref.read(aiBackendsProvider);
    final config = _buildConfig();
    final configs = [
      for (final c in backends.configs)
        if (c.id != config.id) c,
      config,
    ];
    await backends.saveConfigs(configs);
    if (_apiKey.text.trim().isNotEmpty) {
      await backends.setKey(config.id, _apiKey.text.trim());
    }
    if (backends.activeId == null) await backends.setActive(config.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needsUrl =
        _kind != LlmProviderKind.openAi && _kind != LlmProviderKind.anthropic;

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add a model' : 'Edit model',
          style: GoogleFonts.spaceGrotesk(
              fontSize: 16, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<LlmProviderKind>(
                initialValue: _kind,
                decoration:
                    const InputDecoration(labelText: 'Kind', isDense: true),
                items: [
                  for (final k in LlmProviderKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (v) => v == null ? null : _onKindChanged(v),
              ),
              const SizedBox(height: 12),
              if (needsUrl) ...[
                TextField(
                  controller: _baseUrl,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'http://192.168.1.50:8080/v1',
                    helperText: 'The /v1 is added for you if you leave it off.',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _model,
                decoration: InputDecoration(
                  labelText: 'Model',
                  hintText: switch (_kind) {
                    LlmProviderKind.anthropic => kDefaultAnthropicModel,
                    LlmProviderKind.ollama => 'qwen3:4b',
                    _ => 'model name',
                  },
                  isDense: true,
                ),
              ),
              if (_models.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final m in _models.take(12))
                      ActionChip(
                        label: Text(m, style: GoogleFonts.inter(fontSize: 11)),
                        onPressed: () => setState(() => _model.text = m),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'API key',
                  hintText: _keyLoaded ? 'saved — type to replace' : null,
                  helperText: _kind.requiresApiKey
                      ? null
                      : 'Usually blank for a local or LAN server.',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _embedModel,
                decoration: const InputDecoration(
                  labelText: 'Embedding model (optional)',
                  helperText: 'Only needed for retrieval over large sections.',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: _defaultLabel(),
                  helperText: 'Shown next to every answer this model gives.',
                  isDense: true,
                ),
              ),
              if (_probe != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_probe!.ok ? MarioColors.labelGreen : scheme.error)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _probe!.ok ? Icons.check_circle : Icons.error_outline,
                        size: 15,
                        color:
                            _probe!.ok ? MarioColors.labelGreen : scheme.error,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _probe!.latency == null
                              ? _probe!.message
                              : '${_probe!.message} '
                                  '(${_probe!.latency!.inMilliseconds}ms)',
                          style: GoogleFonts.inter(
                              fontSize: 11.5,
                              height: 1.35,
                              color: scheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton.icon(
          onPressed: _testing ? null : _test,
          icon: _testing
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.wifi_tethering, size: 16),
          label: const Text('Test'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Serper key plus the on/off switch for web search.
class _WebSearchSettings extends ConsumerStatefulWidget {
  const _WebSearchSettings();

  @override
  ConsumerState<_WebSearchSettings> createState() => _WebSearchSettingsState();
}

class _WebSearchSettingsState extends ConsumerState<_WebSearchSettings> {
  final _key = TextEditingController();
  bool _enabled = false;
  bool _hasKey = false;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(webSearchProvider);
    final key = await service.readKey();
    final enabled = await service.isEnabled;
    final remaining = await service.remainingToday();
    if (!mounted) return;
    setState(() {
      _hasKey = key != null && key.isNotEmpty;
      _enabled = enabled;
      _remaining = remaining;
    });
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final service = ref.read(webSearchProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Web search',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            )),
        const SizedBox(height: 6),
        Text(
          'With a Serper key, /ask can look things up online. The question is '
          'what gets sent — never the note itself — and you can turn it off '
          'per question in the panel.',
          style: GoogleFonts.inter(
            fontSize: 12,
            height: 1.45,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title:
              Text('Allow web search', style: GoogleFonts.inter(fontSize: 13)),
          subtitle: _hasKey
              ? Text('$_remaining of ${100} searches left today',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: scheme.onSurfaceVariant))
              : Text('Add a key below to enable',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: scheme.onSurfaceVariant)),
          value: _enabled && _hasKey,
          onChanged: _hasKey
              ? (v) async {
                  await service.setEnabled(v);
                  setState(() => _enabled = v);
                }
              : null,
        ),
        TextField(
          controller: _key,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Serper API key',
            hintText: _hasKey ? 'saved — type to replace' : 'from serper.dev',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.save_outlined, size: 18),
              tooltip: 'Save key',
              onPressed: () async {
                await service.writeKey(_key.text.trim());
                _key.clear();
                await _load();
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Model servers found running on this machine, each addable in one tap.
///
/// Shown only when something was actually found: an empty "nothing detected"
/// block on a machine that runs no local model is noise on every visit to
/// Settings.
class _DetectedLocalModels extends ConsumerWidget {
  const _DetectedLocalModels({required this.configured});

  /// Already set up, so the same model is not offered twice.
  final List<LlmProviderConfig> configured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final found = ref.watch(localModelsProvider);

    return found.maybeWhen(
      loading: () => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            const MarioLoader(size: 18),
            const SizedBox(width: 8),
            Text('Looking for a local model server…',
                style: GoogleFonts.inter(
                    fontSize: 11.5, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
      data: (endpoints) {
        // Hide a model that is already configured at the same endpoint.
        final rows = <({DiscoveredEndpoint endpoint, DiscoveredModel model})>[];
        for (final e in endpoints) {
          for (final m in e.models) {
            final already = configured.any((c) =>
                c.model == m.name &&
                OpenAiCompatibleProvider.normalizeBaseUrl(c.baseUrl) ==
                    OpenAiCompatibleProvider.normalizeBaseUrl(e.baseUrl));
            if (!already) rows.add((endpoint: e, model: m));
          }
        }
        if (rows.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.lan_outlined,
                    size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(
                  'FOUND ON THIS MACHINE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Look again',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 15),
                  onPressed: () => ref.invalidate(localModelsProvider),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final row in rows.take(12))
              _DetectedRow(
                endpoint: row.endpoint,
                model: row.model,
                onAdd: () => _add(ref, row.endpoint, row.model),
              ),
          ],
        );
      },
      orElse: SizedBox.shrink.call,
    );
  }

  Future<void> _add(
      WidgetRef ref, DiscoveredEndpoint endpoint, DiscoveredModel model) async {
    final backends = ref.read(aiBackendsProvider);
    final config = endpoint.toConfig(
      model.name,
      id: 'llm-${DateTime.now().microsecondsSinceEpoch}',
    );
    await backends.saveConfigs([...backends.configs, config]);
    // Make the first model anyone adds the active one, so a fresh install goes
    // straight from "found it" to working.
    if (backends.activeId == null || backends.configs.length == 1) {
      await backends.setActive(config.id);
    }
    ref.invalidate(aiConfigsProvider);
  }
}

class _DetectedRow extends StatelessWidget {
  const _DetectedRow({
    required this.endpoint,
    required this.model,
    required this.onAdd,
  });

  final DiscoveredEndpoint endpoint;
  final DiscoveredModel model;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = model.sizeLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(model.name,
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                Text(
                  [
                    endpoint.serverName,
                    if (model.parameters != null) model.parameters!,
                    if (size.isNotEmpty) size,
                  ].join(' · '),
                  style: GoogleFonts.inter(
                      fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 15),
            label: const Text('Use'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: GoogleFonts.inter(
                  fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
