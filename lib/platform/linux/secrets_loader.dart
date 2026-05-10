/// SecretsLoader — pulls the Linux desktop OAuth client credentials from .env.
///
/// .env supports two shapes (whichever is convenient):
///
///   1. The full Google Cloud Console JSON download:
///        desktopclientid={"installed":{"client_id":"…","client_secret":"…"}}
///
///   2. Two bare lines:
///        desktopclientid=`<client-id>`
///        desktopclientsecret=`<client-secret>`
///
/// Process environment variables override .env values (handy for CI), under
/// the names MARIO_DESKTOP_CLIENT_ID / MARIO_DESKTOP_CLIENT_SECRET (or the
/// shorter GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET aliases).
library;

import 'dart:convert';
import 'dart:io';

class MarioSecrets {
  final String desktopClientId;
  final String desktopClientSecret;

  const MarioSecrets({
    required this.desktopClientId,
    required this.desktopClientSecret,
  });
}

class SecretsMissingException implements Exception {
  final List<String> missing;
  const SecretsMissingException(this.missing);

  @override
  String toString() => '''
Mario can't find the Linux OAuth credentials: ${missing.join(', ')}.

Add them to ./.env, either as Google's JSON download:

  desktopclientid={"installed":{"client_id":"…","client_secret":"…"}}

or as two plain values:

  desktopclientid=<your-desktop-client-id>
  desktopclientsecret=<your-desktop-client-secret>

You can find these in Google Cloud Console → APIs & Services →
Credentials → your Desktop OAuth client → DOWNLOAD JSON.''';
}

class SecretsLoader {
  const SecretsLoader._();

  /// Compile-time constants baked in via `--dart-define`. Empty string when
  /// the build didn't set them. Production builds use these so the shipped
  /// binary doesn't need a runtime `.env` or environment variable.
  static const _bakedId = String.fromEnvironment('MARIO_DESKTOP_CLIENT_ID');
  static const _bakedSecret =
      String.fromEnvironment('MARIO_DESKTOP_CLIENT_SECRET');

  /// Reads compile-time `--dart-define` values, then `.env`, then the
  /// process environment. Returns null only when no source exists at all;
  /// throws [SecretsMissingException] when sources exist but lack the
  /// required keys.
  static Future<MarioSecrets?> load({
    String envPath = '.env',
    Map<String, String>? environment,
  }) async {
    // Production fast-path — secrets baked into the binary at build time.
    if (_bakedId.isNotEmpty && _bakedSecret.isNotEmpty) {
      return MarioSecrets(
        desktopClientId: _bakedId,
        desktopClientSecret: _bakedSecret,
      );
    }

    final values = await _readEnvFile(envPath);
    final env = environment ?? Platform.environment;
    final hasFile = values.isNotEmpty;
    final hasEnv = env.keys.any(_isOurEnvVar);
    if (!hasFile && !hasEnv) return null;

    final secrets = parse(envContents: values, environment: env);
    return secrets;
  }

  /// Pure helper — runs the priority chain over already-parsed maps. Exposed
  /// for unit tests.
  static MarioSecrets parse({
    required Map<String, String> envContents,
    required Map<String, String> environment,
  }) {
    String? id;
    String? secret;

    // 1. .env file: prefer the JSON shape, fall back to bare keys.
    final fileJson = _extractGoogleClient(envContents);
    if (fileJson != null) {
      id = fileJson.$1;
      secret = fileJson.$2;
    } else {
      id = envContents['desktopclientid'] ??
          envContents['desktop_client_id'];
      secret = envContents['desktopclientsecret'] ??
          envContents['desktop_client_secret'];
    }

    // 2. Process env vars override anything from the file.
    id = _envFallback(environment, _idVarNames) ?? id;
    secret = _envFallback(environment, _secretVarNames) ?? secret;

    final missing = <String>[
      if (id == null || id.isEmpty) 'desktop client id',
      if (secret == null || secret.isEmpty) 'desktop client secret',
    ];
    if (missing.isNotEmpty) throw SecretsMissingException(missing);

    return MarioSecrets(desktopClientId: id!, desktopClientSecret: secret!);
  }

  // ---------- internals ----------

  static const _idVarNames = [
    'MARIO_DESKTOP_CLIENT_ID',
    'GOOGLE_CLIENT_ID',
    'DESKTOPCLIENTID',
  ];
  static const _secretVarNames = [
    'MARIO_DESKTOP_CLIENT_SECRET',
    'GOOGLE_CLIENT_SECRET',
    'DESKTOPCLIENTSECRET',
  ];
  static bool _isOurEnvVar(String name) =>
      _idVarNames.contains(name) || _secretVarNames.contains(name);

  static String? _envFallback(Map<String, String> env, List<String> names) {
    for (final n in names) {
      final v = env[n];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static Future<Map<String, String>> _readEnvFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return const {};
    return _parse(await file.readAsString());
  }

  /// Tolerant `KEY=VALUE` parser. Handles surrounding whitespace and `#`
  /// comments. Values are returned verbatim (no quote stripping) so JSON
  /// blobs survive intact.
  static Map<String, String> _parse(String content) {
    final out = <String, String>{};
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim().toLowerCase();
      final value = line.substring(eq + 1).trim();
      if (value.isEmpty) continue;
      out[key] = value;
    }
    return out;
  }

  /// Looks for any value that parses as the Google Cloud Console JSON
  /// download shape. Returns (clientId, clientSecret) or null.
  static (String, String)? _extractGoogleClient(Map<String, String> values) {
    for (final value in values.values) {
      final json = _maybeJson(value);
      if (json == null) continue;
      final inner = (json['installed'] ?? json['web'] ?? json);
      if (inner is! Map) continue;
      final id = inner['client_id'];
      final secret = inner['client_secret'];
      if (id is String && secret is String && id.isNotEmpty && secret.isNotEmpty) {
        return (id, secret);
      }
    }
    return null;
  }

  static Map<String, dynamic>? _maybeJson(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('{')) return null;
    // Trailing junk (your file has "...}}keep" on the web line) — strip
    // anything after the matching closing brace.
    var depth = 0;
    var end = -1;
    for (var i = 0; i < trimmed.length; i++) {
      final c = trimmed[i];
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          end = i + 1;
          break;
        }
      }
    }
    if (end == -1) return null;
    try {
      final decoded = jsonDecode(trimmed.substring(0, end));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
