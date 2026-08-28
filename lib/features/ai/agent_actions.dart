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
    this.level = 1,
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
          'level': {'type': 'integer', 'description': 'Heading level, 1-6.'},
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

/// A validated plan, plus what had to be thrown away.
class AgentPlan {
  const AgentPlan({
    required this.summary,
    required this.actions,
    this.dropped = 0,
  });

  final String summary;
  final List<AgentAction> actions;

  /// Actions the model proposed that could not be made safe. Reported rather
  /// than hidden: "9 of 11 steps" is information the user needs to judge the
  /// result.
  final int dropped;

  bool get isEmpty => actions.isEmpty;
  int get destructiveCount => actions.where((a) => a.isDestructive).length;
}

/// Turns a model reply into a plan, discarding anything unusable.
///
/// Every rejection is decidable here, without asking a model: an unknown kind,
/// a heading with no text, a table with ragged rows, a delete with no target, a
/// setting outside the allowlist. A dropped action costs one step; an action
/// executed on a guess costs the user's notes.
AgentPlan parseAgentPlan(Map<String, dynamic> raw,
    {Set<String>? knownBlockIds}) {
  final proposed = asMapList(raw['actions']);
  final actions = <AgentAction>[];

  for (final m in proposed) {
    final action = _parseOne(m, knownBlockIds);
    if (action != null) actions.add(action);
  }

  return AgentPlan(
    summary: asStringOr(raw['summary']).trim(),
    actions: actions,
    dropped: proposed.length - actions.length,
  );
}

/// Kinds that actually consume [AgentAction.blockId]. For everything else the
/// field is meaningless, and — before this distinction existed — fatal.
const _targetedKinds = <AgentActionKind>{
  AgentActionKind.replaceBlock,
  AgentActionKind.deleteBlock,
  AgentActionKind.moveBlock,
};

AgentAction? _parseOne(Map<String, dynamic> m, Set<String>? knownBlockIds) {
  final kind = _wireNames[asStringOr(m['kind']).trim().toLowerCase()];
  if (kind == null) return null;

  // Field aliases, because the schema is advisory on any backend without
  // strict decoding and models reach for the obvious synonym.
  final text =
      asStringOr(m['text'] ?? m['content'] ?? m['body'] ?? m['value']).trim();
  // Two views of the same field. List entries are trimmed, because leading
  // space in a bullet is noise; a code body is not, because indentation is
  // the difference between Python that runs and Python that does not.
  final rawItems = asStringList(m['items'] ?? m['list'] ?? m['bullets']);
  final items =
      rawItems.map((i) => i.trim()).where((i) => i.isNotEmpty).toList();

  var blockId = asString(m['blockId'] ?? m['block_id'])?.trim();
  var afterBlockId = asString(m['afterBlockId'] ?? m['after_block_id'])?.trim();

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
      return null;
    }
    if (afterBlockId != null &&
        afterBlockId.isNotEmpty &&
        !knownBlockIds.contains(afterBlockId)) {
      // Not fatal: append rather than discard the content.
      return _build(kind, m, text, items, rawItems, blockId, null);
    }
  }

  return _build(kind, m, text, items, rawItems, blockId, afterBlockId);
}

AgentAction? _build(
  AgentActionKind kind,
  Map<String, dynamic> m,
  String text,
  List<String> items,
  List<String> rawItems,
  String? blockId,
  String? afterBlockId,
) {
  switch (kind) {
    case AgentActionKind.paragraph:
    case AgentActionKind.quote:
      // Body delivered as a list rather than a string: join it instead of
      // discarding a paragraph the model did write.
      final body = text.isNotEmpty ? text : items.join('\n');
      if (body.isEmpty) return null;
      return AgentAction(kind: kind, text: body, afterBlockId: afterBlockId);

    case AgentActionKind.heading:
      if (text.isEmpty) return null;
      return AgentAction(
        kind: kind,
        text: text,
        level: (asInt(m['level']) ?? 1).clamp(1, 6),
        afterBlockId: afterBlockId,
      );

    case AgentActionKind.bullets:
    case AgentActionKind.numbered:
    case AgentActionKind.todo:
      if (items.isEmpty) return null;
      return AgentAction(kind: kind, items: items, afterBlockId: afterBlockId);

    case AgentActionKind.divider:
      return AgentAction(kind: kind, afterBlockId: afterBlockId);

    case AgentActionKind.code:
      // rawItems, not items: trimming would flatten the indentation.
      final code = text.isNotEmpty ? text : rawItems.join('\n');
      if (code.isEmpty) return null;
      final language = asStringOr(m['language'], 'plaintext').trim();
      return AgentAction(
        kind: kind,
        text: code,
        language: language.isEmpty ? 'plaintext' : language,
        afterBlockId: afterBlockId,
      );

    case AgentActionKind.math:
      if (text.isEmpty) return null;
      return AgentAction(kind: kind, text: text, afterBlockId: afterBlockId);

    case AgentActionKind.table:
    case AgentActionKind.spreadsheet:
      final rows = _normaliseRows(m['rows']);
      if (rows == null) return null;
      return AgentAction(
        kind: kind,
        rows: rows,
        text: text,
        afterBlockId: afterBlockId,
      );

    case AgentActionKind.renamePage:
      if (text.isEmpty) return null;
      // A title is one line; a model that returns a paragraph here would give
      // the page a name nothing can display.
      return AgentAction(
        kind: kind,
        text: text.split('\n').first.trim(),
      );

    case AgentActionKind.replaceBlock:
      if (blockId == null || blockId.isEmpty || text.isEmpty) return null;
      return AgentAction(kind: kind, blockId: blockId, text: text);

    case AgentActionKind.deleteBlock:
      if (blockId == null || blockId.isEmpty) return null;
      return AgentAction(kind: kind, blockId: blockId);

    case AgentActionKind.moveBlock:
      if (blockId == null || blockId.isEmpty) return null;
      // Moving a block to just after itself is a no-op that still costs a
      // transaction and reads as a change in the result list.
      if (afterBlockId == blockId) return null;
      return AgentAction(
        kind: kind,
        blockId: blockId,
        afterBlockId: afterBlockId,
      );

    case AgentActionKind.setting:
      final key = asString(m['settingKey'])?.trim();
      final value = asString(m['settingValue'])?.trim();
      if (key == null || value == null || value.isEmpty) return null;
      if (!agentWritableSettings.contains(key)) return null;
      return AgentAction(kind: kind, settingKey: key, settingValue: value);
  }
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
