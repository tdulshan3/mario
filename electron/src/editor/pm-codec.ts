import type { JSONContent } from '@tiptap/core';
import type { AppFlowyDocument, AppFlowyNode, DeltaAttributes, DeltaOp } from '../shared/types';
import { findInlineMath, flattenNodes, mergeDeltaOps } from '../shared/document-codec';

/**
 * AppFlowy document JSON (what Mario stores, syncs and hands the AI) ⇄ the
 * ProseMirror JSON the editor works on.
 *
 * Text blocks map one to one; their AppFlowy `delta` becomes text nodes with
 * marks. Indented blocks are flat with an `indent` attribute (AppFlowy's nested
 * `children` are flattened on the way in). Spreadsheets, drawings, audio,
 * images, HTML and any block type the editor doesn't know become an `embed`
 * that carries the original `data` untouched, so nothing is lost on a save.
 * Data keys a block doesn't map ride along in `extra`.
 */

const KNOWN_KEYS: Record<string, string[]> = {
  paragraph: ['delta', 'align', 'indent'],
  heading: ['delta', 'align', 'indent', 'level'],
  bulleted_list: ['delta', 'align', 'indent'],
  numbered_list: ['delta', 'align', 'indent', 'number'],
  todo_list: ['delta', 'align', 'indent', 'checked'],
  quote: ['delta', 'align', 'indent'],
  divider: ['indent'],
  code: ['code', 'delta', 'language', 'indent'],
  math_equation: ['formula', 'indent'],
  table: ['colsLen', 'rowsLen', 'indent'],
};

const TEXT_TYPES = new Set(['paragraph', 'heading', 'bulleted_list', 'numbered_list', 'todo_list', 'quote']);

function extraOf(node: AppFlowyNode): Record<string, unknown> | null {
  const known = KNOWN_KEYS[node.type] ?? [];
  const extra: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(node.data ?? {})) {
    if (!known.includes(k)) extra[k] = v;
  }
  return Object.keys(extra).length > 0 ? extra : null;
}

// ── Inline ──────────────────────────────────────────────────────────────────

type PmMark = { type: string; attrs?: Record<string, unknown> };

function attrsToMarks(attrs: DeltaAttributes): PmMark[] {
  const marks: PmMark[] = [];
  const rest: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null || v === false || v === '') continue;
    switch (k) {
      case 'bold':
        marks.push({ type: 'bold' });
        break;
      case 'italic':
        marks.push({ type: 'italic' });
        break;
      case 'underline':
        marks.push({ type: 'underline' });
        break;
      case 'strikethrough':
        marks.push({ type: 'strike' });
        break;
      case 'code':
        marks.push({ type: 'code' });
        break;
      case 'href':
        marks.push({ type: 'link', attrs: { href: String(v) } });
        break;
      case 'text_color':
        marks.push({ type: 'textStyle', attrs: { color: String(v) } });
        break;
      case 'bg_color':
        marks.push({ type: 'highlight', attrs: { color: String(v) } });
        break;
      default:
        rest[k] = v;
    }
  }
  if (Object.keys(rest).length > 0) marks.push({ type: 'afAttrs', attrs: { data: rest } });
  return marks;
}

function marksToAttrs(marks?: JSONContent['marks']): DeltaAttributes {
  const attrs: DeltaAttributes = {};
  for (const m of marks ?? []) {
    switch (m.type) {
      case 'bold':
        attrs.bold = true;
        break;
      case 'italic':
        attrs.italic = true;
        break;
      case 'underline':
        attrs.underline = true;
        break;
      case 'strike':
        attrs.strikethrough = true;
        break;
      case 'code':
        attrs.code = true;
        break;
      case 'link':
        if (m.attrs?.href) attrs.href = String(m.attrs.href);
        break;
      case 'textStyle':
        if (m.attrs?.color) attrs.text_color = String(m.attrs.color);
        break;
      case 'highlight':
        if (m.attrs?.color) attrs.bg_color = String(m.attrs.color);
        break;
      case 'afAttrs':
        Object.assign(attrs, m.attrs?.data ?? {});
        break;
    }
  }
  return attrs;
}

function withMarks(node: JSONContent, marks: PmMark[]): JSONContent {
  return marks.length > 0 ? { ...node, marks } : node;
}

function pushText(out: JSONContent[], text: string, marks: PmMark[]) {
  const lines = text.split('\n');
  lines.forEach((line, i) => {
    if (i > 0) out.push({ type: 'hardBreak' });
    if (line) out.push(withMarks({ type: 'text', text: line }, marks));
  });
}

export function deltaToPmInline(delta?: DeltaOp[]): JSONContent[] {
  const out: JSONContent[] = [];
  for (const op of delta ?? []) {
    if (typeof op.insert !== 'string' || op.insert === '') continue;
    const attrs = op.attributes ?? {};
    if (attrs.formula) {
      // AppFlowy's own inline math: a "$" carrying the formula.
      const { formula, ...others } = attrs;
      out.push(
        withMarks({ type: 'inlineMath', attrs: { latex: String(formula), display: false, source: 'appflowy' } }, attrsToMarks(others)),
      );
      continue;
    }
    const marks = attrsToMarks(attrs);
    if (attrs.code) {
      pushText(out, op.insert, marks);
      continue;
    }
    let last = 0;
    for (const m of findInlineMath(op.insert)) {
      pushText(out, op.insert.slice(last, m.start), marks);
      out.push(withMarks({ type: 'inlineMath', attrs: { latex: m.tex, display: m.display, source: 'dollar' } }, marks));
      last = m.end;
    }
    pushText(out, op.insert.slice(last), marks);
  }
  return out;
}

