/// The AI panel as the desktop window's macOS inspector.
///
/// Widget tests run as Android, which draws the Material panel; these switch
/// the platform to Linux, which is what puts the macOS inspector on screen.
/// They check that every tab lays out without overflowing at the inspector's
/// narrowest and default widths, in Light and Dark, and that the inspector's
/// own controls drive the same state the Material ones do.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/ai_artifacts.dart';
import 'package:mario/core/services/ai/llm_provider_config.dart';
import 'package:mario/core/services/ai/llm_service.dart';
import 'package:mario/core/services/ai/local_model_discovery.dart';
import 'package:mario/features/ai/agent_executor.dart';
import 'package:mario/features/ai/agent_task.dart';
import 'package:mario/features/ai/ai_progress.dart';
import 'package:mario/features/ai/ai_history.dart';
import 'package:mario/features/ai/ai_session_state.dart';
import 'package:mario/features/ai/ai_side_panel.dart';
import 'package:mario/features/ai/ai_state.dart';
import 'package:mario/features/ai/inline_ask.dart';
import 'package:mario/features/ai/note_context.dart';
import 'package:mario/ui/mac/mac_look.dart';
import 'package:mario/ui/mac/mac_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget tests run as Android; Linux is what draws the macOS look.
final _linux = TargetPlatformVariant.only(TargetPlatform.linux);

/// Loads apple_ui's Inter, the face the desktop draws its chrome in, so
/// widths are measured in real text rather than the test font's one-em
/// squares — which make every label nearly twice as wide and would fail the
/// 280 px checks for text the app never draws that wide.
Future<void> _loadInter() async {
  final loader = FontLoader('packages/apple_ui/Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader
        .addFont(rootBundle.load('packages/apple_ui/fonts/Inter-$weight.ttf'));
  }
  await loader.load();
}

/// A pop-up button lays out every option invisibly to size itself, so its
/// current value is on screen twice; the visible one is the last.
Finder _shown(String text) => find.text(text).last;

AiEditorBridge _bridge() => AiEditorBridge(
      pageId: 'p1',
      notebookId: 'nb',
      sectionId: 'sec',
      pageTitle: 'Photosynthesis',
      readPage: () => const NoteText(title: '', blocks: []),
      readAboveCursor: () => const NoteText(title: '', blocks: []),
      readDocument: afe.Document.blank,
      readHtmlArtifact: () => null,
      insertMarkdown: (_) async => true,
      replaceSelection: (_) async => true,
      applyGrammar: (_) async => true,
      snapshot: () => const AgentSnapshot(document: {}, title: 'fake'),
      restore: (_) async => true,
      applyAgentAction: (_) async => true,
      renamePage: (_) async => true,
      createPage: (_, {section, markdown = ''}) async => true,
      createSection: (_) async => true,
      renameSection: (_, {section}) async => true,
      setHtmlArtifact: (_) async => true,
    );

AiProvenance _made() => AiProvenance(
      backend: 'LAN · qwen3.5:4b',
      model: '',
      createdAt: DateTime(2026, 9, 1),
    );

/// A notebook with something in every history list, so the lists are drawn.
final _history = NotebookAiData(
  asks: [
    AskEntry(
      id: 'a1',
      pageId: 'p1',
      question: 'What does the light-dependent stage of photosynthesis '
          'actually produce, and where does it happen?',
      answer: 'ATP and **NADPH**, in the thylakoid membranes. See '
          '[the notes](https://example.com).',
      provenance: _made(),
    ),
    AskEntry(
      id: 'a2',
      pageId: 'p2',
      question: 'Summarise the Calvin cycle',
      answer: 'Carbon fixation, reduction, regeneration.',
      usedWeb: true,
      provenance: _made(),
    ),
  ],
  dos: [
    DoEntry(
      id: 'd1',
      pageId: 'p1',
      instruction: 'Turn the last paragraph into bullet points',
      summary: 'Made a list',
      applied: const ['Replaced a paragraph with a 4-item list'],
      provenance: _made(),
    ),
  ],
);

const _endpoint = DiscoveredEndpoint(
  kind: LlmProviderKind.ollama,
  baseUrl: 'http://127.0.0.1:11434/v1',
  serverName: 'Ollama',
  models: [
    DiscoveredModel(name: 'qwen3.5:4b-instruct-q4_K_M', contextLength: 262144),
    DiscoveredModel(name: 'llama3.2:1b'),
  ],
);

