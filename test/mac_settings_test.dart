/// The desktop Settings window: the macOS look's System Settings layout.
///
/// Widget tests run as Android, which draws the Material screen; these switch
/// the platform to Linux, which is what puts `MacSettingsScreen` on screen.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider_config.dart';
import 'package:mario/core/services/ai/llm_service.dart';
import 'package:mario/core/services/ai/local_model_discovery.dart';
import 'package:mario/core/services/ai/web_search_service.dart';
import 'package:mario/core/services/auth_service.dart';
import 'package:mario/features/ai/ai_state.dart';
import 'package:mario/features/auth/auth_notifier.dart';
import 'package:mario/features/settings/settings_screen.dart';
import 'package:mario/features/settings/settings_state.dart';
import 'package:mario/ui/mac/mac_look.dart';
import 'package:mario/ui/mac/mac_theme.dart';
import 'package:mario/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user =
    MarioUser(uid: 'u1', email: 'sam@example.com', displayName: 'Sam');

/// Widget tests run as Android; Linux is what draws the macOS look.
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

/// Every pane, as the sidebar names them.
const _panes = [
  'Appearance',
  'Editor',
  'Voice',
  'AI models',
  'Sync',
  'Account',
  'About',
];

/// [home] (Settings by default) as the desktop app builds it.
Future<({ProviderContainer container, AiBackends backends})> _pump(
  WidgetTester tester, {
  Widget home = const SettingsScreen(),
  Size size = const Size(1280, 800),
  Brightness brightness = Brightness.light,
  Map<String, Object> prefs = const {},
  Map<String, String> secrets = const {},
  List<DiscoveredEndpoint> localModels = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues(secrets);

  final backends = AiBackends(LlmProviderStore());
  final container = ProviderContainer(overrides: [
    authStateProvider.overrideWith((ref) => Stream.value(_user)),
    aiBackendsProvider.overrideWithValue(backends),
    localModelsProvider.overrideWith((ref) async => localModels),
    webSearchProvider.overrideWithValue(WebSearchService()),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: macMaterialTheme(brightness),
      builder: (context, child) => MacLookScope(child: child!),
      home: home,
    ),
  ));
  await _settle(tester);
  return (container: container, backends: backends);
}

/// Lets the stored settings load and sheets finish sliding in or out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// [label] in the sidebar.
Finder _side(String label) =>
    find.descendant(of: find.byType(MacSidebar), matching: find.text(label));

Future<void> _openPane(WidgetTester tester, String label) async {
  await tester.tap(_side(label));
  await _settle(tester);
}

/// The window title: the open pane's name.
String? _title(WidgetTester tester) =>
    tester.widget<MacTitlebar>(find.byType(MacTitlebar)).title;

ThemeMode _appearanceShown(WidgetTester tester) => tester
    .widget<MacSegmentedControl<ThemeMode>>(
        find.byType(MacSegmentedControl<ThemeMode>))
    .value!;

Finder _appearanceSegment(String label) => find.descendant(
      of: find.byType(MacSegmentedControl<ThemeMode>),
      matching: find.text(label),
    );

