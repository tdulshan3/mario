/// What the agent can do, and how a model's proposal is turned into
/// something safe to execute.
///
/// **Plans, validated in Dart, in turns.** Each turn the model returns a
/// whole list of actions in one structured reply; the list is validated
/// here; then it runs. A turn may include reads — a page, a listing, a
/// search — whose results go back to the model for the next turn, which is
/// what lets it react to what it finds (see AgentTask). Structured plans
/// rather than native tool calls, deliberately:
///
///  * It works on every backend. Native tool calling is unreliable below
///    about 8B and diverges wildly between servers that all claim OpenAI
///    compatibility, whereas structured output already has a working
///    degradation path here (see LlmService.structured).
///  * Each turn is knowable before anything is touched, so the run gets one
///    snapshot and one Undo, the progress list can name each step, and a
///    preview can pause a turn when the user wants that.
///  * It cannot run away. A turn performs exactly the actions it lists, and
///    the loop has a hard turn limit.
///
/// Everything here is pure: no editor, no I/O. The executor and the tools
/// are separate, and this file is what the tests exercise.
library;

import '../../core/services/ai/json_coercion.dart';
import '../math/latex_normalizer.dart';

/// The operations an agent may perform.
///
/// An allowlist, not a filter. Anything absent is impossible rather than
/// discouraged — a model cannot invent `deleteNotebook` because there is no
/// case for it here.
enum AgentActionKind {
  paragraph,
  heading,
  bullets,
  numbered,
  todo,
  quote,
  divider,
  code,
  math,
  table,
  spreadsheet,
  htmlArtifact,
  renamePage,
  createPage,
  createSection,
  renameSection,
  createNotebook,
  replaceBlock,
  deleteBlock,
  moveBlock,
  setting,

  /// Any Markdown, as blocks, on the current page.
  markdown,

  /// Markdown into a named page — or the whole of the current one.
  writePage,

  /// The tools whose result comes back to the model: a read, a listing, a
  /// search. See [observingKinds].
  readPage,
  listNotebooks,
  listPages,
  searchNotes,
  webSearch,

  /// Switches the app to a page. The run ends there: the page it was editing
  /// closes.
  openPage,

  /// A question for the user. The run ends there too; the answer comes back
  /// as the next instruction, with this conversation as its context.
  askUser,
}

/// The kinds whose result is handed back to the model for its next turn.
const Set<AgentActionKind> observingKinds = {
  AgentActionKind.readPage,
  AgentActionKind.listNotebooks,
  AgentActionKind.listPages,
  AgentActionKind.searchNotes,
  AgentActionKind.webSearch,
};

extension AgentActionKindX on AgentActionKind {
  /// Whether the result comes back to the model.
  bool get observes => observingKinds.contains(this);

  /// Whether running it changes what the user has — anything but a read, a
  /// question, or moving to another page.
  bool get isWrite =>
      !observes &&
      this != AgentActionKind.askUser &&
      this != AgentActionKind.openPage;
}

/// What running one action produced: whether it worked and, for a read, a
/// listing or a search, what came back — or, on failure, why, so the model
/// can try another way rather than repeat the same one.
class AgentActionResult {
  const AgentActionResult.ok([this.text]) : ok = true;
  const AgentActionResult.failed([this.text]) : ok = false;

  final bool ok;
  final String? text;
}

/// The wire names the model uses. Kept short and obvious — a small model copies
/// these from the schema, and `insert_code_block_with_language` invites typos.
const _wireNames = <String, AgentActionKind>{
  'paragraph': AgentActionKind.paragraph,
  'heading': AgentActionKind.heading,
  'bullets': AgentActionKind.bullets,
  'numbered': AgentActionKind.numbered,
  'todo': AgentActionKind.todo,
  'quote': AgentActionKind.quote,
  'divider': AgentActionKind.divider,
  'code': AgentActionKind.code,
  'math': AgentActionKind.math,
  'table': AgentActionKind.table,
  'spreadsheet': AgentActionKind.spreadsheet,
  'html': AgentActionKind.htmlArtifact,
  'rename_page': AgentActionKind.renamePage,
  'create_page': AgentActionKind.createPage,
  'create_section': AgentActionKind.createSection,
  'rename_section': AgentActionKind.renameSection,
  'create_notebook': AgentActionKind.createNotebook,
  'markdown': AgentActionKind.markdown,
  'write_page': AgentActionKind.writePage,
  'read_page': AgentActionKind.readPage,
  'list_notebooks': AgentActionKind.listNotebooks,
  'list_pages': AgentActionKind.listPages,
  'search_notes': AgentActionKind.searchNotes,
  'web_search': AgentActionKind.webSearch,
  'open_page': AgentActionKind.openPage,
  'ask_user': AgentActionKind.askUser,
  'replace_block': AgentActionKind.replaceBlock,
  'delete_block': AgentActionKind.deleteBlock,
  'move_block': AgentActionKind.moveBlock,
  'setting': AgentActionKind.setting,
};

