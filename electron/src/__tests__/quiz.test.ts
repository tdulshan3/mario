import { describe, expect, it } from 'vitest';
import { normalizeArtifacts, parseGrade, quizScore, validateQuiz } from '../shared/quiz';
import { describeAgentAction, planWrites } from '../shared/agent-schema';

describe('Saved quizzes of every shape', () => {
  it('reads a Mario v1 quiz (items with kinds) instead of crashing on it', () => {
    const data = normalizeArtifacts({
      askHistory: [],
      doHistory: [],
      quizzes: [
        {
          id: 'v1quiz',
          scope: 'page',
          scopeId: 'pg1',
          title: 'Cells',
          items: [
            { id: 'a', kind: 'mcq', question: 'Q1?', options: ['a', 'b', 'c', 'd'], correctIndex: 2, marks: 1, explanation: 'Because.' },
            { id: 'b', kind: 'essay', question: 'Explain osmosis.', expectedPoints: ['water moves', 'across a membrane'], marks: 2 },
          ],
          sourceHash: 'x',
          pageIds: ['pg1'],
          provenance: { backend: 'Ollama', model: 'qwen', createdAt: '2026-09-01T10:00:00.000Z' },
        },
      ],
    });
    expect(data.quizzes).toHaveLength(1);
    const [entry] = data.quizzes;
    expect(entry.id).toBe('v1quiz');
    expect(entry.pageId).toBe('pg1');
    expect(entry.createdAt).toBe('2026-09-01T10:00:00.000Z');
    expect(entry.quiz.title).toBe('Cells');
    expect(entry.quiz.mcqs).toEqual([{ question: 'Q1?', options: ['a', 'b', 'c', 'd'], correctIndex: 2, explanation: 'Because.' }]);
    expect(entry.quiz.essays).toEqual([{ question: 'Explain osmosis.', expectedPoints: ['water moves', 'across a membrane'], marks: 2 }]);
  });

  it('reads an older Electron essay (one rubric string, maxMarks) and drops entries with nothing to show', () => {
    const data = normalizeArtifacts({
      quizzes: [
        {
          id: 'q1',
          quiz: { title: 'T', mcqs: [], essays: [{ question: 'Why?', rubric: '- one\n- two\n- three', maxMarks: 5 }] },
          createdAt: '2026-10-01T00:00:00.000Z',
        },
        { id: 'broken' },
        null,
        { id: 'empty', quiz: { title: 'x', mcqs: [{ question: '', options: [] }] } },
      ],
    });
    expect(data.quizzes.map((q) => q.id)).toEqual(['q1']);
    expect(data.quizzes[0].quiz.essays[0]).toEqual({ question: 'Why?', expectedPoints: ['one', 'two', 'three'], marks: 5 });
  });

  it('forgets saved answers when a question had to be dropped, so none is marked against the wrong one', () => {
    const data = normalizeArtifacts({
      quizzes: [
        {
          id: 'q',
          quiz: {
            title: 'T',
            mcqs: [
              { question: 'Bad', options: ['a', 'a'], correctIndex: 0 },
              { question: 'Good', options: ['x', 'y'], correctIndex: 1 },
            ],
            essays: [],
          },
          answers: { 0: 0, 1: 1 },
          score: 1,
          createdAt: '2026-10-01T00:00:00.000Z',
        },
      ],
    });
    expect(data.quizzes[0].quiz.mcqs.map((m) => m.question)).toEqual(['Good']);
    expect(data.quizzes[0].answers).toBeUndefined();
    expect(data.quizzes[0].score).toBeUndefined();
  });
});

describe('Generated quizzes', () => {
  it('drops questions that cannot be marked and says why', () => {
    const { quiz, dropped } = validateQuiz({
      title: 'Photosynthesis',
      mcqs: [
        { question: 'Where?', options: ['a', 'b', 'c', 'd'], correctIndex: 1, explanation: '' },
        { question: 'Off by one', options: ['a', 'b', 'c', 'd'], correctIndex: 4, explanation: '' },
        { question: 'Twins', options: ['a', 'A', 'c', 'd'], correctIndex: 0, explanation: '' },
        { question: 'Where?', options: ['e', 'f', 'g', 'h'], correctIndex: 0, explanation: '' },
      ],
      essays: [
        { question: 'Explain it.', expectedPoints: ['light', 'chlorophyll', 'glucose'] },
        { question: 'No rubric', expectedPoints: [] },
      ],
    });
    expect(quiz.mcqs.map((q) => q.question)).toEqual(['Where?']);
    expect(quiz.essays).toEqual([{ question: 'Explain it.', expectedPoints: ['light', 'chlorophyll', 'glucose'], marks: 3 }]);
    expect(dropped.sort()).toEqual(['a repeated question', 'an essay with no rubric', 'no right answer', 'two identical options']);
  });
});

describe('Essay marks', () => {
  const essay = { question: 'Explain.', expectedPoints: ['a', 'b', 'c', 'd'], marks: 4 };

  it('clamps a mark into range and reads "3/4"', () => {
    expect(parseGrade({ awarded: 7, feedback: 'ok', matchedPoints: ['a'], missedPoints: [] }, essay).awarded).toBe(4);
    expect(parseGrade({ awarded: -1, feedback: '', matchedPoints: [], missedPoints: [] }, essay).awarded).toBe(0);
    expect(parseGrade({ awarded: '3/4', feedback: 'good' }, essay).awarded).toBe(3);
    const none = parseGrade({}, essay);
    expect(none.awarded).toBe(0);
    expect(none.feedback).toMatch(/usable mark/);
    expect(none.provisional).toBe(true);
  });

  it('scores multiple choice a mark each, plus essay marks, with the student’s mark replacing the draft', () => {
    const quiz = {
      title: 'T',
      mcqs: [
        { question: '1', options: ['a', 'b'], correctIndex: 0, explanation: '' },
        { question: '2', options: ['a', 'b'], correctIndex: 1, explanation: '' },
      ],
      essays: [essay],
    };
    const grade = { awarded: 2, outOf: 4, feedback: '', matchedPoints: [], missedPoints: [], provisional: true };
    expect(quizScore(quiz, { 0: 0, 1: 0 }, { 0: grade })).toEqual({ awarded: 3, outOf: 6, provisional: true });
    expect(quizScore(quiz, { 0: 0, 1: 1 }, { 0: { ...grade, override: 4 } })).toEqual({ awarded: 6, outOf: 6, provisional: false });
  });
});

describe('Do preview', () => {
  const text = (id: string) => ({ b1: 'The Calvin cycle fixes carbon.', b2: 'Summary' })[id];

  it('describes each change in words and flags the ones that remove or rewrite', () => {
    expect(describeAgentAction({ kind: 'heading', text: 'Summary', afterBlockId: 'b1' }, text)).toEqual({
      text: 'Add a heading “Summary” after “The Calvin cycle fixes carbon.”',
      destructive: false,
    });
    expect(describeAgentAction({ kind: 'bullets', items: ['a', 'b'] }, text)).toEqual({ text: 'Add 2 bullet points', destructive: false });
    expect(describeAgentAction({ kind: 'delete_block', blockId: 'b2' }, text)).toEqual({ text: 'Delete “Summary”', destructive: true });
    expect(describeAgentAction({ kind: 'write_page', mode: 'replace', content: 'x' }).destructive).toBe(true);
  });

  it('only pauses for plans that write', () => {
    expect(planWrites([{ kind: 'read_page' }, { kind: 'search_notes', text: 'x' }])).toBe(false);
    expect(planWrites([{ kind: 'read_page' }, { kind: 'paragraph', text: 'x' }])).toBe(true);
  });
});
