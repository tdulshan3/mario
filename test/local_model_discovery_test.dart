/// Finding a model server that is already running.
///
/// The parsing is where this can go quietly wrong: a machine with Ollama
/// installed but no models pulled must not be offered as a working backend, and
/// something else listening on 11434 must not be mistaken for Ollama. Both look
/// like success from the outside — a 200 response — and both would leave the
/// user one tap from a backend that cannot answer.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mario/core/services/ai/llm_provider_config.dart';
import 'package:mario/core/services/ai/local_model_discovery.dart';

/// Answers a fixed body for paths that match, and 404s everything else — the
/// shape of a machine running exactly one server.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.routes);
  final Map<String, String> routes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = '${request.url.origin}${request.url.path}';
    final body = routes[key];
    if (body == null) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
    );
  }
}

void main() {
  group('parseOllamaTags', () {
    const body = '''
{"models":[
  {"name":"qwen3.5:0.8b","size":1073741824,
   "details":{"parameter_size":"0.8B"}},
  {"name":"qwen3.5:4b","size":3650722201,
   "details":{"parameter_size":"4.0B"}},
  {"name":"gemma3:1b","size":815319791,"details":{"parameter_size":"1.0B"}}
]}''';

    test('reads every model with its size and parameter count', () {
      final models = parseOllamaTags(body);
      expect(models, hasLength(3));
      expect(models.map((m) => m.name),
          containsAll(['qwen3.5:0.8b', 'qwen3.5:4b', 'gemma3:1b']));
    });

    test('orders largest first — the most capable one installed', () {
      expect(parseOllamaTags(body).first.name, 'qwen3.5:4b');
    });

    test('formats a size a person can judge a model by', () {
      final m = parseOllamaTags(body).first;
      expect(m.sizeLabel, '3.4 GB');
      expect(m.parameters, '4.0B');
    });

    test('falls back to MB for a small model', () {
      final gemma =
          parseOllamaTags(body).firstWhere((m) => m.name == 'gemma3:1b');
      expect(gemma.sizeLabel, endsWith('MB'));
    });

    test('an installed-but-empty Ollama yields nothing', () {
      // Offering this as a backend gives a one-tap setup that cannot answer.
      expect(parseOllamaTags('{"models":[]}'), isEmpty);
    });

    test('survives a reply of the wrong shape', () {
      expect(parseOllamaTags('{"models":"nope"}'), isEmpty);
      expect(parseOllamaTags('not json at all'), isEmpty);
      expect(parseOllamaTags(''), isEmpty);
    });

    test('skips entries with no usable name', () {
      const odd = '{"models":[{"size":1},{"name":"   "},{"name":"real:1b"}]}';
      expect(parseOllamaTags(odd).map((m) => m.name), ['real:1b']);
    });

    test('accepts a model with no size rather than dropping it', () {
      final models = parseOllamaTags('{"models":[{"name":"mystery:1b"}]}');
      expect(models, hasLength(1));
      expect(models.single.sizeLabel, '');
    });
  });

  group('parseOpenAiModels', () {
    test('reads a /v1/models list', () {
      const body = '{"data":[{"id":"llama-3"},{"id":"another"}]}';
      expect(parseOpenAiModels(body).map((m) => m.name),
          ['another', 'llama-3']); // sorted
    });

    test('an empty list yields nothing', () {
      expect(parseOpenAiModels('{"data":[]}'), isEmpty);
    });

    test('survives junk', () {
      expect(parseOpenAiModels('<html>login page</html>'), isEmpty);
      expect(parseOpenAiModels('{"data":{"id":"x"}}'), isEmpty);
    });
  });

  group('probing', () {
    test('finds Ollama through its own /api/tags', () async {
      final discovery = LocalModelDiscovery(
        clientFactory: () => _FakeClient({
          'http://127.0.0.1:11434/api/tags':
              '{"models":[{"name":"qwen3.5:4b","size":3650722201}]}',
        }),
      );
      final found = await discovery.scan();
      expect(found, hasLength(1));
      expect(found.single.serverName, 'Ollama');
      expect(found.single.kind, LlmProviderKind.ollama);
      expect(found.single.models.single.name, 'qwen3.5:4b');
    });

    test('normalises the base URL to /v1, ready to save', () async {
      final discovery = LocalModelDiscovery(
        clientFactory: () => _FakeClient({
          'http://127.0.0.1:11434/api/tags': '{"models":[{"name":"m"}]}',
        }),
      );
      final found = await discovery.scan();
      expect(found.single.baseUrl, 'http://127.0.0.1:11434/v1');
    });

    test('finds an OpenAI-compatible server on its own port', () async {
      final discovery = LocalModelDiscovery(
        clientFactory: () => _FakeClient({
          'http://127.0.0.1:1234/v1/models': '{"data":[{"id":"local-model"}]}',
        }),
      );
      final found = await discovery.scan();
      expect(found.single.serverName, 'LM Studio');
      expect(found.single.kind, LlmProviderKind.openAiCompatible);
    });

    test('a machine with nothing running finds nothing, and does not throw',
        () async {
      final discovery =
          LocalModelDiscovery(clientFactory: () => _FakeClient(const {}));
      expect(await discovery.scan(), isEmpty);
    });

    test('a server answering with no models is not offered', () async {
      // Ollama installed but nothing pulled: a backend that cannot answer.
      final discovery = LocalModelDiscovery(
        clientFactory: () => _FakeClient({
          'http://127.0.0.1:11434/api/tags': '{"models":[]}',
        }),
      );
      expect(await discovery.scan(), isEmpty);
    });

    test('something else on 11434 is not mistaken for Ollama', () async {
      // A dev server on the port answers 200 with HTML.
      final discovery = LocalModelDiscovery(
        clientFactory: () => _FakeClient({
          'http://127.0.0.1:11434/api/tags': '<html>hello</html>',
          'http://127.0.0.1:11434/v1/models': '<html>hello</html>',
        }),
      );
      expect(await discovery.scan(), isEmpty);
    });

    test('finds several servers at once', () async {
      final discovery = LocalModelDiscovery(
        clientFactory: () => _FakeClient({
          'http://127.0.0.1:11434/api/tags': '{"models":[{"name":"a"}]}',
          'http://127.0.0.1:8080/v1/models': '{"data":[{"id":"b"}]}',
        }),
      );
      final found = await discovery.scan();
      expect(found.map((e) => e.serverName), containsAll(['Ollama', 'llama.cpp']));
    });

    test('only ever probes loopback — never the LAN', () {
      // Sweeping the subnet for port 11434 would be a port scan.
      for (final c in LocalModelDiscovery.candidates) {
        expect(Uri.parse(c.url).host, anyOf('127.0.0.1', 'localhost'),
            reason: '${c.name} must not be probed off-machine');
      }
    });
  });

  group('turning a find into a config', () {
    test('produces a saveable, correctly-kinded config', () {
      const endpoint = DiscoveredEndpoint(
        kind: LlmProviderKind.ollama,
        baseUrl: 'http://127.0.0.1:11434/v1',
        serverName: 'Ollama',
        models: [DiscoveredModel(name: 'qwen3.5:4b')],
      );
      final config = endpoint.toConfig('qwen3.5:4b', id: 'x');
      expect(config.kind, LlmProviderKind.ollama);
      expect(config.baseUrl, 'http://127.0.0.1:11434/v1');
      expect(config.model, 'qwen3.5:4b');
      expect(config.label, contains('qwen3.5:4b'));
      expect(config.hasApiKey, isFalse, reason: 'a local server needs no key');
    });
  });
}