/// Names a model reaches for that mean one of the [AgentActionKind]s.
///
/// The schema lists the sixteen names above, but on a backend without strict
/// decoding the schema is advice, not a constraint — and a model that has seen
/// AppFlowy or Notion document JSON writes what it saw there. This app's own
/// blocks are called `bulleted_list`, `numbered_list` and `todo_list`, so those
/// are the first names to hand.
///
/// The shape of that failure is what made it worth fixing: `heading` and
/// `paragraph` are spelled the same in both vocabularies, so a model using the
/// other names loses precisely its lists and keeps its headings — which is
/// exactly the plan that came back as nothing but a heading.
///
/// `title` is deliberately absent. It is at least as likely to mean the page
/// title, and guessing wrong turns an intended rename into an inserted
/// heading; better to drop it and be told than to do the wrong thing quietly.
const _kindAliases = <String, AgentActionKind>{
  'text': AgentActionKind.paragraph,
  'p': AgentActionKind.paragraph,
  'insert_markdown': AgentActionKind.markdown,
  'write': AgentActionKind.markdown,
  'insert': AgentActionKind.markdown,
  'append': AgentActionKind.markdown,
  'write_to_page': AgentActionKind.writePage,
  'append_page': AgentActionKind.writePage,
  'update_page': AgentActionKind.writePage,
  'edit_page': AgentActionKind.writePage,
  'get_page': AgentActionKind.readPage,
  'read': AgentActionKind.readPage,
  'view_page': AgentActionKind.readPage,
  'list_sections': AgentActionKind.listNotebooks,
  'notebooks': AgentActionKind.listNotebooks,
  'pages': AgentActionKind.listPages,
  'find_pages': AgentActionKind.listPages,
  'search': AgentActionKind.searchNotes,
  'find': AgentActionKind.searchNotes,
  'search_pages': AgentActionKind.searchNotes,
  'grep': AgentActionKind.searchNotes,
  'search_web': AgentActionKind.webSearch,
  'browse': AgentActionKind.webSearch,
  'lookup': AgentActionKind.webSearch,
  'google': AgentActionKind.webSearch,
  'new_notebook': AgentActionKind.createNotebook,
  'add_notebook': AgentActionKind.createNotebook,
  'navigate': AgentActionKind.openPage,
  'go_to_page': AgentActionKind.openPage,
  'show_page': AgentActionKind.openPage,
  'goto': AgentActionKind.openPage,
  'ask': AgentActionKind.askUser,
  'question': AgentActionKind.askUser,
  'clarify': AgentActionKind.askUser,
  'ask_question': AgentActionKind.askUser,
  'header': AgentActionKind.heading,
  'h1': AgentActionKind.heading,
  'h2': AgentActionKind.heading,
  'h3': AgentActionKind.heading,
  'h4': AgentActionKind.heading,
  'h5': AgentActionKind.heading,
  'h6': AgentActionKind.heading,
  'bulleted_list': AgentActionKind.bullets,
  'bullet_list': AgentActionKind.bullets,
  'bulleted': AgentActionKind.bullets,
  'unordered_list': AgentActionKind.bullets,
  'list': AgentActionKind.bullets,
  'numbered_list': AgentActionKind.numbered,
  'ordered_list': AgentActionKind.numbered,
  'todo_list': AgentActionKind.todo,
  'to_do': AgentActionKind.todo,
  'to_do_list': AgentActionKind.todo,
  'checklist': AgentActionKind.todo,
  'check_list': AgentActionKind.todo,
  'checkbox': AgentActionKind.todo,
  'task': AgentActionKind.todo,
  'tasks': AgentActionKind.todo,
  'code_block': AgentActionKind.code,
  'codeblock': AgentActionKind.code,
  'html_artifact': AgentActionKind.htmlArtifact,
  'webpage': AgentActionKind.htmlArtifact,
  'website': AgentActionKind.htmlArtifact,
  'math_equation': AgentActionKind.math,
  'equation': AgentActionKind.math,
  'formula': AgentActionKind.math,
  'blockquote': AgentActionKind.quote,
  'callout': AgentActionKind.quote,
  'hr': AgentActionKind.divider,
  'horizontal_rule': AgentActionKind.divider,
  'rename': AgentActionKind.renamePage,
  'rename_title': AgentActionKind.renamePage,
  'new_page': AgentActionKind.createPage,
  'add_page': AgentActionKind.createPage,
  'new_section': AgentActionKind.createSection,
  'add_section': AgentActionKind.createSection,
  'update_block': AgentActionKind.replaceBlock,
  'edit_block': AgentActionKind.replaceBlock,
  'remove_block': AgentActionKind.deleteBlock,
};

/// Settings an agent may change.
///
/// Deliberately tiny, and deliberately not a general key/value setter. Nothing
/// here can cost money, leak a note, or lock the user out: an agent that could
/// write `anthropic_api_key` or repoint the model URL would be a way to talk
/// someone's notes into reconfiguring their own backend.
const agentWritableSettings = <String>{
  'theme',
  'fontScale',
  'canvasWidth',
  'spellCheck',
  'autoCorrectMath',
};

