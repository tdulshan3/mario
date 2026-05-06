/// MarioApp — root MaterialApp.router with theme, go_router, and auth-aware redirects.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_notifier.dart';
import 'features/auth/login_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/settings_state.dart';
import 'features/shell/shell_screen.dart';
import 'ui/theme.dart';

class MarioApp extends ConsumerWidget {
  const MarioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    final themeMode = ref.watch(settingsProvider).valueOrNull?.themeMode ??
        ThemeMode.system;
    return MaterialApp.router(
      title: 'Mario',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: MarioTheme.light(),
      darkTheme: MarioTheme.dark(),
      routerConfig: router,
    );
  }
}

final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final loggedIn = auth.valueOrNull != null;
      final goingToLogin = state.matchedLocation == '/login';
      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && goingToLogin) return '/';
      return null;
    },
    refreshListenable: _AuthRefresh(ref),
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/', builder: (_, __) => const ShellScreen()),
      GoRoute(
          path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
});

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}
