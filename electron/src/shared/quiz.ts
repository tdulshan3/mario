import type { AiArtifactData, QuizData, QuizEntry, QuizEssay, QuizGrade, QuizMcq } from './types';

/**
 * Quizzes: the JSON schema they are generated with, the checks a generated quiz
 * has to pass, reading saved quizzes of every shape Mario has written, and
 * essay marks.
 *
 * The rules are Mario v1's:
 *  - Multiple choice is marked here, by comparing indices. No model is asked.
 *  - A generated question that cannot be marked (no right answer, two identical
 *    options, an essay with no rubric) is dropped before anyone sees it.
 *  - An essay mark from the model is a draft: clamped into range, shown with
 *    the rubric points it matched and missed, and open to the student's change.
 */

const str = (v: unknown): string => (typeof v === 'string' ? v : v == null ? '' : String(v));
const strList = (v: unknown): string[] =>
  Array.isArray(v) ? v.map((x) => str(x).trim()).filter(Boolean) : [];
const int = (v: unknown): number | null => {
  const n = typeof v === 'number' ? v : typeof v === 'string' && v.trim() ? Number(v) : NaN;
  return Number.isFinite(n) ? Math.trunc(n) : null;
};
const clampMarks = (n: number) => Math.max(1, Math.min(10, Math.round(n)));

export const QUIZ_SYSTEM_PROMPT = [
  'You write exam questions from a student’s own study notes.',
  'Every question must be answerable from the notes alone. Do not use outside knowledge, and do not ask about anything the notes only mention in passing.',
  'For multiple choice: exactly four options, exactly one correct, and the three wrong ones must be plausible to someone who half-learned the material — not obviously silly. correctIndex is 0-based.',
  'For essay questions: give the rubric in expectedPoints, as the specific points a full-mark answer must make, drawn from the notes.',
  'Vary which position the correct option sits in. Write questions and options in Markdown; use LaTeX ($...$) for formulas.',
].join('\n');

export function quizSchema(mcqCount: number, essayCount: number): Record<string, unknown> {
  return {
    type: 'object',
    required: ['title', 'mcqs', 'essays'],
    additionalProperties: false,
    properties: {
      title: { type: 'string' },
      mcqs: {
        type: 'array',
        minItems: mcqCount,
        maxItems: mcqCount,
        items: {
          type: 'object',
          required: ['question', 'options', 'correctIndex', 'explanation'],
          additionalProperties: false,
          properties: {
            question: { type: 'string' },
            options: { type: 'array', items: { type: 'string' }, minItems: 4, maxItems: 4 },
            correctIndex: { type: 'integer', minimum: 0, maximum: 3 },
            explanation: { type: 'string' },
          },
        },
      },
      essays: {
        type: 'array',
        minItems: essayCount,
        maxItems: essayCount,
        items: {
          type: 'object',
          required: ['question', 'expectedPoints'],
          additionalProperties: false,
          properties: {
            question: { type: 'string' },
            expectedPoints: { type: 'array', items: { type: 'string' }, minItems: 1, maxItems: 8 },
          },
        },
      },
    },
  };
}

export function quizUserPrompt(notes: string, mcqCount: number, essayCount: number): string {
  const asks = [
    mcqCount > 0 ? `${mcqCount} multiple-choice question${mcqCount === 1 ? '' : 's'}` : '',
    essayCount > 0 ? `${essayCount} essay question${essayCount === 1 ? '' : 's'}, each with its rubric points` : '',
  ].filter(Boolean);
  return `Write ${asks.join(' and ')} from these notes. Give the quiz a short title.\n\nNotes:\n${notes}`;
}

/** A rubric written as one string ("- a\n- b", "a; b") as its points. */
function rubricPoints(rubric: unknown): string[] {
  if (Array.isArray(rubric)) return strList(rubric);
  return str(rubric)
    .split(/\n|;|•/)
    .map((p) => p.replace(/^\s*(?:[-*+]|\d+[.)])\s*/, '').trim())
    .filter(Boolean);
}

