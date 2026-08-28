/// The editor's handshake with the AI panel, across a page switch.
///
/// This exists because of a real crash: the editor cleared its bridge from
/// `State.dispose()` using `ref`, and Flutter marks an element inactive
/// *before* calling dispose, so Riverpod threw
/// `Cannot use "ref" after the widget was disposed` on every page switch and
/// on quitting the app.
///
/// The fix has two halves and both are easy to regress, so both are pinned
/// here: the controller is captured while `ref` is still valid, and the
/// withdrawal is deferred and guarded by page id so that closing the old
/// editor cannot wipe the bridge the *new* one has already published.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/ai_state.dart';
import 'package:mario/features/ai/note_context.dart';

/// A stand-in for `_EditorState`'s bridge lifecycle, using the same provider
/// and the same capture-then-defer pattern the editor uses.
class _FakeEditor extends ConsumerStatefulWidget {
  const _FakeEditor({required this.pageId, super.key});
  final String pageId;

  @override
  ConsumerState<_FakeEditor> createState() => _FakeEditorState();
}

class _FakeEditorState extends ConsumerState<_FakeEditor> {
  StateController<AiEditorBridge?>? _bridgeController;

  @override
  void initState() {
    super.initState();
    _bridgeController = ref.read(aiEditorBridgeProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(aiEditorBridgeProvider.notifier).state = AiEditorBridge(
        pageId: widget.pageId,
        notebookId: 'nb',
        sectionId: 'sec',
        pageTitle: 'Page ${widget.pageId}',
        readPage: () => const NoteText(title: '', blocks: []),
        readAboveCursor: () => const NoteText(title: '', blocks: []),
        insertMarkdown: (_) async => true,
        applyGrammar: (_) async => true,
      );
    });
  }

  @override
  void dispose() {
    final controller = _bridgeController;
    final pageId = widget.pageId;
    if (controller != null) {
      scheduleMicrotask(() {
        try {
          if (controller.state?.pageId == pageId) controller.state = null;
        } catch (_) {/* container gone */}
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('publishes a bridge for the open page', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: _FakeEditor(pageId: 'p1')),
    ));
    await tester.pump();

    expect(container.read(aiEditorBridgeProvider)?.pageId, 'p1');
  });

  testWidgets('disposing does not throw "Cannot use ref after dispose"',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: _FakeEditor(pageId: 'p1')),
    ));
    await tester.pump();

    // Tear the editor down — this is the exact path that used to crash.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SizedBox.shrink()),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(container.read(aiEditorBridgeProvider), isNull,
        reason: 'closing the last page should leave no bridge behind');
  });

  testWidgets('a page switch leaves the NEW page bridged, not null',
      (tester) async {
    // The ordering hazard: the outgoing editor's dispose runs after the
    // incoming one has mounted. An unguarded withdrawal would clear the new
    // page's bridge and leave the panel insisting no page is open.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: _FakeEditor(pageId: 'p1', key: ValueKey('p1'))),
    ));
    await tester.pump();
    expect(container.read(aiEditorBridgeProvider)?.pageId, 'p1');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: _FakeEditor(pageId: 'p2', key: ValueKey('p2'))),
    ));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(container.read(aiEditorBridgeProvider)?.pageId, 'p2',
        reason: 'the outgoing page must not withdraw the incoming bridge');
  });

  testWidgets('a bridge published after disposal is not written at all',
      (tester) async {
    // A page opened and closed inside one frame: the post-frame publish must
    // notice it is unmounted rather than publishing a handle to a dead editor.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: _FakeEditor(pageId: 'p1')),
    ));
    // No pump() in between — remove it before the post-frame callback lands.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SizedBox.shrink()),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(container.read(aiEditorBridgeProvider), isNull);
  });
}
