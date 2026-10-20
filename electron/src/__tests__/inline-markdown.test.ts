import { describe, expect, it } from 'vitest';
import {
  deltaToMarkdown,
  documentToMarkdown,
  findInlineMath,
  markdownToNodes,
  parseInlineMarkdownToDelta,
} from '../shared/document-codec';
import type { DeltaOp } from '../shared/types';

const roundTrip = (delta: DeltaOp[]) => parseInlineMarkdownToDelta(deltaToMarkdown(delta));

describe('Inline Markdown parsing (CommonMark rules, like VS Code preview)', () => {
  it('reads the basic marks', () => {
    expect(parseInlineMarkdownToDelta('a **b** *c* ~~d~~ `e` [f](https://x.dev) <u>g</u>')).toEqual([
      { insert: 'a ' },
      { insert: 'b', attributes: { bold: true } },
      { insert: ' ' },
      { insert: 'c', attributes: { italic: true } },
      { insert: ' ' },
      { insert: 'd', attributes: { strikethrough: true } },
      { insert: ' ' },
      { insert: 'e', attributes: { code: true } },
      { insert: ' ' },
      { insert: 'f', attributes: { href: 'https://x.dev' } },
      { insert: ' ' },
      { insert: 'g', attributes: { underline: true } },
    ]);
  });

  it('nests emphasis', () => {
    expect(parseInlineMarkdownToDelta('**bold *both* bold**')).toEqual([
      { insert: 'bold ', attributes: { bold: true } },
      { insert: 'both', attributes: { bold: true, italic: true } },
      { insert: ' bold', attributes: { bold: true } },
    ]);
    expect(parseInlineMarkdownToDelta('***x***')).toEqual([
      { insert: 'x', attributes: { italic: true, bold: true } },
    ]);
    expect(parseInlineMarkdownToDelta('**`c`**')).toEqual([
      { insert: 'c', attributes: { bold: true, code: true } },
    ]);
  });

  it('leaves intraword underscores, spaced asterisks and math alone', () => {
    expect(parseInlineMarkdownToDelta('snake_case_name')).toEqual([{ insert: 'snake_case_name' }]);
    expect(parseInlineMarkdownToDelta('2 * 3 * 4')).toEqual([{ insert: '2 * 3 * 4' }]);
    expect(parseInlineMarkdownToDelta('math $x_i + y_i$ and $a*b*c$')).toEqual([
      { insert: 'math $x_i + y_i$ and $a*b*c$' },
    ]);
  });

  it('finds math with pandoc rules', () => {
    expect(findInlineMath('costs $5 and $10').length).toBe(0);
    expect(findInlineMath('$E=mc^2$ and `$HOME`').map((m) => m.tex)).toEqual(['E=mc^2']);
    expect(findInlineMath('$$\\int x$$')[0]).toMatchObject({ tex: '\\int x', display: true });
  });

  it('expands emoji shortcodes', () => {
    expect(parseInlineMarkdownToDelta('done :tada:')).toEqual([{ insert: 'done 🎉' }]);
  });
});

describe('Delta → Markdown round-trips', () => {
  const cases: Array<[string, DeltaOp[]]> = [
    ['bold + italic overlap', [
      { insert: 'a', attributes: { bold: true } },
      { insert: 'b', attributes: { bold: true, italic: true } },
      { insert: 'c', attributes: { italic: true } },
    ]],
    ['literal asterisks typed as text', [{ insert: 'a *not italic* b' }]],
    ['link with bold inside', [
      { insert: 'see ' },
      { insert: 'the ', attributes: { href: 'https://x.dev/a(b)' } },
      { insert: 'docs', attributes: { href: 'https://x.dev/a(b)', bold: true } },
    ]],
    ['code containing backticks', [{ insert: 'a `b` c', attributes: { code: true } }]],
    ['underline', [{ insert: 'u', attributes: { underline: true } }, { insert: '!' }]],
    ['multi-line text', [{ insert: 'line one\nline two' }]],
  ];
  for (const [name, delta] of cases) {
    it(name, () => {
      expect(roundTrip(delta)).toEqual(delta);
    });
  }

  it('moves edge spaces out of emphasis so it still parses', () => {
    const md = deltaToMarkdown([{ insert: 'bold ', attributes: { bold: true } }, { insert: 'text' }]);
    expect(md).toBe('**bold** text');
  });

  it('drops colour attributes but keeps the text', () => {
    expect(deltaToMarkdown([{ insert: 'red', attributes: { text_color: '#ff0000' } }])).toBe('red');
  });
});

describe('Block Markdown', () => {
  it('nests indented list items and reads images', () => {
    const nodes = markdownToNodes('- a\n  - b\n    - c\n- d\n1. one\n   - sub\n![alt](https://x.dev/i.png)');
    expect(nodes.map((n) => [n.type, n.data.indent ?? 0])).toEqual([
      ['bulleted_list', 0],
      ['bulleted_list', 1],
      ['bulleted_list', 2],
      ['bulleted_list', 0],
      ['numbered_list', 0],
      ['bulleted_list', 1],
      ['image', 0],
    ]);
    expect(nodes[6].data.url).toBe('https://x.dev/i.png');
  });

  it('exports indented lists and flattens AppFlowy children', () => {
    const md = documentToMarkdown({
      type: 'page',
      children: [
        {
          type: 'bulleted_list',
          data: { delta: [{ insert: 'parent' }] },
          children: [{ type: 'todo_list', data: { checked: true, delta: [{ insert: 'child' }] } }],
        },
      ],
    });
    expect(md).toBe('- parent\n    - [x] child\n');
    const back = markdownToNodes(md);
    expect(back.map((n) => [n.type, n.data.indent ?? 0])).toEqual([
      ['bulleted_list', 0],
      ['todo_list', 1],
    ]);
  });
});
