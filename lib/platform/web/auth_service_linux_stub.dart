/// Web stub for the Linux-only [AuthServiceLinux].
///
/// The browser never takes that branch — `isLinuxNative` is false and
/// [AuthServiceWeb] signs in instead — but dart2js type-checks every branch
/// it compiles, so the name and its constructor have to exist or the whole
/// web build fails on "Method not found". Nothing here is ever constructed;
/// the methods throw rather than return a plausible-looking nothing.
library;

import '../../core/services/auth_service.dart';

class AuthServiceLinux implements AuthService {
  AuthServiceLinux({
    required Object googleClientId,
    required Object googleClientSecret,
    required Object firebaseApiKey,
    required Object firedartStore,
  });

  Never _unsupported() => throw UnsupportedError(
      'AuthServiceLinux is not used on the web; AuthServiceWeb is.');

  @override
  Stream<MarioUser?> authStateChanges() => _unsupported();

  @override
  MarioUser? get currentUser => _unsupported();

  @override
  Future<MarioUser?> signInWithGoogle() => _unsupported();

  @override
  Future<void> signOut() => _unsupported();

  @override
  Future<String?> driveAccessToken() => _unsupported();
}
