/// Separating a hybrid model's reasoning from its answer.
///
/// Qwen3.5 and friends emit `<think>…</think>` inline when the server does not
/// lift it into a `reasoning_content` field, and the tags arrive split across
/// SSE chunk boundaries. Two failures live here, and both showed up in real use:
///
///  * the splitter holds back any tail that could still become `<think>`, and
///    if that tail is never flushed at end of stream those bytes are silently
///    dropped — which, when the answer is JSON, turns a valid object into an
///    unparseable fragment;
///  * a model that hits its token ceiling mid-thought never closes the tag, so
///    everything lands in the reasoning channel and the answer is empty. That
///    is the state that produced "the model could not produce the required
///    JSON", and it needs to be *detectable* rather than indistinguishable
///    from a model that simply rambled.
///
/// The splitter is private to the provider, so this drives it through the
/// public streaming API with a fake HTTP client.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/core/services/ai/openai_compatible_provider.dart';

/// Serves a fixed list of content chunks as an SSE stream.
class _FakeSseClient extends http.BaseClient {
  _FakeSseClient(this.chunks);
  final List<String> chunks;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final frames = [
      for (final c in chunks)
        'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': c}
                }
              ]
            })}\n\n',
      'data: [DONE]\n\n',
    ];
    return http.StreamedResponse(
      Stream.fromIterable(frames.map(utf8.encode)),
      200,
    );
  }
}

void main() {
  Future<LlmResponse> run(List<String> chunks) {
    final provider = OpenAiCompatibleProvider(
      id: 'test',
      displayName: 'Fake',
      baseUrl: 'http://localhost:1234/v1',
      model: 'qwen3.5:4b',
      clientFactory: () => _FakeSseClient(chunks),
    );
    return provider.complete(
      const LlmRequest(messages: [LlmMessage(role: LlmRole.user, content: 'hi')]),
    );
  }

  test('plain text passes through untouched', () async {
    final r = await run(['Hello ', 'world']);
    expect(r.text, 'Hello world');
    expect(r.reasoning, isEmpty);
  });

  test('splits a complete think block out of the answer', () async {
    final r = await run(['<think>hmm</think>', 'The answer is 4.']);
    expect(r.text, 'The answer is 4.');
    expect(r.reasoning, 'hmm');
  });

  test('splits a tag arriving across chunk boundaries', () async {
    // The realistic case: SSE frames do not align with tags.
    final r = await run(['<th', 'ink>rea', 'soning</th', 'ink>answer']);
    expect(r.text, 'answer');
    expect(r.reasoning, 'reasoning');
  });

  test('flushes a tail that could have been the start of a tag', () async {
    // A trailing "<" is withheld because it could still become "<think>".
    // At end of stream it cannot be, and dropping it truncates the answer.
    final r = await run(['solve for x ', '<']);
    expect(r.text, 'solve for x <');
  });

  test('flushes a multi-character partial tag', () async {
    final r = await run(['compare ', '<th']);
    expect(r.text, 'compare <th');
  });

  test('does not lose the end of JSON that stops mid-tag-prefix', () async {
    // The shape that mattered: withheld bytes make the reply unparseable and
    // the failure surfaces as "the model did not return usable JSON".
    final r = await run(['{"summary": "x ', '<']);
    expect(r.text, '{"summary": "x <');
  });

  test('an unclosed think block puts everything in reasoning', () async {
    // A model cut off mid-thought by the token ceiling. The answer channel is
    // empty, which is exactly why the caller now looks in `reasoning` for the
    // JSON before giving up.
    final r = await run(['<think>I should first consider', ' the whole page']);
    expect(r.text, isEmpty);
    expect(r.reasoning, 'I should first consider the whole page');
  });

  test('a lone angle bracket does not start a think block', () async {
    final r = await run(['5 < 7 and 9 > 2']);
    expect(r.text, '5 < 7 and 9 > 2');
    expect(r.reasoning, isEmpty);
  });

  test('handles several think blocks in one reply', () async {
    final r = await run(['<think>a</think>one <think>b</think>two']);
    expect(r.text, 'one two');
    expect(r.reasoning, 'ab');
  });

  test('an empty stream yields an empty response rather than throwing',
      () async {
    final r = await run([]);
    expect(r.text, isEmpty);
  });
}
