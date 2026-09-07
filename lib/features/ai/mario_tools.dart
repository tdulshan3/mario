/// The tools the agent reaches for beyond the open page.
///
/// [AgentExecutor] edits the page that is open, through the editor, so the
/// user watches it change and Undo puts it back. Everything else the agent
/// can do — read another page, list what the notebook holds, search, write
/// into a page that is not open, make a notebook, move to a page, look
/// something up on the web — goes through the app's services directly, and
/// lives here. Each tool returns an [AgentActionResult]: whether it worked,
/// and for the reading kinds the text the model gets back for its next turn.
///
/// Pages are named by title or id. Titles are what the model sees in
/// listings and what people say ("the Krebs cycle page"), and matching is
/// forgiving — exact first, then a title that contains the words, the
/// current notebook before the others — because a model that has to quote an
/// id perfectly gives up and writes into the wrong place.
library;

import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/models/section.dart';
import '../../core/services/ai/llm_types.dart';
import '../../core/services/ai/web_search_service.dart';
import '../../core/services/page_content_repository.dart';
import '../../core/services/sync_service.dart';
import 'agent_actions.dart';
import 'ai_markdown_blocks.dart';
import 'ai_progress.dart';
import 'ai_state.dart';
import 'note_context.dart';

/// A page, with where it lives.
class MarioPageRef {
  const MarioPageRef({
    required this.page,
    required this.section,
    required this.notebook,
  });

  final NotePage page;
  final Section section;
  final Notebook notebook;

  String get where => '${section.name} · ${notebook.name}';
}

/// The notebook tree, as the app sees it.
///
/// Read through the same providers the sidebar reads, not the sync service
/// directly: that is what the demo build swaps for fixtures, and what any
/// future cache would sit behind. The panel supplies it from a provider
/// container, which outlives the widget the way the run does.
typedef MarioIndexLoader = Future<MarioIndex> Function();

/// A page's content, through the same provider the editor loads it with.
typedef MarioContentLoader = Future<Map<String, dynamic>> Function(
    String driveFileId);

class MarioTools {
  MarioTools({
    required this.sync,
    required this.content,
    required this.loadIndex,
    required this.loadContent,
    required this.webSearch,
    required this.uid,
    required this.bridge,
    required this.onOpenPage,
  });

  final SyncService sync;
  final PageContentRepository content;
  final MarioIndexLoader loadIndex;
  final MarioContentLoader loadContent;
  final WebSearchService webSearch;
  final String uid;

  /// The open page — whose text is read live rather than from the cache,
  /// and which the panel routes writes for through the editor instead.
  final AiEditorBridge bridge;

  /// Switches the app to a page. Captured by the panel while its `ref` is
  /// valid, because the run outlives the widget.
  final void Function(NotePage page) onOpenPage;

  /// The run, for progress details and web sources. Set once it exists.
  AiRun? run;

  /// Notebooks, sections and pages, read once per run and refreshed after
  /// anything is created.
  MarioIndex? _index;

  /// Whether [ref] names the open page.
  bool isCurrentPage(String? ref) {
    if (ref == null || ref.trim().isEmpty) return true;
    final r = ref.trim();
    return r == bridge.pageId ||
        r.toLowerCase() == bridge.pageTitle.trim().toLowerCase();
  }

  Future<AgentActionResult> perform(AgentAction action) async {
    try {
      switch (action.kind) {
        case AgentActionKind.listNotebooks:
          return AgentActionResult.ok(await _listNotebooks());
        case AgentActionKind.listPages:
          return _listPages(action);
        case AgentActionKind.readPage:
          return _readPage(action);
        case AgentActionKind.searchNotes:
          return AgentActionResult.ok(await _searchNotes(action.text));
        case AgentActionKind.webSearch:
          return _webSearch(action.text);
        case AgentActionKind.createNotebook:
          return _createNotebook(action.text);
        case AgentActionKind.createSection:
          return _createSection(action);
        case AgentActionKind.createPage:
          return _createPage(action);
        case AgentActionKind.writePage:
          return _writePage(action);
        case AgentActionKind.openPage:
          return _openPage(action);
        case AgentActionKind.askUser:
          // Nothing to do: the task records the question and stops.
          return const AgentActionResult.ok();
        default:
          return const AgentActionResult.failed('not a tool');
      }
    } on LlmCancelled {
      rethrow;
    } catch (e) {
      return AgentActionResult.failed('$e');
    }
  }

  // ------------------------------------------------------------- listings

