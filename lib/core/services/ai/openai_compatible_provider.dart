/// OpenAiCompatibleProvider — one client for every server that speaks
/// `/v1/chat/completions`.
///
/// That is the OpenAI API itself, Ollama's `/v1` shim, llama.cpp's
/// `llama-server`, LM Studio, vLLM, TGI, Jan and LocalAI. Pointing Mario at a
/// box on the LAN (`http://192.168.1.50:8080/v1`) is the same code path as
/// pointing it at api.openai.com; only the base URL and the presence of a key
/// differ.
///
/// "OpenAI-compatible" is a spectrum rather than a standard, so this class is
/// defensive in three specific ways:
///
///  * **Strict schemas are opt-in per endpoint.** Sending
///    `response_format: {type: json_schema}` to a server that has never heard
///    of it yields a 400 from vLLM, a silent ignore from some llama.cpp
///    builds, and a correct answer from OpenAI. The capability record decides,
///    and a 400 that names the field downgrades the record so the next call
///    stops asking.
///  * **Reasoning is separated from the answer.** Qwen3 and friends emit
///    `<think>…</think>` inline when the server does not split it into
///    `reasoning_content`. Left in, that thinking would be saved into the
///    user's notes as if it were the answer.
///  * **Cancellation closes the socket.** A 4B model summarising a section can
///    run for a minute; abandoning the future is not enough, the connection
///    has to actually go away.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';
import 'llm_types.dart';
import 'json_coercion.dart';