/// The inspector as the desktop builds it, next to an empty content pane.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  bool configured = true,
  bool page = true,
  AiPanelTab tab = AiPanelTab.ask,
  NotebookAiData? history,
}) async {
  // Wide enough for the inspector at its widest, plus a content pane.
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final backends = AiBackends(LlmProviderStore());
  if (configured) {
    await backends.saveConfigs([
      _endpoint.toConfig('qwen3.5:4b-instruct-q4_K_M', id: 'a'),
      _endpoint.toConfig('llama3.2:1b', id: 'b'),
    ]);
    await backends.setActive('a');
  }

  final container = ProviderContainer(overrides: [
    aiBackendsProvider.overrideWithValue(backends),
    aiConfigsProvider.overrideWith((_) async => backends.configs),
    localModelsProvider.overrideWith((_) async => const [_endpoint]),
    if (page) aiEditorBridgeProvider.overrideWith((ref) => _bridge()),
    aiHistoryProvider
        .overrideWith((ref) async => history ?? const NotebookAiData()),
  ]);
  addTearDown(container.dispose);
  container.read(aiPanelProvider.notifier).showTab(tab);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: macMaterialTheme(brightness),
      builder: (context, child) => MacLookScope(child: child!),
      home: const Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Expanded(child: SizedBox()), AiSidePanel()],
        ),
      ),
    ),
  ));
  // Spinners turn forever, so settle by time rather than pumpAndSettle.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

/// Drags the inspector's left edge to its narrowest width.
Future<void> _narrow(WidgetTester tester) async {
  final handle = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
  expect(handle, findsOneWidget);
  await tester.drag(handle, const Offset(400, 0));
  await tester.pump(const Duration(milliseconds: 100));
}

double _panelWidth(WidgetTester tester) =>
    tester.getSize(find.byType(AiSidePanel)).width;