  Future<String> _listNotebooks() async {
    final index = await _load();
    if (index.notebooks.isEmpty) return 'No notebooks yet.';
    final buf = StringBuffer('Notebooks:\n');
    for (final nb in index.notebooks) {
      final sections = index.sectionsOf(nb.id);
      final current = nb.id == bridge.notebookId ? ' (current)' : '';
      buf.writeln('- "${nb.name}"$current — sections: '
          '${sections.isEmpty ? 'none' : sections.map((s) => '"${s.name}"').join(', ')}');
    }
    return buf.toString().trimRight();
  }

  Future<AgentActionResult> _listPages(AgentAction action) async {
    final index = await _load();
    final notebook = action.notebook == null
        ? index.notebook(bridge.notebookId)
        : index.notebookNamed(action.notebook!);
    if (notebook == null) {
      return AgentActionResult.failed(
          'No notebook called "${action.notebook}". ${_notebookNames(index)}');
    }
    var sections = index.sectionsOf(notebook.id);
    if (action.section != null) {
      final wanted = action.section!.trim().toLowerCase();
      sections =
          sections.where((s) => s.name.trim().toLowerCase() == wanted).toList();
      if (sections.isEmpty) {
        return AgentActionResult.failed(
            'No section called "${action.section}" in "${notebook.name}". '
            'Its sections: ${index.sectionsOf(notebook.id).map((s) => '"${s.name}"').join(', ')}');
      }
    }
    final buf = StringBuffer('Pages in "${notebook.name}":\n');
    var count = 0;
    for (final s in sections) {
      for (final p in index.pagesOf(s.id)) {
        final current = p.id == bridge.pageId ? ' (current)' : '';
        buf.writeln(
            '- "${p.title}"$current — section "${s.name}" — id ${p.id}');
        count++;
      }
    }
    if (count == 0) buf.writeln('(no pages)');
    return AgentActionResult.ok(buf.toString().trimRight());
  }

  // -------------------------------------------------------------- reading

  Future<AgentActionResult> _readPage(AgentAction action) async {
    if (isCurrentPage(action.page)) {
      return AgentActionResult.ok(
          'Page "${bridge.pageTitle}" (current page)\n\n${bridge.readPage().render()}');
    }
    final found = await _findPage(action.page!, notebook: action.notebook);
    if (found == null) {
      return AgentActionResult.failed(_noSuchPage(action.page!));
    }
    final note = await _noteOf(found.page);
    return AgentActionResult.ok(
        'Page "${found.page.title}" — ${found.where} (id ${found.page.id})\n\n'
        '${note.isEmpty ? '(the page is empty)' : note.render()}');
  }

  /// A page's text, through the app's own content provider.
  Future<NoteText> _noteOf(NotePage page) async {
    final fileId = page.driveFileId;
    if (fileId == null) return NoteText(title: page.title, blocks: const []);
    final raw = await loadContent(fileId);
    final document = afe.Document.fromJson(
      raw.containsKey('document') ? raw : <String, dynamic>{'document': raw},
    );
    return extractNoteText(document, title: page.title);
  }

  Future<String> _searchNotes(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 'Nothing to search for.';
    final index = await _load();
    final hits = <String>[];

    // Titles, across every notebook: cheap, and what people mostly mean.
    for (final ref in index.allPages()) {
      if (ref.page.title.toLowerCase().contains(q)) {
        hits.add('- "${ref.page.title}" — ${ref.where} (id ${ref.page.id}) '
            '— title matches');
      }
    }

    // Text, in the current notebook: every page is read, from the cache
    // where it can be, a few at a time. A page that cannot be read is
    // skipped rather than sinking the search.
    final pages = [
      for (final s in index.sectionsOf(bridge.notebookId))
        ...index.pagesOf(s.id),
    ];
    final others = pages.where((p) => p.id != bridge.pageId).toList();
    final texts = <(String, String, String)>[
      (bridge.pageId, bridge.pageTitle, bridge.readPage().render()),
    ];
    for (var i = 0; i < others.length; i += 4) {
      run?.detail(
          'reading ${math.min(i + 4, others.length)} of ${others.length} page(s)');
      final batch = others.sublist(i, math.min(i + 4, others.length));
      final notes = await Future.wait([
        for (final p in batch)
          _noteOf(p).then<NoteText?>((n) => n).catchError((_) => null),
      ]);
      for (var j = 0; j < batch.length; j++) {
        final note = notes[j];
        if (note != null) {
          texts.add((batch[j].id, batch[j].title, note.render()));
        }
      }
    }
    for (final (id, title, text) in texts) {
      final lines = text
          .split('\n')
          .where((l) => l.toLowerCase().contains(q))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .take(3)
          .map((l) => l.length <= 160 ? l : '${l.substring(0, 160)}…')
          .toList();
      if (lines.isEmpty) continue;
      final ref = index.pageRef(id);
      final where = ref == null ? 'this notebook' : ref.where;
      hits.add('- "$title" — $where (id $id):\n'
          '${lines.map((l) => '    $l').join('\n')}');
    }

    if (hits.isEmpty) {
      return 'No page matches "$query" by title in any notebook, or by text '
          'in the current one.';
    }
    final shown = hits.take(20).toList();
    return 'Matches for "$query":\n${shown.join('\n')}'
        '${hits.length > shown.length ? '\n(${hits.length - shown.length} more not shown)' : ''}';
  }

