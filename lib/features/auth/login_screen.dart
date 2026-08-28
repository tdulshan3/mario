/// Login screen — Mario logo + "Sign in with Google" CTA, yellow brand surface.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/colors.dart';
import 'auth_notifier.dart';
import '../../ui/widgets/mario_loader.dart';
import '../../ui/widgets/mario_logo.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final stream = ref.watch(authStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // While the platform's auth stream hasn't emitted yet (e.g. Linux is
    // doing a silent token refresh), don't flash the sign-in CTA — the
    // router will whisk us away to the shell as soon as restore resolves.
    final restoring = !stream.hasValue;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MarioLogo(size: 96, shadow: true),
                const SizedBox(height: 24),
                Text(
                  'Mario',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? MarioColors.onSurfaceDark
                        : MarioColors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your notes, your world',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: isDark
                        ? MarioColors.onSurfaceMutedDark
                        : MarioColors.onSurfaceMuted,
                  ),
                ),
                const SizedBox(height: 40),
                if (restoring)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const MarioLoader(size: 18),
                        const SizedBox(width: 12),
                        Text(
                          'Restoring session…',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark
                                ? MarioColors.onSurfaceMutedDark
                                : MarioColors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: auth.isLoading
                          ? null
                          : () =>
                              ref.read(authNotifierProvider.notifier).signIn(),
                      icon: auth.isLoading
                          ? const MarioLoader(
                              size: 18,
                              color: Color(0xFF1A1A1A),
                            )
                          : const Icon(Icons.login, size: 18),
                      label: const Text('Sign in with Google'),
                    ),
                  ),
                if (auth.hasError) ...[
                  const SizedBox(height: 16),
                  Text(
                    auth.error.toString(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
