/// Sign-in — the redesign's split screen (artboard 2g).
///
/// A navy panel carries the mark and the promise; a cream panel carries the
/// one action. On a narrow window the navy panel drops away and the action
/// column takes the whole screen, so the same screen serves desktop and mobile.
///
/// The design also offers a "Use this device only" button. This app has no
/// local-only auth path — [AuthService] exposes Google sign-in and sign-out
/// and nothing else — so that button is deliberately not here. A control that
/// does nothing would be worse than an honest omission.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/colors.dart';
import '../../ui/widgets/mario_loader.dart';
import 'auth_notifier.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  /// Below this the navy panel is dropped rather than squeezed — at narrow
  /// widths it would crowd the action column instead of framing it.
  static const _splitBreakpoint = 860.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final split = constraints.maxWidth >= _splitBreakpoint;
          final form = _SignInColumn(split: split);
          if (!split) return form;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(flex: 52, child: _BrandPanel()),
              Expanded(flex: 48, child: form),
            ],
          );
        },
      ),
    );
  }
}

/// The navy half: three soft discs behind the mark and the headline.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final onNavy = MarioColors.neutral100;
    return ClipRect(
      child: Container(
        color: MarioColors.neutral900,
        padding: const EdgeInsets.all(56),
        child: Stack(
          children: [
            // The discs are decorative and deliberately clipped by the panel.
            Positioned(
              top: -120,
              right: -120,
              child: _Disc(420, MarioColors.accent2400.withValues(alpha: 0.20)),
            ),
            Positioned(
              top: 180,
              right: 120,
              child: _Disc(240, MarioColors.accent500.withValues(alpha: 0.62)),
            ),
            Positioned(
              bottom: 200,
              left: -40,
              child: _Disc(160, Colors.white.withValues(alpha: 0.18)),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset('assets/logo/mario_mark.png',
                        width: 64, height: 64),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Your notes,\nyour world',
                    style: Theme.of(context)
                        .textTheme
                        .displayLarge
                        ?.copyWith(fontSize: 46, height: 1.05, color: onNavy),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(
                      'Blocks for maths, code, drawing, sheets and voice — '
                      'kept on your machine and synced to your own Drive.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: onNavy.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc(this.size, this.color);
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _SignInColumn extends ConsumerWidget {
  const _SignInColumn({required this.split});

  /// When the navy panel is gone, the mark has to appear here instead — it is
  /// the only thing identifying the screen.
  final bool split;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = ref.watch(authNotifierProvider);
    final stream = ref.watch(authStateProvider);

    // While the platform's auth stream has not emitted yet (Linux doing a
    // silent token refresh, say) do not flash the CTA — the router moves us
    // to the shell as soon as restore resolves.
    final restoring = !stream.hasValue;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(56),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!split) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset('assets/logo/mario_mark.png',
                      width: 64, height: 64),
                ),
                const SizedBox(height: 28),
              ],
              Text(
                'Welcome back',
                style: theme.textTheme.displayMedium?.copyWith(fontSize: 30),
              ),
              const SizedBox(height: 10),
              Text(
                'Sign in to reach the notebooks already on your Drive.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              if (restoring)
                const _RestoringRow()
              else
                _GoogleButton(
                  loading: auth.isLoading,
                  onPressed: () =>
                      ref.read(authNotifierProvider.notifier).signIn(),
                ),
              if (auth.hasError) ...[
                const SizedBox(height: 16),
                Text(
                  auth.error.toString(),
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Mario stores your API keys in the system keychain and never '
                'sends notes anywhere you have not connected.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RestoringRow extends StatelessWidget {
  const _RestoringRow();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MarioLoader(size: 18),
          const SizedBox(width: 12),
          Text(
            'Restoring session…',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
}

/// The one action: a 52px pill on paper, with the G mark in a navy disc.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.pill),
          side: BorderSide(color: scheme.outline),
        ),
        child: InkWell(
          onTap: loading ? null : onPressed,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MarioRadius.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const MarioLoader(size: 22)
              else
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.onSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    'G',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontSize: 12, color: scheme.surface),
                  ),
                ),
              const SizedBox(width: 12),
              Text(
                loading ? 'Signing in…' : 'Continue with Google',
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