MarioThemeMode? _stored(ProviderContainer c) =>
    c.read(settingsProvider).valueOrNull?.themeMode;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('every pane fits 800 × 600 and 1280 × 800 (${brightness.name})',
        (tester) async {
      for (final size in const [Size(800, 600), Size(1280, 800)]) {
        await _pump(tester, size: size, brightness: brightness);
        expect(find.byType(MacSettingsScreen), findsOneWidget);
        expect(find.byType(MacWindow), findsOneWidget);
        for (final pane in _panes) {
          await _openPane(tester, pane);
          expect(_title(tester), pane, reason: 'at $size');
          expect(tester.takeException(), isNull, reason: '$pane at $size');
        }
      }
      // The overlay scroll bars fade on a timer; let it run out.
      await tester.pump(const Duration(seconds: 3));
    }, variant: _linux);
  }

  testWidgets('the sidebar switches panes', (tester) async {
    await _pump(tester);
    expect(_title(tester), 'Appearance');
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('Spell check'), findsNothing);

    await _openPane(tester, 'Editor');
    expect(_title(tester), 'Editor');
    expect(find.text('Spell check'), findsOneWidget);
    expect(find.text('Auto-correct math symbols'), findsOneWidget);
    expect(find.text('Text size'), findsNothing);

    await _openPane(tester, 'Account');
    expect(find.text('sam@example.com'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.widgetWithText(MacButton, 'Sign Out'), findsOneWidget);

    await _openPane(tester, 'About');
    expect(find.text('Version'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  }, variant: _linux);

  testWidgets('a setting applies at once', (tester) async {
    final app = await _pump(tester);
    await _openPane(tester, 'Editor');
    expect(app.container.read(settingsProvider).value!.spellCheck, isTrue);
    final spellCheck = find.descendant(
      of: find.widgetWithText(MacFormRow, 'Spell check'),
      matching: find.byType(MacSwitch),
    );
    await tester.tap(spellCheck);
    await _settle(tester);
    expect(app.container.read(settingsProvider).value!.spellCheck, isFalse);
    await tester.pump(const Duration(seconds: 3));
  }, variant: _linux);

  group('Appearance shows the four grounds as Auto, Light and Dark', () {
    for (final (stored, shown) in const [
      (null, ThemeMode.system),
      ('system', ThemeMode.system),
      ('light', ThemeMode.light),
      ('white', ThemeMode.light),
      ('night', ThemeMode.dark),
      ('black', ThemeMode.dark),
    ]) {
      testWidgets('$stored shows as ${shown.name}', (tester) async {
        await _pump(tester, prefs: {if (stored != null) 'mario.theme': stored});
        expect(_appearanceShown(tester), shown);
        await tester.pump(const Duration(seconds: 3));
      }, variant: _linux);
    }

    testWidgets('picking what is shown keeps the stored ground',
        (tester) async {
      final app = await _pump(tester, prefs: {'mario.theme': 'white'});
      expect(_stored(app.container), MarioThemeMode.white);

      await tester.tap(_appearanceSegment('Light'));
      await _settle(tester);
      expect(_stored(app.container), MarioThemeMode.white);

      await tester.tap(_appearanceSegment('Dark'));
      await _settle(tester);
      expect(_stored(app.container), MarioThemeMode.night);
      expect(_appearanceShown(tester), ThemeMode.dark);

      await tester.tap(_appearanceSegment('Auto'));
      await _settle(tester);
      expect(_stored(app.container), MarioThemeMode.system);

      await tester.tap(_appearanceSegment('Light'));
      await _settle(tester);
      expect(_stored(app.container), MarioThemeMode.light);
      await tester.pump(const Duration(seconds: 3));
    }, variant: _linux);
  });

  testWidgets('a model is added, made active and edited in a sheet',
      (tester) async {
    final app = await _pump(tester);
    await _openPane(tester, 'AI models');
    expect(find.text('No models configured yet.'), findsOneWidget);

    await tester.tap(find.widgetWithText(MacButton, 'Add a Model…'));
    await _settle(tester);
    expect(find.byType(MacSheet), findsOneWidget);
    expect(find.text('Add a Model'), findsOneWidget);

    // A bad context window keeps the sheet open and says why.
    final contextWindow = find.byKey(const ValueKey('ai-context-window'));
    await tester.enterText(contextWindow, '999m');
    await tester.tap(find.widgetWithText(MacButton, 'Save'));
    await _settle(tester);
    expect(find.text('Use a context window from 1k to 4m tokens.'),
        findsOneWidget);
    expect(app.backends.configs, isEmpty);

    await tester.enterText(contextWindow, '128k');
    await tester.tap(find.widgetWithText(MacButton, 'Save'));
    await _settle(tester);
    expect(find.byType(MacSheet), findsNothing);
    expect(app.backends.configs, hasLength(1));
    expect(app.backends.configs.single.contextTokens, 131072);
    // The first model added is the one in use.
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('No models configured yet.'), findsNothing);

    // ⓘ opens it again, with Remove at the sheet's left.
    await tester.tap(find.byType(MacFormIconButton));
    await _settle(tester);
    expect(find.text('Edit Model'), findsOneWidget);
    expect(find.widgetWithText(MacButton, 'Remove…'), findsOneWidget);
    await tester.tap(find.widgetWithText(MacButton, 'Cancel'));
    await _settle(tester);
    expect(find.byType(MacSheet), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  }, variant: _linux);

  testWidgets('a local server is one click away; a search key asks to go',
      (tester) async {
    final app = await _pump(
      tester,
      size: const Size(800, 600),
      secrets: {'mario.ai.serperKey': 'serper-key'},
      localModels: const [
        DiscoveredEndpoint(
          kind: LlmProviderKind.ollama,
          baseUrl: 'http://localhost:11434',
          serverName: 'Ollama',
          models: [DiscoveredModel(name: 'qwen3:4b', parameters: '4B')],
        ),
      ],
    );
    await _openPane(tester, 'AI models');
    expect(find.text('Found on this machine'), findsOneWidget);
    expect(find.text('qwen3:4b'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final use = find.widgetWithText(MacButton, 'Use');
    await tester.ensureVisible(use);
    await tester.tap(use);
    await _settle(tester);
    expect(app.backends.configs.single.model, 'qwen3:4b');
    expect(find.text('Active'), findsOneWidget);
    // Configured now, so no longer offered.
    expect(find.text('Found on this machine'), findsNothing);

    final remove = find.widgetWithText(MacButton, 'Remove Key…');
    await tester.ensureVisible(remove);
    await _settle(tester);
    expect(find.text('Save a key below and this turns on'), findsNothing);
    await tester.tap(remove);
    await _settle(tester);
    expect(find.text('Remove the Serper key?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await _settle(tester);
    expect(find.widgetWithText(MacButton, 'Remove Key…'), findsNothing);
    expect(find.text('Save a key below and this turns on'), findsOneWidget);
    expect(await WebSearchService().readKey(), isNull);
    await tester.pump(const Duration(seconds: 3));
  }, variant: _linux);

  testWidgets('Back and Escape return to the notes', (tester) async {
    await _pump(
      tester,
      home: Builder(
        builder: (context) => Center(
          child: MacButton(
            label: 'Open Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Settings'));
    await _settle(tester);
    expect(find.byType(MacSettingsScreen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byType(MacSettingsScreen), findsNothing);

    await tester.tap(find.text('Open Settings'));
    await _settle(tester);
    await tester.tap(find
        .byWidgetPredicate((w) => w is MacToolbarButton && w.label == 'Back'));
    await _settle(tester);
    expect(find.byType(MacSettingsScreen), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  }, variant: _linux);

  testWidgets('Android and the web keep the Material screen', (tester) async {
    expect(useMacLook, isFalse);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(_user)),
      ],
      child:
          MaterialApp(theme: MarioTheme.light(), home: const SettingsScreen()),
    ));
    await tester.pump();
    expect(find.byType(MacSettingsScreen), findsNothing);
    expect(find.byType(MacWindow), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });
}
