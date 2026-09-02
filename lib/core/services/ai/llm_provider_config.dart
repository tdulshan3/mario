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

  /// Google's Gemini API through its official OpenAI-compatible endpoint.
  gemini,
}

const kDefaultGeminiModel = 'gemini-2.5-flash';

/// Bounds for a user-supplied context window.
///
/// 1k still leaves enough room for the smallest completion Mario makes. Four
/// million covers current long-context models without letting a mistyped zero
/// ask a local runtime to reserve an absurd amount of RAM or VRAM.
const int kMinContextTokens = 1024;
const int kMaxContextTokens = 4 * 1024 * 1024;

/// Parses the Settings field used for a model's context window.
///
/// Empty means automatic. Binary shorthand matches how model windows are
/// normally named: `32k` is 32 * 1024 and `1m` is 1024 * 1024.
int? parseContextWindowOverride(String input) {
  final source = input.trim().toLowerCase().replaceAll(RegExp(r'[, _]'), '');
  if (source.isEmpty) return null;

  final match = RegExp(r'^(\d+(?:\.\d+)?)([km]?)$').firstMatch(source);
  if (match == null) {
    throw const FormatException('Enter a value like 32768, 32k or 1m.');
  }

  final number = double.parse(match.group(1)!);
  final multiplier = switch (match.group(2)) {
    'k' => 1024,
    'm' => 1024 * 1024,
    _ => 1,
  };
  final scaled = number * multiplier;
  if (!scaled.isFinite ||
      scaled < kMinContextTokens ||
      scaled > kMaxContextTokens) {
    throw const FormatException('Use a context window from 1k to 4m tokens.');
  }
  final tokens = scaled.round();
  return tokens;
}

String formatContextWindow(int tokens) {
  if (tokens % (1024 * 1024) == 0) {
    return '${tokens ~/ (1024 * 1024)}m';
  }
  if (tokens % 1024 == 0) return '${tokens ~/ 1024}k';
  return '$tokens';
}

extension LlmProviderKindLabel on LlmProviderKind {
  String get label => switch (this) {
        LlmProviderKind.openAiCompatible => 'OpenAI-compatible server',
        LlmProviderKind.ollama => 'Ollama',
        LlmProviderKind.openAi => 'OpenAI',
        LlmProviderKind.anthropic => 'Claude (Anthropic)',
        LlmProviderKind.gemini => 'Gemini (Google)',
      };

  /// What to prefill the base-URL field with when this kind is picked.
  String get defaultBaseUrl => switch (this) {
        LlmProviderKind.openAiCompatible => 'http://localhost:8080/v1',
        LlmProviderKind.ollama => 'http://localhost:11434/v1',
        LlmProviderKind.openAi => 'https://api.openai.com/v1',
        LlmProviderKind.anthropic => 'https://api.anthropic.com/v1',
        LlmProviderKind.gemini =>
          'https://generativelanguage.googleapis.com/v1beta/openai',
      };

  bool get requiresApiKey =>
      this == LlmProviderKind.openAi ||
      this == LlmProviderKind.anthropic ||
      this == LlmProviderKind.gemini;

