/// What the agent is allowed to do to a page, and how a model's proposal is
/// turned into something safe to execute.
///
/// **Plan-then-execute, not a tool-call loop.** The model returns the whole
/// list of actions in one structured reply; the list is validated in Dart; then
/// it runs. That is a deliberate choice over the usual back-and-forth:
///
///  * It works on every backend. Native tool calling is unreliable below about
///    8B and diverges wildly between servers that all claim OpenAI
///    compatibility, whereas structured output already has a working
///    degradation path here (see LlmService.structured).
///  * The plan is knowable before anything is touched, so the whole run gets
///    one snapshot and one Undo, and the progress list can name each step
///    before it happens.
///  * It cannot run away. A loop that re-reads the document after each edit can
///    decide to keep going; a list of nine actions performs nine actions.
///
/// The cost is that the model cannot react to what it finds mid-run. For
/// "add a table summarising this" that does not matter.
///
/// Everything here is pure: no editor, no I/O. The executor is separate, and
/// this file is what the tests exercise.
library;

import '../../core/services/ai/json_coercion.dart';

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
  renamePage,
  replaceBlock,
  deleteBlock,
  moveBlock,
  setting,
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
  'rename_page': AgentActionKind.renamePage,
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
  'markdown': AgentActionKind.paragraph,
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
  'math_equation': AgentActionKind.math,
  'equation': AgentActionKind.math,
  'formula': AgentActionKind.math,
  'blockquote': AgentActionKind.quote,
  'callout': AgentActionKind.quote,
  'hr': AgentActionKind.divider,
  'horizontal_rule': AgentActionKind.divider,
  'rename': AgentActionKind.renamePage,
  'rename_title': AgentActionKind.renamePage,
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
        AgentActionKind.renamePage => 'Renamed the page to "${_clip(text)}"',
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
      kind == AgentActionKind.replaceBlock;

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
              'rename_page',
              'replace_block',
              'delete_block',
              'move_block',
              'setting',
            ],
          },
          'text': {
            'type': 'string',
            'description': 'Body text. For rename_page, the new title. For '
                'replace_block, the replacement text.',
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
  });

  final String summary;
  final List<AgentAction> actions;

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
  final text =
      asStringOr(m['text'] ?? m['content'] ?? m['body'] ?? m['value']).trim();
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

    case AgentActionKind.math:
      if (text.isEmpty) return reject('a formula with no LaTeX');
      return AgentAction(kind: kind, text: text, afterBlockId: afterBlockId);

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
      return AgentAction(
        kind: kind,
        text: text.split('\n').first.trim(),
      );

    case AgentActionKind.replaceBlock:
      // Same recovery in the other direction: "rewrite this as a task plus an
      // action" naturally produces a list, and dropping it wasted a valid
      // target the model had correctly identified.
      final body = text.isNotEmpty ? text : items.join('\n');
      if (blockId == null || blockId.isEmpty) {
        return reject('a rewrite with no block to rewrite');
      }
      if (body.isEmpty) return reject('a rewrite with no replacement text');
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
