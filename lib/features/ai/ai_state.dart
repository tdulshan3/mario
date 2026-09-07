/// Riverpod wiring for the AI layer, plus the state the side panel renders.
///
/// The panel is app-level rather than per-page: an answer being streamed
/// should not be thrown away because the user clicked another page to check
/// something. So the open/closed state, the active tab and the current run all
/// live here, above the editor.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../core/services/ai/ai_artifact_store.dart';
import '../../core/services/ai/llm_provider_config.dart';
import '../../core/services/ai/local_model_discovery.dart';
import '../../core/services/ai/llm_service.dart';
import '../../core/services/ai/web_search_service.dart';
import '../../core/services/asset_sync_service.dart';
import '../../core/services/ocr_service.dart';
import '../../core/services/page_content_repository.dart';
import 'agent_actions.dart';
import 'agent_executor.dart';
import 'agent_task.dart';
import 'ai_tasks.dart';
import 'grammar_check.dart';
import 'note_context.dart';
import 'note_images.dart';
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

final agentTaskProvider = Provider<AgentTask>((ref) => AgentTask(
      ref.watch(llmServiceProvider),
      ref.watch(webSearchProvider),
    ));

/// Reads the pictures in a note — bytes for a vision model, OCR text for
/// everything else.
final noteImageReaderProvider = Provider<NoteImageReader>(
  (ref) => NoteImageReader(GetIt.I<AssetSyncService>(), GetIt.I<OcrService>()),
);

final aiTasksProvider = Provider<AiTasks>((ref) => AiTasks(
      llm: ref.watch(llmServiceProvider),
      search: ref.watch(webSearchProvider),
      images: ref.watch(noteImageReaderProvider),
    ));