function readMcq(raw: unknown, reject: (why: string) => void): QuizMcq | null {
  const m = (raw ?? {}) as Record<string, unknown>;
  const question = str(m.question ?? m.prompt).trim();
  const options = Array.isArray(m.options) ? m.options.map((o) => str(o).trim()) : [];
  const correctIndex = int(m.correctIndex ?? m.correct_index ?? m.answerIndex);
  if (!question) return reject('a blank question'), null;
  if (options.length < 2 || options.some((o) => !o)) return reject('missing options'), null;
  if (new Set(options.map((o) => o.toLowerCase())).size !== options.length) return reject('two identical options'), null;
  if (correctIndex === null || correctIndex < 0 || correctIndex >= options.length) return reject('no right answer'), null;
  return { question, options, correctIndex, explanation: str(m.explanation).trim() };
}

function readEssay(raw: unknown, reject: (why: string) => void): QuizEssay | null {
  const m = (raw ?? {}) as Record<string, unknown>;
  const question = str(m.question ?? m.prompt).trim();
  const expectedPoints = rubricPoints(m.expectedPoints ?? m.rubric ?? m.points);
  if (!question) return reject('a blank question'), null;
  if (expectedPoints.length === 0) return reject('an essay with no rubric'), null;
  const given = int(m.marks ?? m.maxMarks);
  return { question, expectedPoints, marks: clampMarks(given && given > 0 ? given : expectedPoints.length) };
}

/** The questions of a generated quiz that can be marked, and why the rest were dropped. */
export function validateQuiz(raw: unknown): { quiz: QuizData; dropped: string[] } {
  const r = (raw ?? {}) as Record<string, unknown>;
  const dropped: string[] = [];
  const reject = (why: string) => void dropped.push(why);
  const seen = new Set<string>();
  const fresh = (q: string) => {
    const key = q.toLowerCase().replace(/[\p{P}\p{S}]/gu, '').replace(/\s+/g, ' ').trim();
    if (seen.has(key)) return reject('a repeated question'), false;
    seen.add(key);
    return true;
  };
  const mcqs = (Array.isArray(r.mcqs) ? r.mcqs : [])
    .map((m) => readMcq(m, reject))
    .filter((m): m is QuizMcq => m !== null && fresh(m.question));
  const essays = (Array.isArray(r.essays) ? r.essays : [])
    .map((e) => readEssay(e, reject))
    .filter((e): e is QuizEssay => e !== null && fresh(e.question));
  return { quiz: { title: str(r.title).trim() || 'Quiz', mcqs, essays }, dropped };
}

function readGrade(raw: unknown, outOf: number): QuizGrade | null {
  if (!raw || typeof raw !== 'object') return null;
  const g = raw as Record<string, unknown>;
  const awarded = Number(g.awarded);
  if (!Number.isFinite(awarded)) return null;
  const override = Number(g.override);
  return {
    awarded: Math.max(0, Math.min(outOf, awarded)),
    outOf,
    feedback: str(g.feedback),
    matchedPoints: strList(g.matchedPoints),
    missedPoints: strList(g.missedPoints),
    provisional: g.provisional !== false,
    ...(g.override != null && Number.isFinite(override) ? { override: Math.max(0, Math.min(outOf, override)) } : {}),
  };
}

function numberMap<T>(raw: unknown, read: (v: unknown) => T | null): Record<number, T> {
  const out: Record<number, T> = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    const i = int(k);
    const val = read(v);
    if (i !== null && i >= 0 && val !== null) out[i] = val;
  }
  return out;
}

/**
 * A saved quiz in any shape Mario has written, or null when nothing in it can be shown.
 *
 * - Electron: `{ id, quiz: { title, mcqs, essays }, answers, … }`; essays used to carry
 *   one `rubric` string and `maxMarks`.
 * - Mario v1 (Flutter): `{ id, title, items: [{ kind: 'mcq' | 'essay', … }], pageIds, provenance }`.
 */
