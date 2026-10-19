/// Sign-in on the desktop builds: the macOS welcome window.
///
/// Widget tests run as Android, which draws the Material split screen; these
/// switch the platform to Linux, which is what puts `MacLoginScreen` up. The
/// last test stays on Android to pin that the Material screen is untouched.
library;

import 'dart:async';

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/auth_service.dart';
import 'package:mario/features/auth/auth_notifier.dart';
import 'package:mario/features/auth/login_screen.dart';
import 'package:mario/features/auth/mac_login_screen.dart';
import 'package:mario/ui/mac/mac_look.dart';
import 'package:mario/ui/mac/mac_theme.dart';
import 'package:mario/ui/theme.dart';

/// Sign-in that waits for the test to say how it went.
class _FakeAuth implements AuthService {
  int signIns = 0;
  Completer<MarioUser?>? pending;

  @override
  Future<MarioUser?> signInWithGoogle() {
    signIns++;
    return (pending = Completer<MarioUser?>()).future;
  }

  @override
  Stream<MarioUser?> authStateChanges() => const Stream.empty();

  @override
  MarioUser? get currentUser => null;

  @override
  Future<void> signOut() async {}

  @override
  Future<String?> driveAccessToken() async => null;
}

/// Widget tests run as Android; Linux is what draws the macOS look.
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

/// The sign-in screen as the app builds it. [restoring] keeps the platform's
/// auth stream silent, as on Linux while a saved session is refreshed.
Future<_FakeAuth> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  Brightness brightness = Brightness.light,
  bool restoring = false,
  bool mac = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final auth = _FakeAuth();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      authStateProvider.overrideWith((ref) => restoring
          ? StreamController<MarioUser?>().stream
          : Stream<MarioUser?>.value(null)),
    ],
    child: MaterialApp(
      theme: mac ? macMaterialTheme(brightness) : MarioTheme.light(),
      builder: mac ? (context, child) => MacLookScope(child: child!) : null,
      home: const LoginScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return auth;
}

final _signIn = find.byWidgetPredicate(
    (w) => w is MacButton && w.label == 'Sign In with Google');

MacButton _button(WidgetTester tester) => tester.widget<MacButton>(_signIn);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('the sign-in window fills every size on ${brightness.name}',
        (tester) async {
      for (final size in const [Size(800, 600), Size(1280, 800)]) {
        await _pump(tester, size: size, brightness: brightness);
        expect(tester.takeException(), isNull, reason: 'at $size');

        expect(find.byType(MacLoginScreen), findsOneWidget);
        final window = tester.getRect(find.byType(MacWindow));
        expect(window, Offset.zero & size, reason: 'fills the window');
        // The mark, the name, one line, and the action — centred.
        expect(find.image(const AssetImage('assets/logo/mario_mark.png')),
            findsOneWidget);
        expect(find.text('Mario'), findsOneWidget);
        expect(
            find.text('Sign in to reach the notebooks already on your Drive.'),
            findsOneWidget);
        expect(_signIn, findsOneWidget);
        expect(_button(tester).style, MacButtonStyle.prominent);
        expect(tester.getCenter(_signIn).dx, closeTo(size.width / 2, 1));
      }
    }, variant: _linux);
  }

  testWidgets('Linux keeps the system title bar: no lights, no bar of ours',
      (tester) async {
    await _pump(tester);
    expect(find.byType(MacTitlebar), findsNothing);
    expect(find.byType(MacWindowControls), findsNothing);
    // Nothing Material on the desktop screen.
    for (final type in [Scaffold, InkWell, TextButton, ElevatedButton]) {
      expect(find.byType(type), findsNothing, reason: '$type');
    }
  }, variant: _linux);

  testWidgets('on macOS the title bar is only room for the system lights',
      (tester) async {
    await _pump(tester);
    final bar = tester.widget<MacTitlebar>(find.byType(MacTitlebar));
    expect(bar.title, isNull);
    expect(bar.actions, isEmpty);
    expect(find.byType(MacWindowControls), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('while a session is restored, a spinner stands in for the button',
      (tester) async {
    await _pump(tester, restoring: true);
    expect(_signIn, findsNothing);
    expect(find.byType(MacSpinner), findsOneWidget);
    expect(find.text('Restoring session…'), findsOneWidget);
    // Return does nothing while there is nothing to press.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }, variant: _linux);

  testWidgets('Return signs in; the button waits, and a failure shows in red',
      (tester) async {
    final auth = await _pump(tester);
    expect(_button(tester).onPressed, isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(auth.signIns, 1);
    expect(_button(tester).onPressed, isNull, reason: 'disabled while busy');
    expect(find.byType(MacSpinner), findsOneWidget);
    expect(find.text('Signing in…'), findsOneWidget);

    // A second Return while it runs starts nothing new.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(auth.signIns, 1);

    auth.pending!.completeError(Exception('The browser was closed.'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(MacSpinner), findsNothing);
    expect(_button(tester).onPressed, isNotNull);
    final error = find.text('Exception: The browser was closed.');
    expect(error, findsOneWidget);
    expect(tester.widget<Text>(error).style!.color, MacColors.light.accentRed);

    // Clicking the button tries again.
    await tester.tap(_signIn);
    await tester.pump();
    expect(auth.signIns, 2);
    auth.pending!.complete(null);
    await tester.pump();
  }, variant: _linux);

  testWidgets('the Material sign-in screen is unchanged', (tester) async {
    expect(useMacLook, isFalse);
    await _pump(tester, mac: false);
    expect(find.byType(MacLoginScreen), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
