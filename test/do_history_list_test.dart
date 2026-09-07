/// The Do tab's history: earlier instructions, what they did, and a way to
/// run one again or be rid of it.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/ai_artifacts.dart';
import 'package:mario/features/ai/agent_executor.dart';
import 'package:mario/features/ai/ai_history.dart';
import 'package:mario/features/ai/ai_state.dart';
import 'package:mario/features/ai/note_context.dart';
import 'package:mario/ui/theme.dart';

AiEditorBridge _bridge() => AiEditorBridge(
      pageId: 'p1',
      notebookId: 'nb',
      sectionId: 'sec',
      pageTitle: 'Page',
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

DoEntry _entry(String id, String instruction, {String pageId = 'p1'}) =>
    DoEntry(
      id: id,
      pageId: pageId,
      instruction: instruction,
      summary: 'Did the thing',
      applied: const ['Added a paragraph', 'Renamed the page to "X"'],
      provenance: AiProvenance(
        backend: 'LAN · test',
        model: '',
        createdAt: DateTime(2026, 9, 1),
      ),
    );

Future<void> _pump(
  WidgetTester tester, {
  required NotebookAiData data,
  Future<void> Function(String)? onReplay,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      aiEditorBridgeProvider.overrideWith((ref) => _bridge()),
      aiHistoryProvider.overrideWith((ref) async => data),
    ],
    child: MaterialApp(
      theme: MarioTheme.light(),
      home: Scaffold(
        body: ListView(children: [DoHistoryList(onReplay: onReplay)]),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nothing has run yet: nothing is shown', (tester) async {
    await _pump(tester, data: const NotebookAiData());
    expect(find.text('Earlier instructions'), findsNothing);
  });

  testWidgets('earlier runs are listed, this page first, newest first',
      (tester) async {
    await _pump(
      tester,
      data: NotebookAiData(dos: [
        _entry('d1', 'Older, other page', pageId: 'p2'),
        _entry('d2', 'Older, this page'),
        _entry('d3', 'Newer, this page'),
      ]),
    );

    expect(find.text('Earlier instructions'), findsOneWidget);
    final newer = tester.getTopLeft(find.text('Newer, this page')).dy;
    final older = tester.getTopLeft(find.text('Older, this page')).dy;
    final other = tester.getTopLeft(find.text('Older, other page')).dy;
    expect(newer, lessThan(older));
    expect(older, lessThan(other));
    expect(find.text('another page'), findsOneWidget);
  });

  testWidgets('opening a run shows what it did, and Run again re-runs it',
      (tester) async {
    String? replayed;
    await _pump(
      tester,
      data: NotebookAiData(dos: [_entry('d1', 'Pull out the to-dos')]),
      onReplay: (instruction) async => replayed = instruction,
    );

    await tester.tap(find.text('Pull out the to-dos'));
    await tester.pumpAndSettle();
    expect(find.text('Did the thing'), findsOneWidget);
    expect(find.text('Added a paragraph'), findsOneWidget);

    await tester.tap(find.text('Run again'));
    await tester.pumpAndSettle();
    expect(replayed, 'Pull out the to-dos');
  });

  testWidgets('deleting asks first', (tester) async {
    await _pump(
      tester,
      data: NotebookAiData(dos: [_entry('d1', 'Pull out the to-dos')]),
    );
    await tester.tap(find.text('Pull out the to-dos'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete this chat'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this chat?'), findsOneWidget);

    // Backing out leaves the run where it was.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Pull out the to-dos'), findsOneWidget);
  });
}