export function normalizeQuizEntry(raw: unknown, index = 0): QuizEntry | null {
  if (!raw || typeof raw !== 'object') return null;
  const e = raw as Record<string, unknown>;
  let dropped = 0;
  const ignore = () => void dropped++;
  let source: Record<string, unknown>;
  if (e.quiz && typeof e.quiz === 'object') {
    source = e.quiz as Record<string, unknown>;
  } else if (Array.isArray(e.items)) {
    const items = e.items as Array<Record<string, unknown>>;
    const isEssay = (it: Record<string, unknown>) =>
      /essay/i.test(str(it?.kind)) || (!Array.isArray(it?.options) && (it?.expectedPoints != null || it?.rubric != null));
    source = {
      title: e.title,
      mcqs: items.filter((it) => !isEssay(it)),
      essays: items.filter((it) => isEssay(it)),
    };
  } else {
    return null;
  }
  const mcqs = (Array.isArray(source.mcqs) ? source.mcqs : [])
    .map((m) => readMcq(m, ignore))
    .filter((m): m is QuizMcq => m !== null);
  const essays = (Array.isArray(source.essays) ? source.essays : [])
    .map((x) => readEssay(x, ignore))
    .filter((x): x is QuizEssay => x !== null);
  if (mcqs.length + essays.length === 0) return null;

  const provenance = (e.provenance ?? {}) as Record<string, unknown>;
  const pageIds = Array.isArray(e.pageIds) ? e.pageIds : [];
  const createdAt = str(e.createdAt ?? provenance.createdAt) || new Date(0).toISOString();
  const answers = numberMap(e.answers, (v) => {
    const n = int(v);
    return n !== null && n >= 0 ? n : null;
  });
  const essayAnswers = numberMap(e.essayAnswers, (v) => (typeof v === 'string' ? v : null));
  const essayGrades: Record<number, QuizGrade> = {};
  for (const [k, v] of Object.entries((e.essayGrades ?? {}) as Record<string, unknown>)) {
    const i = int(k);
    const essay = i !== null ? essays[i] : undefined;
    const grade = essay ? readGrade(v, essay.marks) : null;
    if (i !== null && grade) essayGrades[i] = grade;
  }
  const score = Number(e.score);
  const outOf = Number(e.outOf);
  const pageId = str(e.pageId) || str(pageIds[0]) || undefined;
  const base = {
    id: str(e.id) || `quiz-${index}`,
    ...(pageId ? { pageId } : {}),
    quiz: { title: str(source.title ?? e.title).trim() || 'Quiz', mcqs, essays },
    createdAt,
  };
  // A dropped question moves the ones after it, so saved answers would mark the wrong questions.
  if (dropped > 0) return base;
  return {
    ...base,
    ...(Object.keys(answers).length ? { answers } : {}),
    ...(Object.keys(essayAnswers).length ? { essayAnswers } : {}),
    ...(Object.keys(essayGrades).length ? { essayGrades } : {}),
    ...(e.score != null && Number.isFinite(score) ? { score } : {}),
    ...(e.outOf != null && Number.isFinite(outOf) ? { outOf } : {}),
    ...(e.checkedAt ? { checkedAt: str(e.checkedAt) } : {}),
  };
}

/** A notebook's AI history as the panel can rely on it: lists of entries with the fields it reads. */
export function normalizeArtifacts(raw: unknown): AiArtifactData {
  const d = (raw ?? {}) as Record<string, unknown>;
  const list = (v: unknown) => (Array.isArray(v) ? v.filter((x) => x && typeof x === 'object') : []) as Array<Record<string, unknown>>;
  return {
    askHistory: list(d.askHistory).map((a) => ({
      ...(a as unknown as AiArtifactData['askHistory'][number]),
      id: str(a.id) || `ask-${Math.random().toString(36).slice(2)}`,
      question: str(a.question),
      answer: str(a.answer),
      createdAt: str(a.createdAt) || new Date(0).toISOString(),
    })),
    doHistory: list(d.doHistory).map((r) => ({
      ...(r as unknown as AiArtifactData['doHistory'][number]),
      id: str(r.id) || `do-${Math.random().toString(36).slice(2)}`,
      instruction: str(r.instruction),
      summary: str(r.summary),
      steps: strList(r.steps),
      createdAt: str(r.createdAt) || new Date(0).toISOString(),
    })),
    quizzes: list(d.quizzes)
      .map((q, i) => normalizeQuizEntry(q, i))
      .filter((q): q is QuizEntry => q !== null),
  };
}

