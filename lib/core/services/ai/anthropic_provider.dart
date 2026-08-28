/// AnthropicProvider — Claude via `POST /v1/messages`.
///
/// Its own implementation rather than a tweak of [OpenAiCompatibleProvider]
/// because the wire shape genuinely differs: `system` is a top-level parameter
/// rather than a message, content is an array of typed blocks rather than a
/// string, tools use `input_schema` and come back as `tool_use` blocks, and
/// auth is `x-api-key` rather than a bearer token.
///
/// Three current-API details this file exists to get right, each of which is a
/// 400 or a silently worse answer if you carry over an older pattern:
///
///  * **No `temperature`.** Sampling parameters were removed on the current
///    models (Opus 5, Sonnet 5, Opus 4.8/4.7). Sending one is rejected, so the
///    provider-neutral [LlmRequest.temperature] is deliberately dropped here
///    and reasoning depth is expressed through `output_config.effort` instead.
///  * **No assistant prefill.** The old trick of seeding the reply with `{` to
///    force JSON returns a 400. Structured output goes through
///    `output_config.format` with a JSON schema, which constrains the decoder
///    properly — so Claude is a `strictJsonSchema` backend and never needs the
///    repair path in json_coercion.dart.
///  * **Thinking is on by default** on Opus 5. That is usually right, but a
///    grammar check should not deliberate, so cheap tasks ride at
///    `effort: low` rather than disabling thinking (disabling it has its own
///    failure modes, including tags leaking into the visible answer).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';
import 'llm_types.dart';
import 'json_coercion.dart';

/// Sensible default when the user supplies a key but names no model.
const kDefaultAnthropicModel = 'claude-opus-5';

class AnthropicProvider implements LlmProvider {
  AnthropicProvider({
    required this.id,
    required this.displayName,
    required this.apiKey,
    this.model = kDefaultAnthropicModel,
    this.baseUrl = 'https://api.anthropic.com/v1',
    this.timeout = const Duration(minutes: 5),
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  @override
  final String id;
  @override
  final String displayName;

  final String apiKey;
  final String model;
  final String baseUrl;
  final Duration timeout;
  final http.Client Function() _clientFactory;

  static const _version = '2023-06-01';

  @override
  LlmCapabilities get capabilities => const LlmCapabilities(
        streaming: true,
        // output_config.format constrains the decoder — valid by construction.
        strictJsonSchema: true,
        jsonMode: true,
        tools: true,
        // Anthropic has no embeddings endpoint; retrieval uses a local or
        // OpenAI-compatible embedder instead. See EmbeddingService.
        embeddings: false,
        systemRole: true,
        contextTokens: 200000,
      );

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': _version,
      };

  Map<String, dynamic> _body(LlmRequest req, {required bool stream}) {
    final messages = <Map<String, dynamic>>[];
    for (final m in req.messages) {
      switch (m.role) {
        case LlmRole.system:
          // Anthropic takes system out-of-band; a stray system turn folds into
          // the top-level field rather than being dropped.
          continue;
        case LlmRole.tool:
          // A tool result is a *user* turn carrying a tool_result block.
          messages.add({
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': m.toolCallId ?? '',
                'content': m.content,
              },
            ],
          });
        case LlmRole.assistant:
          final blocks = <Map<String, dynamic>>[
            if (m.content.isNotEmpty) {'type': 'text', 'text': m.content},
            for (final c in m.toolCalls)
              {
                'type': 'tool_use',
                'id': c.id,
                'name': c.name,
                'input': _decodeArgs(c.arguments),
              },
          ];
          messages.add({'role': 'assistant', 'content': blocks});
        case LlmRole.user:
          messages.add({'role': 'user', 'content': m.content});
      }
    }

    final systemParts = <String>[
      if (req.system != null && req.system!.isNotEmpty) req.system!,
      for (final m in req.messages)
        if (m.role == LlmRole.system) m.content,
    ];

