/// A model that thinks its whole budget away gets one more turn without
/// thinking, before anyone tries to "repair" an answer that was never
/// written.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider.dart';
import 'package:mario/core/services/ai/llm_provider_config.dart';
import 'package:mario/core/services/ai/llm_service.dart';
import 'package:mario/core/services/ai/llm_types.dart';

void main() {
  const schema = {
    'type': 'object',
    'properties': {
      'ok': {'type': 'boolean'}
    },
  };

  LlmRequest request(LlmEffort effort) => LlmRequest(
        messages: [LlmMessage.user('Answer in JSON.')],
        maxTokens: 200,
        effort: effort,
      );

  test('thought and no answer → asked again with thinking off', () async {
    final provider = _ScriptedProvider([
      const LlmResponse(
          text: '', reasoning: 'Let me plan this…', finishReason: 'length'),
      const LlmResponse(text: '{"ok": true}'),
    ]);
    final llm = _ServiceWith(provider);

    final result = await llm.structured(
      request: request(LlmEffort.medium),
      schemaName: 'probe',
      schema: schema,
    );

    expect(result, {'ok': true});
    expect(provider.requests, hasLength(2));
    expect(provider.requests[0].effort, LlmEffort.medium);
    expect(provider.requests[1].effort, LlmEffort.low,
        reason: 'the retry turns thinking off');
    // The retry keeps the same messages and schema; it is not a repair.
    expect(provider.requests[1].messages.single.content, 'Answer in JSON.');
    expect(provider.requests[1].jsonFormat, isNotNull);
  });

  test('already not thinking → no retry, straight to the repair round',
      () async {
    final provider = _ScriptedProvider([
      const LlmResponse(text: '', reasoning: 'hmm', finishReason: 'length'),
      const LlmResponse(text: '{"ok": false}'),
    ]);
    final llm = _ServiceWith(provider);

    final result = await llm.structured(
      request: request(LlmEffort.low),
      schemaName: 'probe',
      schema: schema,
    );

    expect(result, {'ok': false});
    expect(provider.requests, hasLength(2));
    // The second call is the repair: it carries the correction message.
    expect(
        provider.requests[1].messages.last.content, contains('not valid JSON'));
  });

  test('a good answer first time is not retried', () async {
    final provider = _ScriptedProvider([
      const LlmResponse(text: '{"ok": true}', reasoning: 'brief'),
    ]);
    final llm = _ServiceWith(provider);
    await llm.structured(
      request: request(LlmEffort.high),
      schemaName: 'probe',
      schema: schema,
    );
    expect(provider.requests, hasLength(1));
  });
}

class _ServiceWith extends LlmService {
  _ServiceWith(this.provider) : super(AiBackends(LlmProviderStore()));

  final LlmProvider provider;

  @override
  Future<LlmProvider> requireProvider([String? id]) async => provider;

  @override
  LlmEffort get userEffort => LlmEffort.medium;
}

class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.replies);

  final List<LlmResponse> replies;
  final requests = <LlmRequest>[];
  var _i = 0;

  @override
  String get id => 'scripted';

  @override
  String get displayName => 'Scripted';

  @override
  LlmCapabilities get capabilities => const LlmCapabilities();

  @override
  Future<LlmResponse> complete(LlmRequest request,
      {CancelToken? cancel}) async {
    requests.add(request);
    final reply = replies[_i < replies.length ? _i : replies.length - 1];
    _i++;
    return reply;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
