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
        MarioThemeMode.system;
    // Resolve our 4-mode enum to a concrete ThemeData. For system mode we
    // still defer to MaterialApp's themeMode + theme/darkTheme so the OS
    // signal flows through; for explicit modes we force one theme into both
    // slots.
    final ThemeData lightTheme;
    final ThemeData darkTheme;
    final ThemeMode flutterMode;
    switch (themeMode) {
      case MarioThemeMode.system:
        // System pairs the two defaults: cream by day, the mark's navy by
        // night. Black is deliberately not the system dark — it is a choice,
        // not a fallback.
        lightTheme = MarioTheme.light();
        darkTheme = MarioTheme.night();
        flutterMode = ThemeMode.system;
      case MarioThemeMode.light:
        lightTheme = MarioTheme.light();
        darkTheme = MarioTheme.light();
        flutterMode = ThemeMode.light;
      case MarioThemeMode.white:
        lightTheme = MarioTheme.white();
        darkTheme = MarioTheme.white();
        flutterMode = ThemeMode.light;
      case MarioThemeMode.night:
        lightTheme = MarioTheme.night();
        darkTheme = MarioTheme.night();
        flutterMode = ThemeMode.dark;
      case MarioThemeMode.black:
        lightTheme = MarioTheme.black();
        darkTheme = MarioTheme.black();
        flutterMode = ThemeMode.dark;
    }
    return MaterialApp.router(
      title: 'Mario',
      debugShowCheckedModeBanner: false,
      themeMode: flutterMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      routerConfig: router,
    );
  }
}

final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      // Auth still resolving (e.g. silent refresh on Linux). Keep the user
      // parked at /login — the login screen renders a spinner — and let the
      // refresh listener re-trigger the redirect once a value lands.
      if (!auth.hasValue) {
        return state.matchedLocation == '/login' ? null : '/login';
      }
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
