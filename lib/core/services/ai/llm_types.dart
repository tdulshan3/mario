/// LLM transport vocabulary — the provider-agnostic types every Mario AI
/// feature speaks, whether the answer comes from a 1.7B model on the user's
/// LAN, Ollama on localhost, the OpenAI API, or Claude.
///
/// Deliberately small: a chat turn, a request, a streamed delta, a capability
/// record and a cancel token. Everything provider-specific (auth headers, the
/// shape of a "message", how JSON is coerced out of a weak model) lives in the
/// provider implementations, not here.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'json_coercion.dart';

/// The context window assumed for a local backend when the server has not
/// said otherwise.
///
/// 64k. It was 8k, which is Ollama's own conservative default and far below
/// what the models people actually run locally will hold — a long page was
/// being trimmed to fit a window the hardware did not have to impose.
///
/// A CLAIM has to be backed by a request: Ollama allocates the context named
/// by `num_ctx` and silently truncates past it, so the OpenAI-compatible
/// provider sends this number with every call. Without that, raising it here
/// would only make the app overfill a window the server never widened.
///
/// Servers that report their own figure (see `local_model_discovery.dart`)
/// override it, and the cloud providers state theirs outright.
const int kLocalContextTokens = 65536;

enum LlmRole { system, user, assistant, tool }

/// One turn in a conversation.
///
/// [toolCalls] is only ever populated on an assistant turn; [toolCallId] only
/// on a tool turn, tying the result back to the call that asked for it.
/// An image attached to a message.
///
/// Carried as raw bytes rather than a path or a URL: every backend wants it
/// base64-encoded inline, a local server cannot fetch a file:// URL from the
/// user's disk, and the alternative — uploading somewhere first — would send
/// a picture out of someone's notes to reach a model running on their own
/// machine.
class LlmImage {
  const LlmImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;

  /// e.g. `image/png`. Both wire formats require it and neither sniffs.
  final String mimeType;

  /// Base64 payload, without a data: prefix — Anthropic wants it bare and
  /// OpenAI wants it prefixed, so each provider adds what it needs.
  String get base64Data => base64Encode(bytes);

  /// Roughly what this costs to send: base64 inflates by a third.
  int get encodedBytes => (bytes.length * 4 / 3).ceil();
}

class LlmMessage {
  const LlmMessage({
    required this.role,
    required this.content,
    this.toolCalls = const [],
    this.toolCallId,
    this.images = const [],
  });

  final LlmRole role;
  final String content;
  final List<LlmToolCall> toolCalls;
  final String? toolCallId;

  /// Images the model should look at alongside [content]. Only meaningful on a
  /// user turn, and only sent when the backend reports [LlmCapabilities.vision].
  final List<LlmImage> images;

  factory LlmMessage.system(String content) =>
      LlmMessage(role: LlmRole.system, content: content);
  factory LlmMessage.user(String content, {List<LlmImage> images = const []}) =>
      LlmMessage(role: LlmRole.user, content: content, images: images);
  factory LlmMessage.assistant(String content,
          {List<LlmToolCall> toolCalls = const []}) =>
      LlmMessage(
          role: LlmRole.assistant, content: content, toolCalls: toolCalls);
  factory LlmMessage.tool(String content, {required String toolCallId}) =>
      LlmMessage(role: LlmRole.tool, content: content, toolCallId: toolCallId);

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        if (toolCalls.isNotEmpty)
          'toolCalls': [for (final c in toolCalls) c.toJson()],
        if (toolCallId != null) 'toolCallId': toolCallId,
      };

  factory LlmMessage.fromJson(Map<String, dynamic> m) => LlmMessage(
        role: LlmRole.values.firstWhere(
          (r) => r.name == m['role'],
          orElse: () => LlmRole.user,
        ),
        content: asStringOr(m['content']),
        toolCalls: [
          for (final c in asMapList(m['toolCalls'])) LlmToolCall.fromJson(c),
        ],
        toolCallId: asString(m['toolCallId']),
      );
}

/// A model's request to run one of the tools we advertised.
class LlmToolCall {
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;