export function pmInlineToDelta(content?: JSONContent[]): DeltaOp[] {
  const ops: DeltaOp[] = [];
  for (const n of content ?? []) {
    const attributes = marksToAttrs(n.marks);
    if (n.type === 'text') {
      ops.push({ insert: n.text ?? '', attributes });
    } else if (n.type === 'hardBreak') {
      ops.push({ insert: '\n' });
    } else if (n.type === 'inlineMath') {
      const latex = String(n.attrs?.latex ?? '');
      if (n.attrs?.source === 'appflowy') {
        ops.push({ insert: '$', attributes: { ...attributes, formula: latex } });
      } else {
        ops.push({ insert: n.attrs?.display ? `$$${latex}$$` : `$${latex}$`, attributes });
      }
    }
  }
  return mergeDeltaOps(ops);
}

function textOf(content?: JSONContent[]): string {
  return (content ?? [])
    .map((n) => (n.type === 'text' ? (n.text ?? '') : n.type === 'hardBreak' ? '\n' : textOf(n.content)))
    .join('');
}

// ── Blocks: AppFlowy → ProseMirror ──────────────────────────────────────────

function blockToPm(node: AppFlowyNode, prev: AppFlowyNode | null): JSONContent {
  const data = node.data ?? {};
  const indent = Math.max(0, Math.min(8, Number(data.indent ?? 0) || 0));
  const align = data.align === 'center' || data.align === 'right' ? data.align : null;
  const base = { id: node.id ?? null, indent, extra: extraOf(node) };
  const inline = () => deltaToPmInline(data.delta);
  switch (node.type) {
    case 'paragraph':
    case 'bulleted_list':
    case 'quote':
      return { type: node.type, attrs: { ...base, align }, content: inline() };
    case 'heading':
      return {
        type: 'heading',
        attrs: { ...base, align, level: Math.min(6, Math.max(1, Number(data.level ?? 1) || 1)) },
        content: inline(),
      };
    case 'numbered_list': {
      // Only the first item of a run carries a start number, and only when it isn't 1.
      const continues =
        prev?.type === 'numbered_list' && Number(prev.data?.indent ?? 0) === indent;
      const n = Number(data.number);
      const start = !continues && Number.isFinite(n) && n > 1 ? n : null;
      return { type: 'numbered_list', attrs: { ...base, align, start }, content: inline() };
    }
    case 'todo_list':
      return { type: 'todo_list', attrs: { ...base, align, checked: Boolean(data.checked) }, content: inline() };
    case 'divider':
      return { type: 'horizontalRule', attrs: { id: base.id, extra: base.extra } };
    case 'code': {
      const code = typeof data.code === 'string' ? data.code : textOf(deltaToPmInline(data.delta));
      const language = String(data.language ?? 'plaintext');
      return {
        type: 'codeBlock',
        attrs: { ...base, language },
        content: code ? [{ type: 'text', text: code }] : [],
      };
    }
    case 'math_equation':
      return { type: 'math_block', attrs: { ...base, formula: String(data.formula ?? '') } };
    case 'table':
      return tableToPm(node);
    default: {
      const { indent: _drop, ...rest } = data;
      return { type: 'embed', attrs: { id: base.id, indent, kind: node.type, data: rest } };
    }
  }
}

function tableToPm(node: AppFlowyNode): JSONContent {
  const cells = (node.children ?? []).filter((c) => c.type === 'table/cell');
  let rowsLen = Number(node.data?.rowsLen ?? 0);
  let colsLen = Number(node.data?.colsLen ?? 0);
  for (const c of cells) {
    rowsLen = Math.max(rowsLen, Number(c.data?.rowPosition ?? 0) + 1);
    colsLen = Math.max(colsLen, Number(c.data?.colPosition ?? 0) + 1);
  }
  rowsLen = Math.max(1, rowsLen);
  colsLen = Math.max(1, colsLen);
  const grid: (AppFlowyNode | undefined)[][] = Array.from({ length: rowsLen }, () =>
    Array.from({ length: colsLen }, () => undefined),
  );
  for (const c of cells) {
    grid[Number(c.data?.rowPosition ?? 0)][Number(c.data?.colPosition ?? 0)] = c;
  }
  return {
    type: 'table',
    attrs: { id: node.id ?? null, extra: extraOf(node) },
    content: grid.map((row) => ({
      type: 'tableRow',
      content: row.map((cell) => {
        const width = Number(cell?.data?.width);
        const blocks = flattenNodes(cell?.children ?? []);
        let prev: AppFlowyNode | null = null;
        const content = blocks.map((b) => {
          const pm = blockToPm({ ...b, id: undefined }, prev);
          prev = b;
          return pm;
        });
        return {
          type: 'tableCell',
          attrs: { colwidth: Number.isFinite(width) && width > 0 ? [width] : null },
          content: content.length > 0 ? content : [{ type: 'paragraph' }],
        };
      }),
    })),
  };
}

