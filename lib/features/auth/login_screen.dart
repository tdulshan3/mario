/// Login screen — Mario logo + "Sign in with Google" CTA, yellow brand surface.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/colors.dart';
import 'auth_notifier.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MarioMark(),
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: auth.isLoading
                        ? null
                        : () => ref.read(authNotifierProvider.notifier).signIn(),
                    icon: auth.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF1A1A1A),
                            ),
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

class _MarioMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: MarioColors.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: MarioColors.primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'M',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 56,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
