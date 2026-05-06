/// AuthService — abstract sign-in interface. Linux + web implementations selected at startup.
import 'package:firebase_auth/firebase_auth.dart' as fb;

class MarioUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  const MarioUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  factory MarioUser.fromFirebase(fb.User u) => MarioUser(
        uid: u.uid,
        email: u.email,
        displayName: u.displayName,
        photoUrl: u.photoURL,
      );
}

abstract class AuthService {
  Stream<MarioUser?> authStateChanges();
  MarioUser? get currentUser;
  Future<MarioUser?> signInWithGoogle();
  Future<void> signOut();

  /// Access token for Drive API calls. Refreshed on demand.
  Future<String?> driveAccessToken();
}
