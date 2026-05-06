/// AuthNotifier — Riverpod AsyncNotifier wrapping AuthService for sign-in / sign-out flows.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../core/services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => GetIt.I<AuthService>());

final authStateProvider = StreamProvider<MarioUser?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, MarioUser?>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<MarioUser?> {
  @override
  Future<MarioUser?> build() async {
    final service = ref.watch(authServiceProvider);
    return service.currentUser;
  }

  Future<void> signIn() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authServiceProvider).signInWithGoogle();
      return user;
    });
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authServiceProvider).signOut();
      return null;
    });
  }
}