class AgentAction {
  const AgentAction({
    required this.kind,
    this.text = '',
    this.items = const [],
    this.rows = const [],
    this.level = 2,
    this.language = 'plaintext',
    this.blockId,
    this.afterBlockId,
    this.settingKey,
    this.settingValue,
    this.section,
    this.content = '',
    this.page,
    this.notebook,
    this.mode = 'append',
  });

  final AgentActionKind kind;
  final String text;
  final List<String> items;

  /// Row-major, as a person would write a table.
  final List<List<String>> rows;

  final int level;
  final String language;

  /// Target for replace/delete.
  final String? blockId;

  /// Where to insert. Null appends at the end of the page.
  final String? afterBlockId;

  final String? settingKey;
  final String? settingValue;

  /// A section named by the model — where a new page goes, or which section
  /// to rename. Null means the section this page is in.
  final String? section;

  /// Markdown for a new page's body. Empty makes a blank page.
  final String content;

  /// A page, by title or id — the target of write_page, read_page and
  /// open_page. Null means the current page.
  final String? page;

  /// A notebook, by name, for anything aimed outside the current one. Null
  /// means the current notebook.
  final String? notebook;

  /// For write_page: append, prepend or replace.
  final String mode;

  /// A short line for the progress list, in the past tense once done.
  String get summary => switch (kind) {
        AgentActionKind.paragraph => 'Added a paragraph',
        AgentActionKind.heading => 'Added heading "${_clip(text)}"',
        AgentActionKind.bullets => 'Added ${items.length} bullet(s)',
        AgentActionKind.numbered => 'Added a numbered list of ${items.length}',
        AgentActionKind.todo => 'Added ${items.length} to-do(s)',
        AgentActionKind.quote => 'Added a quote',
        AgentActionKind.divider => 'Added a divider',
        AgentActionKind.code => 'Added a $language code block',
        AgentActionKind.math => 'Added a formula',
        AgentActionKind.table =>
          'Added a ${rows.length}x${rows.isEmpty ? 0 : rows.first.length} table',
        AgentActionKind.spreadsheet => 'Added a spreadsheet',
        AgentActionKind.htmlArtifact => 'Created an HTML artifact preview',
        AgentActionKind.renamePage => 'Renamed the page to "${_clip(text)}"',
        AgentActionKind.createPage => section == null
            ? 'Created page "${_clip(text)}"'
            : 'Created page "${_clip(text)}" in ${_clip(section!)}',
        AgentActionKind.createSection => 'Created section "${_clip(text)}"',
        AgentActionKind.renameSection => section == null
            ? 'Renamed this section to "${_clip(text)}"'
            : 'Renamed section ${_clip(section!)} to "${_clip(text)}"',
        AgentActionKind.createNotebook => 'Created notebook "${_clip(text)}"',
        AgentActionKind.markdown => 'Added ${_lineCount(text)} line(s)',
        AgentActionKind.writePage => switch (mode) {
            'replace' => 'Replaced the body of ${_pageName()}',
            'prepend' => 'Wrote at the top of ${_pageName()}',
            _ => 'Wrote into ${_pageName()}',
          },
        AgentActionKind.readPage => 'Read ${_pageName()}',
        AgentActionKind.listNotebooks => 'Listed the notebooks',
        AgentActionKind.listPages => section == null
            ? 'Listed the pages'
            : 'Listed the pages in ${_clip(section!)}',
        AgentActionKind.searchNotes =>
          'Searched the notes for "${_clip(text)}"',
        AgentActionKind.webSearch => 'Searched the web for "${_clip(text)}"',
        AgentActionKind.openPage => 'Opened ${_pageName()}',
        AgentActionKind.askUser => 'Asked: ${_clip(text)}',
        AgentActionKind.replaceBlock => 'Rewrote a block',
        AgentActionKind.deleteBlock => 'Deleted a block',
        AgentActionKind.moveBlock => 'Moved a block',
        AgentActionKind.setting => 'Changed $settingKey to $settingValue',
      };

  /// True for anything that removes or overwrites the user's existing words, as
  /// opposed to adding new ones. Surfaced separately in the UI, because
  /// "added 3 things" and "deleted 3 things" deserve different attention.
  bool get isDestructive =>
      kind == AgentActionKind.deleteBlock ||
      kind == AgentActionKind.replaceBlock ||
      (kind == AgentActionKind.writePage && mode == 'replace');

  String _pageName() => page == null ? 'this page' : 'page "${_clip(page!)}"';

  static int _lineCount(String s) =>
      s.split('\n').where((l) => l.trim().isNotEmpty).length;

  static String _clip(String s) =>
      s.length <= 40 ? s : '${s.substring(0, 40)}…';
}