export const GRADING_SYSTEM_PROMPT = [
  'You mark a student’s exam answer against a rubric.',
  'Award marks only for rubric points the answer actually makes. Do not reward length, confidence or vocabulary, and do not penalise an answer for being brief if it is correct.',
  'List which rubric points were matched and which were missed — those are the evidence for the mark, and the student will read them.',
  'If the answer is correct but phrased differently from the rubric, that is a match. If it is confidently wrong, that is not.',
  'Write the feedback to the student, in one or two sentences.',
].join('\n');

export const gradeSchema: Record<string, unknown> = {
  type: 'object',
  required: ['awarded', 'feedback', 'matchedPoints', 'missedPoints'],
  additionalProperties: false,
  properties: {
    awarded: { type: 'number' },
    feedback: { type: 'string' },
    matchedPoints: { type: 'array', items: { type: 'string' } },
    missedPoints: { type: 'array', items: { type: 'string' } },
  },
};

export function gradingPrompt(essay: QuizEssay, answer: string): string {
  return [
    `Question:\n${essay.question}`,
    `Points a full-mark answer must make:\n${essay.expectedPoints.map((p) => `- ${p}`).join('\n')}`,
    `Marks available: ${essay.marks}`,
    `Student’s answer:\n${answer}`,
  ].join('\n\n');
}

/**
 * The model's mark, clamped into range. A small model asked for a mark out of 4
 * sometimes returns 7, -1 or "3/4"; none of those should reach a student.
 */
export function parseGrade(raw: unknown, essay: QuizEssay): QuizGrade {
  const g = (raw ?? {}) as Record<string, unknown>;
  const rawMark = g.awarded ?? g.score ?? g.marks;
  const fraction = typeof rawMark === 'string' ? /^\s*(-?\d+(?:\.\d+)?)\s*\/\s*\d+/.exec(rawMark) : null;
  const n = fraction ? Number(fraction[1]) : Number(rawMark);
  const usable = rawMark != null && Number.isFinite(n);
  return {
    awarded: usable ? Math.max(0, Math.min(essay.marks, Math.round(n * 2) / 2)) : 0,
    outOf: essay.marks,
    feedback: usable ? str(g.feedback).trim() : 'The model did not return a usable mark.',
    matchedPoints: strList(g.matchedPoints),
    missedPoints: strList(g.missedPoints),
    provisional: true,
  };
}

/** No answer, no model: nothing to mark. */
export function blankGrade(essay: QuizEssay): QuizGrade {
  return {
    awarded: 0,
    outOf: essay.marks,
    feedback: 'No answer given.',
    matchedPoints: [],
    missedPoints: essay.expectedPoints,
    provisional: false,
  };
}

export const gradeMark = (g: QuizGrade) => g.override ?? g.awarded;

/** Marks awarded and available. Multiple choice is one mark each; an unmarked essay counts as 0. */
export function quizScore(
  quiz: QuizData,
  answers: Record<number, number>,
  grades: Record<number, QuizGrade>,
): { awarded: number; outOf: number; provisional: boolean } {
  let awarded = 0;
  let provisional = false;
  quiz.mcqs.forEach((q, i) => {
    if (answers[i] === q.correctIndex) awarded += 1;
  });
  quiz.essays.forEach((_, i) => {
    const g = grades[i];
    if (!g) return;
    awarded += gradeMark(g);
    if (g.provisional && g.override == null) provisional = true;
  });
  const outOf = quiz.mcqs.length + quiz.essays.reduce((n, e) => n + e.marks, 0);
  return { awarded, outOf, provisional };
}

/** "3", "2.5": a mark without a trailing ".0". */
export const formatMark = (n: number) => (Number.isInteger(n) ? String(n) : n.toFixed(1));
