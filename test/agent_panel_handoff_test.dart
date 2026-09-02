/// Handing an instruction to the Do tab must not crash it.
///
/// `runInstruction` sets the pending instruction AND switches to the agent
/// tab in one write, so the panel is MOUNTED BY the same rebuild that queued
/// the work. Taking the instruction from `initState` therefore wrote to
/// `aiPanelProvider` while the tree was still building, and Riverpod threw
/// "Tried to modify a provider while the widget tree was building" — a red
/// screen where the Do tab should be. The take has to be deferred to a
/// post-frame callback, the way the Ask tab has always done it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/agent_panel.dart';
import 'package:mario/features/ai/ai_state.dart';
import 'package:mario/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Mounts the Do tab only while it is the selected tab, which is what makes
  /// `runInstruction` mount it mid-build — the shape the real side panel has.
  Future<WidgetRef> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: MarioTheme.light(),
        home: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            final tab = ref.watch(aiPanelProvider).tab;
            return Scaffold(
              body: tab == AiPanelTab.agent
                  ? const AgentPanel()
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    ));
    return captured;
  }

  testWidgets('an instruction handed to the Do tab does not throw',
      (tester) async {
    final ref = await pumpPanel(tester);

    ref.read(aiPanelProvider.notifier).runInstruction('tidy up this page');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(AgentPanel), findsOneWidget);
  });

  testWidgets('the instruction is consumed, not left to re-run',
      (tester) async {
    final ref = await pumpPanel(tester);

    ref.read(aiPanelProvider.notifier).runInstruction('tidy up this page');
    await tester.pump();
    // The post-frame callback runs on the next frame, not this one.
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      ref.read(aiPanelProvider).pendingInstruction,
      isNull,
      reason: 'a queued instruction left in place would re-run on remount',
    );
  });

  testWidgets('opening the Do tab with nothing queued is fine', (tester) async {
    final ref = await pumpPanel(tester);

    ref.read(aiPanelProvider.notifier).showTab(AiPanelTab.agent);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(AgentPanel), findsOneWidget);
  });
}