final grammarCheckerProvider = Provider<GrammarChecker>(
    (ref) => GrammarChecker(ref.watch(llmServiceProvider)));

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
final aiConfigsProvider = FutureProvider<List<LlmProviderConfig>>((ref) async {
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
    required this.readDocument,
    required this.readHtmlArtifact,
    required this.insertMarkdown,
    required this.replaceSelection,
    required this.applyGrammar,
    required this.snapshot,
    required this.restore,
    required this.applyAgentAction,
    required this.renamePage,
    required this.createPage,
    required this.createSection,
    required this.renameSection,
    required this.setHtmlArtifact,
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

  /// The live document, for reading the pictures out of it. Handed over as a
  /// getter rather than a parsed result because resolving images is slow —
  /// a Drive fetch and possibly OCR — and only some backends want it.
  final afe.Document Function() readDocument;

  /// Verbatim HTML attached to the page, typically from a full-document paste
  /// or an AI artifact. It is persisted in the page's Drive JSON.
  final String? Function() readHtmlArtifact;

  /// Inserts Markdown after the current block. Returns false when the editor
  /// went away mid-flight.
  final Future<bool> Function(String markdown) insertMarkdown;

  /// Swaps the highlighted passage for Markdown. False when nothing is
  /// highlighted, or the editor went away mid-flight.
  final Future<bool> Function(String markdown) replaceSelection;

  /// Applies one proofreading fix. False when the text it targets has since
  /// changed — a stale suggestion, not an error.
  final Future<bool> Function(GrammarSuggestion) applyGrammar;

  /// Captures the page exactly as it is, so an agent run can be undone in one
  /// step rather than N presses of Ctrl-Z.
  final AgentSnapshot Function() snapshot;

  /// Puts a snapshot back, discarding everything a run did.
  final Future<bool> Function(AgentSnapshot) restore;

  /// Performs one validated agent action. False when it could not be applied —
  /// a target block edited away between planning and running.
  final Future<bool> Function(AgentAction) applyAgentAction;

  /// Renames the page. Separate from [applyAgentAction] because the title is
  /// index metadata in Firestore, not a block in the document.
  final Future<bool> Function(String title) renamePage;

  /// Creates a page in this notebook — in the named section, or this page's
  /// own — with an optional Markdown body. The new page is not opened: the
  /// run asking for it is still editing this one.
  final Future<bool> Function(String title, {String? section, String markdown})
      createPage;

  /// Creates a section in this notebook.
  final Future<bool> Function(String name) createSection;

  /// Renames the named section, or this page's own.
  final Future<bool> Function(String name, {String? section}) renameSection;

  /// Replaces the page's HTML artifact and opens its rendered preview.
  final Future<bool> Function(String html) setHtmlArtifact;
}

/// Text the user has highlighted in the editor, or null when nothing is
/// selected.
///
/// Published by the editor as the selection settles, and consumed by the Ask
/// tab so a question can be asked *about the highlighted passage* rather than
/// about the whole page.
final editorSelectionProvider = StateProvider<String?>((ref) => null);

/// Null whenever no page is open.
final aiEditorBridgeProvider = StateProvider<AiEditorBridge?>((ref) => null);

/// Whether the on-page ask composer is showing, and what to seed it with.
///
/// It used to sit at the foot of every page permanently, which put a control
/// under every document whether or not anyone was asking anything. It is
/// summoned instead: `/ask` opens it at the end of the page, carrying whatever
/// was typed after the command.
class InlineAskPrompt {
  const InlineAskPrompt({
    this.open = false,
    this.seed = '',
    this.anchor,
    this.above,
  });

  final bool open;

  /// Where the caret was when it opened, in the editor canvas's own
  /// coordinates. Null falls back to the foot of the canvas.
  ///
  /// Captured once rather than followed: the composer takes focus off the
  /// page the moment it appears, so there is no live caret to track — and a
  /// box that wandered while you typed into it would be worse than one that
  /// stays where you summoned it.
  final Offset? anchor;

  /// The page ABOVE the caret, captured at the same moment.
  ///
  /// Asking at a point in a page means asking about what leads up to it —
  /// the same thing `/summary` means by "the notes above". It has to be taken
  /// on open, because by submit time the caret is in the composer and the
  /// editor no longer knows where it was.
  final NoteText? above;

  /// The question `/ask what is a monad` typed after the command. Consumed
  /// once — the composer submits it and clears it, so a later rebuild does
  /// not ask again.
  final String seed;
}

class InlineAskNotifier extends Notifier<InlineAskPrompt> {
  @override
  InlineAskPrompt build() => const InlineAskPrompt();

  void openWith(String seed, {Offset? anchor, NoteText? above}) =>
      state = InlineAskPrompt(
        open: true,
        seed: seed,
        anchor: anchor,
        above: above,
      );

  /// Clears the seed but leaves the composer open — called the moment the
  /// question has been handed over.
  void seedTaken() => state = InlineAskPrompt(
        open: state.open,
        anchor: state.anchor,
        above: state.above,
      );

  void close() => state = const InlineAskPrompt();
}

final inlineAskProvider =
    NotifierProvider<InlineAskNotifier, InlineAskPrompt>(InlineAskNotifier.new);

/// How much room the floating composer needs at the foot of a panel.
///
/// The composer is not a docked bar — it floats over the tab's content so the
/// answer scrolls behind it, the way a chat composer does. That only works if
/// each panel's scroll view reserves this much at its bottom; without it the
/// last line parks permanently underneath and cannot be scrolled clear.
const double kComposerReserve = 76;

/// Publishes the composer's MEASURED height to the tab below it.
///
/// [kComposerReserve] is only a first guess, and a guessed constant is exactly
/// how a docked footer ends up painted underneath the composer: the number was
/// close enough to look right and wrong enough to overlap. The composer now
/// measures itself and hands the real figure down here, so a panel reserves
/// what the composer actually occupies rather than what someone once assumed.
class ComposerReserve extends InheritedWidget {
  const ComposerReserve({
    super.key,
    required this.height,
    required super.child,
  });

  final double height;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ComposerReserve>()?.height ??
      kComposerReserve;

  @override
  bool updateShouldNotify(ComposerReserve old) => old.height != height;
}

/// Which tab of the side panel is showing.
enum AiPanelTab { ask, quiz, writing, agent }

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
    this.pendingInstruction,
  });

  final bool isOpen;
  final AiPanelTab tab;

  /// A question handed over by the `/ask` slash command, to be picked up and
  /// submitted once the panel mounts. Cleared as soon as it is consumed, so a
  /// rebuild cannot fire the same question twice.
  final String? pendingQuestion;

  /// The same idea for the Do tab: an instruction handed over by the composer
  /// or by a preset, run once the tab picks it up. The two are separate fields
  /// because they go to different places — a question is answered, an
  /// instruction edits the page — and mixing them would mean the composer's
  /// text landing in whichever tab happened to read it first.
  final String? pendingInstruction;

  AiPanelState copyWith({
    bool? isOpen,
    AiPanelTab? tab,
    String? pendingQuestion,
    bool clearPendingQuestion = false,
    String? pendingInstruction,
    bool clearPendingInstruction = false,
  }) =>
      AiPanelState(
        isOpen: isOpen ?? this.isOpen,
        tab: tab ?? this.tab,
        pendingQuestion: clearPendingQuestion
            ? null
            : (pendingQuestion ?? this.pendingQuestion),
        pendingInstruction: clearPendingInstruction
            ? null
            : (pendingInstruction ?? this.pendingInstruction),
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

  /// Opens the Do tab with an instruction queued to run.
  void runInstruction(String instruction) => state = state.copyWith(
        isOpen: true,
        tab: AiPanelTab.agent,
        pendingInstruction: instruction,
      );

  String? takePendingInstruction() {
    final i = state.pendingInstruction;
    if (i != null) state = state.copyWith(clearPendingInstruction: true);
    return i;
  }
}

final aiPanelProvider =
    NotifierProvider<AiPanelNotifier, AiPanelState>(AiPanelNotifier.new);
