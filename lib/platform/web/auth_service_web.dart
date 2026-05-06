/// Web AuthService — Firebase signInWithPopup using GoogleAuthProvider.
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../core/services/auth_service.dart';

class AuthServiceWeb implements AuthService {
  String? _accessToken;

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
    final provider = fb.GoogleAuthProvider()
      ..addScope('https://www.googleapis.com/auth/drive.appdata')
      ..addScope('https://www.googleapis.com/auth/drive.file')
      ..setCustomParameters({'prompt': 'select_account'});
    final result = await fb.FirebaseAuth.instance.signInWithPopup(provider);
    final cred = result.credential;
    if (cred is fb.OAuthCredential) {
      _accessToken = cred.accessToken;
    }
    return result.user == null ? null : MarioUser.fromFirebase(result.user!);
  }

  @override
  Future<void> signOut() async {
    _accessToken = null;
    await fb.FirebaseAuth.instance.signOut();
  }

  @override
  Future<String?> driveAccessToken() async => _accessToken;
}
