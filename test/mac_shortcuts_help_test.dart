/// The keyboard shortcuts help (Ctrl+/) on the desktop builds: a sheet.
///
/// Widget tests run as Android, which shows the Material dialog; these
/// switch the platform to Linux, which is what shows the macOS sheet. The
/// last test stays on Android to pin that the dialog lists the same rows.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/shell/keyboard_shortcuts.dart';
import 'package:mario/features/shell/mac_shortcuts_help.dart';
import 'package:mario/ui/mac/mac_theme.dart';
import 'package:mario/ui/mac/mac_look.dart';
import 'package:mario/ui/theme.dart';

/// Widget tests run as Android; Linux is what draws the macOS look.
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

/// A window under the app's shortcuts, as the shell has it.
Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  Brightness brightness = Brightness.light,
  bool mac = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: mac ? macMaterialTheme(brightness) : MarioTheme.light(),
      builder: mac ? (context, child) => MacLookScope(child: child!) : null,
      home: const GlobalShortcuts(child: SizedBox.expand()),
    ),
  ));
  await tester.pump();
}

/// Ctrl+/, then past the sheet's slide.
Future<void> _showHelp(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.slash);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Past the sheet's slide back up, and the route's removal.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  for (final brightness in Brightness.values) {
    for (final size in const [Size(800, 600), Size(1280, 800)]) {
      testWidgets(
          'Ctrl+/ shows every shortcut in a sheet at '
          '${size.width.round()}×${size.height.round()} on ${brightness.name}',
          (tester) async {
        await _pump(tester, size: size, brightness: brightness);
        await _showHelp(tester);
        expect(tester.takeException(), isNull);

        expect(find.byType(MacShortcutsSheet), findsOneWidget);
        expect(find.text('Keyboard Shortcuts'), findsOneWidget);
        // The action on the left, its keys on the right, in the secondary
        // label colour — every row of the list, in its order.
        final rows = tester
            .widgetList<MacFormRow>(find.byType(MacFormRow))
            .map((r) => (keys: r.value, label: r.label))
            .toList();
        expect(rows, [
          for (final s in kShortcutHelp) (keys: s.keys, label: s.label),
        ]);
        final secondary =
            (brightness == Brightness.light ? MacColors.light : MacColors.dark)
                .labelSecondary;
        for (final s in kShortcutHelp) {
          expect(tester.widget<Text>(find.text(s.keys)).style!.color, secondary,
              reason: s.keys);
        }
        // The whole sheet is on screen: nothing to scroll to.
        final sheet = tester.getRect(find.byType(MacSheet));
        expect(sheet.bottom, lessThanOrEqualTo(size.height));

        final done =
            find.byWidgetPredicate((w) => w is MacButton && w.label == 'Done');
        expect(tester.widget<MacButton>(done).style, MacButtonStyle.prominent);
        await tester.tap(done);
        await _settle(tester);
        expect(find.byType(MacShortcutsSheet), findsNothing);
      }, variant: _linux);
    }
  }

  testWidgets('Return and Escape both close it', (tester) async {
    await _pump(tester);
    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.escape]) {
      await _showHelp(tester);
      expect(find.byType(MacShortcutsSheet), findsOneWidget);
      await tester.sendKeyEvent(key);
      await _settle(tester);
      expect(find.byType(MacShortcutsSheet), findsNothing, reason: '$key');
    }
  }, variant: _linux);

  testWidgets('the Material dialog lists the same shortcuts', (tester) async {
    expect(useMacLook, isFalse);
    await _pump(tester, mac: false);
    await _showHelp(tester);
    expect(find.byType(MacShortcutsSheet), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    for (final s in kShortcutHelp) {
      expect(find.text(s.keys), findsOneWidget);
      expect(find.text(s.label), findsOneWidget);
    }
  });
}
