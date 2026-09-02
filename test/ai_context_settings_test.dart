import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider_config.dart';
import 'package:mario/core/services/ai/llm_service.dart';
import 'package:mario/core/services/ai/web_search_service.dart';
import 'package:mario/features/ai/ai_settings_section.dart';
import 'package:mario/features/ai/ai_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a model context window can be changed in Settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final backends = AiBackends(LlmProviderStore());

    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiBackendsProvider.overrideWithValue(backends),
        aiConfigsProvider.overrideWith((_) async => const []),
        localModelsProvider.overrideWith((_) async => const []),
        webSearchProvider.overrideWithValue(WebSearchService()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AiSettingsSection())),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a model'));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('ai-context-window'));
    expect(field, findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('32k'), findsOneWidget);

    await tester.enterText(field, '128k');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(backends.configs, hasLength(1));
    expect(backends.configs.single.contextTokens, 131072);
    expect(backends.configs.single.effectiveCapabilities.contextTokens, 131072);
  });

  testWidgets('an invalid context window stays in the dialog with an error',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final backends = AiBackends(LlmProviderStore());

    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiBackendsProvider.overrideWithValue(backends),
        aiConfigsProvider.overrideWith((_) async => const []),
        localModelsProvider.overrideWith((_) async => const []),
        webSearchProvider.overrideWithValue(WebSearchService()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AiSettingsSection())),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a model'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ai-context-window')),
      '999m',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Use a context window from 1k to 4m tokens.'),
        findsOneWidget);
    expect(backends.configs, isEmpty);
  });
}