  /// The optimistic starting point for a kind. Endpoints that turn out to be
  /// less capable get narrowed by probing and by 400s — see
  /// [OpenAiCompatibleProvider.downgrade].
  LlmCapabilities get assumedCapabilities => switch (this) {
        LlmProviderKind.openAi => const LlmCapabilities(
            strictJsonSchema: true,
            jsonMode: true,
            tools: true,
            embeddings: true,
            vision: true,
            contextTokens: 128000,
          ),
        LlmProviderKind.anthropic => const LlmCapabilities(
            strictJsonSchema: true,
            jsonMode: true,
            tools: true,
            vision: true,
            contextTokens: 200000,
          ),
        LlmProviderKind.gemini => const LlmCapabilities(
            jsonMode: true,
            tools: true,
            embeddings: true,
            vision: true,
            contextTokens: 1048576,
          ),
        // Ollama serves plenty of text-only models, so vision is off until the
        // user turns it on for a model they know can see. Sending an image to
        // a text-only model wastes a long prefill and returns confident
        // nonsense about a picture it never received.
        LlmProviderKind.ollama => const LlmCapabilities(
            strictJsonSchema: true,
            jsonMode: true,
            tools: true,
            embeddings: true,
            contextTokens: kLocalContextTokens,
          ),
        // The unknown case. Assume only what every server in the family
        // genuinely does, and let a successful strict call promote it later —
        // guessing high here means a 400 on the user's very first quiz.
        LlmProviderKind.openAiCompatible => const LlmCapabilities(
            jsonMode: true,
            contextTokens: kLocalContextTokens,
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
    this.effort = LlmEffort.medium,
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

  /// How hard this backend should think before answering.
  ///
  /// Per backend rather than per app, because the word means different things
  /// to different models and costs different amounts: "high" on a 36B on the
  /// LAN is thirty seconds of thinking that is free, and on a hosted model it
  /// is money. Someone running both wants a different answer for each.
  ///
  /// Only user-facing generation honours it — an answer, a quiz, an agent plan.
  /// The machinery around them (deciding what to search for, marking an essay,
  /// checking grammar) stays where it is: nobody asking for deeper thinking
  /// means they want the search-query planner to deliberate.
  final LlmEffort effort;

  LlmCapabilities get effectiveCapabilities {
    final base = capabilities ?? kind.assumedCapabilities;
    return contextTokens == null
        ? base
        : base.copyWith(contextTokens: contextTokens);
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
    LlmEffort? effort,
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
        effort: effort ?? this.effort,
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
        'effort': effort.name,
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
        // Absent in files written before this existed, which is most of them.
        effort: LlmEffort.values.firstWhere(
          (e) => e.name == m['effort'],
          orElse: () => LlmEffort.medium,
        ),
      );

  /// Builds the live provider for this config.
  LlmProvider build({required String? apiKey}) {
    final requestModel = kind == LlmProviderKind.gemini
        ? model.replaceFirst(RegExp(r'^models/'), '')
        : model;
    switch (kind) {
      case LlmProviderKind.anthropic:
        return AnthropicProvider(
          id: id,
          displayName: label,
          apiKey: apiKey ?? '',
          model: model.isEmpty ? kDefaultAnthropicModel : model,
          baseUrl: baseUrl.isEmpty ? 'https://api.anthropic.com/v1' : baseUrl,
          contextTokens: effectiveCapabilities.contextTokens,
        );
      case LlmProviderKind.openAi:
      case LlmProviderKind.gemini:
      case LlmProviderKind.ollama:
      case LlmProviderKind.openAiCompatible:
        return OpenAiCompatibleProvider(
          id: id,
          displayName: label,
          baseUrl: baseUrl,
          model: requestModel.isEmpty && kind == LlmProviderKind.gemini
              ? kDefaultGeminiModel
              : requestModel,
          apiKey: apiKey,
          embeddingModel: embeddingModel,
          capabilities: effectiveCapabilities,
          // api.openai.com 400s on unrecognised body fields; local servers
          // ignore what they do not know.
          sendThinkingControls:
              kind != LlmProviderKind.openAi && kind != LlmProviderKind.gemini,
          sendContextWindowOption: kind == LlmProviderKind.ollama ||
              kind == LlmProviderKind.openAiCompatible,
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
    final next = [
      for (final c in configs)
        if (c.id != id) c
    ];
    await save(next);
    await _secure.delete(key: '$_keyPrefix$id');
    final active = await activeId();
    if (active == id) await setActiveId(next.isEmpty ? null : next.first.id);
    return next;
  }

  /// Turns the old standalone Anthropic key into a first-class provider config.
  Future<List<LlmProviderConfig>> _migrateLegacy(
      SharedPreferences prefs) async {
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
