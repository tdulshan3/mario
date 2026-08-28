/// LlmProvider — the one interface every Mario AI feature talks to.
///
/// Implementations: [OpenAiCompatibleProvider] (covers the OpenAI API, Ollama's
/// /v1 shim, llama.cpp's llama-server, LM Studio, vLLM, Jan, LocalAI — anything
/// exposing `/v1/chat/completions`) and [AnthropicProvider] (Claude's
/// `/v1/messages`, which is a different enough shape to need its own).
///
/// Features never branch on which one is behind the interface. Where backends
/// genuinely differ — strict JSON schemas, tool calling, streaming — they
/// declare it in [capabilities] and callers degrade against that record.
library;

import 'llm_types.dart';

abstract class LlmProvider {
  /// Stable id of the configuration that produced this provider.
  String get id;

  /// Human-facing, e.g. "LAN · qwen3:4b" — shown in the UI so the user always
  /// knows which brain answered.
  String get displayName;

  LlmCapabilities get capabilities;

  /// Streamed completion. Providers that cannot stream emit one final delta.
  Stream<LlmDelta> stream(LlmRequest request, {CancelToken? cancel});

  /// Buffered completion. Default implementation folds [stream]; providers
  /// override when a non-streaming call is cheaper or more reliable.
  Future<LlmResponse> complete(LlmRequest request, {CancelToken? cancel});

  /// Embeddings for retrieval. Throws [LlmException] when
  /// `capabilities.embeddings` is false.
  Future<List<List<double>>> embed(List<String> texts, {CancelToken? cancel});

  /// Reachability + capability probe, used by the settings "Test connection"
  /// button and at startup to notice the LAN box is off.
  Future<LlmProbeResult> probe({CancelToken? cancel});

  void dispose();
}

/// What a probe learned about an endpoint.
class LlmProbeResult {
  const LlmProbeResult({
    required this.ok,
    required this.message,
    this.models = const [],
    this.capabilities,
    this.latency,
  });

  final bool ok;
  final String message;

  /// Model ids the endpoint advertises, so settings can offer a picker instead
  /// of making the user type `qwen3:4b` exactly right.
  final List<String> models;

  final LlmCapabilities? capabilities;
  final Duration? latency;
}
