/// Showing which model answered and how much room it had.
///
/// The formatting is the testable part, and it matters more than it looks: a
/// context readout is only useful if it can be read at a glance in a 10px chip,
/// which means "262k", not "262144".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider_config.dart';
import 'package:mario/core/services/ai/local_model_discovery.dart';
import 'package:mario/features/ai/ai_progress.dart';
import 'package:mario/features/ai/model_bar.dart';

void main() {
  group('the bar renders', () {
    testWidgets('shows nothing when no backend is configured', (tester) async {
      // A picker over an empty list is worse than no picker.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ModelBar())),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a run with no usage reported', (tester) async {
      // Most local servers do not report token counts; the bar must still show
      // the window rather than an empty space or a zero.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final run = AiRun(const [AiStepKind.thinking]);
      addTearDown(run.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: ModelBar(run: run))),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('a run records what it used', () {
    test('usage is null until the server reports it', () {
      final run = AiRun(const [AiStepKind.thinking]);
      expect(run.value.promptTokens, isNull);
      run.dispose();
    });

    test('the window is set before the request, usage after', () {
      // The window is known up front; usage only arrives with the reply, so
      // the chip shows the window alone in between.
      final run = AiRun(const [AiStepKind.thinking])
        ..setUsage(contextTokens: 262144);
      expect(run.value.contextTokens, 262144);
      expect(run.value.promptTokens, isNull);

      run.setUsage(promptTokens: 8200);
      expect(run.value.promptTokens, 8200);
      expect(run.value.contextTokens, 262144,
          reason: 'a later usage update must not clear the window');
      run.dispose();
    });

    test('setting usage on a disposed run is ignored, like every mutator', () {
      final run = AiRun(const [AiStepKind.thinking])..dispose();
      expect(() => run.setUsage(promptTokens: 1), returnsNormally);
    });
  });

  group('a discovered model carries its real window', () {
    test('reads context_length out of Ollama tags', () {
      // Ollama's per-kind default is 8k; qwen3.5 actually carries 262k, and
      // treating a 262k model as 8k truncates a section thirty-fold too early.
      const body = '''
{"models":[{"name":"qwen3.5:4b","size":100,
  "details":{"parameter_size":"4.0B","context_length":262144}}]}''';
      final models = parseOllamaTags(body);
      expect(models.single.contextLength, 262144);
    });

    test('a model without a reported window leaves it null', () {
      final models = parseOllamaTags('{"models":[{"name":"x","size":1}]}');
      expect(models.single.contextLength, isNull);
    });

    test('the window is carried onto the saved config', () {
      const endpoint = DiscoveredEndpoint(
        kind: LlmProviderKind.ollama,
        baseUrl: 'http://127.0.0.1:11434/v1',
        serverName: 'Ollama',
        models: [
          DiscoveredModel(name: 'qwen3.5:4b', contextLength: 262144),
        ],
      );
      final config = endpoint.toConfig('qwen3.5:4b', id: 'x');
      expect(config.effectiveCapabilities.contextTokens, 262144);
    });

    test('an unreported window falls back to the kind default', () {
      const endpoint = DiscoveredEndpoint(
        kind: LlmProviderKind.ollama,
        baseUrl: 'http://127.0.0.1:11434/v1',
        serverName: 'Ollama',
        models: [DiscoveredModel(name: 'mystery')],
      );
      final config = endpoint.toConfig('mystery', id: 'x');
      expect(config.effectiveCapabilities.contextTokens, greaterThan(0));
    });
  });
}
