/// Finding a model server that is already running on this machine.
///
/// Setting up a backend by hand means knowing that Ollama listens on 11434,
/// that the OpenAI-compatible path is `/v1`, and what your model is called
/// exactly. Anyone running Ollama already has all of that; they should not have
/// to type it.
///
/// **Loopback only, deliberately.** Every candidate below is `127.0.0.1`. It
/// would be easy to sweep the local subnet for port 11434 and find the user's
/// LAN box too — and that is a port scan. It is slow, it looks exactly like
/// hostile traffic to anything watching the network, and on a shared or
/// corporate network it is not the app's business. A machine on the LAN gets
/// typed in once, by someone who knows it is theirs.
///
/// Ollama is identified through its own `/api/tags` rather than the
/// OpenAI-compatible `/v1/models`, because that endpoint proves it *is* Ollama
/// — something else could be on 11434 — and returns each model's size, which
/// is what tells a 0.8B apart from a 9B when both are installed.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'json_coercion.dart';
import 'llm_provider_config.dart';

/// A model server found listening locally.
class DiscoveredEndpoint {
  const DiscoveredEndpoint({
    required this.kind,
    required this.baseUrl,
    required this.serverName,
    required this.models,
    this.latency,
  });

  final LlmProviderKind kind;

  /// Normalised, ready to store on a config.
  final String baseUrl;

  /// What is running there — "Ollama", "LM Studio", "llama.cpp".
  final String serverName;

  /// Model ids, largest-looking first where the server reports sizes.
  final List<DiscoveredModel> models;

  final Duration? latency;

  bool get isEmpty => models.isEmpty;

  /// A config ready to save, for the model the user picked.
  LlmProviderConfig toConfig(String model, {required String id}) {
    final found = models.where((m) => m.name == model).firstOrNull;
    return LlmProviderConfig(
      id: id,
      label: '$serverName · $model',
      kind: kind,
      baseUrl: baseUrl,
      model: model,
      // Carried over where the server told us, so a 262k model is not treated
      // as an 8k one from the moment it is added.
      contextTokens: found?.contextLength,
    );
  }
}

class DiscoveredModel {
  const DiscoveredModel({
    required this.name,
    this.sizeBytes,
    this.parameters,
    this.contextLength,
  });

  final String name;
  final int? sizeBytes;

  /// The model's real context window, where the server reports one. Far better
  /// than the per-kind guess: Ollama's default assumption is 8k, and a model
  /// like qwen3.5 actually carries 262k — a thirty-fold difference in how much
  /// of a section fits in one request.
  final int? contextLength;

  /// Reported parameter count, e.g. "4.0B". Ollama supplies it; most others
  /// do not.
  final String? parameters;

  /// Human-readable size, for a picker where "qwen3.5:0.8b" and
  /// "qwen3.5:9b" otherwise look equally cheap to run.
  String get sizeLabel {
    final b = sizeBytes;
    if (b == null || b <= 0) return '';
    final gb = b / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    return '${(b / (1024 * 1024)).round()} MB';
  }
}

class LocalModelDiscovery {
  LocalModelDiscovery({http.Client Function()? clientFactory})
      : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  /// Short on purpose: this runs while a settings page is opening, and a
  /// server that is not there refuses the connection almost instantly. The
  /// timeout only matters for a port that accepts but never answers.
  static const probeTimeout = Duration(milliseconds: 1500);

  /// Where locally-run model servers actually listen.
  static const candidates = <LocalServerCandidate>[
    LocalServerCandidate(
        'Ollama', 'http://127.0.0.1:11434', LlmProviderKind.ollama),
    LocalServerCandidate(
        'LM Studio', 'http://127.0.0.1:1234', LlmProviderKind.openAiCompatible),
    LocalServerCandidate(
        'llama.cpp', 'http://127.0.0.1:8080', LlmProviderKind.openAiCompatible),
    LocalServerCandidate(
        'llama.cpp', 'http://127.0.0.1:8081', LlmProviderKind.openAiCompatible),
    LocalServerCandidate(
        'vLLM', 'http://127.0.0.1:8000', LlmProviderKind.openAiCompatible),
    LocalServerCandidate(
        'Jan', 'http://127.0.0.1:1337', LlmProviderKind.openAiCompatible),
  ];