export function appflowyToPm(doc: AppFlowyDocument | undefined): JSONContent {
  const content: JSONContent[] = [];
  let prev: AppFlowyNode | null = null;
  for (const node of flattenNodes(doc?.children ?? [])) {
    content.push(blockToPm(node, prev));
    prev = node;
  }
  // Always an empty line after a final object or list, to click into and type;
  // pmToAppflowy drops it again on save.
  if (content.length === 0 || content[content.length - 1].type !== 'paragraph') {
    content.push({ type: 'paragraph' });
  }
  return { type: 'doc', content };
}

// ── Blocks: ProseMirror → AppFlowy ──────────────────────────────────────────

function pmBlockToAppflowy(n: JSONContent): AppFlowyNode | null {
  const a = n.attrs ?? {};
  const data: AppFlowyNode['data'] = { ...((a.extra as Record<string, unknown>) ?? {}) };
  if (a.indent) data.indent = Number(a.indent);
  if (a.align === 'center' || a.align === 'right') data.align = a.align;
  const id = (a.id as string | null) ?? undefined;
  const node = (type: string, extra: AppFlowyNode['data']): AppFlowyNode =>
    id ? { id, type, data: { ...data, ...extra } } : { type, data: { ...data, ...extra } };
  switch (n.type) {
    case 'paragraph':
    case 'bulleted_list':
    case 'quote':
      return node(n.type, { delta: pmInlineToDelta(n.content) });
    case 'heading':
      return node('heading', { level: Number(a.level ?? 1), delta: pmInlineToDelta(n.content) });
    case 'numbered_list':
      return node('numbered_list', {
        ...(a.start ? { number: Number(a.start) } : {}),
        delta: pmInlineToDelta(n.content),
      });
    case 'todo_list':
      return node('todo_list', { checked: Boolean(a.checked), delta: pmInlineToDelta(n.content) });
    case 'horizontalRule':
      return node('divider', {});
    case 'codeBlock': {
      const code = textOf(n.content);
      return node('code', { language: String(a.language || 'plaintext'), code, delta: [{ insert: code }] });
    }
    case 'math_block':
      return node('math_equation', { formula: String(a.formula ?? '') });
    case 'embed': {
      const kind = String(a.kind || 'paragraph');
      const embedData = { ...((a.data as Record<string, unknown>) ?? {}) };
      if (a.indent) embedData.indent = Number(a.indent);
      return id ? { id, type: kind, data: embedData } : { type: kind, data: embedData };
    }
    case 'table':
      return tableToAppflowy(n, id, data);
    default: {
      const text = textOf(n.content);
      return text ? node('paragraph', { delta: [{ insert: text }] }) : null;
    }
  }
}

function tableToAppflowy(n: JSONContent, id: string | undefined, data: AppFlowyNode['data']): AppFlowyNode {
  const rows = (n.content ?? []).filter((r) => r.type === 'tableRow');
  const rowsLen = Math.max(1, rows.length);
  const colsLen = Math.max(1, ...rows.map((r) => r.content?.length ?? 0));
  const children: AppFlowyNode[] = [];
  for (let c = 0; c < colsLen; c++) {
    for (let r = 0; r < rowsLen; r++) {
      const cell = rows[r]?.content?.[c];
      const width = Array.isArray(cell?.attrs?.colwidth) ? Number(cell?.attrs?.colwidth[0]) : NaN;
      const blocks = (cell?.content ?? [])
        .map(pmBlockToAppflowy)
        .filter((b): b is AppFlowyNode => b !== null)
        .map(({ id: _id, ...b }) => b);
      children.push({
        type: 'table/cell',
        data: { colPosition: c, rowPosition: r, ...(Number.isFinite(width) ? { width } : {}) },
        children: blocks.length > 0 ? blocks : [{ type: 'paragraph', data: { delta: [] } }],
      });
    }
  }
  const node: AppFlowyNode = { type: 'table', data: { ...data, colsLen, rowsLen }, children };
  return id ? { id, ...node } : node;
}

function isEmptyParagraph(node: AppFlowyNode): boolean {
  return (
    node.type === 'paragraph' &&
    !node.data?.indent &&
    (node.data?.delta ?? []).every((op) => !op.insert)
  );
}

export function pmToAppflowy(json: JSONContent): AppFlowyDocument {
  const children = (json.content ?? [])
    .map(pmBlockToAppflowy)
    .filter((b): b is AppFlowyNode => b !== null);
  // The editor keeps an empty line after the last block to type into; it isn't content.
  while (children.length > 1 && isEmptyParagraph(children[children.length - 1])) children.pop();
  if (children.length === 0) children.push({ type: 'paragraph', data: { delta: [] } });
  return { type: 'page', children };
}

export function isTextBlockType(type: string): boolean {
  return TEXT_TYPES.has(type);
}
