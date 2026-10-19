/// Sign-in on the desktop builds: a plain macOS window holding the app, one
/// line about it and the one action — the welcome window of a Mac app.
///
/// The title bar is only the window's lights and somewhere to drag it by:
/// nothing is open yet, so there is no title to show. The content centres in
/// whatever size the window is, and scrolls if the window is too short.
///
/// Same paths as the Material screen ([LoginScreen]): Google sign-in through
/// [AuthNotifier.signIn]; while the platform's auth stream has not emitted
/// (Linux restoring a session) a spinner stands where the button would be;
/// while sign-in runs the button is disabled with a spinner under it; a
/// failure shows under the button in red. Demo builds never land here —
/// their auth state is a signed-in fixture — so they need nothing of their
/// own.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/mac/mac_window_frame.dart';
import 'auth_notifier.dart';

/// The app icon, at the size a Mac welcome window shows it.
const double _kMarkSize = 128;

/// The text column: wide enough for the description on one line.
const double _kColumnWidth = 420;

class MacLoginScreen extends StatelessWidget {
  const MacLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lights = macWindowLights();
    return MacWindow(
      // No title: the bar is transparent, just the lights and a drag area.
      titlebar: lights == null
          ? null
          : MacWindowDragArea(child: MacTitlebar(windowControls: lights)),
      child: const MacContent(child: Center(child: _SignIn())),
    );
  }
}

class _SignIn extends ConsumerWidget {
  const _SignIn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = MacTypography.of(context);
    final c = context.macColors;
    final auth = ref.watch(authNotifierProvider);
    final stream = ref.watch(authStateProvider);

    // While the platform's auth stream has not emitted yet (Linux doing a
    // silent token refresh, say) do not offer the button — the router moves
    // us to the shell as soon as restore resolves.
    final restoring = !stream.hasValue;
    final signingIn = auth.isLoading;
    final canSignIn = !restoring && !signingIn;
    void signIn() => ref.read(authNotifierProvider.notifier).signIn();
    void onReturn() {
      if (canSignIn) signIn();
    }

    final secondary = type.body.copyWith(color: c.labelSecondary);

    // Sign In is the window's default button, so Return presses it.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): onReturn,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): onReturn,
      },
      child: Focus(
        autofocus: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kColumnWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo/mario_mark.png',
                width: _kMarkSize,
                height: _kMarkSize,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: 20),
              Text(
                'Mario',
                textAlign: TextAlign.center,
                style: type.emphasized(MacTextSpecs.largeTitle),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to reach the notebooks already on your Drive.',
                textAlign: TextAlign.center,
                style: secondary,
              ),
              const SizedBox(height: 20),
              if (restoring)
                const _Status('Restoring session…')
              else
                MacButton(
                  label: 'Sign In with Google',
                  style: MacButtonStyle.prominent,
                  size: MacControlSize.large,
                  onPressed: canSignIn ? signIn : null,
                ),
              if (signingIn && !restoring) ...[
                const SizedBox(height: 12),
                const _Status('Signing in…'),
              ],
              if (auth.hasError) ...[
                const SizedBox(height: 12),
                Text(
                  auth.error.toString(),
                  textAlign: TextAlign.center,
                  style: type.callout.copyWith(color: c.accentRed),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Mario stores your API keys in the system keychain and never '
                'sends notes anywhere you have not connected.',
                textAlign: TextAlign.center,
                style: type.subheadline.copyWith(color: c.labelSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A spinner and what it is waiting for.
class _Status extends StatelessWidget {
  const _Status(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MacSpinner(semanticLabel: label),
          const SizedBox(width: 8),
          Text(
            label,
            style: MacTypography.of(context)
                .body
                .copyWith(color: context.macColors.labelSecondary),
          ),
        ],
      );
}
