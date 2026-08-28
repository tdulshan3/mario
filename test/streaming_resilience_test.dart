/// What happens when a model server goes quiet, or refuses a hint.
///
/// Both reported as the same thing by the person using it: "stuck on
/// thinking". A reasoning model legitimately streams nothing visible for a
/// long time, so the panel cannot tell deliberation from a dead connection —
/// and before this there was nothing to tell them apart with, because the only
/// timeout covered the wait for response headers. Once a stream opened, it
/// could hang until the user pressed Stop.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/core/services/ai/openai_compatible_provider.dart';

void main() {
  /// An SSE frame carrying visible text.
  String chunk(String text) => 'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': text}
              }
            ]
          })}\n\n';

  OpenAiCompatibleProvider provider(
    _FakeClient client, {
    Duration idle = const Duration(milliseconds: 200),
  }) =>
      OpenAiCompatibleProvider(
        id: 'x',
        displayName: 'Ollama',
        baseUrl: 'http://127.0.0.1:11434/v1',
        model: 'qwen3.6',
        idleTimeout: idle,
        clientFactory: () => client,
      );

  group('a stream that goes quiet is not waited on forever', () {
    test('a stall after the first token is reported, not hung on', () async {
      // The bug: `timeout` covered only the wait for headers, so a server that
      // accepted the request and then stopped sending left the panel spinning
      // with nothing to end it.
      final client = _FakeClient.stalling([chunk('Glycolysis ')]);
      final p = provider(client);

      final text = StringBuffer();
      await expectLater(
        p.stream(const LlmRequest(messages: [])).map((d) {
          text.write(d.text);
          return d;
        }).drain<void>(),
        throwsA(isA<LlmException>()),
      );
      expect(text.toString(), 'Glycolysis ',
          reason: 'what did arrive is not lost');
    });

    test('the message says it went quiet mid-reply, and offers a way out',
        () async {
      final p = provider(_FakeClient.stalling([chunk('x')]));
      try {
        await p.stream(const LlmRequest(messages: [])).drain<void>();
        fail('expected a timeout');
      } on LlmException catch (e) {
        expect(e.message, contains('quiet'));
        expect(e.message, contains('Fast'),
            reason: 'the user needs to know what to change');
        expect(e.isNetwork, isTrue);
      }
    });

    test('the clock restarts on every line, so a slow reply survives',
        () async {
      // The distinction that matters: silence is a stall, slowness is not. A
      // total-duration cap would kill exactly the long reasoning replies the
      // thinking control exists to allow.
      final client = _FakeClient.paced(
        [chunk('a'), chunk('b'), chunk('c'), 'data: [DONE]\n\n'],
        gap: const Duration(milliseconds: 60),
      );
      final p = provider(client, idle: const Duration(milliseconds: 200));

      final text = StringBuffer();
      await for (final d in p.stream(const LlmRequest(messages: []))) {
        text.write(d.text);
      }
      expect(text.toString(), 'abc',
          reason: 'total time exceeds the idle limit; no single gap does');
    });

    test('reasoning-only output counts as progress', () async {
      // A thinking model sends nothing visible for a long time. If only
      // `content` reset the clock, deliberation would be killed as a stall.
      final thinking = 'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'reasoning_content': 'weighing it up… '}
              }
            ]
          })}\n\n';
      final client = _FakeClient.paced(
        [thinking, thinking, chunk('Net two ATP.'), 'data: [DONE]\n\n'],
        gap: const Duration(milliseconds: 60),
      );
      final p = provider(client, idle: const Duration(milliseconds: 200));

      final answer = StringBuffer();
      await for (final d in p.stream(const LlmRequest(messages: []))) {
        answer.write(d.text);
      }
      expect(answer.toString(), 'Net two ATP.');
    });
  });

  group('a server that will not take the reasoning hints', () {
    test('the request is retried without them rather than failing', () async {
      // reasoning_effort, chat_template_kwargs and think are non-standard
      // passthroughs. A server that validates its body 400s instead of
      // ignoring them, and losing the depth setting beats losing the answer.
      final client = _FakeClient.rejectingThenAccepting(
        rejectBody: '{"error":"unknown field: chat_template_kwargs"}',
        then: [chunk('It worked.'), 'data: [DONE]\n\n'],
      );
      final p = provider(client, idle: const Duration(seconds: 5));

      final answer = StringBuffer();
      await for (final d
          in p.stream(const LlmRequest(messages: [], effort: LlmEffort.high))) {
        answer.write(d.text);
      }
      expect(answer.toString(), 'It worked.');
      expect(client.bodies, hasLength(2));
      expect(client.bodies.first, contains('chat_template_kwargs'));
      expect(client.bodies.last, isNot(contains('chat_template_kwargs')),
          reason: 'the retry must actually drop them');
      expect(client.bodies.last, isNot(contains('reasoning_effort')));
    });

    test('a 400 about something else is still an error', () async {
      // Only a complaint about the hints earns a retry; retrying everything
      // would double every genuine failure.
      final client = _FakeClient.rejectingThenAccepting(
        rejectBody: '{"error":"context length exceeded"}',
        then: [chunk('never reached')],
      );
      final p = provider(client, idle: const Duration(seconds: 5));

      await expectLater(
        p.stream(const LlmRequest(messages: [])).drain<void>(),
        throwsA(isA<LlmException>()),
      );
      expect(client.bodies, hasLength(1), reason: 'no retry');
    });
  });

  group('each server names its thinking channel differently', () {
    // The bug that made Ollama return nothing at all while the same model on
    // llama.cpp worked. Verified against Ollama 0.32.15 with qwen3.6: its
    // OpenAI-compatible endpoint puts the ENTIRE reply in `reasoning` and
    // sends `content: ""` on every chunk, so reading only `reasoning_content`
    // and `thinking` meant every token was read as nothing.

    Future<(String, String)> collect(String field) async {
      final frame = 'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '', field: 'deliberating'}
              }
            ]
          })}\n\n';
      final client = _FakeClient.paced(
        [frame, chunk('The answer.'), 'data: [DONE]\n\n'],
        gap: Duration.zero,
      );
      final p = OpenAiCompatibleProvider(
        id: 'x',
        displayName: 'srv',
        baseUrl: 'http://127.0.0.1:11434/v1',
        model: 'm',
        clientFactory: () => client,
      );
      final text = StringBuffer();
      final reasoning = StringBuffer();
      await for (final d in p.stream(const LlmRequest(messages: []))) {
        text.write(d.text);
        reasoning.write(d.reasoning);
      }
      return (text.toString(), reasoning.toString());
    }

    test('Ollama says `reasoning`', () async {
      final (text, reasoning) = await collect('reasoning');
      expect(reasoning, 'deliberating',
          reason: 'missing this is what returned an empty answer');
      expect(text, 'The answer.');
    });

    test('vLLM and DeepSeek say `reasoning_content`', () async {
      final (text, reasoning) = await collect('reasoning_content');
      expect(reasoning, 'deliberating');
      expect(text, 'The answer.');
    });

    test("Ollama's native API says `thinking`", () async {
      final (text, reasoning) = await collect('thinking');
      expect(reasoning, 'deliberating');
      expect(text, 'The answer.');
    });

    test('thinking never leaks into the answer', () async {
      // The reason these are separate channels at all: reasoning saved into
      // someone's notes as the answer would be worse than no answer.
      for (final field in ['reasoning', 'reasoning_content', 'thinking']) {
        final (text, _) = await collect(field);
        expect(text, isNot(contains('deliberating')), reason: field);
      }
    });
  });

  group('turning thinking off', () {
    Future<String> bodyFor(LlmRequest request) async {
      final client = _FakeClient.paced(
        [chunk('hi'), 'data: [DONE]\n\n'],
        gap: Duration.zero,
      );
      final p = OpenAiCompatibleProvider(
        id: 'x',
        displayName: 'srv',
        baseUrl: 'http://127.0.0.1:11434/v1',
        model: 'm',
        clientFactory: () => client,
      );
      await p.stream(request).drain<void>();
      return client.bodies.single;
    }

    test('Fast sends the flag that actually works', () async {
      // Measured against the real thing: Ollama accepts `enable_thinking:
      // false` and `think: false` and ignores both — the model thinks anyway,
      // fills its budget and returns no content. `reasoning_effort: "none"` is
      // the one it honours.
      final body =
          await bodyFor(const LlmRequest(messages: [], effort: LlmEffort.low));
      expect(body, contains('"reasoning_effort":"none"'));
      expect(body, contains('"enable_thinking":false'),
          reason: 'llama.cpp and vLLM read this one instead');
      expect(body, contains('"think":false'));
    });

    test('a structured call always turns it off, whatever the depth', () async {
      // Deliberation and schema-shaped output do not mix at this size: the
      // model spends the whole budget thinking and emits no JSON at all.
      final body = await bodyFor(const LlmRequest(
        messages: [],
        effort: LlmEffort.high,
        jsonFormat: LlmJsonFormat(name: 'x', schema: {'type': 'object'}),
      ));
      expect(body, contains('"reasoning_effort":"none"'));
    });

    test('Thorough asks for thinking rather than turning it off', () async {
      final body =
          await bodyFor(const LlmRequest(messages: [], effort: LlmEffort.high));
      expect(body, contains('"reasoning_effort":"high"'));
      expect(body, contains('"enable_thinking":true'));
    });
  });
}