/// The schema handed to the model.
///
/// One flat action object with optional fields, rather than a union per kind:
/// a small model copies a flat shape far more reliably than a discriminated
/// one, and the validation below rejects whatever comes back wrong anyway.
const agentPlanSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'summary': {
      'type': 'string',
      'description': 'One sentence saying what you are about to do.',
    },
    'actions': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'kind': {
            'type': 'string',
            'enum': [
              'paragraph',
              'heading',
              'bullets',
              'numbered',
              'todo',
              'quote',
              'divider',
              'code',
              'math',
              'table',
              'spreadsheet',
              'html',
              'rename_page',
              'create_page',
              'create_section',
              'rename_section',
              'create_notebook',
              'markdown',
              'write_page',
              'read_page',
              'list_notebooks',
              'list_pages',
              'search_notes',
              'web_search',
              'open_page',
              'ask_user',
              'replace_block',
              'delete_block',
              'move_block',
              'setting',
            ],
          },
          'text': {
            'type': 'string',
            'description': 'Body text. For rename_page, the new title. For '
                'create_page, the new page\'s title. For create_section and '
                'rename_section, the section\'s name. For replace_block, the '
                'replacement text. For html, the complete self-contained HTML '
                'document.',
          },
          'section': {
            'type': 'string',
            'description': 'A section name: for create_page, where the page '
                'goes; for rename_section, which section. Omit for the '
                'section this page is in.',
          },
          'content': {
            'type': 'string',
            'description': 'For create_page: Markdown for the new page\'s '
                'body. Omit for an empty page.',
          },
          'page': {
            'type': 'string',
            'description': 'A page title or id, for write_page, read_page '
                'and open_page. Omit write_page\'s for the current page.',
          },
          'notebook': {
            'type': 'string',
            'description': 'A notebook name, for list_pages, create_page, '
                'create_section and write_page aimed at another notebook. '
                'Omit for the current one.',
          },
          'mode': {
            'type': 'string',
            'enum': ['append', 'prepend', 'replace'],
            'description': 'For write_page: where the Markdown goes. '
                'Default append.',
          },
          'items': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'List entries, for bullets/numbered/todo.',
          },
          'rows': {
            'type': 'array',
            'items': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'description':
                'Table or spreadsheet rows, first row being the header.',
          },
          'level': {
            'type': 'integer',
            'minimum': 2,
            'maximum': 6,
            'description': 'Heading level, 2-6. The page title is the only '
                'level 1, so a heading added to the body starts at 2.',
          },
          'language': {'type': 'string', 'description': 'Code language.'},
          'blockId': {
            'type': 'string',
            'description': 'Existing block to replace, delete or move.',
          },
          'afterBlockId': {
            'type': 'string',
            'description': 'Insert, or move, to just after this block. Omit '
                'to place at the end.',
          },
          'settingKey': {
            'type': 'string',
            'enum': [
              'theme',
              'fontScale',
              'canvasWidth',
              'spellCheck',
              'autoCorrectMath',
            ],
          },
          'settingValue': {'type': 'string'},
        },
        'required': ['kind'],
      },
    },
    'done': {
      'type': 'boolean',
      'description': 'True when the work is finished after these actions. '
          'False when you need the results of read_page, list_notebooks, '
          'list_pages, search_notes or web_search before the next step.',
    },
    'followUps': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'Up to three short next instructions the user might '
          'want, worded the way they would type them.',
    },
  },
  'required': ['summary', 'actions'],
};

/// One action the validator refused, and why.
///
/// The reason is the whole point. A bare count made every rejection look the
/// same and, worse, made them all look deliberate — the panel could only say
/// "rejected as unsafe", which is true of a setting outside the allowlist and
/// false of the far commoner case: a to-do the model wrote in a shape the
/// parser did not read. One is a guard doing its job; the other is a bug, and
/// a count cannot tell them apart.
class DroppedAction {
  const DroppedAction({required this.kind, required this.reason});

  /// Whatever the model called it, as written. Empty when it named nothing.
  final String kind;

  /// A short phrase, lowercase, no trailing stop — it is composed into a
  /// sentence by the caller.
  final String reason;

  @override
  String toString() => kind.isEmpty ? reason : '$kind: $reason';
}

/// A validated plan, plus what had to be thrown away.
class AgentPlan {
  const AgentPlan({
    required this.summary,
    required this.actions,
    this.rejected = const [],
    this.done = true,
    this.followUps = const [],
  });

  final String summary;
  final List<AgentAction> actions;

  /// False when the model wants the results of this turn's reads before it
  /// decides the next step. Reads force another turn regardless.
  final bool done;

  /// Suggested next instructions, for the user to tap.
  final List<String> followUps;

  /// Actions the model proposed that could not be made safe or made sense of.
  /// Reported rather than hidden: "9 of 11 steps" is information the user needs
  /// to judge the result.
  final List<DroppedAction> rejected;

  int get dropped => rejected.length;

  bool get isEmpty => actions.isEmpty;
  int get destructiveCount => actions.where((a) => a.isDestructive).length;

  /// The reasons, deduplicated and counted — "2 x unknown kind" rather than the
  /// same phrase twice.
  List<String> get rejectionSummary {
    final counts = <String, int>{};
    for (final r in rejected) {
      counts[r.reason] = (counts[r.reason] ?? 0) + 1;
    }
    return [
      for (final e in counts.entries)
        e.value == 1 ? e.key : '${e.key} (x${e.value})',
    ];
  }
}

