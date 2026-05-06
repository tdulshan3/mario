/// Linux AuthService — custom IPv4 OAuth flow + Identity Toolkit exchange
/// + firedart's FirebaseAuth (since FlutterFire has no Linux SDK).
library;

import 'dart:async';
import 'dart:convert';

import 'package:firedart/firedart.dart' as fd;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/auth_service.dart';
import 'google_oauth_flow.dart';

class AuthServiceLinux implements AuthService {
  AuthServiceLinux({
    required this.googleClientId,
    required this.googleClientSecret,
    required this.firebaseApiKey,
    required this.firedartStore,
  });

  final String googleClientId;
  final String googleClientSecret;
  final String firebaseApiKey;
  final fd.TokenStore firedartStore;

  static const _scopes = [
    'email',
    'profile',
    'openid',
    'https://www.googleapis.com/auth/drive.appdata',
    'https://www.googleapis.com/auth/drive.file',
  ];

  static const _storage = FlutterSecureStorage();
  static const _refreshKey = 'mario_google_refresh_token';

  GoogleOAuthTokens? _googleTokens;
  MarioUser? _current;
  Future<MarioUser?>? _signInInFlight;
  final _stateController = StreamController<MarioUser?>.broadcast();

  @override
  MarioUser? get currentUser => _current;

  /// Subscribers see the latest known state immediately, then any subsequent
  /// changes — so the router redirect doesn't get stuck thinking the user is
  /// logged out after a successful sign-in.
  @override
  Stream<MarioUser?> authStateChanges() async* {
    yield _current;
    yield* _stateController.stream;
  }

  @override
  Future<MarioUser?> signInWithGoogle() {
    // Reentrancy guard — if the OAuth browser is already open, return the
    // pending future instead of relaunching.
    final inFlight = _signInInFlight;
    if (inFlight != null) return inFlight;

    final fut = _doSignIn().whenComplete(() => _signInInFlight = null);
    _signInInFlight = fut;
    return fut;
  }

  Future<MarioUser?> _doSignIn() async {
    final flow = GoogleOAuthFlow(
      clientId: googleClientId,
      clientSecret: googleClientSecret,
      scopes: _scopes,
      openBrowser: (url) async {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      },
    );

    // Try silent refresh first.
    GoogleOAuthTokens? tokens;
    final storedRefresh = await _storage.read(key: _refreshKey);
    if (storedRefresh != null && storedRefresh.isNotEmpty) {
      tokens = await flow.refresh(storedRefresh);
    }
    tokens ??= await flow.run();

    _googleTokens = tokens;
    if (tokens.refreshToken != null) {
      await _storage.write(key: _refreshKey, value: tokens.refreshToken);
    }

    final googleIdToken = tokens.idToken;
    if (googleIdToken == null) {
      throw StateError(
          'Google did not return an ID token. Make sure the OAuth client is '
          'a "Desktop" type and that the openid scope is requested.');
    }

    final firebase = await _exchangeForFirebaseSession(googleIdToken);
    _current = MarioUser(
      uid: firebase.uid,
      email: firebase.email,
      displayName: firebase.displayName,
      photoUrl: firebase.photoUrl,
    );
    _stateController.add(_current);
    return _current;
  }

  Future<_FirebaseSession> _exchangeForFirebaseSession(
      String googleIdToken) async {
    final url = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$firebaseApiKey');
    final body = jsonEncode({
      'postBody': 'id_token=$googleIdToken&providerId=google.com',
      'requestUri': 'http://localhost',
      'returnSecureToken': true,
      'returnIdpCredential': true,
    });
    final res = await http.post(url,
        headers: {'Content-Type': 'application/json'}, body: body);
    if (res.statusCode != 200) {
      throw _identityToolkitException(res);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final session = _FirebaseSession.fromMap(data);
    _injectIntoFiredart(session);
    return session;
  }

  /// Identity Toolkit failures are almost always Firebase Console
  /// misconfiguration. Translate the codes into actionable hints so the user
  /// doesn't have to decode raw JSON.
  StateError _identityToolkitException(http.Response res) {
    String? code;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final error = body['error'] as Map<String, dynamic>?;
      code = error?['message'] as String?;
    } catch (_) {}
    final hint = switch (code) {
      'CONFIGURATION_NOT_FOUND' =>
        '\n\nFirebase Authentication is not enabled for this project. '
            'Open Firebase Console → Authentication → Sign-in method, '
            'enable the Google provider, and add this OAuth client id to '
            '"Whitelist client IDs from external projects":\n  '
            '$googleClientId',
      'OPERATION_NOT_ALLOWED' =>
        '\n\nGoogle sign-in is disabled for this Firebase project. '
            'Enable it under Authentication → Sign-in method → Google.',
      'INVALID_IDP_RESPONSE' =>
        '\n\nFirebase rejected the Google ID token. Most often this means '
            'the OAuth client id is not on the Firebase project\'s whitelist. '
            'Add it under Authentication → Sign-in method → Google → Web SDK '
            'configuration → "Whitelist client IDs from external projects":\n  '
            '$googleClientId',
      _ => '\n\nRaw response: ${res.body}',
    };
    return StateError('Sign-in failed (${code ?? res.statusCode}).$hint');
  }

  /// firedart owns its FirebaseAuth singleton + TokenStore. We reach into the
  /// store directly to seed the freshly-acquired tokens — `setToken` is the
  /// public injection point on TokenStore.
  void _injectIntoFiredart(_FirebaseSession session) {
    if (!fd.FirebaseAuth.initialized) {
      throw StateError('firedart FirebaseAuth must be initialised before sign-in');
    }
    firedartStore.setToken(
      session.uid,
      session.idToken,
      session.refreshToken,
      session.expiresIn,
    );
  }

  @override
  Future<void> signOut() async {
    await _storage.delete(key: _refreshKey);
    _googleTokens = null;
    if (fd.FirebaseAuth.initialized) {
      fd.FirebaseAuth.instance.signOut();
    }
    _current = null;
    _stateController.add(null);
  }

  @override
  Future<String?> driveAccessToken() async {
    final tokens = _googleTokens;
    if (tokens == null) return null;
    if (tokens.expiry.isAfter(DateTime.now().toUtc())) {
      return tokens.accessToken;
    }
    final refresh = tokens.refreshToken;
    if (refresh == null) return null;
    final flow = GoogleOAuthFlow(
      clientId: googleClientId,
      clientSecret: googleClientSecret,
      scopes: _scopes,
      openBrowser: (_) async {},
    );
    final refreshed = await flow.refresh(refresh);
    if (refreshed == null) return null;
    _googleTokens = refreshed;
    return refreshed.accessToken;
  }
}

class _FirebaseSession {
  final String uid;
  final String idToken;
  final String refreshToken;
  final int expiresIn;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  const _FirebaseSession({
    required this.uid,
    required this.idToken,
    required this.refreshToken,
    required this.expiresIn,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  factory _FirebaseSession.fromMap(Map<String, dynamic> m) => _FirebaseSession(
        uid: m['localId'] as String,
        idToken: m['idToken'] as String,
        refreshToken: m['refreshToken'] as String,
        expiresIn: int.tryParse(m['expiresIn']?.toString() ?? '3600') ?? 3600,
        email: m['email'] as String?,
        displayName: m['displayName'] as String?,
        photoUrl: m['photoUrl'] as String?,
      );
}
