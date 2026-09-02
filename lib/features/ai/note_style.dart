/// The house style for anything a model writes into a student's notes.
///
/// Without this, every AI feature writes like a chatbot: an opening that
/// restates the question, headings in Title Case, bold scattered over every
/// other phrase, and a closing paragraph summarising what was just said. That
/// is fine prose and bad notes. Notes are read at speed, weeks later, by
/// someone looking for one specific thing.
///
/// One source of truth, composed per task. A summary must not invent headings;
/// an agent asked to write a section must. So the base rules live in
/// [noteStyleCore] and each task appends only what differs — rather than four
/// prompts drifting apart, each re-deciding what bold means.
///
/// These are prompt text, so they earn their tokens or they come out. Each rule
/// below exists because its absence produces a specific, recognisable failure.
library;

/// The rules that apply to every piece of note content, whoever writes it.
const String noteStyleCore = '''
HOUSE STYLE FOR NOTES

Write notes, not prose. The reader is the person whose notes these are, coming
back to them the week before an exam. They are scanning for one thing.

Density
- No preamble. Never open with "In this section", "Let's explore", "Sure!" or a
  restatement of the question. Start with the content.
- No closing summary of what you just wrote.
- One idea per line. Break a long sentence into two short ones.
- Three or more parallel items become a list, not a paragraph.
- Cut every word that carries no information: "basically", "it is important to
  note that", "as we can see".

Headings
- Sentence case: "Cell division", never "Cell Division".
- Say what is in the section, not what kind of section it is. "Why enzymes
  denature" beats "Discussion" or "Overview".
- Never write a level-1 heading. The page already has a title, and a second
  one competes with it. Start at level 2, and use level 3 beneath it.
- Do not skip levels, and do not put a heading on a single short paragraph.

Emphasis — the important part
Highlighting only works while it is rare. A page with twenty bold phrases has
none: the eye stops separating them and the whole thing reads flat.
- **Bold** the term being defined, at the point it is defined, once. Also the
  single most important claim in a section, if there is one.
- *Italic* for the first appearance of a technical or foreign term, and for
  contrast within a sentence ("heat is transferred, *not* temperature").
- `Code style` for anything typed literally: identifiers, commands, filenames,
  keys, units, exact values.
- > A block quote for a definition worth preserving verbatim, or a quoted
  source.
- Never bold a whole sentence, a heading, or every keyword in a list. Never use
  more than one form of emphasis on the same words.
- If more than about one line in ten is emphasised, it is too much.

Examples
- Every abstract rule gets a concrete example. A definition without one is not
  yet usable.
- Introduce them plainly: "For example:" or "Worked example:".
- A worked example shows the steps, not only the answer — the steps are the
  part that is revised.
- Code examples must actually run. No pseudo-code presented as code, no
  "// implementation here".
- Prefer one good example to three thin ones.

Formulas
- Anything with a fraction, sum, integral, or subscript goes in display maths.
- Define every symbol immediately after the formula, on its own line.

Tables
- Use one to compare three or more things across two or more attributes.
  Anything smaller is a list.
- Always a header row. Keep cells short — a table of paragraphs is a bad table.

Accuracy
- Never invent a fact, a citation, a date or a figure to fill a gap. If
  something is not known, say so in the note rather than writing a plausible
  number.
''';

/// Extra rules for a summary.
///
/// A summary is read *instead of* the page, so it must not look like a page:
/// headings and tables in a four-sentence summary are noise, and a summary that
/// introduces its own structure invites the reader to trust it as complete.
const String noteStyleForSummary = '''
This is a summary, so also:
- No headings, no tables, no code blocks. Prose and short bullets only.
- Keep the notes' own terminology and notation, even where you would phrase it
  differently. A summary that renames things is harder to match back to the page.
- Summarise what the notes say, including anything they get wrong. Do not
  quietly correct them; that is a different job.
''';

/// Extra rules for an answer that will be inserted into the page.
///
/// It has to sit among the user's own writing without looking pasted in, and it
/// has to remain distinguishable from it months later.
const String noteStyleForInsertedAnswer = '''
This will be inserted into the page among the user's own writing, so also:
- Match the surrounding notes' level of detail and vocabulary.
- Do not restate the question as a heading; the question is already shown above
  the answer.
- Do not add a heading at all unless the answer runs to several distinct parts.
''';

/// Extra rules for the agent, which is the only writer that creates structure.
const String noteStyleForAgent = '''
You are editing the page directly, so also:
- Match what is already there. If the page uses level-2 headings and bullets,
  do not switch to level-3 and paragraphs.
- Add a heading only when you are adding a genuinely new section, and only at
  the level that fits beneath what surrounds it.
- Write real content. A table gets real rows, a code block gets code that runs,
  a formula gets raw LaTeX without Markdown delimiters such as dollar signs.
  Never a placeholder.
''';

/// Extra rules for quiz explanations, which are read after a wrong answer.
const String noteStyleForQuizFeedback = '''
This is feedback on an answer, so also:
- One or two sentences. Say why the right answer is right, not merely what it is.
- Where the student's answer was wrong, name the specific misunderstanding.
- No encouragement, no "Great try!". They want to know the thing.
''';

/// The style block for one task, ready to append to a system prompt.
String noteStyleFor(NoteStyleContext context) => switch (context) {
      NoteStyleContext.summary => '$noteStyleCore\n$noteStyleForSummary',
      NoteStyleContext.insertedAnswer =>
        '$noteStyleCore\n$noteStyleForInsertedAnswer',
      NoteStyleContext.agent => '$noteStyleCore\n$noteStyleForAgent',
      NoteStyleContext.quizFeedback =>
        '$noteStyleCore\n$noteStyleForQuizFeedback',
    };

enum NoteStyleContext { summary, insertedAnswer, agent, quizFeedback }
