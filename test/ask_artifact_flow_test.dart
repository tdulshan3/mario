import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider.dart';
import 'package:mario/core/services/ai/llm_service.dart';
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/core/services/ai/web_search_service.dart';
import 'package:mario/features/ai/ai_progress.dart';
import 'package:mario/features/ai/ai_tasks.dart';
import 'package:mario/features/ai/note_context.dart';

void main() {
  test('Ask can revise exact pasted HTML without note-only restrictions',
      () async {
    final provider = _RecordingProvider();
    final task = AiTasks(llm: _AskLlm(provider), search: _NoSearch());
    const html = '<!doctype html><html><style>.hero{color:red}</style>'
        '<body><main class="hero">Old</main></body></html>';
    final run = task.ask(
      question: 'Turn this HTML into an interactive landing page',
      ctx: const AiTaskContext(
        notebookId: 'n',
        pageId: 'p',
        note: NoteText(title: 'Page', blocks: []),
        htmlArtifact: html,
      ),
      useWeb: false,
    );

    for (var i = 0; i < 100 && run.value.status == AiRunStatus.running; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    expect(run.value.status, AiRunStatus.done);
    expect(provider.request.messages.single.content, contains(html));
    expect(provider.request.system, contains('general-purpose assistant'));
    expect(provider.request.system, isNot(contains('HOUSE STYLE FOR NOTES')));
    expect(provider.request.system, contains('single ```html fenced block'));
    expect(provider.request.maxTokens, greaterThan(4000));
    run.dispose();
  });
}

class _AskLlm implements LlmService {
  _AskLlm(this.provider);
  final LlmProvider provider;

  @override
  Future<LlmProvider> requireProvider([String? id]) async => provider;

  @override
  LlmEffort get userEffort => LlmEffort.medium;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingProvider implements LlmProvider {
  late LlmRequest request;

  @override
  String get id => 'test';

  @override
  String get displayName => 'Test model';

  @override
  LlmCapabilities get capabilities =>
      const LlmCapabilities(contextTokens: 32000);

  @override
  Stream<LlmDelta> stream(LlmRequest request, {CancelToken? cancel}) async* {
    this.request = request;
    yield const LlmDelta(
      text: '```html\n<html><body><button>New</button></body></html>\n```',
    );
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSearch implements WebSearchService {
  @override
  Future<WebSearchStatus> status() async => WebSearchStatus.turnedOff;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