/// Turns a model reply into a plan, discarding anything unusable.
///
/// Every rejection is decidable here, without asking a model: an unknown kind,
/// a heading with no text, a table with ragged rows, a delete with no target, a
/// setting outside the allowlist. A dropped action costs one step; an action
/// executed on a guess costs the user's notes.
AgentPlan parseAgentPlan(Map<String, dynamic> raw,
    {Set<String>? knownBlockIds}) {
  // The raw list, not just its object entries: `"actions": ["add a todo"]` used
  // to vanish entirely and be reported as "the model proposed no changes",
  // which sent anyone debugging it in exactly the wrong direction.
  final rawList = raw['actions'] is List ? raw['actions'] as List : const [];
  final actions = <AgentAction>[];
  final rejected = <DroppedAction>[];

  for (final entry in rawList) {
    final m = asMap(entry);
    if (m == null) {
      rejected
          .add(const DroppedAction(kind: '', reason: 'not an action object'));
      continue;
    }
    final action = _parseOne(m, knownBlockIds, rejected);
    if (action != null) actions.add(action);
  }

  return AgentPlan(
    summary: asStringOr(raw['summary']).trim(),
    actions: actions,
    rejected: rejected,
    done: asBool(raw['done'] ?? raw['finished'] ?? raw['complete'],
        fallback: true),
    followUps: asStringList(
            raw['followUps'] ?? raw['follow_ups'] ?? raw['suggestions'])
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .take(3)
        .toList(),
  );
}

/// Kinds that actually consume [AgentAction.blockId]. For everything else the
/// field is meaningless, and — before this distinction existed — fatal.
const _targetedKinds = <AgentActionKind>{
  AgentActionKind.replaceBlock,
  AgentActionKind.deleteBlock,
  AgentActionKind.moveBlock,
};

/// List entries, however the model chose to shape them.
///
/// [asStringList] keeps only entries that are already strings, which loses the
/// most natural shape a model reaches for on a to-do: `[{"text": "Draft it",
/// "checked": false}]`. A to-do *has* a done flag, so an object per entry is
/// the obvious echo of what a note app's own JSON looks like — and losing it
/// silently deleted whole lists.
List<String> _readEntries(Object? v) {
  if (v is! List) return asStringList(v);
  final out = <String>[];
  for (final e in v) {
    final direct = asString(e);
    if (direct != null) {
      if (direct.trim().isNotEmpty) out.add(direct);
      continue;
    }
    final o = asMap(e);
    if (o == null) continue;
    final s = asStringOr(
        o['text'] ?? o['content'] ?? o['name'] ?? o['title'] ?? o['label']);
    if (s.trim().isNotEmpty) out.add(s);
  }
  return out;
}

/// A block id as the model wrote it, matched to one the page actually has.
///
/// The prompt prints ids as `[id:ab12cd]`, so a model copying an id back
/// copies the brackets with it — and a target that does not match exactly is
/// dropped, because acting on a wrong id would edit the wrong block. Stripping
/// the decoration the prompt itself added is not a guess.
///
/// The case-insensitive fallback is used only when it is unambiguous: nanoid
/// ids are case-sensitive, so two live blocks can differ by case alone, and
/// picking one of them would be exactly the wrong-block edit this guards.
String? _normaliseId(String? raw, Set<String>? known) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return s;

  final bracketed = RegExp(r'^\[\s*id\s*:\s*([^\]\s]+)\s*\]$').firstMatch(s);
  if (bracketed != null) s = bracketed.group(1)!;
  s = s.replaceFirst(RegExp(r'^id\s*[:=]\s*'), '');
  // Quotes, brackets and sentence punctuation a model trailed onto the id.
  s = s.replaceAll(RegExp(r'^[\s"\x27`(\[]+|[\s"\x27`).,;:\]]+$'), '');

  if (known == null || known.contains(s)) return s;
  final ci = known.where((k) => k.toLowerCase() == s.toLowerCase()).toList();
  return ci.length == 1 ? ci.first : s;
}

/// Reads replacement content from the shapes unconstrained models commonly
/// choose. A few models wrap it as `{ "replacement": { "text": "..." } }`
/// instead of using the schema's top-level `text`; that is still unambiguous,
/// so it is safe to recover rather than discarding the rewrite.
String? _readReplacementText(Object? raw) {
  final direct = asString(raw);
  if (direct != null && direct.trim().isNotEmpty) return direct;
  final wrapped = asMap(raw);
  if (wrapped == null) return null;
  for (final candidate in [
    wrapped['text'],
    wrapped['content'],
    wrapped['body'],
    wrapped['value'],
  ]) {
    final text = asString(candidate);
    if (text != null && text.trim().isNotEmpty) return text;
  }
  return null;
}

/// Whether the model wrote a replacement field at all, even an empty one.
bool _replacementGiven(Map<String, dynamic> m) => const [
      'text',
      'content',
      'body',
      'value',
      'replacement',
      'replacementText',
      'replacement_text',
      'newText',
      'new_text',
      'replacementContent',
      'replacement_content',
      'newContent',
      'new_content',
    ].any((k) => m[k] is String);