class OpenAiCompatibleProvider implements LlmProvider {
  OpenAiCompatibleProvider({
    required this.id,
    required this.displayName,
    required String baseUrl,
    required this.model,
    this.apiKey,
    this.embeddingModel,
    LlmCapabilities? capabilities,
    this.timeout = const Duration(minutes: 5),
    bool flatJsonSchema = false,
    this.sendThinkingControls = true,
    http.Client Function()? clientFactory,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        usesFlatJsonSchema = flatJsonSchema,
        _capabilities = capabilities ?? const LlmCapabilities(),
        _clientFactory = clientFactory ?? http.Client.new;

  @override
  final String id;
  @override
  final String displayName;

  final String baseUrl;
  final String model;
  final String? apiKey;
  final String? embeddingModel;
  final Duration timeout;

  /// Whether to send non-standard hints that turn a hybrid model's reasoning
  /// mode off.
  ///
  /// Qwen3.5-4B and friends default to thinking ON. For a schema-shaped task
  /// that is actively harmful: the model spends its whole `max_tokens` budget
  /// inside `<think>`, generation is cut off before it ever emits the JSON, and
  /// the caller sees "the model could not produce the required JSON" when what
  /// actually happened is that it never got as far as trying.
  ///
  /// `chat_template_kwargs` is the passthrough llama.cpp, vLLM and Ollama all
  /// accept. The real OpenAI API rejects unknown body fields with a 400, so
  /// this is off for that backend.
  final bool sendThinkingControls;
  final http.Client Function() _clientFactory;

  LlmCapabilities _capabilities;
  @override
  LlmCapabilities get capabilities => _capabilities;

  /// Which `response_format` dialect this endpoint speaks.
  ///
  /// The real OpenAI API nests the schema:
  ///   {"type":"json_schema","json_schema":{"name":…,"strict":true,"schema":{…}}}
  /// llama.cpp's llama-server takes it flat:
  ///   {"type":"json_schema","schema":{…}}
  /// Sending the wrong one is not a clean 400 everywhere — some builds accept
  /// the request and simply do not constrain anything, so the failure shows up
  /// as an unparseable quiz rather than an error. [LlmService] tries the
  /// nested form, and flips this on a rejection.
  bool usesFlatJsonSchema;

  /// Accepts everything a user might paste and produces a `…/v1` root with no
  /// trailing slash: `192.168.1.50:8080`, `http://host:8080`,
  /// `http://host:8081/`, `http://host:8081/v1`, `http://host:8081/v1/`, and
  /// even a full `…/v1/chat/completions` pasted out of a curl example.
  static String normalizeBaseUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    // Drop a pasted endpoint path so the user does not end up requesting
    // /v1/chat/completions/chat/completions.
    for (final suffix in const [
      '/chat/completions',
      '/completions',
      '/embeddings',
      '/models',
    ]) {
      if (s.endsWith(suffix)) s = s.substring(0, s.length - suffix.length);
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (!s.endsWith('/v1') && !RegExp(r'/v\d+$').hasMatch(s)) {
      s = '$s/v1';
    }
    return s;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey != null && apiKey!.isNotEmpty)
          'Authorization': 'Bearer $apiKey',
      };

  // ---------------------------------------------------------------- requests

  Map<String, dynamic> _body(LlmRequest req, {required bool stream}) {
    final messages = <Map<String, dynamic>>[];
    final system = req.system;
    if (system != null && system.isNotEmpty) {
      // A handful of instruct-tuned small models were never trained with a
      // system role and quietly ignore it; folding it into the first user turn
      // is the documented workaround and costs nothing when unnecessary.
      if (_capabilities.systemRole) {
        messages.add({'role': 'system', 'content': system});
      }
    }
    for (final m in req.messages) {
      messages.add(_encodeMessage(m, foldSystem: !_capabilities.systemRole));
    }
    if (system != null && system.isNotEmpty && !_capabilities.systemRole) {
      final first = messages.indexWhere((m) => m['role'] == 'user');
      if (first >= 0) {
        messages[first] = {
          'role': 'user',
          'content': '$system\n\n---\n\n${messages[first]['content']}',
        };
      } else {
        messages.insert(0, {'role': 'user', 'content': system});
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': req.maxTokens,
      'temperature': req.temperature,
      if (stream) 'stream': true,
      if (req.stopSequences.isNotEmpty) 'stop': req.stopSequences,
    };

    final fmt = req.jsonFormat;
    if (fmt != null && sendThinkingControls) {
      // Structured output and deliberation do not mix at this size — see
      // [sendThinkingControls].
      body['chat_template_kwargs'] = {'enable_thinking': false};
      body['think'] = false; // Ollama's own spelling
    }
    if (fmt != null) {
      if (_capabilities.strictJsonSchema) {
        body['response_format'] = usesFlatJsonSchema
            ? {'type': 'json_schema', 'schema': fmt.schema}
            : {
                'type': 'json_schema',
                'json_schema': {
                  'name': fmt.name,
                  'strict': true,
                  'schema': fmt.schema,
                },
              };
      } else if (_capabilities.jsonMode) {
        body['response_format'] = {'type': 'json_object'};
      }
      // Otherwise the schema travels in the prompt and the reply goes through
      // json_coercion — see StructuredCompletion in llm_service.dart.
    }

    if (req.tools.isNotEmpty && _capabilities.tools) {
      body['tools'] = [
        for (final t in req.tools)
          {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.parameters,
            },
          },
      ];
    }
    return body;
  }

  Map<String, dynamic> _encodeMessage(LlmMessage m, {required bool foldSystem}) {
    switch (m.role) {
      case LlmRole.tool:
        return {
          'role': 'tool',
          'tool_call_id': m.toolCallId ?? '',
          'content': m.content,
        };
      case LlmRole.assistant:
        return {
          'role': 'assistant',
          'content': m.content,
          if (m.toolCalls.isNotEmpty)
            'tool_calls': [
              for (final c in m.toolCalls)
                {
                  'id': c.id,
                  'type': 'function',
                  'function': {'name': c.name, 'arguments': c.arguments},
                },
            ],
        };
      case LlmRole.system:
        return {'role': foldSystem ? 'user' : 'system', 'content': m.content};
      case LlmRole.user:
        return {'role': 'user', 'content': m.content};
    }
  }

  // ----------------------------------------------------------------- streaming

  @override
  Stream<LlmDelta> stream(LlmRequest request, {CancelToken? cancel}) async* {
    if (!_capabilities.streaming) {
      final r = await complete(request, cancel: cancel);
      yield LlmDelta(text: r.text, reasoning: r.reasoning, toolCalls: r.toolCalls);
      return;
    }

    final client = _clientFactory();
    final sub = cancel?.whenCancelled.then((_) => client.close());
    // Keeps the analyzer honest about the fire-and-forget close hook.
    unawaited(sub ?? Future<void>.value());

    final thinking = _ThinkTagSplitter();
    try {
      final req = http.Request('POST', Uri.parse('$baseUrl/chat/completions'))
        ..headers.addAll(_headers)
        ..body = jsonEncode(_body(request, stream: true));

      final response = await client.send(req).timeout(timeout);
      if (response.statusCode >= 400) {
        final body = await response.stream.bytesToString();
        throw _errorFor(response.statusCode, body);
      }

      final toolBuf = <int, _ToolCallBuffer>{};

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        cancel?.throwIfCancelled();
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') break;

        Map<String, dynamic> chunk;
        try {
          chunk = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue; // keep-alive or a partial frame; the next line completes it
        }

        final choices = chunk['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final choice = choices.first as Map<String, dynamic>;
        final delta = choice['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        // Servers that split reasoning for us: Ollama sends `thinking`,
        // vLLM/DeepSeek-style servers send `reasoning_content`.
        final reasoning =
            asString(delta['reasoning_content'] ?? delta['thinking']);
        final content = asString(delta['content']);

        for (final tc in (delta['tool_calls'] as List? ?? const [])) {
          final m = tc as Map<String, dynamic>;
          final idx = asInt(m['index']) ?? 0;
          final buf = toolBuf.putIfAbsent(idx, _ToolCallBuffer.new);
          buf.absorb(m);
        }

        if (reasoning != null && reasoning.isNotEmpty) {
          yield LlmDelta(reasoning: reasoning);
        }
        if (content != null && content.isNotEmpty) {
          // Servers that do NOT split it leave <think>…</think> inline.
          final split = thinking.add(content);
          if (split.reasoning.isNotEmpty || split.text.isNotEmpty) {
            yield LlmDelta(text: split.text, reasoning: split.reasoning);
          }
        }
      }

      // Flush whatever the tag splitter was holding back. It withholds any
      // tail that could still turn out to be the start of `<think>`; at end of
      // stream it cannot, and dropping it silently truncates the answer — or,
      // when the answer is JSON, produces an unparseable fragment.
      final tail = thinking.flush();
      if (tail.text.isNotEmpty || tail.reasoning.isNotEmpty) {
        yield LlmDelta(text: tail.text, reasoning: tail.reasoning);
      }

      if (toolBuf.isNotEmpty) {
        final calls = [
          for (final k in (toolBuf.keys.toList()..sort())) toolBuf[k]!.build(),
        ];
        yield LlmDelta(toolCalls: calls);
      }
    } on TimeoutException {
      throw LlmException('Timed out after ${timeout.inSeconds}s',
          provider: displayName, isNetwork: true);
    } catch (e) {
      if (cancel?.isCancelled ?? false) throw const LlmCancelled();
      if (e is LlmException || e is LlmCancelled) rethrow;
      throw LlmException(_networkMessage(e),
          provider: displayName, isNetwork: true);
    } finally {
      client.close();
    }
  }

  @override
  Future<LlmResponse> complete(LlmRequest request, {CancelToken? cancel}) async {
    // Streaming and buffering hit the same endpoint; folding the stream keeps
    // one code path for tool-call assembly and think-tag splitting.
    if (_capabilities.streaming) {
      final text = StringBuffer();
      final reasoning = StringBuffer();
      final calls = <LlmToolCall>[];
      await for (final d in stream(request, cancel: cancel)) {
        text.write(d.text);
        reasoning.write(d.reasoning);
        if (d.toolCalls.isNotEmpty) calls.addAll(d.toolCalls);
      }
      return LlmResponse(
        text: text.toString(),
        reasoning: reasoning.toString(),
        toolCalls: calls,
      );
    }

    final client = _clientFactory();
    try {
      final res = await client
          .post(Uri.parse('$baseUrl/chat/completions'),
              headers: _headers,
              body: jsonEncode(_body(request, stream: false)))
          .timeout(timeout);
      if (res.statusCode >= 400) {
        throw _errorFor(res.statusCode, res.body);
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final choice =
          ((json['choices'] as List?)?.firstOrNull as Map<String, dynamic>?) ??
              const {};
      final message = choice['message'] as Map<String, dynamic>? ?? const {};
      final raw = asStringOr(message['content']);
      final split = _ThinkTagSplitter().addAll(raw);
      final usage = json['usage'] as Map<String, dynamic>?;
      return LlmResponse(
        text: split.text,
        reasoning:
            asString(message['reasoning_content'] ?? message['thinking']) ??
                split.reasoning,
        toolCalls: [
          for (final tc in (message['tool_calls'] as List? ?? const []))
            _decodeToolCall(tc as Map<String, dynamic>),
        ],
        promptTokens: asInt(usage?['prompt_tokens']),
        completionTokens: asInt(usage?['completion_tokens']),
        finishReason: asString(choice['finish_reason']),
      );
    } on TimeoutException {
      throw LlmException('Timed out after ${timeout.inSeconds}s',
          provider: displayName, isNetwork: true);
    } catch (e) {
      if (e is LlmException) rethrow;
      throw LlmException(_networkMessage(e),
          provider: displayName, isNetwork: true);
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------- embeddings

  @override
  Future<List<List<double>>> embed(List<String> texts,
      {CancelToken? cancel}) async {
    final m = embeddingModel;
    if (m == null || m.isEmpty) {
      throw LlmException('No embedding model configured',
          provider: displayName);
    }
    if (texts.isEmpty) return const [];
    final client = _clientFactory();
    try {
      final res = await client
          .post(Uri.parse('$baseUrl/embeddings'),
              headers: _headers,
              body: jsonEncode({'model': m, 'input': texts}))
          .timeout(timeout);
      if (res.statusCode >= 400) throw _errorFor(res.statusCode, res.body);
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = (json['data'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .toList()
        // The spec says results carry an `index`; not every server returns
        // them in request order, and a mismatched vector is a silently wrong
        // retrieval rather than a visible error.
        ..sort((a, b) =>
            (asInt(a['index']) ?? 0).compareTo(asInt(b['index']) ?? 0));
      return [
        for (final d in data)
          [for (final v in (d['embedding'] as List? ?? const [])) (v as num).toDouble()],
      ];
    } on TimeoutException {
      throw LlmException('Embedding timed out',
          provider: displayName, isNetwork: true);
    } catch (e) {
      if (e is LlmException) rethrow;
      throw LlmException(_networkMessage(e),
          provider: displayName, isNetwork: true);
    } finally {
      client.close();
    }
  }

  // --------------------------------------------------------------------- probe

  @override
  Future<LlmProbeResult> probe({CancelToken? cancel}) async {
    final client = _clientFactory();
    final started = DateTime.now();
    try {
      final res = await client
          .get(Uri.parse('$baseUrl/models'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final latency = DateTime.now().difference(started);

      if (res.statusCode == 401 || res.statusCode == 403) {
        return LlmProbeResult(
          ok: false,
          message: 'Reachable, but the API key was rejected (HTTP '
              '${res.statusCode}).',
          latency: latency,
        );
      }
      if (res.statusCode >= 400) {
        // llama-server builds without /v1/models still serve chat fine, so a
        // 404 here is not fatal — say so rather than declaring the box dead.
        return LlmProbeResult(
          ok: res.statusCode == 404,
          message: res.statusCode == 404
              ? 'Reachable. This server does not list models, so type the '
                  'model name manually.'
              : 'HTTP ${res.statusCode} from $baseUrl/models',
          latency: latency,
        );
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final models = <String>[];
      if (json is Map<String, dynamic>) {
        for (final d in (json['data'] as List? ?? const [])) {
          final id = (d as Map<String, dynamic>)['id'];
          if (id is String) models.add(id);
        }
      }
      models.sort();
      return LlmProbeResult(
        ok: true,
        message: models.isEmpty
            ? 'Connected. No models advertised.'
            : 'Connected. ${models.length} model(s) available.',
        models: models,
        latency: latency,
      );
    } on TimeoutException {
      return const LlmProbeResult(
          ok: false, message: 'No response within 10s — is the server running?');
    } catch (e) {
      return LlmProbeResult(ok: false, message: _networkMessage(e));
    } finally {
      client.close();
    }
  }

  /// Narrows the capability record after a server rejects a feature, so the
  /// next request stops asking for something this endpoint cannot do.
  void downgrade(LlmCapabilities Function(LlmCapabilities) mut) {
    _capabilities = mut(_capabilities);
  }

  @override
  void dispose() {}

  LlmException _errorFor(int status, String body) {
    final detail = _extractErrorMessage(body);
    return LlmException(
      switch (status) {
        401 || 403 => 'Authentication failed — check the API key.',
        404 => 'Endpoint not found at $baseUrl. Check the base URL.',
        429 => 'Rate limited by the server.',
        >= 500 => 'Server error ($status) — the model may have crashed or run '
            'out of memory.',
        _ => detail ?? 'HTTP $status',
      },
      statusCode: status,
      provider: displayName,
      body: body,
    );
  }

  String? _extractErrorMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map<String, dynamic>) {
        final err = j['error'];
        if (err is String) return err;
        final errMap = asMap(err);
        if (errMap != null) return asString(errMap['message']);
        return asString(j['message']);
      }
    } catch (_) {}
    return body.isEmpty ? null : body.substring(0, body.length.clamp(0, 300));
  }

  String _networkMessage(Object e) {
    final s = e.toString();
    if (s.contains('Connection refused')) {
      return 'Connection refused by $baseUrl — the server is not listening.';
    }
    if (s.contains('Failed host lookup') || s.contains('No address')) {
      return 'Cannot resolve the host in $baseUrl.';
    }
    if (s.contains('Network is unreachable') || s.contains('No route to host')) {
      return 'No route to $baseUrl — are you on the same network?';
    }
    return s;
  }
}

LlmToolCall _decodeToolCall(Map<String, dynamic> m) {
  final fn = m['function'] as Map<String, dynamic>? ?? const {};
  return LlmToolCall(
    id: asStringOr(m['id']),
    name: asStringOr(fn['name']),
    arguments: asStringOr(fn['arguments'], '{}'),
  );
}

/// Accumulates the fragments of one streamed tool call.
class _ToolCallBuffer {
  String id = '';
  String name = '';
  final args = StringBuffer();

  void absorb(Map<String, dynamic> m) {
    final i = m['id'];
    if (i is String && i.isNotEmpty) id = i;
    final fn = m['function'] as Map<String, dynamic>?;
    if (fn == null) return;
    final n = fn['name'];
    if (n is String && n.isNotEmpty) name = n;
    final a = fn['arguments'];
    if (a is String) args.write(a);
  }

  LlmToolCall build() => LlmToolCall(
        id: id,
        name: name,
        arguments: args.isEmpty ? '{}' : args.toString(),
      );
}

/// Splits `<think>…</think>` out of a token stream.
///
/// Qwen3 and other hybrid-reasoning models emit their scratchpad inline when
/// the server does not lift it into a separate field. Because the tags arrive
/// split across chunk boundaries, this holds back any tail that could be the
/// start of a tag and releases it once the ambiguity resolves.
class _ThinkTagSplitter {
  static const _open = '<think>';
  static const _close = '</think>';

  var _inThink = false;
  var _pending = '';

  ({String text, String reasoning}) add(String chunk) {
    _pending += chunk;
    final text = StringBuffer();
    final reasoning = StringBuffer();

    while (_pending.isNotEmpty) {
      final marker = _inThink ? _close : _open;
      final idx = _pending.indexOf(marker);
      if (idx >= 0) {
        final before = _pending.substring(0, idx);
        (_inThink ? reasoning : text).write(before);
        _pending = _pending.substring(idx + marker.length);
        _inThink = !_inThink;
        continue;
      }
      // No complete marker. Hold back only as much as could still become one.
      final keep = _longestPartialSuffix(_pending, marker);
      final emit = _pending.substring(0, _pending.length - keep);
      (_inThink ? reasoning : text).write(emit);
      _pending = _pending.substring(_pending.length - keep);
      break;
    }
    return (text: text.toString(), reasoning: reasoning.toString());
  }

  /// Releases anything still held back. Call once the stream has ended: a
  /// partial `<think` at the very end of the output is just text.
  ({String text, String reasoning}) flush() {
    final tail = _pending;
    _pending = '';
    return (
      text: _inThink ? '' : tail,
      reasoning: _inThink ? tail : '',
    );
  }

  /// Whole-string convenience for the non-streaming path.
  ({String text, String reasoning}) addAll(String whole) {
    final r = add(whole);
    final tail = flush();
    return (
      text: r.text + tail.text,
      reasoning: r.reasoning + tail.reasoning,
    );
  }

  /// True when the output opened a `<think>` block and never closed it —
  /// which means generation was cut off mid-thought and there is no answer,
  /// only reasoning. Distinguishing this from "the model wrote prose" is the
  /// difference between a useful error and a baffling one.
  bool get endedInsideThinking => _inThink;

  static int _longestPartialSuffix(String s, String marker) {
    final max = marker.length - 1 < s.length ? marker.length - 1 : s.length;
    for (var n = max; n > 0; n--) {
      if (marker.startsWith(s.substring(s.length - n))) return n;
    }
    return 0;
  }
}