  Future<AgentActionResult> _webSearch(String query) async {
    final status = await webSearch.status();
    if (status != WebSearchStatus.ready) {
      return AgentActionResult.failed(
          'Web search is unavailable: ${status.reason}');
    }
    final sources = await webSearch.search(query, cancel: run?.cancelToken);
    if (sources.isEmpty) return const AgentActionResult.ok('No results.');
    run?.addSources(sources);
    // The project's injection boundary: results are fenced and labelled as
    // untrusted before the model sees them.
    return AgentActionResult.ok(renderSourcesForPrompt(sources));
  }

  // ------------------------------------------------------------ structure

  Future<AgentActionResult> _createNotebook(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return const AgentActionResult.failed('no name');
    if (uid.isEmpty) return const AgentActionResult.failed('not signed in');
    final now = DateTime.now();
    final id = await sync.createNotebook(Notebook(
      id: '',
      name: clean,
      ownerId: uid,
      createdAt: now,
      updatedAt: now,
    ));
    _index = null;
    return AgentActionResult.ok('Created notebook "$clean" (id $id). It has no '
        'sections yet: create_section with notebook "$clean" before adding '
        'pages to it.');
  }

  /// A section in a named notebook. The current notebook's sections are made
  /// by the editor bridge, so this only sees the other case.
  Future<AgentActionResult> _createSection(AgentAction action) async {
    final index = await _load();
    final notebook = action.notebook == null
        ? index.notebook(bridge.notebookId)
        : index.notebookNamed(action.notebook!);
    if (notebook == null) {
      return AgentActionResult.failed(
          'No notebook called "${action.notebook}". ${_notebookNames(index)}');
    }
    final sections = index.sectionsOf(notebook.id);
    final id = await sync.createSection(Section(
      id: '',
      notebookId: notebook.id,
      name: action.text,
      colorIndex: 2,
      order: sections.length,
    ));
    _index = null;
    return AgentActionResult.ok(
        'Created section "${action.text}" in "${notebook.name}" (id $id).');
  }

  /// A page in a named notebook — see [_createSection] for why only that.
  Future<AgentActionResult> _createPage(AgentAction action) async {
    final index = await _load();
    final notebook = action.notebook == null
        ? index.notebook(bridge.notebookId)
        : index.notebookNamed(action.notebook!);
    if (notebook == null) {
      return AgentActionResult.failed(
          'No notebook called "${action.notebook}". ${_notebookNames(index)}');
    }
    final sections = index.sectionsOf(notebook.id);
    if (sections.isEmpty) {
      return AgentActionResult.failed(
          '"${notebook.name}" has no sections; create_section there first.');
    }
    Section? section;
    if (action.section == null) {
      section = sections.first;
    } else {
      final wanted = action.section!.trim().toLowerCase();
      section = sections
          .where((s) => s.name.trim().toLowerCase() == wanted)
          .firstOrNull;
      if (section == null) {
        return AgentActionResult.failed(
            'No section called "${action.section}" in "${notebook.name}". '
            'Its sections: ${sections.map((s) => '"${s.name}"').join(', ')}');
      }
    }
    final now = DateTime.now();
    final id = await sync.createPage(
      NotePage(
        id: '',
        sectionId: section.id,
        notebookId: notebook.id,
        title: action.text,
        order: index.pagesOf(section.id).length,
        createdAt: now,
        updatedAt: now,
      ),
      document: _documentFor(action.content),
    );
    _index = null;
    return AgentActionResult.ok(
        'Created page "${action.text}" in ${section.name} · ${notebook.name} '
        '(id $id).');
  }

