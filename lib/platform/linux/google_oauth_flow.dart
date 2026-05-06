/// Custom Google OAuth 2.0 desktop flow that binds to IPv4 explicitly.
///
/// Why we don't use `googleapis_auth.clientViaUserConsent`: the package's
/// `AuthorizationCodeGrantServerFlow` calls
/// `HttpServer.bind('localhost', port)` which on modern Linux resolves
/// `localhost` to IPv6 `::1` first — so the loopback server only listens on
/// IPv6. Google's redirect target is `http://localhost:PORT`, which Chrome/
/// Firefox happily resolve to IPv4 `127.0.0.1`, and the browser then times out
/// trying to reach a server that isn't there.
///
/// We sidestep the whole thing by binding to `InternetAddress.loopbackIPv4`
/// and constructing the redirect URI as `http://127.0.0.1:PORT/`, which
/// Google's Desktop OAuth client accepts implicitly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

class GoogleOAuthTokens {
  final String accessToken;
  final String? idToken;
  final String? refreshToken;
  final DateTime expiry;

  const GoogleOAuthTokens({
    required this.accessToken,
    required this.idToken,
    required this.refreshToken,
    required this.expiry,
  });
}

class GoogleOAuthFlow {
  GoogleOAuthFlow({
    required this.clientId,
    required this.clientSecret,
    required this.scopes,
    required this.openBrowser,
  });

  final String clientId;
  final String clientSecret;
  final List<String> scopes;
  final Future<void> Function(Uri url) openBrowser;

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';

  /// Run the full code-grant flow: spin up loopback server → open browser →
  /// wait for redirect → exchange code for tokens. Times out after [timeout].
  Future<GoogleOAuthTokens> run({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final port = server.port;
      final redirectUri = 'http://127.0.0.1:$port/';
      final state = _randomState();

      final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scopes.join(' '),
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent select_account',
      });

      await openBrowser(authUrl);

      final request = await server.first.timeout(timeout);
      try {
        final params = request.uri.queryParameters;
        await _writeResponsePage(request, params);

        if (params['state'] != state) {
          throw const _OAuthException('OAuth state mismatch');
        }
        final error = params['error'];
        if (error != null) {
          throw _OAuthException('Google returned an error: $error');
        }
        final code = params['code'];
        if (code == null || code.isEmpty) {
          throw const _OAuthException('Google did not return an auth code');
        }
        return _exchangeCode(code, redirectUri);
      } finally {
        await request.response.close().catchError((_) {});
      }
    } finally {
      await server.close(force: true);
    }
  }

  Future<GoogleOAuthTokens> _exchangeCode(String code, String redirectUri) async {
    final res = await http.post(
      Uri.parse(_tokenEndpoint),
      body: {
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      },
    );
    if (res.statusCode != 200) {
      throw _OAuthException('Token exchange failed: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    return GoogleOAuthTokens(
      accessToken: data['access_token'] as String,
      idToken: data['id_token'] as String?,
      refreshToken: data['refresh_token'] as String?,
      expiry: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
    );
  }

  /// Refresh the access token using a stored [refreshToken]. Returns the new
  /// tokens, or null if the refresh failed (token revoked, expired, etc).
  Future<GoogleOAuthTokens?> refresh(String refreshToken) async {
    try {
      final res = await http.post(
        Uri.parse(_tokenEndpoint),
        body: {
          'refresh_token': refreshToken,
          'client_id': clientId,
          'client_secret': clientSecret,
          'grant_type': 'refresh_token',
        },
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      return GoogleOAuthTokens(
        accessToken: data['access_token'] as String,
        idToken: data['id_token'] as String?,
        // refresh_token isn't always returned on refresh; keep the old one.
        refreshToken: data['refresh_token'] as String? ?? refreshToken,
        expiry: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeResponsePage(
      HttpRequest request, Map<String, String> params) async {
    final ok = params['error'] == null && (params['code']?.isNotEmpty ?? false);
    request.response
      ..statusCode = ok ? 200 : 400
      ..headers.set('Content-Type', 'text/html; charset=UTF-8')
      ..write(_completionHtml(ok ? null : params['error']));
  }

  String _completionHtml(String? error) {
    final accent = '#FFDE7A';
    final body = error == null
        ? '<h1>Signed in to Mario</h1><p>You can close this tab.</p>'
        : '<h1>Sign-in failed</h1><pre>$error</pre>';
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Mario</title></head>
<body style="font-family: system-ui; background:#1E1E1E; color:#F0EFE8; display:grid; place-items:center; height:100vh; margin:0">
<div style="text-align:center; padding:32px; border-left:4px solid $accent">
$body
</div></body></html>''';
  }

  static String _randomState() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class _OAuthException implements Exception {
  final String message;
  const _OAuthException(this.message);

  @override
  String toString() => message;
}