void main() {
  setUpAll(_loadInter);

  testWidgets('the panel is the macOS inspector, not the Material panel',
      (tester) async {
    await _pump(tester);
    expect(useMacLook, isTrue);
    expect(find.byType(MacSegmentedControl<AiPanelTab>), findsOneWidget);
    expect(find.byType(MacTextField), findsOneWidget);
    // No Material controls in the chrome.
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(_panelWidth(tester), 400);
  }, variant: _linux);

  testWidgets('the left edge resizes it within 280–560', (tester) async {
    await _pump(tester);
    final handle = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
    await tester.drag(handle, const Offset(-500, 0));
    await tester.pump();
    expect(_panelWidth(tester), 560);
    await tester.drag(handle, const Offset(800, 0));
    await tester.pump();
    expect(_panelWidth(tester), 280);
  }, variant: _linux);

  for (final brightness in Brightness.values) {
    for (final narrow in [true, false]) {
      final where = '${brightness.name}, ${narrow ? '280' : '400'} wide';
      for (final tab in AiPanelTab.values) {
        testWidgets('the ${tab.name} tab lays out ($where)', (tester) async {
          await _pump(tester,
              brightness: brightness, tab: tab, history: _history);
          if (narrow) await _narrow(tester);
          expect(_panelWidth(tester), narrow ? 280 : 400);
          // Open a history row too: its foot is the widest row the tab has.
          final row = switch (tab) {
            AiPanelTab.ask => find.textContaining('light-dependent'),
            AiPanelTab.agent =>
              find.text('Turn the last paragraph into bullet points'),
            _ => null,
          };
          if (row != null) {
            await tester.ensureVisible(row);
            await tester.tap(row);
            await tester.pump(const Duration(milliseconds: 300));
          }
          expect(tester.takeException(), isNull);

          // The segmented control paints past its box rather than throwing
          // when it does not fit, so check the last segment clears Close.
          final doRight = tester.getTopRight(find.text('Do')).dx;
          final closeLeft =
              tester.getTopLeft(find.bySemanticsLabel('Close').first).dx;
          expect(doRight, lessThan(closeLeft));
        }, variant: _linux);
      }

      testWidgets('first run, nothing configured ($where)', (tester) async {
        await _pump(tester, brightness: brightness, configured: false);
        if (narrow) await _narrow(tester);
        expect(find.text('No Model Set Up'), findsOneWidget);
        expect(find.text('Set Up a Model…'), findsNothing,
            reason: 'a server was found, so Settings is the long way round');
        expect(find.text('More Options…'), findsOneWidget);
        expect(find.text('qwen3.5:4b-instruct-q4_K_M'), findsOneWidget);
        expect(find.text('Use'), findsNWidgets(2));
        // No composer until a backend exists.
        expect(find.byType(MacTextField), findsNothing);
        expect(tester.takeException(), isNull);
      }, variant: _linux);

      testWidgets('a finished answer lays out ($where)', (tester) async {
        final container = await _pump(tester, brightness: brightness);
        if (narrow) await _narrow(tester);
        final run = AiRun(const [
          AiStepKind.readingNote,
          AiStepKind.searchingWeb,
          AiStepKind.thinking,
          AiStepKind.answering,
        ])
          ..begin(AiStepKind.readingNote)
          ..begin(AiStepKind.searchingWeb, detail: 'photosynthesis stages')
          ..setSearchQuery('light dependent reactions products thylakoid')
          ..addSources(const [
            AiSource(
                title: 'Light-dependent reactions - Wikipedia',
                url: 'https://en.wikipedia.org/wiki/Light-dependent_reactions'),
            AiSource(
                title: 'Photosynthesis | Khan Academy',
                url: 'https://www.khanacademy.org/science/photosynthesis'),
          ])
          ..begin(AiStepKind.thinking)
          ..appendReasoning('First, **recall** the two stages.')
          ..begin(AiStepKind.answering)
          ..appendAnswer('## Products\n\nATP and NADPH [1], made in the '
              '[thylakoid](https://example.com).\n\n> Light is required.\n\n'
              '```python\nprint("ATP")\n```\n')
          ..setBackend('LAN · qwen3.5:4b-instruct-q4_K_M')
          ..finish();
        addTearDown(run.dispose);
        // Starting a run drops the attached passage, so quote after it.
        container.read(askSessionProvider.notifier)
          ..startRun(run, question: 'What do they produce?')
          ..quote('the light-dependent reactions take place in the thylakoid '
              'membranes of the chloroplast');
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Insert into Page'), findsOneWidget);
        expect(find.text('Answered Using 2 Web Sources'), findsOneWidget);
        expect(find.text('Asking About Your Highlight'), findsOneWidget);
        expect(find.text('Read 2 sites'), findsOneWidget);
        await tester.tap(find.text("Model's Reasoning"));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }, variant: _linux);

      testWidgets('a Do outcome lays out ($where)', (tester) async {
        final container =
            await _pump(tester, brightness: brightness, tab: AiPanelTab.agent);
        if (narrow) await _narrow(tester);
        final run = AiRun(const [AiStepKind.thinking, AiStepKind.answering])
          ..begin(AiStepKind.thinking)
          ..begin(AiStepKind.answering)
          ..setResult(const AgentOutcome(
            summary: 'Turned the paragraph into a list',
            applied: ['Replaced a paragraph with a 4-item bulleted list'],
            failed: 1,
            dropped: 1,
            dropReasons: ['an action named a block that does not exist'],
            destructive: 1,
            followUps: [
              'Add a summary table comparing the light and dark reactions',
              'Bold the key terms',
            ],
            question: 'Should the list keep the original order?',
          ))
          ..finish();
        container
            .read(agentSessionProvider.notifier)
            .start(run, instruction: 'Make it a list');
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Undo All'), findsOneWidget);
        expect(find.text('Bold the key terms'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, variant: _linux);

      testWidgets('a quiz paper and its marks lay out ($where)',
          (tester) async {
        final container =
            await _pump(tester, brightness: brightness, tab: AiPanelTab.quiz);
        if (narrow) await _narrow(tester);
        container.read(quizSessionProvider.notifier).generated(const [
          QuizItem(
            id: 'q1',
            kind: QuizItemKind.mcq,
            question: 'Which `molecule` carries the energy from the light '
                'reactions into the Calvin cycle?',
            options: [
              'ATP and NADPH, made in the thylakoid membranes by the '
                  'light-dependent reactions',
              'Glucose',
              'Oxygen released from water',
            ],
            correctIndex: 0,
          ),
          QuizItem(
            id: 'q2',
            kind: QuizItemKind.essay,
            question: 'Explain why the Calvin cycle stops in the dark.',
            marks: 11,
          ),
        ], 'Photosynthesis');
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Submit for Marking'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Clicking an option's text picks it, as clicking a label does.
        await tester.tap(find.text('Glucose'));
        await tester.pump();
        expect(container.read(quizSessionProvider).answers['q1'], '1');

        final notifier = container.read(quizSessionProvider.notifier);
        notifier.graded(
            'q1',
            const QuizGrade(
                itemId: 'q1', awarded: 0, outOf: 1, isProvisional: false));
        notifier.graded(
            'q2',
            const QuizGrade(
              itemId: 'q2',
              awarded: 7,
              outOf: 11,
              feedback: 'Good on **light dependence**.',
              matchedPoints: ['Needs ATP and NADPH'],
              missedPoints: ['Enzyme regulation by light'],
            ));
        notifier.markingFinished();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('New Quiz'), findsOneWidget);
        expect(find.text('Draft mark — change it:'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, variant: _linux);
    }
  }

  testWidgets('the segmented control switches tabs; Close closes',
      (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.text('Quiz'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(aiPanelProvider).tab, AiPanelTab.quiz);
    expect(find.text('Generate Quiz'), findsOneWidget);

    await tester.tap(find.text('Do'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(aiPanelProvider).tab, AiPanelTab.agent);
    expect(find.text('Pull out the to-dos'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close').first);
    await tester.pump();
    expect(container.read(aiPanelProvider).isOpen, isFalse);
    expect(find.byType(MacSegmentedControl<AiPanelTab>), findsNothing);
  }, variant: _linux);

  testWidgets('send is disabled until there is something to send',
      (tester) async {
    await _pump(tester);
    MacButton send() => tester.widget<MacButton>(find
        .byWidgetPredicate((w) => w is MacButton && w.semanticLabel == 'Ask'));
    expect(send().onPressed, isNull);

    await tester.enterText(find.byType(EditableText), 'Why is the sky blue?');
    await tester.pump();
    expect(send().onPressed, isNotNull);
  }, variant: _linux);

  testWidgets('the web pop-up sets the tab\'s preference exactly',
      (tester) async {
    final container = await _pump(tester);
    expect(container.read(askSessionProvider).useWeb, isNull);
    expect(find.text('Web: Auto'), findsWidgets);

    await tester.tap(_shown('Web: Auto'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Web: Off').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(askSessionProvider).useWeb, isFalse);

    await tester.tap(_shown('Web: Off'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Web: On').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(askSessionProvider).useWeb, isTrue);
  }, variant: _linux);

  testWidgets('the model pop-up lists both models and shows the window',
      (tester) async {
    await _pump(tester);
    expect(find.byType(MacPopUpButton<LlmProviderConfig>), findsOneWidget);
    expect(find.text('262k context'), findsOneWidget);
    expect(find.text('Balanced'), findsWidgets);
  }, variant: _linux);

  testWidgets('history rows open on the answer, and delete asks first',
      (tester) async {
    await _pump(tester, history: _history);
    expect(find.text('Earlier Questions'), findsOneWidget);
    // This page first.
    final mine = tester.getTopLeft(find.textContaining('light-dependent')).dy;
    final other = tester.getTopLeft(find.text('Summarise the Calvin cycle')).dy;
    expect(mine, lessThan(other));

    await tester.tap(find.textContaining('light-dependent'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ask Again'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Delete this chat').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Delete this chat?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Delete this chat?'), findsNothing);
  }, variant: _linux);

  testWidgets('the Do launcher runs from the form and keeps its switch',
      (tester) async {
    final container = await _pump(tester, tab: AiPanelTab.agent);
    expect(find.text('Act on This Page'), findsOneWidget);
    expect(container.read(agentSessionProvider).reviewBeforeWriting, isFalse);
    await tester.tap(find.byType(MacSwitch));
    await tester.pump();
    expect(container.read(agentSessionProvider).reviewBeforeWriting, isTrue);
  }, variant: _linux);

  testWidgets('quiz presets and the stepper set the counts', (tester) async {
    final container = await _pump(tester, tab: AiPanelTab.quiz);
    await tester.tap(find.text('30'));
    await tester.pump();
    expect(container.read(quizSessionProvider).mcqCount, 30);
  }, variant: _linux);

  testWidgets('no page open: each tab says so', (tester) async {
    final container = await _pump(tester, page: false);
    expect(find.text('Open a Page First'), findsOneWidget);
    container.read(aiPanelProvider.notifier).showTab(AiPanelTab.quiz);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No Page Open'), findsOneWidget);
    container.read(aiPanelProvider.notifier).showTab(AiPanelTab.writing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No Page Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _linux);

  testWidgets('the in-page /ask composer and answer are macOS controls',
      (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      aiEditorBridgeProvider.overrideWith((ref) => _bridge()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: macMaterialTheme(Brightness.dark),
        builder: (context, child) => MacLookScope(child: child!),
        home: const Scaffold(
          body: SizedBox(width: 720, height: 600, child: InlineAsk(inset: 52)),
        ),
      ),
    ));
    container
        .read(inlineAskProvider.notifier)
        .openWith('', anchor: const Offset(0, 40));
    await tester.pump();
    await tester.pump();
    expect(find.byType(MacTextField), findsOneWidget);
    expect(find.byType(MacGlass), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // An answer arrives (as if asked from the panel, which shares the run).
    final run = AiRun(const [AiStepKind.answering])
      ..begin(AiStepKind.answering)
      ..appendAnswer('ATP and **NADPH**.')
      ..setBackend('LAN · qwen3.5:4b')
      ..finish();
    addTearDown(run.dispose);
    container
        .read(askSessionProvider.notifier)
        .startRun(run, question: 'What do they produce?');
    await tester.pump();
    expect(find.text('Insert Below'), findsOneWidget);
    expect(find.text('Replace Selection'), findsOneWidget);

    // Discard clears the answer and closes the composer.
    await tester.tap(find.text('Discard'));
    await tester.pump();
    expect(container.read(askSessionProvider).run, isNull);
    expect(container.read(inlineAskProvider).open, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: _linux);
}