/// An http client that plays a scripted SSE response.
class _FakeClient extends http.BaseClient {
  _FakeClient._({
    required this.frames,
    this.gap = Duration.zero,
    this.stallAtEnd = false,
    this.rejectFirstWith,
  });

  /// Sends [frames], then stops sending without closing — the stall.
  factory _FakeClient.stalling(List<String> frames) =>
      _FakeClient._(frames: frames, stallAtEnd: true);

  /// Sends [frames] with [gap] between each.
  factory _FakeClient.paced(List<String> frames, {required Duration gap}) =>
      _FakeClient._(frames: frames, gap: gap);

  /// 400s the first request, plays [then] for the second.
  factory _FakeClient.rejectingThenAccepting({
    required String rejectBody,
    required List<String> then,
  }) =>
      _FakeClient._(frames: then, rejectFirstWith: rejectBody);

  final List<String> frames;
  final Duration gap;
  final bool stallAtEnd;
  final String? rejectFirstWith;

  /// Every request body sent, so a test can prove what the retry dropped.
  final bodies = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    bodies.add((request as http.Request).body);

    if (rejectFirstWith != null && bodies.length == 1) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(rejectFirstWith!)),
        400,
      );
    }

    final controller = StreamController<List<int>>();
    unawaited(() async {
      for (final f in frames) {
        if (gap > Duration.zero) await Future<void>.delayed(gap);
        if (controller.isClosed) return;
        controller.add(utf8.encode(f));
      }
      // A stall leaves the stream open with nothing more coming, which is
      // exactly what a wedged server looks like from here.
      if (!stallAtEnd && !controller.isClosed) await controller.close();
    }());
    return http.StreamedResponse(controller.stream, 200);
  }
}
