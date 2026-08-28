/// LlmProviderConfig — a saved model backend, and the store that persists them.
///
/// The user can point Mario at whatever they already run: a box on the LAN
/// (`http://192.168.1.50:8080/v1`), Ollama on localhost, the OpenAI API, or
/// Claude. Each of those is one config; the active one answers, and the others
/// stand by as fallbacks.
///
/// Split storage, deliberately: the non-secret fields live in
/// shared_preferences as JSON (so the list survives a restart and is easy to
/// inspect), while API keys go to flutter_secure_storage under a per-config
/// key. Nothing secret is ever written to prefs, and deleting a config deletes
/// its secret with it.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anthropic_provider.dart';
import 'llm_provider.dart';
import 'llm_types.dart';
import 'openai_compatible_provider.dart';
import 'json_coercion.dart';

enum LlmProviderKind {
  /// Anything speaking `/v1/chat/completions` — llama.cpp's llama-server, LM
  /// Studio, vLLM, Jan, LocalAI, or a box on the LAN.
  openAiCompatible,

  /// Ollama. Same wire protocol via its `/v1` shim; separate kind so the UI can
  /// default the port to 11434 and explain `ollama pull`.
  ollama,

  /// api.openai.com itself.
  openAi,

  /// Claude via `/v1/messages`.
  anthropic,
}

extension LlmProviderKindLabel on LlmProviderKind {
  String get label => switch (this) {
        LlmProviderKind.openAiCompatible => 'OpenAI-compatible server',
        LlmProviderKind.ollama => 'Ollama',
        LlmProviderKind.openAi => 'OpenAI',
        LlmProviderKind.anthropic => 'Claude (Anthropic)',
      };

  /// What to prefill the base-URL field with when this kind is picked.
  String get defaultBaseUrl => switch (this) {
        LlmProviderKind.openAiCompatible => 'http://localhost:8080/v1',
        LlmProviderKind.ollama => 'http://localhost:11434/v1',
        LlmProviderKind.openAi => 'https://api.openai.com/v1',
        LlmProviderKind.anthropic => 'https://api.anthropic.com/v1',
      };

  bool get requiresApiKey =>
      this == LlmProviderKind.openAi || this == LlmProviderKind.anthropic;

  /// The optimistic starting point for a kind. Endpoints that turn out to be
  /// less capable get narrowed by probing and by 400s — see
  /// [OpenAiCompatibleProvider.downgrade].
  LlmCapabilities get assumedCapabilities => switch (this) {
        LlmProviderKind.openAi => const LlmCapabilities(
            strictJsonSchema: true,
            jsonMode: true,
            tools: true,
            embeddings: true,
            contextTokens: 128000,
          ),
        LlmProviderKind.anthropic => const LlmCapabilities(
            strictJsonSchema: true,
            jsonMode: true,
            tools: true,
            contextTokens: 200000,
          ),
        LlmProviderKind.ollama => const LlmCapabilities(
            strictJsonSchema: true,
            jsonMode: true,
            tools: true,
            embeddings: true,
            contextTokens: 8192,
          ),
        // The unknown case. Assume only what every server in the family
        // genuinely does, and let a successful strict call promote it later —
        // guessing high here means a 400 on the user's very first quiz.
        LlmProviderKind.openAiCompatible => const LlmCapabilities(
            jsonMode: true,
            contextTokens: 8192,
          ),
      };
}

class LlmProviderConfig {
  const LlmProviderConfig({
    required this.id,
    required this.label,
    required this.kind,
    required this.baseUrl,
    required this.model,
    this.embeddingModel,
    this.hasApiKey = false,
    this.capabilities,
    this.contextTokens,
  });

  /// Stable id — also the secure-storage key suffix for this config's secret.
  final String id;

  /// User-facing name, shown wherever an answer is attributed.
  final String label;

  final LlmProviderKind kind;
  final String baseUrl;
  final String model;
  final String? embeddingModel;

  /// Whether a secret exists in secure storage for this config. The key itself
  /// never travels in this object.
  final bool hasApiKey;

  /// Learned capabilities, once probing or a rejected request has taught us
  /// something. Null means "use the kind's assumption".
  final LlmCapabilities? capabilities;

  /// User override for the context window, since a local server will happily
  /// advertise nothing and the real limit is whatever the model was loaded with.
  final int? contextTokens;

  LlmCapabilities get effectiveCapabilities {
    final base = capabilities ?? kind.assumedCapabilities;
    return contextTokens == null ? base : base.copyWith(contextTokens: contextTokens);
  }