  /// Markdown into a page that is not open, through the content repository.
  ///
  /// The open page is written through the editor instead — the panel routes
  /// it there — so the user sees it happen and Undo covers it. A page that
  /// is not open has no editor; its file is read, changed and saved, and the
  /// next visit to it reads the saved copy.
  Future<AgentActionResult> _writePage(AgentAction action) async {
    if (isCurrentPage(action.page)) {
      return const AgentActionResult.failed(
          'the current page is written through the editor');
    }
    final found = await _findPage(action.page!, notebook: action.notebook);
    if (found == null) {
      return AgentActionResult.failed(_noSuchPage(action.page!));
    }
    final fileId = found.page.driveFileId;
    if (fileId == null) {
      return AgentActionResult.failed(
          '"${found.page.title}" has no content file yet; open it once first.');
    }
    final nodes = marioMarkdownToNodes(action.text);
    if (nodes.isEmpty) {
      return const AgentActionResult.failed('nothing to write');
    }

    final raw = Map<String, dynamic>.from(
        await content.load(fileId, revalidate: false));
    final existing = afe.Document.fromJson(
      raw.containsKey('document') ? raw : <String, dynamic>{'document': raw},
    );
    final old = [for (final n in existing.root.children) n.copyWith()];
    final children = switch (action.mode) {
      'prepend' => [...nodes, ...old],
      'replace' => nodes,
      _ => [...old, ...nodes],
    };
    final document = afe.Document(root: afe.pageNode(children: children));
    raw['document'] = document.toJson()['document'];
    await content.save(fileId, raw);
    await sync.updatePage(found.page.copyWith(updatedAt: DateTime.now()));
    final verb = switch (action.mode) {
      'prepend' => 'Wrote at the top of',
      'replace' => 'Replaced the body of',
      _ => 'Wrote into',
    };
    return AgentActionResult.ok(
        '$verb "${found.page.title}" (${found.where}).');
  }

  Future<AgentActionResult> _openPage(AgentAction action) async {
    if (isCurrentPage(action.page)) {
      return const AgentActionResult.ok('Already on that page.');
    }
    final found = await _findPage(action.page!, notebook: action.notebook);
    if (found == null) {
      return AgentActionResult.failed(_noSuchPage(action.page!));
    }
    onOpenPage(found.page);
    return AgentActionResult.ok(
        'Opened "${found.page.title}" (${found.where}).');
  }

  // ------------------------------------------------------------- helpers

  afe.Document? _documentFor(String markdown) {
    if (markdown.trim().isEmpty) return null;
    final nodes = marioMarkdownToNodes(markdown);
    if (nodes.isEmpty) return null;
    return afe.Document(root: afe.pageNode(children: nodes));
  }

  /// The page called [ref] — an id, an exact title, or a title containing
  /// the words — preferring the current notebook, then [notebook] if named.
  Future<MarioPageRef?> _findPage(String ref, {String? notebook}) async {
    final index = await _load();
    final r = ref.trim();
    final lower = r.toLowerCase();
    var candidates = index.allPages();
    if (notebook != null) {
      final nb = index.notebookNamed(notebook);
      if (nb != null) {
        candidates = candidates.where((p) => p.notebook.id == nb.id).toList();
      }
    }
    int rank(MarioPageRef p) => p.notebook.id == bridge.notebookId ? 0 : 1;
    MarioPageRef? best(bool Function(MarioPageRef) test) {
      final hits = candidates.where(test).toList()
        ..sort((a, b) => rank(a).compareTo(rank(b)));
      return hits.firstOrNull;
    }

    return best((p) => p.page.id == r) ??
        best((p) => p.page.title.trim().toLowerCase() == lower) ??
        best((p) => p.page.title.toLowerCase().contains(lower));
  }

  String _noSuchPage(String ref) =>
      'No page called "$ref". Use list_pages to see the titles, then name '
      'one exactly.';

  String _notebookNames(MarioIndex index) => index.notebooks.isEmpty
      ? 'There are no notebooks.'
      : 'Notebooks: ${index.notebooks.map((n) => '"${n.name}"').join(', ')}.';

  Future<MarioIndex> _load() async => _index ??= await loadIndex();
}

/// A snapshot of the notebook tree, for one run.
class MarioIndex {
  const MarioIndex(this.notebooks, this._sections, this._pages);

  final List<Notebook> notebooks;
  final Map<String, List<Section>> _sections;
  final Map<String, List<NotePage>> _pages;

  Notebook? notebook(String id) =>
      notebooks.where((n) => n.id == id).firstOrNull;

  Notebook? notebookNamed(String name) {
    final wanted = name.trim().toLowerCase();
    return notebooks
            .where((n) => n.name.trim().toLowerCase() == wanted)
            .firstOrNull ??
        notebooks
            .where((n) => n.name.toLowerCase().contains(wanted))
            .firstOrNull;
  }

  List<Section> sectionsOf(String notebookId) =>
      _sections[notebookId] ?? const [];

  List<NotePage> pagesOf(String sectionId) => _pages[sectionId] ?? const [];

  List<MarioPageRef> allPages() => [
        for (final nb in notebooks)
          for (final s in sectionsOf(nb.id))
            for (final p in pagesOf(s.id))
              MarioPageRef(page: p, section: s, notebook: nb),
      ];

  MarioPageRef? pageRef(String pageId) =>
      allPages().where((p) => p.page.id == pageId).firstOrNull;
}
