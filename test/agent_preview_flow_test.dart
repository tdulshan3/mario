import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider.dart';
import 'package:mario/core/services/ai/llm_service.dart';
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/core/services/ai/web_search_service.dart';
import 'package:mario/features/ai/agent_actions.dart';
import 'package:mario/features/ai/agent_task.dart';
import 'package:mario/features/ai/ai_progress.dart';
import 'package:mario/features/ai/note_context.dart';

void main() {
  const note = NoteText(
    title: 'Page',
    blocks: [
      NoteBlock(nodeId: 'a', path: [0], type: 'paragraph', text: 'Original'),
    ],
  );

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(condition(), isTrue);
  }

  test('a plan cannot touch the page before the user approves it', () async {
    final llm = _AgentLlm({
      'summary': 'Add a paragraph',
      'actions': [
        {'kind': 'paragraph', 'text': 'New'},
      ],
    });
    final approval = Completer<bool>();
    var applied = 0;
    var previewed = false;
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Add one paragraph',
      note: note,
      onPlanned: (plan) {
        previewed = true;
        return approval.future;
      },
      applyAction: (_) async {
        applied++;
        return const AgentActionResult.ok();
      },
      useWeb: false,
      // The preview is opt-in now; this is the test of what it guards.
      reviewBeforeWriting: true,
    );

    await until(() => previewed);
    expect(applied, 0,
        reason: 'review must happen while the page is untouched');

    approval.complete(true);
    await until(() => run.value.status == AiRunStatus.done);
    expect(applied, 1);
    run.dispose();
  });

  test('current pasted HTML reaches the model verbatim with artifact room',
      () async {
    final llm = _AgentLlm({
      'summary': 'Update the artifact',
      'actions': [
        {'kind': 'html', 'text': '<html><body>New</body></html>'},
      ],
    });
    const oldHtml =
        '<html><style>.old{color:red}</style><body>Old</body></html>';
    var previewed = false;
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Improve this HTML page',
      note: note,
      htmlArtifact: oldHtml,
      onPlanned: (plan) async {
        previewed = true;
        return false;
      },
      applyAction: (_) async => const AgentActionResult.ok(),
      useWeb: false,
      reviewBeforeWriting: true,
    );

    await until(() => previewed);
    expect(llm.request.messages.single.content, contains(oldHtml));
    expect(llm.request.system, contains('self-contained document'));
    expect(llm.request.maxTokens, greaterThan(3000));
    await until(() => run.value.status == AiRunStatus.done);
    run.dispose();
  });
}

class _AgentLlm implements LlmService {
  _AgentLlm(this.reply);

  final Map<String, dynamic> reply;
  late LlmRequest request;

  @override
  Future<LlmProvider> requireProvider([String? id]) async => _StubProvider();

  @override
  LlmEffort get userEffort => LlmEffort.medium;

  @override
  Future<Map<String, dynamic>> structured({
    required LlmRequest request,
    required String schemaName,
    required Map<String, dynamic> schema,
    CancelToken? cancel,
    bool describeSchema = true,
    int repairAttempts = 1,
  }) async {
    this.request = request;
    return reply;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubProvider implements LlmProvider {
  @override
  String get displayName => 'Test model';

  @override
  LlmCapabilities get capabilities =>
      const LlmCapabilities(contextTokens: 32000);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSearch implements WebSearchService {
  @override
  Future<WebSearchStatus> status() async => WebSearchStatus.turnedOff;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