  /// Raw JSON text as the model emitted it. Kept as a string rather than a
  /// decoded map because small models routinely emit *almost*-JSON here, and
  /// the repair pass belongs to the caller that knows the expected shape.
  final String arguments;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'arguments': arguments};

  factory LlmToolCall.fromJson(Map<String, dynamic> m) => LlmToolCall(
        id: asStringOr(m['id']),
        name: asStringOr(m['name']),
        arguments: asStringOr(m['arguments'], '{}'),
      );
}

/// A tool offered to the model.
class LlmTool {
  const LlmTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;

  /// JSON Schema for the arguments object.
  final Map<String, dynamic> parameters;
}

/// How a caller wants structured output enforced.
///
/// The *request* states the shape it needs; each provider then picks the
/// strongest mechanism it actually supports (strict json_schema, plain JSON
/// mode, or prompt-and-repair). Callers never branch on the backend.
class LlmJsonFormat {
  const LlmJsonFormat({
    required this.name,
    required this.schema,
  });

  /// Schema name — some backends require one for strict mode.
  final String name;
  final Map<String, dynamic> schema;
}

class LlmRequest {
  const LlmRequest({
    required this.messages,
    this.system,
    this.maxTokens = 1024,
    this.temperature = 0.2,
    this.jsonFormat,
    this.tools = const [],
    this.stopSequences = const [],
    this.effort = LlmEffort.low,
  });

  final List<LlmMessage> messages;

  /// Hoisted out of [messages] because Anthropic takes it as a top-level
  /// parameter while OpenAI-compatible servers take it as a message. Providers
  /// place it correctly.
  final String? system;

  final int maxTokens;
  final double temperature;
  final LlmJsonFormat? jsonFormat;
  final List<LlmTool> tools;
  final List<String> stopSequences;

  /// How hard the model should think. Providers map this to whatever they
  /// actually support: Anthropic's `output_config.effort`, a reasoning-effort
  /// field on servers that expose one, or nothing at all.
  ///
  /// Most of Mario's work — fixing a comma, summarising a paragraph — wants
  /// [LlmEffort.low]: a grammar check that pauses to deliberate is a worse
  /// grammar check. Grading an essay is the one task that earns more.
  final LlmEffort effort;

  LlmRequest copyWith({
    List<LlmMessage>? messages,
    String? system,
    int? maxTokens,
    double? temperature,
    LlmJsonFormat? jsonFormat,
    List<LlmTool>? tools,
    List<String>? stopSequences,
    LlmEffort? effort,
  }) =>
      LlmRequest(
        messages: messages ?? this.messages,
        system: system ?? this.system,
        maxTokens: maxTokens ?? this.maxTokens,
        temperature: temperature ?? this.temperature,
        jsonFormat: jsonFormat ?? this.jsonFormat,
        tools: tools ?? this.tools,
        stopSequences: stopSequences ?? this.stopSequences,
        effort: effort ?? this.effort,
      );
}

/// Reasoning depth, in provider-neutral terms.
enum LlmEffort { low, medium, high }

/// One streamed increment. [text] is the visible answer; [reasoning] is the
/// separate thinking channel some servers emit (Ollama's `thinking`, OpenAI's
/// reasoning summaries) which must never be mistaken for the answer.
class LlmDelta {
  const LlmDelta({
    this.text = '',
    this.reasoning = '',
    this.toolCalls = const [],
    this.promptTokens,
    this.completionTokens,
    this.finishReason,
  });

  final String text;
  final String reasoning;
  final List<LlmToolCall> toolCalls;

  /// Usage and stop reason, when the server reports them. On a streamed reply
  /// they arrive in a final chunk carrying no text, which is why they live on
  /// the delta rather than only on [LlmResponse].
  final int? promptTokens;
  final int? completionTokens;
  final String? finishReason;
}

class LlmResponse {
  const LlmResponse({
    required this.text,
    this.reasoning = '',
    this.toolCalls = const [],
    this.promptTokens,
    this.completionTokens,
    this.finishReason,
  });

  final String text;
  final String reasoning;
  final List<LlmToolCall> toolCalls;
  final int? promptTokens;
  final int? completionTokens;
  final String? finishReason;

  /// True when the model was cut off by the token ceiling rather than
  /// finishing — the single most common cause of a truncated, unparseable
  /// JSON body, so callers check this before blaming the schema.
  bool get hitTokenLimit =>
      finishReason == 'length' || finishReason == 'max_tokens';
}

