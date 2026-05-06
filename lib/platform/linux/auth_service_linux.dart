/// Linux AuthService — googleapis_auth localhost OAuth2 redirect, then Firebase sign-in.
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/auth_service.dart';

class AuthServiceLinux implements AuthService {
  AuthServiceLinux({
    required this.clientId,
    required this.clientSecret,
  });

  final String clientId;
  final String clientSecret;

  static const _scopes = [
    'email',
    'profile',
    'openid',
    'https://www.googleapis.com/auth/drive.appdata',
    'https://www.googleapis.com/auth/drive.file',
  ];

  static const _storage = FlutterSecureStorage();
  static const _refreshKey = 'mario_google_refresh_token';

  gauth.AutoRefreshingAuthClient? _client;

  @override
  MarioUser? get currentUser {
    final u = fb.FirebaseAuth.instance.currentUser;
    return u == null ? null : MarioUser.fromFirebase(u);
  }

  @override
  Stream<MarioUser?> authStateChanges() => fb.FirebaseAuth.instance
      .authStateChanges()
      .map((u) => u == null ? null : MarioUser.fromFirebase(u));

  @override
  Future<MarioUser?> signInWithGoogle() async {
    final id = gauth.ClientId(clientId, clientSecret);
    _client = await gauth.clientViaUserConsent(
      id,
      _scopes,
      (url) async {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
    );
    final creds = _client!.credentials;
    if (creds.refreshToken != null) {
      await _storage.write(key: _refreshKey, value: creds.refreshToken);
    }
    final cred = fb.GoogleAuthProvider.credential(
      accessToken: creds.accessToken.data,
      idToken: creds.idToken,
    );
    final result = await fb.FirebaseAuth.instance.signInWithCredential(cred);
    return result.user == null ? null : MarioUser.fromFirebase(result.user!);
  }

  @override
  Future<void> signOut() async {
    await _storage.delete(key: _refreshKey);
    _client?.close();
    _client = null;
    await fb.FirebaseAuth.instance.signOut();
  }

  @override
  Future<String?> driveAccessToken() async =>
      _client?.credentials.accessToken.data;
}