  LlmProviderConfig copyWith({
    String? label,
    LlmProviderKind? kind,
    String? baseUrl,
    String? model,
    String? embeddingModel,
    bool? hasApiKey,
    LlmCapabilities? capabilities,
    int? contextTokens,
  }) =>
      LlmProviderConfig(
        id: id,
        label: label ?? this.label,
        kind: kind ?? this.kind,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        embeddingModel: embeddingModel ?? this.embeddingModel,
        hasApiKey: hasApiKey ?? this.hasApiKey,
        capabilities: capabilities ?? this.capabilities,
        contextTokens: contextTokens ?? this.contextTokens,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'baseUrl': baseUrl,
        'model': model,
        if (embeddingModel != null) 'embeddingModel': embeddingModel,
        'hasApiKey': hasApiKey,
        if (capabilities != null) 'capabilities': capabilities!.toJson(),
        if (contextTokens != null) 'contextTokens': contextTokens,
      };

  factory LlmProviderConfig.fromJson(Map<String, dynamic> m) =>
      LlmProviderConfig(
        id: asStringOr(m['id']),
        label: asStringOr(m['label'], 'Model'),
        kind: LlmProviderKind.values.firstWhere(
          (k) => k.name == m['kind'],
          orElse: () => LlmProviderKind.openAiCompatible,
        ),
        baseUrl: asStringOr(m['baseUrl']),
        model: asStringOr(m['model']),
        embeddingModel: asString(m['embeddingModel']),
        hasApiKey: asBool(m['hasApiKey']),
        capabilities: asMap(m['capabilities']) == null
            ? null
            : LlmCapabilities.fromJson(asMap(m['capabilities'])!),
        contextTokens: asInt(m['contextTokens']),
      );

  /// Builds the live provider for this config.
  LlmProvider build({required String? apiKey}) {
    switch (kind) {
      case LlmProviderKind.anthropic:
        return AnthropicProvider(
          id: id,
          displayName: label,
          apiKey: apiKey ?? '',
          model: model.isEmpty ? kDefaultAnthropicModel : model,
          baseUrl: baseUrl.isEmpty
              ? 'https://api.anthropic.com/v1'
              : baseUrl,
        );
      case LlmProviderKind.openAi:
      case LlmProviderKind.ollama:
      case LlmProviderKind.openAiCompatible:
        return OpenAiCompatibleProvider(
          id: id,
          displayName: label,
          baseUrl: baseUrl,
          model: model,
          apiKey: apiKey,
          embeddingModel: embeddingModel,
          capabilities: effectiveCapabilities,
          // api.openai.com 400s on unrecognised body fields; local servers
          // ignore what they do not know.
          sendThinkingControls: kind != LlmProviderKind.openAi,
        );
    }
  }
}

/// Persistence for the provider list, the active selection and the secrets.
class LlmProviderStore {
  LlmProviderStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  static const _kConfigs = 'mario.ai.providers';
  static const _kActive = 'mario.ai.activeProvider';
  static const _keyPrefix = 'mario.ai.key.';

  /// The pre-existing single-key setting, migrated on first load so a user who
  /// already pasted a Claude key in Settings does not have to do it again.
  static const _legacyAnthropicKey = 'anthropic_api_key';

  Future<List<LlmProviderConfig>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kConfigs);
    if (raw == null) return _migrateLegacy(prefs);
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          LlmProviderConfig.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<LlmProviderConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kConfigs, jsonEncode([for (final c in configs) c.toJson()]));
  }

  Future<String?> activeId() async =>
      (await SharedPreferences.getInstance()).getString(_kActive);

  Future<void> setActiveId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kActive);
    } else {
      await prefs.setString(_kActive, id);
    }
  }

  Future<String?> readKey(String configId) =>
      _secure.read(key: '$_keyPrefix$configId');

  Future<void> writeKey(String configId, String? key) =>
      key == null || key.isEmpty
          ? _secure.delete(key: '$_keyPrefix$configId')
          : _secure.write(key: '$_keyPrefix$configId', value: key);

  /// Removes a config and its secret together, so a deleted backend cannot
  /// leave a live API key behind in the keyring.
  Future<List<LlmProviderConfig>> remove(
      List<LlmProviderConfig> configs, String id) async {
    final next = [for (final c in configs) if (c.id != id) c];
    await save(next);
    await _secure.delete(key: '$_keyPrefix$id');
    final active = await activeId();
    if (active == id) await setActiveId(next.isEmpty ? null : next.first.id);
    return next;
  }

  /// Turns the old standalone Anthropic key into a first-class provider config.
  Future<List<LlmProviderConfig>> _migrateLegacy(SharedPreferences prefs) async {
    final legacy = await _secure.read(key: _legacyAnthropicKey);
    if (legacy == null || legacy.isEmpty) return const [];
    const id = 'anthropic-legacy';
    final config = LlmProviderConfig(
      id: id,
      label: 'Claude',
      kind: LlmProviderKind.anthropic,
      baseUrl: 'https://api.anthropic.com/v1',
      model: kDefaultAnthropicModel,
      hasApiKey: true,
    );
    await _secure.write(key: '$_keyPrefix$id', value: legacy);
    await prefs.setString(_kConfigs, jsonEncode([config.toJson()]));
    await prefs.setString(_kActive, id);
    return [config];
  }
}