    return <String, dynamic>{
      'model': model,
      'max_tokens': req.maxTokens,
      if (systemParts.isNotEmpty) 'system': systemParts.join('\n\n'),
      'messages': messages,
      if (stream) 'stream': true,
      if (req.stopSequences.isNotEmpty) 'stop_sequences': req.stopSequences,
      'output_config': {
        'effort': switch (req.effort) {
          LlmEffort.low => 'low',
          LlmEffort.medium => 'medium',
          LlmEffort.high => 'high',
        },
        if (req.jsonFormat != null)
          'format': {
            'type': 'json_schema',
            'schema': req.jsonFormat!.schema,
          },
      },
      if (req.tools.isNotEmpty)
        'tools': [
          for (final t in req.tools)
            {
              'name': t.name,
              'description': t.description,
              'input_schema': t.parameters,
            },
        ],
      // Deliberately absent: `temperature`. Removed on current models — see
      // the file header.
    };
  }

  @override
  Stream<LlmDelta> stream(LlmRequest request, {CancelToken? cancel}) async* {
    final client = _clientFactory();
    unawaited(cancel?.whenCancelled.then((_) => client.close()) ??
        Future<void>.value());

    // Tool arguments arrive as `input_json_delta` fragments keyed by the
    // content block's index, so they have to be reassembled per index.
    final toolBlocks = <int, _AnthropicToolBlock>{};

    try {
      final req = http.Request('POST', Uri.parse('$baseUrl/messages'))
        ..headers.addAll(_headers)
        ..body = jsonEncode(_body(request, stream: true));

      final response = await client.send(req).timeout(timeout);
      if (response.statusCode >= 400) {
        throw _errorFor(
            response.statusCode, await response.stream.bytesToString());
      }

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        cancel?.throwIfCancelled();
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;

        Map<String, dynamic> event;
        try {
          event = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        switch (asString(event['type'])) {
          case 'content_block_start':
            final idx = asInt(event['index']) ?? 0;
            final block = asMap(event['content_block']);
            if (block?['type'] == 'tool_use') {
              toolBlocks[idx] = _AnthropicToolBlock(
                id: asStringOr(block!['id']),
                name: asStringOr(block['name']),
              );
            }
          case 'content_block_delta':
            final idx = asInt(event['index']) ?? 0;
            final delta = asMap(event['delta']);
            if (delta == null) break;
            switch (asString(delta['type'])) {
              case 'text_delta':
                final t = asStringOr(delta['text']);
                if (t.isNotEmpty) yield LlmDelta(text: t);
              case 'thinking_delta':
                // Summarised reasoning, when display: summarized is on. Kept
                // apart from the answer so it can drive the "thinking" step in
                // the progress UI without ever landing in the user's note.
                final t = asStringOr(delta['thinking']);
                if (t.isNotEmpty) yield LlmDelta(reasoning: t);
              case 'input_json_delta':
                toolBlocks[idx]?.args.write(asStringOr(delta['partial_json']));
            }
          case 'message_stop':
            break;
        }
      }

      if (toolBlocks.isNotEmpty) {
        yield LlmDelta(toolCalls: [
          for (final k in (toolBlocks.keys.toList()..sort()))
            toolBlocks[k]!.build(),
        ]);
      }
    } on TimeoutException {
      throw LlmException('Claude timed out after ${timeout.inSeconds}s',
          provider: displayName, isNetwork: true);
    } catch (e) {
      if (cancel?.isCancelled ?? false) throw const LlmCancelled();
      if (e is LlmException || e is LlmCancelled) rethrow;
      throw LlmException(e.toString(), provider: displayName, isNetwork: true);
    } finally {
      client.close();
    }
  }

  @override
  Future<LlmResponse> complete(LlmRequest request, {CancelToken? cancel}) async {
    final client = _clientFactory();
    try {
      final res = await client
          .post(Uri.parse('$baseUrl/messages'),
              headers: _headers,
              body: jsonEncode(_body(request, stream: false)))
          .timeout(timeout);
      if (res.statusCode >= 400) throw _errorFor(res.statusCode, res.body);

      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final text = StringBuffer();
      final reasoning = StringBuffer();
      final calls = <LlmToolCall>[];

      for (final b in asMapList(json['content'])) {
        switch (asString(b['type'])) {
          case 'text':
            text.write(asStringOr(b['text']));
          case 'thinking':
            reasoning.write(asStringOr(b['thinking']));
          case 'tool_use':
            calls.add(LlmToolCall(
              id: asStringOr(b['id']),
              name: asStringOr(b['name']),
              arguments: jsonEncode(b['input'] ?? const {}),
            ));
        }
      }

      final usage = asMap(json['usage']);
      final stopReason = asString(json['stop_reason']);

      // A safety decline arrives as a 200 with stop_reason "refusal" — it is
      // not an error to retry, and it must not be mistaken for an empty answer.
      if (stopReason == 'refusal') {
        final details = asMap(json['stop_details']);
        throw LlmException(
          'Claude declined this request'
          '${details?['category'] == null ? '' : ' (${details!['category']})'}.',
          provider: displayName,
        );
      }

      return LlmResponse(
        text: text.toString(),
        reasoning: reasoning.toString(),
        toolCalls: calls,
        promptTokens: asInt(usage?['input_tokens']),
        completionTokens: asInt(usage?['output_tokens']),
        finishReason: stopReason,
      );
    } on TimeoutException {
      throw LlmException('Claude timed out after ${timeout.inSeconds}s',
          provider: displayName, isNetwork: true);
    } catch (e) {
      if (e is LlmException) rethrow;
      throw LlmException(e.toString(), provider: displayName, isNetwork: true);
    } finally {
      client.close();
    }
  }

  @override
  Future<List<List<double>>> embed(List<String> texts,
          {CancelToken? cancel}) async =>
      throw LlmException(
        'Claude has no embeddings endpoint — configure a local or '
        'OpenAI-compatible embedding model for retrieval.',
        provider: displayName,
      );

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
            message: 'API key rejected (HTTP ${res.statusCode}).',
            latency: latency);
      }
      if (res.statusCode >= 400) {
        return LlmProbeResult(
            ok: false,
            message: 'HTTP ${res.statusCode} from the Anthropic API.',
            latency: latency);
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final models = <String>[
        for (final d in (json['data'] as List? ?? const []))
          if ((d as Map<String, dynamic>)['id'] is String) d['id'] as String,
      ]..sort();
      return LlmProbeResult(
        ok: true,
        message: 'Connected to the Anthropic API.',
        models: models,
        latency: latency,
      );
    } on TimeoutException {
      return const LlmProbeResult(
          ok: false, message: 'No response from api.anthropic.com within 10s.');
    } catch (e) {
      return LlmProbeResult(ok: false, message: e.toString());
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {}

  LlmException _errorFor(int status, String body) {
    String? detail;
    try {
      final error = asMap(asMap(jsonDecode(body))?['error']);
      detail = asString(error?['message']);
    } catch (_) {
      // A non-JSON body (an HTML error page from a proxy). The status-based
      // message below is more useful than the markup anyway.
    }
    return LlmException(
      switch (status) {
        401 => 'Anthropic rejected the API key.',
        403 => 'This API key is not permitted to use $model.',
        404 => 'Model "$model" not found.',
        429 => 'Rate limited by Anthropic — try again shortly.',
        >= 500 => 'Anthropic server error ($status).',
        _ => detail ?? 'HTTP $status',
      },
      statusCode: status,
      provider: displayName,
      body: body,
    );
  }

  Map<String, dynamic> _decodeArgs(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

class _AnthropicToolBlock {
  _AnthropicToolBlock({required this.id, required this.name});
  final String id;
  final String name;
  final args = StringBuffer();

  LlmToolCall build() => LlmToolCall(
        id: id,
        name: name,
        arguments: args.isEmpty ? '{}' : args.toString(),
      );
}