String _firstReplacementText(Iterable<Object?> values) {
  for (final value in values) {
    final text = _readReplacementText(value);
    if (text != null) return text.trim();
  }
  return '';
}

AgentAction? _parseOne(Map<String, dynamic> m, Set<String>? knownBlockIds,
    List<DroppedAction> rejected) {
  // `kind` is the discriminator and had no alias of its own, unlike every
  // other field here.
  final wire = asStringOr(m['kind'] ?? m['type'] ?? m['action'] ?? m['op'])
      .trim()
      .toLowerCase();
  final kind = _wireNames[wire] ?? _kindAliases[wire];
  if (kind == null) {
    rejected.add(DroppedAction(
      kind: wire,
      reason: wire.isEmpty ? 'no action kind given' : 'not an action Mario has',
    ));
    return null;
  }

  // Field aliases, because the schema is advisory on any backend without
  // strict decoding and models reach for the obvious synonym.
  final text = _firstReplacementText([
    m['text'],
    m['content'],
    m['body'],
    m['value'],
    if (kind == AgentActionKind.replaceBlock) ...[
      m['replacement'],
      m['replacementText'],
      m['replacement_text'],
      m['newText'],
      m['new_text'],
      m['replacementContent'],
      m['replacement_content'],
      m['newContent'],
      m['new_content'],
    ],
  ]);
  // Two views of the same field. List entries are trimmed, because leading
  // space in a bullet is noise; a code body is not, because indentation is
  // the difference between Python that runs and Python that does not.
  final rawItems = _readEntries(m['items'] ??
      m['list'] ??
      m['bullets'] ??
      m['todos'] ??
      m['tasks'] ??
      m['steps'] ??
      m['entries']);
  final items =
      rawItems.map((i) => i.trim()).where((i) => i.isNotEmpty).toList();

  var blockId = _normaliseId(
      asString(m['blockId'] ?? m['block_id'])?.trim(), knownBlockIds);
  var afterBlockId = _normaliseId(
      asString(m['afterBlockId'] ?? m['after_block_id'])?.trim(),
      knownBlockIds);

  // A blockId on an *insert* almost always means "put it here" — the model
  // reaching for the only id field it can see. Treating that as a target used
  // to drop the whole action, which is why a plan could come back as nothing
  // but the handful of headings that happened to carry no id.
  if (!_targetedKinds.contains(kind) && blockId != null && blockId.isNotEmpty) {
    afterBlockId ??= blockId;
    blockId = null;
  }

  if (knownBlockIds != null) {
    // A target that does not exist is a hallucinated id, and acting on it
    // would hit whatever block happens to be there. Only fatal for the kinds
    // that need one — there is nothing to do without it.
    if (_targetedKinds.contains(kind) &&
        blockId != null &&
        blockId.isNotEmpty &&
        !knownBlockIds.contains(blockId)) {
      rejected.add(DroppedAction(
          kind: wire, reason: 'points at a block that is not on this page'));
      return null;
    }
    if (afterBlockId != null &&
        afterBlockId.isNotEmpty &&
        !knownBlockIds.contains(afterBlockId)) {
      // Not fatal: append rather than discard the content.
      return _build(
          kind, m, wire, text, items, rawItems, blockId, null, rejected);
    }
  }

  return _build(
      kind, m, wire, text, items, rawItems, blockId, afterBlockId, rejected);
}