/// What a backend can actually do.
///
/// "OpenAI-compatible" is a spectrum, not a standard: llama.cpp's server,
/// LM Studio, vLLM, Ollama's /v1 shim and OpenAI itself all diverge on strict
/// schemas, tool calling and streaming. Features degrade against this record
/// instead of crashing on a 400.
class LlmCapabilities {
  const LlmCapabilities({
    this.streaming = true,
    this.strictJsonSchema = false,
    this.jsonMode = false,
    this.tools = false,
    this.embeddings = false,
    this.systemRole = true,
    this.vision = false,
    this.contextTokens = kLocalContextTokens,
  });

  final bool streaming;

  /// `response_format: {type: json_schema, strict: true}` — the decoder is
  /// constrained, so the output is valid by construction.
  final bool strictJsonSchema;

  /// `response_format: {type: json_object}` — valid JSON, but not necessarily
  /// *your* shape. Still worth a lot over free text.
  final bool jsonMode;

  final bool tools;
  final bool embeddings;
  final bool systemRole;

  /// Whether the model can look at an image. Every current small model is
  /// natively multimodal, but the *server* still has to accept image parts, and
  /// a text-only model given one either errors or silently ignores it.
  final bool vision;

  final int contextTokens;

  LlmCapabilities copyWith({
    bool? streaming,
    bool? strictJsonSchema,
    bool? jsonMode,
    bool? tools,
    bool? embeddings,
    bool? systemRole,
    bool? vision,
    int? contextTokens,
  }) =>
      LlmCapabilities(
        streaming: streaming ?? this.streaming,
        strictJsonSchema: strictJsonSchema ?? this.strictJsonSchema,
        jsonMode: jsonMode ?? this.jsonMode,
        tools: tools ?? this.tools,
        embeddings: embeddings ?? this.embeddings,
        systemRole: systemRole ?? this.systemRole,
        vision: vision ?? this.vision,
        contextTokens: contextTokens ?? this.contextTokens,
      );

  Map<String, dynamic> toJson() => {
        'streaming': streaming,
        'strictJsonSchema': strictJsonSchema,
        'jsonMode': jsonMode,
        'tools': tools,
        'embeddings': embeddings,
        'systemRole': systemRole,
        'vision': vision,
        'contextTokens': contextTokens,
      };

  factory LlmCapabilities.fromJson(Map<String, dynamic> m) => LlmCapabilities(
        streaming: asBool(m['streaming'], fallback: true),
        strictJsonSchema: asBool(m['strictJsonSchema']),
        jsonMode: asBool(m['jsonMode']),
        tools: asBool(m['tools']),
        embeddings: asBool(m['embeddings']),
        systemRole: asBool(m['systemRole'], fallback: true),
        vision: asBool(m['vision']),
        contextTokens: asInt(m['contextTokens']) ?? kLocalContextTokens,
      );
}

/// Cooperative cancellation.
///
/// A local 4B model answering a section-wide question can run for a minute;
/// the user must be able to stop it, and the HTTP connection must actually
/// close rather than the UI merely ignoring the result.
class CancelToken {
  final _completer = Completer<void>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Throws if cancellation has already been requested — call at each await
  /// boundary in a long pipeline.
  void throwIfCancelled() {
    if (_cancelled) throw const LlmCancelled();
  }
}

class LlmCancelled implements Exception {
  const LlmCancelled();
  @override
  String toString() => 'Cancelled';
}

/// A failure that carries the model output that caused it, so the UI can show
/// the user what was actually said rather than only that it was unusable.
abstract interface class HasRawOutput {
  String? get raw;
}

/// A failure that carries enough context for the UI to say something true.
class LlmException implements Exception {
  const LlmException(
    this.message, {
    this.statusCode,
    this.provider,
    this.isNetwork = false,
    this.body,
  });

  final String message;
  final int? statusCode;
  final String? provider;

  /// The host was unreachable rather than unhappy — the LAN box is off, or
  /// there is no network. Worth a different message and a different retry.
  final bool isNetwork;

  final String? body;

  @override
  String toString() => provider == null
      ? 'LlmException: $message'
      : 'LlmException($provider): $message';
}