  /// Probes every candidate at once and returns those that answered with at
  /// least one model.
  ///
  /// Never throws: a machine with nothing running returns an empty list, which
  /// is the normal case and not an error.
  Future<List<DiscoveredEndpoint>> scan() async {
    final results = await Future.wait(candidates.map(probe));
    return [
      for (final r in results)
        if (r != null && !r.isEmpty) r,
    ];
  }

  /// Probes one candidate. Null when nothing usable is there.
  Future<DiscoveredEndpoint?> probe(LocalServerCandidate candidate) async {
    final started = DateTime.now();
    final client = _clientFactory();
    try {
      // Ollama first: /api/tags proves it is Ollama and reports sizes.
      if (candidate.kind == LlmProviderKind.ollama) {
        final res = await client
            .get(Uri.parse('${candidate.url}/api/tags'))
            .timeout(probeTimeout);
        if (res.statusCode == 200) {
          final models = parseOllamaTags(utf8.decode(res.bodyBytes));
          if (models.isNotEmpty) {
            return DiscoveredEndpoint(
              kind: LlmProviderKind.ollama,
              baseUrl: '${candidate.url}/v1',
              serverName: candidate.name,
              models: models,
              latency: DateTime.now().difference(started),
            );
          }
        }
      }

      final res = await client
          .get(Uri.parse('${candidate.url}/v1/models'))
          .timeout(probeTimeout);
      if (res.statusCode != 200) return null;
      final models = parseOpenAiModels(utf8.decode(res.bodyBytes));
      if (models.isEmpty) return null;
      return DiscoveredEndpoint(
        kind: candidate.kind,
        baseUrl: '${candidate.url}/v1',
        serverName: candidate.name,
        models: models,
        latency: DateTime.now().difference(started),
      );
    } catch (_) {
      // Connection refused is the expected answer for a port nobody is
      // listening on, which is most of them.
      return null;
    } finally {
      client.close();
    }
  }
}

/// One place a locally-run model server might be listening.
class LocalServerCandidate {
  const LocalServerCandidate(this.name, this.url, this.kind);

  /// What runs there, for the UI: "Ollama", "LM Studio".
  final String name;

  /// Origin only — no path. Loopback by construction; see the library doc.
  final String url;

  final LlmProviderKind kind;
}

/// Reads Ollama's `/api/tags`, largest model first.
///
/// Largest first because that is usually the most capable one installed, and
/// because the sizes are the whole reason for preferring this endpoint: with
/// several models pulled, "which of these can actually write a quiz" is
/// answered far better by 5.2 GB than by the name.
List<DiscoveredModel> parseOllamaTags(String body) {
  final json = asMap(_decode(body));
  if (json == null) return const [];
  final out = <DiscoveredModel>[];
  for (final m in asMapList(json['models'])) {
    final name = asString(m['name']) ?? asString(m['model']);
    if (name == null || name.trim().isEmpty) continue;
    final details = asMap(m['details']);
    out.add(DiscoveredModel(
      name: name.trim(),
      sizeBytes: asInt(m['size']),
      parameters: asString(details?['parameter_size']),
      contextLength: asInt(details?['context_length']),
    ));
  }
  out.sort((a, b) => (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0));
  return out;
}

/// Reads an OpenAI-compatible `/v1/models` list.
List<DiscoveredModel> parseOpenAiModels(String body) {
  final json = asMap(_decode(body));
  if (json == null) return const [];
  final out = <DiscoveredModel>[];
  for (final m in asMapList(json['data'])) {
    final id = asString(m['id']);
    if (id == null || id.trim().isEmpty) continue;
    out.add(DiscoveredModel(name: id.trim()));
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    // Something is listening on the port, but it is not a model server —
    // a dev server, a database admin page, anything.
    return null;
  }
}