AgentAction? _build(
  AgentActionKind kind,
  Map<String, dynamic> m,
  String wire,
  String text,
  List<String> items,
  List<String> rawItems,
  String? blockId,
  String? afterBlockId,
  List<DroppedAction> rejected,
) {
  AgentAction? reject(String reason) {
    rejected.add(DroppedAction(kind: wire, reason: reason));
    return null;
  }

  switch (kind) {
    case AgentActionKind.paragraph:
    case AgentActionKind.quote:
      // Body delivered as a list rather than a string: join it instead of
      // discarding a paragraph the model did write.
      final body = text.isNotEmpty ? text : items.join('\n');
      if (body.isEmpty) return reject('no text to add');
      return AgentAction(kind: kind, text: body, afterBlockId: afterBlockId);

    case AgentActionKind.heading:
      if (text.isEmpty) return reject('a heading with no words');
      return AgentAction(
        kind: kind,
        text: text,
        // 2, not 1: the page already has a title, and a level-1 heading in the
        // body competes with it. The same house style is in the prompt, but
        // `level` is optional and an omitted field defaulted to a second title.
        level: (asInt(m['level']) ?? 2).clamp(2, 6),
        afterBlockId: afterBlockId,
      );

    case AgentActionKind.bullets:
    case AgentActionKind.numbered:
    case AgentActionKind.todo:
      // Recover a list whose body arrived in `text`, exactly as paragraph and
      // code already recover a body that arrived in `items`. A one-entry list
      // is a string to most models — "add a todo for X" produces
      // {"kind":"todo","text":"X"} far more often than a one-element array —
      // and requiring the array dropped the action outright.
      final entries = items.isNotEmpty ? items : _splitEntries(text);
      if (entries.isEmpty) return reject('a list with no entries');
      return AgentAction(
          kind: kind, items: entries, afterBlockId: afterBlockId);

    case AgentActionKind.divider:
      return AgentAction(kind: kind, afterBlockId: afterBlockId);

    case AgentActionKind.code:
      // rawItems, not items: trimming would flatten the indentation.
      final code = text.isNotEmpty ? text : rawItems.join('\n');
      if (code.isEmpty) return reject('a code block with no code');
      final language = asStringOr(m['language'], 'plaintext').trim();
      return AgentAction(
        kind: kind,
        text: code,
        language: language.isEmpty ? 'plaintext' : language,
        afterBlockId: afterBlockId,
      );

    case AgentActionKind.htmlArtifact:
      // An artifact is allowed to be a fragment (the preview wrapper supplies
      // the document shell), but it must contain real markup. Plain prose in
      // an `html` action is almost always a model choosing the wrong kind.
      final html = text.isNotEmpty ? text : rawItems.join('\n');
      if (html.isEmpty ||
          !RegExp(r'<[a-z][^>]*>', caseSensitive: false).hasMatch(html)) {
        return reject('an HTML artifact with no HTML');
      }
      return AgentAction(kind: kind, text: html);

    case AgentActionKind.math:
      final formula = normalizeLatexFormula(text);
      if (formula.isEmpty) return reject('a formula with no LaTeX');
      return AgentAction(
        kind: kind,
        text: formula,
        afterBlockId: afterBlockId,
      );

    case AgentActionKind.table:
    case AgentActionKind.spreadsheet:
      final rows = _normaliseRows(m['rows']);
      if (rows == null) {
        return reject(
            'rows that are missing, ragged or far too many — there is '
            'no safe way to square them up');
      }
      return AgentAction(
        kind: kind,
        rows: rows,
        text: text,
        afterBlockId: afterBlockId,
      );

    case AgentActionKind.renamePage:
      if (text.isEmpty) return reject('a rename with no new title');
      // A title is one line; a model that returns a paragraph here would give
      // the page a name nothing can display.
      return AgentAction(kind: kind, text: _firstLine(text));

    case AgentActionKind.createPage:
      // Read raw rather than through `text`, which falls back to `content`:
      // a page whose only field is its body must not take that body as its
      // title.
      final title = _firstString([m['title'], m['name'], m['text']]);
      if (title.isEmpty) return reject('a new page with no title');
      return AgentAction(
        kind: kind,
        text: _firstLine(title),
        section: _sectionOf(m),
        notebook: _notebookOf(m),
        content: asStringOr(m['content'] ?? m['body'] ?? m['markdown']).trim(),
      );

    case AgentActionKind.createSection:
      final name = _firstString([m['name'], m['title'], m['text']]);
      if (name.isEmpty) return reject('a new section with no name');
      return AgentAction(
          kind: kind, text: _firstLine(name), notebook: _notebookOf(m));

    case AgentActionKind.createNotebook:
      final name = _firstString([m['name'], m['title'], m['text']]);
      if (name.isEmpty) return reject('a new notebook with no name');
      return AgentAction(kind: kind, text: _firstLine(name));

    case AgentActionKind.markdown:
      // rawItems, not items: a code fence inside keeps its indentation.
      final body = text.isNotEmpty ? text : rawItems.join('\n');
      if (body.isEmpty) return reject('markdown with nothing in it');
      return AgentAction(kind: kind, text: body, afterBlockId: afterBlockId);

    case AgentActionKind.writePage:
      final body = text.isNotEmpty ? text : rawItems.join('\n');
      if (body.isEmpty) return reject('a page write with nothing to write');
      return AgentAction(
        kind: kind,
        text: body,
        page: _pageOf(m),
        notebook: _notebookOf(m),
        mode: _modeOf(m),
      );

    case AgentActionKind.readPage:
    case AgentActionKind.openPage:
      final page = _pageOf(m, orTitle: true);
      if (page == null) return reject('no page named');
      return AgentAction(kind: kind, page: page, notebook: _notebookOf(m));

    case AgentActionKind.listNotebooks:
      return AgentAction(kind: kind);

    case AgentActionKind.listPages:
      return AgentAction(
          kind: kind, notebook: _notebookOf(m), section: _sectionOf(m));

    case AgentActionKind.searchNotes:
    case AgentActionKind.webSearch:
      final query = _firstString([m['text'], m['query'], m['q'], m['search']]);
      if (query.isEmpty) return reject('a search with no query');
      return AgentAction(kind: kind, text: _firstLine(query));

    case AgentActionKind.askUser:
      final question = _firstString([m['text'], m['question'], m['prompt']]);
      if (question.isEmpty) return reject('a question with no words');
      return AgentAction(kind: kind, text: question);

    case AgentActionKind.renameSection:
      final name = _firstString(
          [m['text'], m['name'], m['newName'], m['new_name'], m['title']]);
      if (name.isEmpty) return reject('a rename with no new name');
      return AgentAction(
        kind: kind,
        text: _firstLine(name),
        section: _sectionOf(m),
      );

    case AgentActionKind.replaceBlock:
      // Same recovery in the other direction: "rewrite this as a task plus an
      // action" naturally produces a list, and dropping it wasted a valid
      // target the model had correctly identified.
      final body = text.isNotEmpty ? text : items.join('\n');
      if (blockId == null || blockId.isEmpty) {
        return reject('a rewrite with no block to rewrite');
      }
      if (body.isEmpty) {
        // "Replace this with nothing" is a delete, and it is what a model
        // says when told to strip something a block consists of entirely —
        // "remove the HTML tags" on a line that is only `</div>` came back
        // as three empty rewrites, all refused. A replacement the model
        // never supplied at all is still a mistake, and still refused.
        if (_replacementGiven(m)) {
          return AgentAction(
              kind: AgentActionKind.deleteBlock, blockId: blockId);
        }
        return reject('a rewrite with no replacement text');
      }
      return AgentAction(kind: kind, blockId: blockId, text: body);

    case AgentActionKind.deleteBlock:
      if (blockId == null || blockId.isEmpty) {
        return reject('a delete with no block to delete');
      }
      return AgentAction(kind: kind, blockId: blockId);

    case AgentActionKind.moveBlock:
      if (blockId == null || blockId.isEmpty) {
        return reject('a move with no block to move');
      }
      // Moving a block to just after itself is a no-op that still costs a
      // transaction and reads as a change in the result list.
      if (afterBlockId == blockId) {
        return reject('a move to where the block already is');
      }
      return AgentAction(
        kind: kind,
        blockId: blockId,
        afterBlockId: afterBlockId,
      );

    case AgentActionKind.setting:
      final key = asString(m['settingKey'])?.trim();
      final value = asString(m['settingValue'])?.trim();
      if (key == null || value == null || value.isEmpty) {
        return reject('a setting with no name or no value');
      }
      // The one rejection that really is about safety.
      if (!agentWritableSettings.contains(key)) {
        return reject('"$key" is not a setting Mario lets the model change');
      }
      return AgentAction(kind: kind, settingKey: key, settingValue: value);
  }
}

