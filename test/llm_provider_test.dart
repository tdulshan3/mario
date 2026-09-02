/// Talking to whatever the user actually runs.
///
/// The base-URL cases come from what people really paste into a settings box:
/// a bare host:port, a URL with or without `/v1`, a trailing slash, and a whole
/// endpoint copied out of a curl example. Getting any of them wrong produces a
/// 404 that looks like "the server is down" rather than "the URL has /v1
/// twice", which is a genuinely hard thing to debug from the outside.
///
/// The rest covers the capability record that decides how structured output is
/// requested — the single most divergent feature across servers that all claim
/// to be OpenAI-compatible.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider_config.dart';
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/core/services/ai/openai_compatible_provider.dart';

void main() {
  group('normalizeBaseUrl', () {
    String n(String s) => OpenAiCompatibleProvider.normalizeBaseUrl(s);

    test('adds a scheme to a bare host:port', () {
      expect(n('192.168.1.50:8080'), 'http://192.168.1.50:8080/v1');
    });

    test('leaves a correct URL alone', () {
      expect(n('http://192.168.1.50:8080/v1'), 'http://192.168.1.50:8080/v1');
    });

    test('appends /v1 when missing', () {
      expect(n('http://localhost:11434'), 'http://localhost:11434/v1');
    });

    test('strips a trailing slash rather than doubling it', () {
      expect(n('http://localhost:11434/v1/'), 'http://localhost:11434/v1');
      expect(n('http://localhost:11434/'), 'http://localhost:11434/v1');
    });

    test('strips an endpoint path pasted from a curl example', () {
      // Otherwise the request goes to /v1/chat/completions/chat/completions.
      expect(
        n('http://192.168.1.50:8080/v1/chat/completions'),
        'http://192.168.1.50:8080/v1',
      );
      expect(
          n('https://api.openai.com/v1/models'), 'https://api.openai.com/v1');
    });

    test('preserves https', () {
      expect(n('https://api.openai.com/v1'), 'https://api.openai.com/v1');
    });

    test('accepts a non-v1 API version rather than appending /v1 to it', () {
      expect(n('http://host:8000/v2'), 'http://host:8000/v2');
    });

    test('preserves the official Gemini OpenAI-compatible root', () {
      expect(
        n('https://generativelanguage.googleapis.com/v1beta/openai/'),
        'https://generativelanguage.googleapis.com/v1beta/openai',
      );
    });

    test('leaves an empty string empty, so a blank field is not a bad URL', () {
      expect(n(''), '');
      expect(n('   '), '');
    });
  });

  group('provider kind defaults', () {
    test('an unknown OpenAI-compatible server is assumed least capable', () {
      // Assuming strict schemas here would 400 on the user's first quiz. The
      // capability is promoted only once an endpoint proves it.
      final caps = LlmProviderKind.openAiCompatible.assumedCapabilities;
      expect(caps.strictJsonSchema, isFalse);
      expect(caps.jsonMode, isTrue);
    });

    test('the hosted APIs are assumed to support strict schemas', () {
      expect(
          LlmProviderKind.openAi.assumedCapabilities.strictJsonSchema, isTrue);
      expect(LlmProviderKind.anthropic.assumedCapabilities.strictJsonSchema,
          isTrue);
      expect(LlmProviderKind.gemini.assumedCapabilities.tools, isTrue);
    });

    test('only the hosted APIs require a key', () {
      expect(LlmProviderKind.openAi.requiresApiKey, isTrue);
      expect(LlmProviderKind.anthropic.requiresApiKey, isTrue);
      expect(LlmProviderKind.gemini.requiresApiKey, isTrue);
      expect(LlmProviderKind.ollama.requiresApiKey, isFalse);
      expect(LlmProviderKind.openAiCompatible.requiresApiKey, isFalse);
    });

    test('Ollama defaults to its own port', () {
      expect(LlmProviderKind.ollama.defaultBaseUrl, contains('11434'));
    });
  });

  group('LlmProviderConfig', () {
    const config = LlmProviderConfig(
      id: 'lan',
      label: 'LAN box',
      kind: LlmProviderKind.openAiCompatible,
      baseUrl: 'http://192.168.1.50:8080/v1',
      model: 'qwen3:4b',
    );

    test('round-trips through JSON', () {
      final restored = LlmProviderConfig.fromJson(config.toJson());
      expect(restored.id, config.id);
      expect(restored.label, config.label);
      expect(restored.kind, config.kind);
      expect(restored.baseUrl, config.baseUrl);
      expect(restored.model, config.model);
    });

    test('never serialises a secret', () {
      final json = config.copyWith(hasApiKey: true).toJson().toString();
      expect(json.contains('sk-'), isFalse);
      expect(json, contains('hasApiKey'));
    });

    test('a learned capability overrides the kind assumption', () {
      final learned = config.copyWith(
        capabilities: const LlmCapabilities(strictJsonSchema: true),
      );
      expect(learned.effectiveCapabilities.strictJsonSchema, isTrue);
    });

    test('a user-set context window overrides both', () {
      final sized = config.copyWith(contextTokens: 32768);
      expect(sized.effectiveCapabilities.contextTokens, 32768);
    });

    test('a context override survives saved JSON', () {
      final sized = config.copyWith(contextTokens: 131072);
      final restored = LlmProviderConfig.fromJson(sized.toJson());
      expect(restored.contextTokens, 131072);
      expect(restored.effectiveCapabilities.contextTokens, 131072);
    });

    test('a context override reaches the Claude provider too', () {
      const claude = LlmProviderConfig(
        id: 'claude',
        label: 'Claude',
        kind: LlmProviderKind.anthropic,
        baseUrl: 'https://api.anthropic.com/v1',
        model: 'claude-opus-5',
        contextTokens: 32768,
      );
      expect(claude.build(apiKey: 'key').capabilities.contextTokens, 32768);
    });

    test('builds the right provider class for its kind', () {
      expect(config.build(apiKey: null), isA<OpenAiCompatibleProvider>());
    });

    test('Gemini uses its default model and compatible transport', () {
      const gemini = LlmProviderConfig(
        id: 'gemini',
        label: 'Gemini',
        kind: LlmProviderKind.gemini,
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
        model: '',
      );
      final provider = gemini.build(apiKey: 'key');
      expect(provider, isA<OpenAiCompatibleProvider>());
      expect((provider as OpenAiCompatibleProvider).model, kDefaultGeminiModel);
    });

    test('Gemini strips the resource prefix returned by model discovery', () {
      const gemini = LlmProviderConfig(
        id: 'gemini',
        label: 'Gemini',
        kind: LlmProviderKind.gemini,
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
        model: 'models/gemini-2.5-flash',
      );
      final provider = gemini.build(apiKey: 'key');
      expect(
        (provider as OpenAiCompatibleProvider).model,
        'gemini-2.5-flash',
      );
    });

    test('an unknown kind in stored JSON falls back rather than throwing', () {
      // Forward compatibility: a config written by a newer build must not stop
      // the whole list from loading.
      final restored = LlmProviderConfig.fromJson({
        'id': 'x',
        'kind': 'some-future-backend',
        'baseUrl': 'http://host/v1',
        'model': 'm',
      });
      expect(restored.kind, LlmProviderKind.openAiCompatible);
    });
  });

  group('CancelToken', () {
    test('reports cancellation and throws at a checkpoint', () {
      final token = CancelToken();
      expect(token.isCancelled, isFalse);
      token.throwIfCancelled(); // no throw
      token.cancel();
      expect(token.isCancelled, isTrue);
      expect(token.throwIfCancelled, throwsA(isA<LlmCancelled>()));
    });

    test('cancelling twice is harmless', () {
      final token = CancelToken()..cancel();
      expect(token.cancel, returnsNormally);
    });

    test('whenCancelled completes, so a stream can close its socket', () async {
      final token = CancelToken();
      var closed = false;
      unawaited(token.whenCancelled.then((_) => closed = true));
      token.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(closed, isTrue);
    });
  });

  group('LlmResponse', () {
    test('recognises a token-limit stop, the usual cause of broken JSON', () {
      expect(const LlmResponse(text: '', finishReason: 'length').hitTokenLimit,
          isTrue);
      expect(
          const LlmResponse(text: '', finishReason: 'max_tokens').hitTokenLimit,
          isTrue);
      expect(const LlmResponse(text: '', finishReason: 'stop').hitTokenLimit,
          isFalse);
    });
  });

  group('context window input', () {
    test('empty selects the detected or provider default', () {
      expect(parseContextWindowOverride(''), isNull);
      expect(parseContextWindowOverride('   '), isNull);
    });

    test('accepts exact tokens and model-style shorthand', () {
      expect(parseContextWindowOverride('32768'), 32768);
      expect(parseContextWindowOverride('32k'), 32768);
      expect(parseContextWindowOverride('1M'), 1048576);
      expect(parseContextWindowOverride('1.5m'), 1572864);
    });

    test('rejects malformed or dangerous allocations', () {
      expect(() => parseContextWindowOverride('lots'), throwsFormatException);
      expect(() => parseContextWindowOverride('512'), throwsFormatException);
      expect(() => parseContextWindowOverride('8m'), throwsFormatException);
      expect(
        () => parseContextWindowOverride('999999999999999999999999999999'),
        throwsFormatException,
      );
    });

    test('formats common presets for the settings chips', () {
      expect(formatContextWindow(32768), '32k');
      expect(formatContextWindow(1048576), '1m');
    });
  });
}

void unawaited(Future<void> f) {}
