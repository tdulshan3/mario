import { describe, expect, it } from 'vitest';
import {
  documentToMarkdown,
  evaluateSheetCell,
  expandEmojiShortcodes,
  makeCodeNode,
  makeMathNode,
  makeSpreadsheetNode,
  markdownToDocument,
  normalizeLatexFormula,
  normalizeWorkbook,
} from '../shared/document-codec';
import { parseAgentPlan } from '../shared/agent-schema';
import { newClientId } from '../shared/ids';
import type { SheetData } from '../shared/types';

describe('Document Codec & Markdown Exporter', () => {
  it('round-trips headings, lists, checklists, quotes, code blocks, and math', () => {
    const md = [
      '# Photosynthesis',
      '## Light Reactions',
      '- Thylakoid membrane',
      '1. Photon absorption',
      '- [x] ATP synthesis',
      '> Sunlight powers the biosphere',
      '```python\nprint("Hello ATP")\n```',
      '$$\n6CO_2 + 6H_2O \\rightarrow C_6H_{12}O_6 + 6O_2\n$$',
    ].join('\n\n');

    const doc = markdownToDocument(md);
    expect(doc.children.map((n) => n.type)).toEqual([
      'heading',
      'heading',
      'bulleted_list',
      'numbered_list',
      'todo_list',
      'quote',
      'code',
      'math_equation',
    ]);

    // Verify code block sets both delta and code attributes (fixing Flutter /code bug)
    const codeBlock = makeCodeNode('const x = 42;', 'typescript');
    expect(codeBlock.data?.code).toBe('const x = 42;');
    expect(codeBlock.data?.delta?.[0]?.insert).toBe('const x = 42;');

    const exported = documentToMarkdown(doc);
    expect(exported).toContain('# Photosynthesis');
    expect(exported).toContain('- [x] ATP synthesis');
    expect(exported).toContain('```python\nprint("Hello ATP")\n```');
    expect(exported).toContain('6CO_2 + 6H_2O \\rightarrow C_6H_{12}O_6 + 6O_2');
  });

  it('exports math_equation and spreadsheet blocks in documentToMarkdown', () => {
    const mathNode = makeMathNode('E = mc^2');
    const sheetNode = makeSpreadsheetNode({
      activeIndex: 0,
      sheets: [
        {
          name: 'Budget',
          rows: 3,
          cols: 2,
          cells: {
            A1: 'Item',
            B1: 'Amount',
            A2: 'GPU',
            B2: '900',
            A3: 'Total',
            B3: '=SUM(B2:B2)',
          },
        },
      ],
    });
    const out = documentToMarkdown({
      type: 'page',
      children: [mathNode, sheetNode],
    });
    expect(out).toContain('$$\nE = mc^2\n$$');
    expect(out).toContain('#### Spreadsheet: Budget');
    expect(out).toContain('| Total | 900 |');
  });
});

describe('Spreadsheet Formula Evaluator', () => {
  const sheet: SheetData = {
    name: 'Sheet1',
    rows: 8,
    cols: 4,
    cells: {
      A1: '10',
      A2: '20',
      A3: '30',
      A4: '=SUM(A1:A3)',
      A5: '=AVERAGE(A1:A3)',
      A6: '=MAX(A1:A3) - MIN(A1:A3)',
      A7: '=COUNT(A1:A3)',
    },
  };

  it('evaluates SUM, AVERAGE, MIN, MAX, COUNT, and arithmetic', () => {
    expect(evaluateSheetCell(sheet, 'A4')).toBe('60');
    expect(evaluateSheetCell(sheet, 'A5')).toBe('20');
    expect(evaluateSheetCell(sheet, 'A6')).toBe('20');
    expect(evaluateSheetCell(sheet, 'A7')).toBe('3');
  });

  it('guards against circular references', () => {
    const cycleSheet: SheetData = {
      name: 'Cycle',
      rows: 2,
      cols: 2,
      cells: {
        A1: '=B1',
        B1: '=A1',
      },
    };
    expect(evaluateSheetCell(cycleSheet, 'A1')).toBe('#CYCLE!');
  });

  it('normalizes legacy Flutter JSON-stringified workbooks with "row,col" cell keys', () => {
    const wb = normalizeWorkbook({
      data: JSON.stringify({
        version: 2,
        active: 0,
        sheets: [
          {
            name: 'Lab Run #1',
            rows: 3,
            cols: 4,
            cells: {
              '0,0': 'Trial',
              '1,1': '2.5',
              '1,2': '3.2',
              '1,3': '=B2*C2',
            },
          },
        ],
      }),
    });
    expect(wb.sheets[0].name).toBe('Lab Run #1');
    expect(wb.sheets[0].cells.A1).toBe('Trial');
    expect(evaluateSheetCell(wb.sheets[0], 'D2')).toBe('8');
  });
});

describe('Mario Do Agent Plan Parser', () => {
  it('parses valid actions and drops block-targeting actions with unknown blockIds', () => {
    const known = new Set(['b1', 'b2']);
    const plan = parseAgentPlan(
      {
        summary: 'Updated b1 and added a math block',
        done: true,
        followUps: ['Add a practice quiz'],
        actions: [
          {
            kind: 'replace_block',
            blockId: 'b1',
            text: 'Updated paragraph',
          },
          {
            kind: 'delete_block',
            blockId: 'unknown_id',
          },
          {
            kind: 'math',
            afterBlockId: 'b2',
            text: '\\nabla \\cdot \\mathbf{E} = \\frac{\\rho}{\\varepsilon_0}',
          },
        ],
      },
      known,
    );

    expect(plan.summary).toBe('Updated b1 and added a math block');
    expect(plan.done).toBe(true);
    expect(plan.actions).toHaveLength(2);
    expect(plan.actions[0].kind).toBe('replace_block');
    expect(plan.actions[1].kind).toBe('math');
  });
});

describe('IDs, LaTeX Normalizer & Emoji Shortcodes', () => {
  it('mints prefixed client IDs and expands shortcodes', () => {
    const nbId = newClientId('nb');
    expect(nbId.startsWith('nb_')).toBe(true);
    expect(expandEmojiShortcodes('Done :check: :rocket:')).toBe('Done ✅ 🚀');
    expect(normalizeLatexFormula('a \\rarr b \\sube c')).toBe(
      'a \\rightarrow b \\subseteq c',
    );
  });
});

describe('Agent plans as models write them', () => {
  it('reads block ids copied with their [id:…] label and keeps inserts after unknown blocks', () => {
    const plan = parseAgentPlan(
      {
        summary: 'Adding a summary',
        actions: [
          { kind: 'heading', text: 'Summary', level: 2, afterBlockId: 'id:ph0010' },
          { kind: 'bullets', items: ['One'], afterBlockId: '[id:ph0002]' },
          { kind: 'bullets', items: ['Two'], afterBlockId: 'no-such-block' },
          { kind: 'delete_block', blockId: 'no-such-block' },
        ],
      },
      new Set(['ph0002', 'ph0010']),
    );
    expect(plan.actions.map((a) => [a.kind, a.afterBlockId])).toEqual([
      ['heading', 'ph0010'],
      ['bullets', 'ph0002'],
      ['bullets', undefined],
    ]);
  });
});