/// The first line of a name or title; the rest would be a name nothing can
/// display.
String _firstLine(String s) => s.split('\n').first.trim();

/// The first candidate that is a non-empty string.
String _firstString(List<Object?> candidates) {
  for (final c in candidates) {
    final s = asString(c)?.trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return '';
}

/// The section a model named, or null for this page's own.
String? _sectionOf(Map<String, dynamic> m) {
  final s =
      asString(m['section'] ?? m['sectionName'] ?? m['section_name'])?.trim();
  return s == null || s.isEmpty ? null : s;
}

/// The notebook a model named, or null for the current one.
String? _notebookOf(Map<String, dynamic> m) {
  final s = asString(m['notebook'] ?? m['notebookName'] ?? m['notebook_name'])
      ?.trim();
  return s == null || s.isEmpty ? null : s;
}

/// The page a model named — by title or id — or null for the current one.
/// [orTitle] also reads `title`, `name` and `text`, for the kinds where
/// those can only mean the target page.
String? _pageOf(Map<String, dynamic> m, {bool orTitle = false}) {
  final s = _firstString([
    m['page'],
    m['pageTitle'],
    m['page_title'],
    m['pageId'],
    m['page_id'],
    if (orTitle) m['title'],
    if (orTitle) m['name'],
    if (orTitle) m['text'],
  ]);
  return s.isEmpty ? null : s;
}

/// append, prepend or replace — however the model spelt it.
String _modeOf(Map<String, dynamic> m) {
  final raw =
      asStringOr(m['mode'] ?? m['position'] ?? m['where']).trim().toLowerCase();
  return switch (raw) {
    'prepend' || 'start' || 'top' || 'beginning' || 'before' => 'prepend',
    'replace' || 'overwrite' || 'rewrite' || 'set' => 'replace',
    _ => 'append',
  };
}

/// One block of prose read as list entries.
///
/// Lines first, then the numbered or bulleted markers a model writes when it
/// puts a whole list into a single string. A body with neither is one entry —
/// which is the common case, and the one that used to be thrown away.
List<String> _splitEntries(String text) {
  if (text.trim().isEmpty) return const [];
  final lines = text
      .split('\n')
      .map((l) =>
          l.replaceFirst(RegExp(r'^\s*(?:[-*\u2022]|\d+[.)])\s+'), '').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return lines;
}

/// Squares up a table, or rejects it.
///
/// Ragged rows are the common model failure and there is no safe repair: a
/// short row could be a missing leading cell or a missing trailing one, and
/// padding the wrong end silently shifts every value into the wrong column.
List<List<String>>? _normaliseRows(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final rows = <List<String>>[];
  for (final r in raw) {
    final cells = asStringList(r);
    if (cells.isEmpty) continue;
    rows.add(cells);
  }
  if (rows.isEmpty) return null;

  final width = rows.first.length;
  if (width == 0) return null;
  if (rows.any((r) => r.length != width)) return null;
  // A guard against a model emitting a whole dataset into a note.
  if (rows.length > 200 || width > 30) return null;
  return rows;
}
