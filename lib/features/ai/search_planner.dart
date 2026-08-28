/// Letting the model decide what to look up.
///
/// Every search this app made used to be a mechanical transform of something
/// else: `/ask` sent the user's question verbatim, and a hard quiz glued the
/// note's title to its first three headings. Both produce queries no person
/// would type. "given what my notes say about Article 22, does this still
/// apply?" is a fine question and a terrible search — the pronoun carries the
/// subject, and the subject is in the passage the user highlighted, which never
/// reached the query at all. "Cell Respiration Glycolysis Krebs cycle Electron
/// transport" is four topics in a trench coat.
///
/// So the model writes the query, the way it would if it were doing the looking
/// up itself: it reads the task, decides whether the web is even needed, and
/// says what it would type into a search box.
///
/// Three properties this deliberately has:
///
///  * **It cannot fail.** Any error, any malformed reply, any backend that
///    cannot do structured output at all — the caller gets the mechanical
///    query it would have used anyway. A planner that can break searching is
///    worse than no planner.
///  * **It never sees retrieved text.** Only the user's own words and their
///    notes go in. Feeding a page fetched from the web back into the thing
///    that chooses the next search is how a retrieved page gets to steer what
///    the app looks up next.
///  * **It is capped.** Serper bills per query against a daily allowance, so
///    two queries is the ceiling — enough to cover a question with two halves,
///    cheap enough that a quiz does not cost three credits.
library;

import '../../core/services/ai/json_coercion.dart';
import '../../core/services/ai/llm_service.dart';
import '../../core/services/ai/llm_types.dart';

/// What to search for, and whether to bother.
class SearchPlan {
  const SearchPlan({
    required this.queries,
    this.needsSearch = true,
    this.fromModel = false,
  });

  /// In the order they should run. Never empty when [needsSearch] is true.
  final List<String> queries;

  /// The model's judgement that the web adds nothing here — a question about
  /// what is already written on the page, say. Advisory: a caller who was
  /// explicitly told to search by the user ignores it.
  final bool needsSearch;

  /// False when this is the mechanical fallback rather than the model's
  /// choice, so the UI can say "searching for X" honestly either way.
  final bool fromModel;
}

const _system = 'You decide what to look up on the web, and nothing else.\n'
    'Given a task, write the search queries you would type into a search '
    'engine to find what is missing.\n'
    'Write queries a person would type: the specific subject, named entities, '
    'the terms of art. Not the user\'s sentence with the question mark '
    'removed, and not a list of every topic on the page glued together.\n'
    'Resolve pronouns. If the task says "does this still apply", work out what '
    '"this" is from the context and put the actual subject in the query.\n'
    'One query is usually right. Use two only when the task genuinely has two '
    'separate things to find out.\n'
    'Set needsSearch to false when the web adds nothing — the answer is '
    'already in the notes, or the task is about the user\'s own writing.';

const _schema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'needsSearch': {
      'type': 'boolean',
      'description': 'False when the web would add nothing here.',
    },
    'queries': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'What to type into a search engine. One, or two at most.',
    },
  },
  'required': ['needsSearch', 'queries'],
};

/// How much of the surrounding material the planner is shown.
///
/// Enough to resolve a pronoun, not enough to swamp its own small budget. A
/// planning call that costs as much as the answer is not worth making.
const int _contextChars = 700;

/// Asks the model what to search for.
///
/// [task] is what the user actually wants — their question, or a description
/// of the quiz being built. [context] is the material it refers to: the
/// highlighted passage, the note's headings. [fallback] is the mechanical
/// query to use when the model gives nothing usable, and must not be empty.
Future<SearchPlan> planSearch({
  required LlmService llm,
  required String task,
  required String fallback,
  String? context,
  int maxQueries = 2,
  CancelToken? cancel,
}) async {
  final safeFallback = fallback.trim();
  SearchPlan mechanical() => SearchPlan(
        queries: safeFallback.isEmpty ? const [] : [safeFallback],
        needsSearch: safeFallback.isNotEmpty,
      );

  if (task.trim().isEmpty) return mechanical();

  try {
    final prompt = StringBuffer()..writeln('Task: ${task.trim()}');
    final trimmedContext = context?.trim() ?? '';
    if (trimmedContext.isNotEmpty) {
      prompt
        ..writeln()
        ..writeln('What it refers to:')
        ..writeln(trimmedContext.length <= _contextChars
            ? trimmedContext
            : '${trimmedContext.substring(0, _contextChars)}…');
    }

    final raw = await llm.structured(
      request: LlmRequest(
        system: _system,
        messages: [LlmMessage.user(prompt.toString())],
        // A planning call has to be cheap or it is not worth making. Two short
        // queries and a boolean need very little room.
        maxTokens: 200,
        effort: LlmEffort.low,
      ),
      schemaName: 'search_plan',
      schema: _schema,
      cancel: cancel,
    );

    // Coerced, not cast. A small backend returns a bare string where the schema
    // says array often enough that a cast here would throw past every guard
    // this function exists to provide.
    final queries = [
      for (final q in asStringList(raw['queries']))
        if (q.trim().isNotEmpty) q.trim(),
    ].take(maxQueries).toList();

    if (queries.isEmpty) return mechanical();
    return SearchPlan(
      queries: queries,
      needsSearch: asBool(raw['needsSearch'], fallback: true),
      fromModel: true,
    );
  } on LlmCancelled {
    // The user stopped the run; that is not a planning failure.
    rethrow;
  } catch (_) {
    // Everything else — a backend with no structured output, a timeout, a
    // reply that is not JSON at all — degrades to the query the caller would
    // have used before this existed.
    return mechanical();
  }
}
