/// Riverpod wiring for the AI layer, plus the state the side panel renders.
///
/// The panel is app-level rather than per-page: an answer being streamed
/// should not be thrown away because the user clicked another page to check
/// something. So the open/closed state, the active tab and the current run all
/// live here, above the editor.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../core/services/ai/ai_artifact_store.dart';
import '../../core/services/ai/llm_provider_config.dart';
import '../../core/services/ai/local_model_discovery.dart';
import '../../core/services/ai/llm_service.dart';
import '../../core/services/ai/web_search_service.dart';
import '../../core/services/page_content_repository.dart';
import 'ai_tasks.dart';
import 'grammar_check.dart';
import 'note_context.dart';
import 'section_reader.dart';

final aiBackendsProvider = Provider<AiBackends>((ref) => GetIt.I<AiBackends>());
final llmServiceProvider = Provider<LlmService>((ref) => GetIt.I<LlmService>());
final webSearchProvider =
    Provider<WebSearchService>((ref) => GetIt.I<WebSearchService>());
final aiArtifactStoreProvider =
    Provider<AiArtifactStore>((ref) => GetIt.I<AiArtifactStore>());

/// Reads every page of a section, reusing valid cached summaries.
final sectionReaderProvider = Provider<SectionReader>((ref) => SectionReader(
      GetIt.I<PageContentRepository>(),
      ref.watch(aiArtifactStoreProvider),
    ));

final aiTasksProvider = Provider<AiTasks>((ref) => AiTasks(
      llm: ref.watch(llmServiceProvider),
      search: ref.watch(webSearchProvider),
    ));

final grammarCheckerProvider =
    Provider<GrammarChecker>((ref) => GrammarChecker(ref.watch(llmServiceProvider)));

/// How the Writing tab applies a fix — null when no page is open.
final grammarApplierProvider =
    Provider<Future<bool> Function(GrammarSuggestion)?>((ref) {
  return ref.watch(aiEditorBridgeProvider)?.applyGrammar;
});

/// Model servers already running on this machine.
///
/// autoDispose so it re-probes when settings are reopened — someone who just
/// started Ollama should not have to restart Mario for it to be noticed.
final localModelsProvider =
    FutureProvider.autoDispose<List<DiscoveredEndpoint>>((ref) async {
  return LocalModelDiscovery().scan();
});

/// The configured backends, re-read whenever settings change.
final aiConfigsProvider =
    FutureProvider<List<LlmProviderConfig>>((ref) async {
  final backends = ref.watch(aiBackendsProvider);
  await backends.load();
  return backends.configs;
});

/// The handle the side panel uses to reach the open editor.
///
/// The panel lives above the editor in the widget tree, so it cannot touch the
/// AppFlowy [EditorState] directly — and should not: only the editor knows how
/// to apply a transaction safely (see `blocks/_safe_transaction.dart`, and the
/// canvas-freeze bugs in this repo's history that motivated it). The editor
/// publishes this bridge when it mounts and withdraws it on dispose, so the
/// panel's Insert button is simply unavailable when no page is open.
class AiEditorBridge {
  const AiEditorBridge({
    required this.pageId,
    required this.notebookId,
    required this.sectionId,
    required this.pageTitle,
    required this.readPage,
    required this.readAboveCursor,
    required this.insertMarkdown,
    required this.applyGrammar,
  });

  final String pageId;
  final String notebookId;
  final String sectionId;
  final String pageTitle;

  /// The whole page as text.
  final NoteText Function() readPage;

  /// Everything above the caret — what `/summary` means by "the note above".
  /// Falls back to the whole page when there is no caret.
  final NoteText Function() readAboveCursor;

  /// Inserts Markdown after the current block. Returns false when the editor
  /// went away mid-flight.
  final Future<bool> Function(String markdown) insertMarkdown;

  /// Applies one proofreading fix. False when the text it targets has since
  /// changed — a stale suggestion, not an error.
  final Future<bool> Function(GrammarSuggestion) applyGrammar;
}

/// Null whenever no page is open.
final aiEditorBridgeProvider =
    StateProvider<AiEditorBridge?>((ref) => null);

/// Which tab of the side panel is showing.
enum AiPanelTab { ask, quiz, writing }

/// Which tab is showing and whether the panel is open — and nothing else.
///
/// Each tab's work lives in its own session provider (see
/// `ai_session_state.dart`) rather than here, so switching tabs or closing the
/// panel is a pure view change and never cancels a run.
class AiPanelState {
  const AiPanelState({
    this.isOpen = false,
    this.tab = AiPanelTab.ask,
    this.pendingQuestion,
  });

  final bool isOpen;
  final AiPanelTab tab;

  /// A question handed over by the `/ask` slash command, to be picked up and
  /// submitted once the panel mounts. Cleared as soon as it is consumed, so a
  /// rebuild cannot fire the same question twice.
  final String? pendingQuestion;

  AiPanelState copyWith({
    bool? isOpen,
    AiPanelTab? tab,
    String? pendingQuestion,
    bool clearPendingQuestion = false,
  }) =>
      AiPanelState(
        isOpen: isOpen ?? this.isOpen,
        tab: tab ?? this.tab,
        pendingQuestion: clearPendingQuestion
            ? null
            : (pendingQuestion ?? this.pendingQuestion),
      );
}

class AiPanelNotifier extends Notifier<AiPanelState> {
  @override
  AiPanelState build() => const AiPanelState();

  void open({AiPanelTab? tab}) =>
      state = state.copyWith(isOpen: true, tab: tab);

  /// Closing the panel hides it and nothing more.
  ///
  /// It used to cancel the running request, on the theory that a model
  /// generating into a panel nobody can see is wasted work. In practice it
  /// meant glancing away threw the answer out — so a run now survives, and the
  /// Stop button in each tab is the only thing that ends one.
  void close() => state = state.copyWith(isOpen: false);

  void toggle() => state.isOpen ? close() : open();

  void showTab(AiPanelTab tab) =>
      state = state.copyWith(isOpen: true, tab: tab);

  /// Opens the Ask tab with a question queued for submission.
  void askQuestion(String question) => state = state.copyWith(
        isOpen: true,
        tab: AiPanelTab.ask,
        pendingQuestion: question,
      );

  String? takePendingQuestion() {
    final q = state.pendingQuestion;
    if (q != null) state = state.copyWith(clearPendingQuestion: true);
    return q;
  }

}

final aiPanelProvider =
    NotifierProvider<AiPanelNotifier, AiPanelState>(AiPanelNotifier.new);
