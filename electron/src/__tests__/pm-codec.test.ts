import { describe, expect, it } from 'vitest';
import { appflowyToPm, pmToAppflowy } from '../editor/pm-codec';
import { DEMO_PAGE_CONTENTS } from '../shared/demo-data';
import { flattenNodes } from '../shared/document-codec';
import type { AppFlowyDocument, AppFlowyNode } from '../shared/types';

/** What a save must preserve: every block's type, data and (table) cells. */
function normalise(doc: AppFlowyDocument): AppFlowyNode[] {
  const strip = (n: AppFlowyNode): AppFlowyNode => {
    const data = { ...n.data };
    if (Array.isArray(data.delta) && data.delta.length === 0) delete data.delta;
    if (n.type === 'code') {
      data.code = typeof data.code === 'string' ? data.code : (data.delta ?? []).map((o) => o.insert).join('');
      delete data.delta;
    }
    if (n.type === 'table') {
      delete data.colsLen;
      delete data.rowsLen;
    }
    if (n.type === 'numbered_list') delete data.number;
    if (n.type === 'todo_list') data.checked = Boolean(data.checked);
    const out: AppFlowyNode = { type: n.type, data };
    if (n.children?.length) out.children = n.children.map(strip);
    return out;
  };
  return flattenNodes(doc.children).map(strip);
}

const roundTrip = (doc: AppFlowyDocument) => pmToAppflowy(appflowyToPm(doc));

describe('AppFlowy ⇄ ProseMirror', () => {
  for (const [id, page] of Object.entries(DEMO_PAGE_CONTENTS)) {
    it(`keeps demo page ${id} intact`, () => {
      expect(normalise(roundTrip(page.document))).toEqual(normalise(page.document));
    });
  }

  it('keeps every block kind, ids, indents, marks and unknown data', () => {
    const doc: AppFlowyDocument = {
      type: 'page',
      children: [
        { id: 'h1aaaa', type: 'heading', data: { level: 2, delta: [{ insert: 'Title' }], align: 'center' } },
        {
          id: 'p1aaaa',
          type: 'paragraph',
          data: {
            delta: [
              { insert: 'bold', attributes: { bold: true } },
              { insert: ' and ' },
              { insert: 'red', attributes: { text_color: '#ff3b30', bg_color: 'rgba(255,214,10,0.4)' } },
              { insert: ' $E=mc^2$ ' },
              { insert: 'link', attributes: { href: 'https://x.dev', italic: true } },
              { insert: ' font', attributes: { font_family: 'Georgia' } },
              { insert: '\nsecond line' },
            ],
            custom_key: 42,
          },
        },
        { id: 'b1aaaa', type: 'bulleted_list', data: { delta: [{ insert: 'parent' }] } },
        { id: 'b2aaaa', type: 'todo_list', data: { indent: 1, checked: true, delta: [{ insert: 'child' }] } },
        { id: 'n1aaaa', type: 'numbered_list', data: { number: 3, delta: [{ insert: 'three' }] } },
        { id: 'q1aaaa', type: 'quote', data: { delta: [{ insert: 'quoted' }] } },
        { id: 'd1aaaa', type: 'divider', data: {} },
        { id: 'c1aaaa', type: 'code', data: { language: 'python', code: 'print("hi")\n  x = 1', delta: [{ insert: 'print("hi")\n  x = 1' }] } },
        { id: 'm1aaaa', type: 'math_equation', data: { formula: '\\int_0^1 x^2\\,dx' } },
        { id: 's1aaaa', type: 'spreadsheet', data: { workbook: { activeIndex: 0, sheets: [{ name: 'S', rows: 2, cols: 2, cells: { A1: '1' } }] } } },
        { id: 'i1aaaa', type: 'image', data: { url: '/tmp/a.png', width: 300, align: 'left' } },
        { id: 'x1aaaa', type: 'toggle_list', data: { delta: [{ insert: 'unknown kind' }], collapsed: true } },
        {
          id: 't1aaaa',
          type: 'table',
          data: { colsLen: 2, rowsLen: 2 },
          children: [
            { type: 'table/cell', data: { colPosition: 0, rowPosition: 0 }, children: [{ type: 'paragraph', data: { delta: [{ insert: 'A' }] } }] },
            { type: 'table/cell', data: { colPosition: 0, rowPosition: 1 }, children: [{ type: 'paragraph', data: { delta: [{ insert: '1' }] } }] },
            { type: 'table/cell', data: { colPosition: 1, rowPosition: 0 }, children: [{ type: 'paragraph', data: { delta: [{ insert: 'B', attributes: { bold: true } }] } }] },
            { type: 'table/cell', data: { colPosition: 1, rowPosition: 1 }, children: [{ type: 'paragraph', data: { delta: [{ insert: '2' }] } }] },
          ],
        },
      ],
    };
    const back = roundTrip(doc);
    expect(back.children.map((n) => n.id)).toEqual(doc.children.map((n) => n.id));
    expect(normalise(back)).toEqual(normalise(doc));
    // The start number survives on the first item of a run.
    expect(back.children[4].data.number).toBe(3);
  });

  it('flattens AppFlowy nested children into indents', () => {
    const back = roundTrip({
      type: 'page',
      children: [
        {
          type: 'bulleted_list',
          data: { delta: [{ insert: 'a' }] },
          children: [{ type: 'bulleted_list', data: { delta: [{ insert: 'b' }] } }],
        },
      ],
    });
    expect(back.children.map((n) => [n.type, n.data.indent ?? 0])).toEqual([
      ['bulleted_list', 0],
      ['bulleted_list', 1],
    ]);
  });

  it('turns $…$ into inline math and back, but not inside code', () => {
    const pm = appflowyToPm({
      type: 'page',
      children: [
        { type: 'paragraph', data: { delta: [{ insert: 'a $x^2$ b ' }, { insert: '$HOME', attributes: { code: true } }] } },
      ],
    });
    const inline = pm.content?.[0].content ?? [];
    expect(inline.map((n) => n.type)).toEqual(['text', 'inlineMath', 'text', 'text']);
    expect(pmToAppflowy(pm).children[0].data.delta).toEqual([
      { insert: 'a $x^2$ b ' },
      { insert: '$HOME', attributes: { code: true } },
    ]);
  });

  it('keeps AppFlowy formula ops in their own format', () => {
    const delta = [{ insert: 'f ' }, { insert: '$', attributes: { formula: 'a+b' } }];
    const back = roundTrip({ type: 'page', children: [{ type: 'paragraph', data: { delta } }] });
    expect(back.children[0].data.delta).toEqual(delta);
  });

  it('drops the empty line the editor keeps at the end', () => {
    const back = pmToAppflowy({
      type: 'doc',
      content: [
        { type: 'paragraph', content: [{ type: 'text', text: 'x' }] },
        { type: 'paragraph' },
      ],
    });
    expect(back.children.length).toBe(1);
  });
});
