/// LlmService — provider resolution plus the one hard problem the pluggable
/// backend creates: getting *reliable structured output* from endpoints of
/// wildly different capability.
///
/// Quiz generation, grading and grammar suggestions are all schema-shaped. On
/// Claude or OpenAI the decoder can be constrained and the reply is valid by
/// construction. On a llama.cpp server running a 1.7B model there may be no
/// `response_format` support at all, and the reply arrives fenced, prefixed
/// with an apology, or truncated. [structured] hides that difference behind
/// one call:
///
///   1. **Strict schema** where the backend supports it — one request, done.
///   2. **JSON mode** plus the schema in the prompt — valid JSON, shape coaxed.
///   3. **Prompt only**, then [extractJson] repair — the weak-backend path.
///   4. **One repair round-trip**, showing the model its own broken output.
///
/// A 400 that names `response_format` narrows the stored capability record, so
/// an endpoint only ever rejects a feature once rather than on every request.
library;

import 'dart:convert';

import 'json_coercion.dart';
import 'llm_provider.dart';
import 'llm_provider_config.dart';
import 'llm_types.dart';
import 'openai_compatible_provider.dart';

/// The live set of configured backends.
class AiBackends {
  AiBackends(this._store);

  final LlmProviderStore _store;

  List<LlmProviderConfig> _configs = const [];
  String? _activeId;
  final _providers = <String, LlmProvider>{};

  List<LlmProviderConfig> get configs => List.unmodifiable(_configs);
  String? get activeId => _activeId;

  /// True when nothing is configured — every AI entry point checks this and
  /// offers to open Settings rather than failing mid-request.
  bool get isConfigured => activeConfig != null;

  LlmProviderConfig? get activeConfig {
    if (_configs.isEmpty) return null;
    return _configs.where((c) => c.id == _activeId).firstOrNull ??
        _configs.first;
  }

  Future<void> load() async {
    _configs = await _store.load();
    _activeId = await _store.activeId() ?? _configs.firstOrNull?.id;
  }

  Future<void> saveConfigs(List<LlmProviderConfig> configs) async {
    _configs = configs;
    await _store.save(configs);
    _providers.clear(); // rebuild lazily against the new settings
  }

  Future<void> setActive(String id) async {
    _activeId = id;
    await _store.setActiveId(id);
  }

  Future<void> remove(String id) async {
    _configs = await _store.remove(_configs, id);
    _providers.remove(id)?.dispose();
    _activeId = await _store.activeId();
  }

  Future<void> setKey(String configId, String? key) async {
    await _store.writeKey(configId, key);
    _providers.remove(configId)?.dispose();
    _configs = [
      for (final c in _configs)
        c.id == configId
            ? c.copyWith(hasApiKey: key != null && key.isNotEmpty)
            : c,
    ];
    await _store.save(_configs);
  }

  Future<LlmProvider?> provider([String? id]) async {
    final config = id == null
        ? activeConfig
        : _configs.where((c) => c.id == id).firstOrNull;
    if (config == null) return null;
    final existing = _providers[config.id];
    if (existing != null) return existing;
    final key = config.hasApiKey ? await _store.readKey(config.id) : null;
    final built = config.build(apiKey: key);
    _providers[config.id] = built;
    return built;
  }

  /// Persists a capability the backend just proved it does not have, so the
  /// next request stops asking.
  Future<void> recordCapability(
      String configId, LlmCapabilities Function(LlmCapabilities) mut) async {
    _configs = [
      for (final c in _configs)
        c.id == configId
            ? c.copyWith(capabilities: mut(c.effectiveCapabilities))
            : c,
    ];
    await _store.save(_configs);
  }

  void dispose() {
    for (final p in _providers.values) {
      p.dispose();
    }
    _providers.clear();
  }
}

/// Thrown when a structured request could not be coerced into the requested
/// shape even after a repair attempt.
class StructuredOutputException implements Exception, HasRawOutput {
  const StructuredOutputException(this.message, {this.raw});
  final String message;

  /// What the model actually said. Shown to the user behind a disclosure —
  /// with a local model this is usually the fastest way to see whether it
  /// rambled, thought itself out of budget, or emitted almost-JSON.
  @override
  final String? raw;

  @override
  String toString() => message;
}

class LlmService {
  LlmService(this.backends);

  final AiBackends backends;

  Future<LlmProvider> requireProvider([String? id]) async {
    final p = await backends.provider(id);
    if (p == null) {
      throw const LlmException(
          'No AI model is set up yet. Add one in Settings → AI models.');
    }
    return p;
  }

  /// Free-text completion, streamed.
  Stream<LlmDelta> stream(LlmRequest request, {CancelToken? cancel}) async* {
    final provider = await requireProvider();
    yield* provider.stream(request, cancel: cancel);
  }

  /// A completion constrained to [schema], returning the decoded object.
  ///
  /// [schemaName] is required by strict-mode backends. [describeSchema]
  /// controls whether the schema is also spelled out in the prompt — on by
  /// default because it costs a few tokens and is the only thing keeping the
  /// weak-backend path on the rails.
  Future<Map<String, dynamic>> structured({
    required LlmRequest request,
    required String schemaName,
    required Map<String, dynamic> schema,
    CancelToken? cancel,
    bool describeSchema = true,
    int repairAttempts = 1,
  }) async {
    final provider = await requireProvider();
    final caps = provider.capabilities;

    // The schema goes in the prompt even when the backend can constrain the
    // decoder. Grammar-constrained sampling — llama.cpp's GBNF, and Ollama's
    // `format`, which is built on it — shapes the output but never shows the
    // model the schema, so a constrained model emits the right *structure*
    // full of wrong values: it has no idea what `correctIndex` is supposed to
    // mean. The hosted APIs do surface the schema, so for them this is a few
    // redundant tokens; for a local server it is the difference between a
    // usable quiz and well-formed nonsense.
    final withSchema = request.copyWith(
      jsonFormat: LlmJsonFormat(name: schemaName, schema: schema),
      system: describeSchema
          ? _appendSchemaInstruction(request.system, schema)
          : request.system,
    );

    LlmResponse response;
    try {
      response = await provider.complete(withSchema, cancel: cancel);
    } on LlmException catch (e) {
      if (!_isUnsupportedFormatError(e)) rethrow;

      // Before concluding the endpoint cannot do schemas at all, try the other
      // dialect: llama-server wants the schema flat rather than nested under
      // `json_schema`, and rejects the nested form. One retry distinguishes
      // "speaks a different dialect" from "does not support this".
      if (provider is OpenAiCompatibleProvider &&
          !provider.usesFlatJsonSchema) {
        provider.usesFlatJsonSchema = true;
        try {
          response = await provider.complete(withSchema, cancel: cancel);
          final viaFlat = extractJsonObject(response.text);
          if (viaFlat != null) return viaFlat;
        } on LlmException {
          provider.usesFlatJsonSchema = false;
        }
      }

      // Neither dialect worked: this endpoint genuinely has no structured
      // output. Narrow the stored record so later calls stop asking, and fall
      // back to prompt-and-repair for this one.
      if (provider is OpenAiCompatibleProvider) {
        provider.downgrade(
            (c) => c.copyWith(strictJsonSchema: false, jsonMode: false));
      }
      await backends.recordCapability(provider.id,
          (c) => c.copyWith(strictJsonSchema: false, jsonMode: false));
      response = await provider.complete(
        request.copyWith(
            system: _appendSchemaInstruction(request.system, schema)),
        cancel: cancel,
      );
    }

    final parsed = extractJsonObject(response.text);
    if (parsed != null) return parsed;

    // A hybrid-reasoning model that was never told to stop thinking spends the
    // whole budget inside <think> and is cut off before it writes anything. The
    // answer channel is then empty and the JSON, if it exists at all, is in the
    // reasoning. Worth a look before giving up — it costs nothing and turns a
    // hard failure into a success surprisingly often.
    if (response.text.trim().isEmpty && response.reasoning.trim().isNotEmpty) {
      final fromReasoning = extractJsonObject(response.reasoning);
      if (fromReasoning != null) return fromReasoning;
    }

    if (repairAttempts <= 0) {
      throw StructuredOutputException(
        _diagnose(response),
        raw: response.text.trim().isEmpty ? response.reasoning : response.text,
      );
    }

    final repaired = await provider.complete(
      LlmRequest(
        messages: [
          ...request.messages,
          LlmMessage.assistant(response.text),
          LlmMessage.user(
            'That was not valid JSON matching the required schema. Reply with '
            'the corrected JSON object only — no prose, no code fence.\n\n'
            'Schema:\n${const JsonEncoder.withIndent('  ').convert(schema)}',
          ),
        ],
        system: request.system,
        maxTokens: request.maxTokens,
        temperature: 0,
        effort: request.effort,
        jsonFormat: caps.strictJsonSchema
            ? LlmJsonFormat(name: schemaName, schema: schema)
            : null,
      ),
      cancel: cancel,
    );

    final second = extractJsonObject(repaired.text) ??
        (repaired.text.trim().isEmpty
            ? extractJsonObject(repaired.reasoning)
            : null);
    if (second != null) return second;
    throw StructuredOutputException(
      _diagnose(repaired),
      raw: repaired.text.trim().isEmpty ? repaired.reasoning : repaired.text,
    );
  }

  /// Says what actually went wrong, in terms the user can act on.
  ///
  /// "The model could not produce the required JSON" is true of every failure
  /// here and useful for none of them. These four cases have four different
  /// fixes, and the user cannot pick one without being told which they hit.
  String _diagnose(LlmResponse response) {
    final text = response.text.trim();
    final reasoning = response.reasoning.trim();

    if (text.isEmpty && reasoning.isNotEmpty) {
      return 'The model spent its whole response thinking and never wrote an '
          'answer. This model has reasoning mode on by default — turn it off '
          '(for Qwen, "/no_think" or enable_thinking=false), pick a '
          'non-thinking model, or raise the token limit.';
    }
    if (text.isEmpty) {
      return 'The model returned nothing at all. Check that the model name in '
          'Settings matches one the server actually has loaded.';
    }
    if (response.hitTokenLimit) {
      return 'The model ran out of output space before finishing its answer. '
          'Try a smaller scope, or a model with more room.';
    }
    return 'The model replied with prose instead of JSON. Small models often '
        'cannot follow a schema reliably — 2B is about the floor for this, and '
        'a heavily quantised model is worse at it than its size suggests.';
  }

  String _appendSchemaInstruction(String? system, Map<String, dynamic> schema) {
    final pretty = const JsonEncoder.withIndent('  ').convert(schema);
    final instruction =
        'Reply with a single JSON object and nothing else. No prose before or '
        'after it, no markdown code fence. It must match this JSON Schema '
        'exactly:\n\n$pretty';
    return system == null || system.isEmpty
        ? instruction
        : '$system\n\n$instruction';
  }

  /// Recognises the several ways a server says "I don't do response_format".
  bool _isUnsupportedFormatError(LlmException e) {
    if (e.statusCode != 400 && e.statusCode != 422 && e.statusCode != 501) {
      return false;
    }
    final haystack = '${e.message} ${e.body ?? ''}'.toLowerCase();
    return haystack.contains('response_format') ||
        haystack.contains('json_schema') ||
        haystack.contains('guided') ||
        haystack.contains('not supported') ||
        haystack.contains('unrecognized');
  }
}
