import {
  AppFlowyDocument,
  AppFlowyNode,
  DeltaAttributes,
  DeltaOp,
  PageContent,
  SheetData,
  WorkbookData,
} from './types';
import { nanoid6 } from './ids';
import { Lexer } from 'marked';

export const EMOJI_MAP: Record<string, string> = {
  tada: '🎉',
  smile: '😄',
  rocket: '🚀',
  sparkles: '✨',
  fire: '🔥',
  heart: '❤️',
  thumbsup: '👍',
  thumbsdown: '👎',
  check: '✅',
  warning: '⚠️',
  bulb: '💡',
  book: '📖',
  memo: '📝',
  star: '⭐',
  pin: '📌',
  thinking: '🤔',
  eyes: '👀',
  wave: '👋',
  clap: '👏',
  gear: '⚙️',
  lock: '🔒',
  key: '🔑',
  calendar: '📅',
  clock: '🕒',
  link: '🔗',
};

export function expandEmojiShortcodes(text: string): string {
  return text.replace(/:([a-z0-9_+-]+):/gi, (match, name) => {
    const key = String(name).toLowerCase();
    return EMOJI_MAP[key] ?? match;
  });
}

/**
 * Fixes JSON control-char escapes (e.g. \frac -> \f + rac, \beta -> \b + eta, \tau -> \t + au)
 * and strips surrounding $$/\[...\]/\(...\) delimiters.
 */
export function normalizeLatexFormula(raw: string): string {
  if (!raw) return '';
  let s = raw
    .replace(/\f(?=[a-zA-Z])/g, '\\f')
    .replace(/[\b](?=[a-zA-Z])/g, '\\b')
    .replace(/\t(?=[a-zA-Z])/g, '\\t')
    .replace(/\r(?=[a-zA-Z])/g, '\\r')
    .replace(/\\rarr\b/g, '\\rightarrow')
    .replace(/\\larr\b/g, '\\leftarrow')
    .replace(/\\lrarr\b/g, '\\leftrightarrow')
    .replace(/\\sube\b/g, '\\subseteq')
    .replace(/\\supe\b/g, '\\supseteq')
    .trim();

  if (s.startsWith('$$') && s.endsWith('$$') && s.length >= 4) {
    s = s.slice(2, -2).trim();
  } else if (s.startsWith('\\[') && s.endsWith('\\]') && s.length >= 4) {
    s = s.slice(2, -2).trim();
  } else if (s.startsWith('\\(') && s.endsWith('\\)') && s.length >= 4) {
    s = s.slice(2, -2).trim();
  } else if (s.startsWith('$') && s.endsWith('$') && s.length >= 2) {
    s = s.slice(1, -1).trim();
  }
  return s;
}

export function ensureNodeIds(doc: AppFlowyDocument): AppFlowyDocument {
  const seen = new Set<string>();
  const assign = (node: AppFlowyNode): AppFlowyNode => {
    let id = node.id;
    if (!id || seen.has(id)) {
      do {
        id = nanoid6();
      } while (seen.has(id));
    }
    seen.add(id);
    return {
      ...node,
      id,
      data: { ...(node.data ?? {}) },
      children: node.children ? node.children.map(assign) : undefined,
    };
  };
  return {
    type: 'page',
    children: (doc?.children ?? []).map(assign),
  };
}

export function stripNodeIdsForStorage(doc: AppFlowyDocument): AppFlowyDocument {
  const clean = (node: AppFlowyNode): AppFlowyNode => {
    const copy: AppFlowyNode = {
      type: node.type,
      data: { ...(node.data ?? {}) },
    };
    if (node.children && node.children.length > 0) {
      copy.children = node.children.map(clean);
    }
    return copy;
  };
  return {
    type: 'page',
    children: (doc?.children ?? []).map(clean),
  };
}

export function emptyPageContent(title = 'Untitled page'): PageContent {
  return {
    document: {
      type: 'page',
      children: [
        {
          id: nanoid6(),
          type: 'paragraph',
          data: { delta: [] },
        },
      ],
    },
    title,
    createdAt: new Date().toISOString(),
  };
}

export function deltaToPlainText(delta?: DeltaOp[]): string {
  if (!Array.isArray(delta)) return '';
  return delta.map((op) => (typeof op.insert === 'string' ? op.insert : '')).join('');
}

// ── Inline Markdown ⇄ Delta ─────────────────────────────────────────────────
// Inline Markdown is read with marked's CommonMark/GFM inline lexer, so emphasis
// follows the same flanking rules as VS Code's preview: `snake_case_name` and
// `2 * 3 * 4` stay plain and `**bold *italic* bold**` nests. `$…$` math is cut
// out first, so `_` and `*` inside a formula are never read as emphasis; it
// stays in the delta as literal `$…$` text, which the editor renders with KaTeX.

/** Delta attributes that Markdown can express; the rest (colours, fonts) it can't. */
const MARKDOWN_ATTRS = ['bold', 'italic', 'strikethrough', 'underline', 'code', 'href'] as const;

export interface InlineMathSpan {
  start: number;
  end: number;
  tex: string;
  display: boolean;
}

/** Finds `$…$` / `$$…$$` spans outside code spans, with pandoc's rules: no space
 *  just inside either `$`, and a closing `$` is not followed by a digit — so
 *  "costs $5 and $10" is not math. */
export function findInlineMath(text: string): InlineMathSpan[] {
  const spans: InlineMathSpan[] = [];
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (ch === '\\') {
      i += 2;
      continue;
    }
    if (ch === '`') {
      let n = 1;
      while (text[i + n] === '`') n++;
      let j = i + n;
      let closed = -1;
      while (j < text.length) {
        if (text[j] === '`') {
          let m = 1;
          while (text[j + m] === '`') m++;
          if (m === n) {
            closed = j + m;
            break;
          }
          j += m;
        } else j++;
      }
      i = closed > 0 ? closed : i + n;
      continue;
    }
    if (ch === '$') {
      const span = matchMathAt(text, i);
      if (span) {
        spans.push(span);
        i = span.end;
        continue;
      }
      i += text[i + 1] === '$' ? 2 : 1;
      continue;
    }
    i++;
  }
  return spans;
}

/** The math span that starts exactly at `i` (a `$`), if there is one. */
export function matchMathAt(text: string, i: number): InlineMathSpan | null {
  if (text[i] !== '$') return null;
  if (text[i + 1] === '$') {
    const close = text.indexOf('$$', i + 2);
    return close > i + 2
      ? { start: i, end: close + 2, tex: text.slice(i + 2, close), display: true }
      : null;
  }
  const next = text[i + 1];
  if (!next || /\s/.test(next)) return null;
  let j = i + 1;
  while (j < text.length && text[j] !== '$' && text[j] !== '\n') {
    j += text[j] === '\\' ? 2 : 1;
  }
  if (j < text.length && text[j] === '$' && !/\s/.test(text[j - 1]) && !/\d/.test(text[j + 1] ?? '')) {
    return { start: i, end: j + 1, tex: text.slice(i + 1, j), display: false };
  }
  return null;
}

function cleanAttributes(attrs: DeltaAttributes): DeltaAttributes | undefined {
  const out: DeltaAttributes = {};
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null || v === false || v === '') continue;
    out[k] = v;
  }
  return Object.keys(out).length > 0 ? out : undefined;
}

function sameAttributes(a?: DeltaAttributes, b?: DeltaAttributes): boolean {
  const ka = Object.keys(a ?? {}).sort();
  const kb = Object.keys(b ?? {}).sort();
  if (ka.length !== kb.length) return false;
  return ka.every((k, i) => k === kb[i] && JSON.stringify(a![k]) === JSON.stringify(b![k]));
}

/** Joins neighbouring ops that carry the same attributes and drops empty ones. */
export function mergeDeltaOps(ops: DeltaOp[]): DeltaOp[] {
  const out: DeltaOp[] = [];
  for (const op of ops) {
    if (typeof op.insert !== 'string' || op.insert === '') continue;
    const attributes = op.attributes ? cleanAttributes(op.attributes) : undefined;
    const prev = out[out.length - 1];
    if (prev && sameAttributes(prev.attributes, attributes)) {
      prev.insert += op.insert;
    } else {
      out.push(attributes ? { insert: op.insert, attributes } : { insert: op.insert });
    }
  }
  return out;
}

type InlineToken = {
  type: string;
  raw: string;
  text?: string;
  href?: string;
  tokens?: InlineToken[];
};

export function parseInlineMarkdownToDelta(line: string): DeltaOp[] {
  const expanded = expandEmojiShortcodes(line);
  if (!expanded) return [];

  // Swap math for private-use placeholders the lexer reads as plain letters.
  const math = findInlineMath(expanded);
  let src = '';
  let last = 0;
  math.forEach((m, idx) => {
    src += expanded.slice(last, m.start) + '' + String.fromCharCode(0xe100 + idx) + '';
    last = m.end;
  });
  src += expanded.slice(last);
  const restoreMath = (text: string) =>
    text.replace(/([-])/g, (_, c: string) => {
      const m = math[c.charCodeAt(0) - 0xe100];
      return m ? expanded.slice(m.start, m.end) : '';
    });

  const hasClosedUnderline = /<u>[\s\S]*?<\/u>/i.test(src);
  let underline = false;
  const ops: DeltaOp[] = [];
  const push = (text: string | undefined, attrs: DeltaAttributes) => {
    if (!text) return;
    ops.push({
      insert: restoreMath(text),
      attributes: underline ? { ...attrs, underline: true } : attrs,
    });
  };
  const walk = (tokens: InlineToken[], attrs: DeltaAttributes) => {
    for (const t of tokens) {
      switch (t.type) {
        case 'strong':
          walk(t.tokens ?? [], { ...attrs, bold: true });
          break;
        case 'em':
          walk(t.tokens ?? [], { ...attrs, italic: true });
          break;
        case 'del':
          walk(t.tokens ?? [], { ...attrs, strikethrough: true });
          break;
        case 'codespan':
          push(t.text, { ...attrs, code: true });
          break;
        case 'link':
          walk(t.tokens ?? [], { ...attrs, href: t.href });
          break;
        case 'br':
          push('\n', attrs);
          break;
        case 'escape':
          push(t.text, attrs);
          break;
        case 'html':
          if (hasClosedUnderline && /^<u>$/i.test(t.raw)) underline = true;
          else if (hasClosedUnderline && /^<\/u>$/i.test(t.raw)) underline = false;
          else if (/^<br\s*\/?>$/i.test(t.raw)) push('\n', attrs);
          else push(t.raw, attrs);
          break;
        case 'text':
          if (t.tokens && t.tokens.length > 0) walk(t.tokens, attrs);
          else push(t.text ?? t.raw, attrs);
          break;
        default:
          // Images and anything else inline stay as their literal source.
          push(t.raw, attrs);
      }
    }
  };
  walk(Lexer.lexInline(src) as unknown as InlineToken[], {});
  const merged = mergeDeltaOps(ops);
  return merged.length > 0 ? merged : [{ insert: expanded }];
}

type OpenMark = {
  key: 'href' | 'bold' | 'italic' | 'strikethrough' | 'underline';
  value?: string;
  delim?: string;
};
const MARK_ORDER: OpenMark['key'][] = ['href', 'bold', 'italic', 'strikethrough', 'underline'];

/** Opens a mark. Emphasis right after a `*` run opens with `_` instead, or the
 *  two runs would merge into one ambiguous `****`. */
function openToken(m: OpenMark, before: string): string {
  switch (m.key) {
    case 'href':
      return '[';
    case 'bold':
      m.delim = before.endsWith('*') ? '__' : '**';
      return m.delim;
    case 'italic':
      m.delim = before.endsWith('*') ? '_' : '*';
      return m.delim;
    case 'strikethrough':
      return '~~';
    case 'underline':
      return '<u>';
  }
}

function closeToken(m: OpenMark): string {
  switch (m.key) {
    case 'href': {
      const href = m.value ?? '';
      return /[\s()<>]/.test(href) ? `](<${href}>)` : `](${href})`;
    }
    case 'bold':
    case 'italic':
      return m.delim ?? (m.key === 'bold' ? '**' : '*');
    case 'strikethrough':
      return '~~';
    case 'underline':
      return '</u>';
  }
}

function codeSpan(text: string): string {
  let longest = 0;
  for (const run of text.match(/`+/g) ?? []) longest = Math.max(longest, run.length);
  const fence = '`'.repeat(longest + 1);
  const pad = /^[`\s]|[`\s]$/.test(text) ? ' ' : '';
  return `${fence}${pad}${text}${pad}${fence}`;
}

const escapeMarkdownText = (text: string) => text.replace(/([\\`*_~[\]<>$])/g, '\\$1');

function serializeInline(ops: DeltaOp[], escapePlain: boolean): string {
  // Emphasis can't open or close against a space (`**bold **` is literal), so
  // the spaces at the edges of a bold/italic/struck run move outside it.
  const split: DeltaOp[] = [];
  for (const op of ops) {
    const a = op.attributes ?? {};
    if (!a.code && (a.bold || a.italic || a.strikethrough)) {
      const m = /^(\s*)([\s\S]*?)(\s*)$/.exec(op.insert)!;
      const plain = { ...a, bold: undefined, italic: undefined, strikethrough: undefined };
      if (m[1]) split.push({ insert: m[1], attributes: plain });
      if (m[2]) split.push({ insert: m[2], attributes: a });
      if (m[3]) split.push({ insert: m[3], attributes: plain });
    } else split.push(op);
  }

  let out = '';
  const stack: OpenMark[] = [];
  const same = (x: OpenMark, y: OpenMark) => x.key === y.key && x.value === y.value;
  for (const op of mergeDeltaOps(split)) {
    const a = op.attributes ?? {};
    const desired: OpenMark[] = MARK_ORDER.filter((k) => a[k]).map(
      (key): OpenMark => (key === 'href' ? { key, value: String(a.href) } : { key }),
    );
    // A bare URL that links to itself stays a bare URL (GFM autolinks it).
    const autolink =
      desired.length === 1 &&
      desired[0].key === 'href' &&
      !a.code &&
      desired[0].value === op.insert &&
      /^https?:\/\/[^\s<>]+$/.test(op.insert);
    let keep = 0;
    while (keep < stack.length && desired.some((d) => same(d, stack[keep]))) keep++;
    for (let k = stack.length - 1; k >= keep; k--) out += closeToken(stack[k]);
    stack.length = keep;
    if (autolink) {
      out += op.insert;
      continue;
    }
    for (const d of desired) {
      if (!stack.some((s) => same(s, d))) {
        out += openToken(d, out);
        stack.push(d);
      }
    }
    out += a.code ? codeSpan(op.insert) : escapePlain ? escapeMarkdownText(op.insert) : op.insert;
  }
  for (let k = stack.length - 1; k >= 0; k--) out += closeToken(stack[k]);
  return out;
}

function markdownView(delta: DeltaOp[]): DeltaOp[] {
  return mergeDeltaOps(
    delta.map((op) => {
      const attributes: Record<string, unknown> = {};
      for (const k of MARKDOWN_ATTRS) if (op.attributes?.[k]) attributes[k] = op.attributes[k];
      return { insert: op.insert, attributes };
    }),
  );
}

/** Delta → inline Markdown that parses back to the same delta. Plain text is
 *  written as-is when that already round-trips, and escaped only when it
 *  wouldn't (a literal `*a*` typed as text, say). Colours have no Markdown. */
export function deltaToMarkdown(delta?: DeltaOp[]): string {
  if (!Array.isArray(delta) || delta.length === 0) return '';
  const ops = markdownView(delta);
  const plain = serializeInline(ops, false);
  const roundTrips = (md: string) => {
    const back = markdownView(parseInlineMarkdownToDelta(md));
    return back.length === ops.length && back.every((op, i) => op.insert === ops[i].insert && sameAttributes(op.attributes, ops[i].attributes));
  };
  if (roundTrips(plain)) return plain;
  return serializeInline(ops, true);
}

export function extractTableRowsFromNode(node: AppFlowyNode): string[][] {
  const colsLen = Number(node.data?.colsLen ?? 0);
  const rowsLen = Number(node.data?.rowsLen ?? 0);
  if (colsLen <= 0 || rowsLen <= 0) {
    if (Array.isArray(node.data?.rows)) {
      return (node.data.rows as unknown[][]).map((r) => r.map((c) => String(c ?? '')));
    }
    return [['', ''], ['', '']];
  }
  const grid: string[][] = Array.from({ length: rowsLen }, () =>
    Array.from({ length: colsLen }, () => ''),
  );
  for (const cell of node.children ?? []) {
    if (cell.type === 'table/cell') {
      const r = Number(cell.data?.rowPosition ?? 0);
      const c = Number(cell.data?.colPosition ?? 0);
      const text = (cell.children ?? [])
        .map((ch) => deltaToPlainText(ch.data?.delta))
        .join(' ');
      if (r >= 0 && r < rowsLen && c >= 0 && c < colsLen) {
        grid[r][c] = text;
      }
    }
  }
  return grid;
}

export function buildTableNodeFromRows(rows: string[][]): AppFlowyNode {
  const rowsLen = Math.max(1, rows.length);
  const colsLen = Math.max(1, rows.reduce((m, r) => Math.max(m, r.length), 1));
  const children: AppFlowyNode[] = [];
  for (let c = 0; c < colsLen; c++) {
    for (let r = 0; r < rowsLen; r++) {
      const val = rows[r]?.[c] ?? '';
      children.push({
        type: 'table/cell',
        data: { colPosition: c, rowPosition: r },
        children: [
          {
            type: 'paragraph',
            data: { delta: parseInlineMarkdownToDelta(val) },
          },
        ],
      });
    }
  }
  return {
    id: nanoid6(),
    type: 'table',
    data: { colsLen, rowsLen },
    children,
  };
}

/**
 * AppFlowy nests indented blocks as `children`; Mario's editor keeps blocks flat
 * with `data.indent`. Flattens the first into the second (tables keep their
 * cells), so both read the same everywhere.
 */
export function flattenNodes(nodes: AppFlowyNode[], depth = 0): AppFlowyNode[] {
  const out: AppFlowyNode[] = [];
  for (const node of nodes) {
    if (node.type === 'table') {
      out.push(node);
      continue;
    }
    const indent = Number(node.data?.indent ?? 0) + depth;
    const { children, ...rest } = node;
    const data = { ...(node.data ?? {}) };
    if (indent > 0) data.indent = indent;
    else delete data.indent;
    out.push({ ...rest, data });
    if (children && children.length > 0) out.push(...flattenNodes(children, indent + 1));
  }
  return out;
}

/**
 * Converts a Mario/AppFlowy Document JSON into clean Markdown.
 * Fixes the Flutter bug where `/code` blocks threw `Delta is null` and where
 * `math_equation`, `drawing`, `spreadsheet`, and `audio_clip` were dropped!
 */
export function documentToMarkdown(docOrWrapper: AppFlowyDocument | PageContent): string {
  const doc: AppFlowyDocument =
    'document' in docOrWrapper ? docOrWrapper.document : docOrWrapper;
  const lines: string[] = [];

  for (const node of flattenNodes(doc?.children ?? [])) {
    // Four spaces per level nest under both "- " and "1. " items.
    const pad = '    '.repeat(Number(node.data?.indent ?? 0));
    switch (node.type) {
      case 'heading': {
        const level = Math.min(6, Math.max(1, Number(node.data?.level ?? 2)));
        lines.push(`${'#'.repeat(level)} ${deltaToMarkdown(node.data?.delta)}`);
        lines.push('');
        break;
      }
      case 'paragraph': {
        lines.push(deltaToMarkdown(node.data?.delta));
        break;
      }
      case 'bulleted_list': {
        lines.push(`${pad}- ${deltaToMarkdown(node.data?.delta)}`);
        break;
      }
      case 'numbered_list': {
        const num = node.data?.number ?? 1;
        lines.push(`${pad}${num}. ${deltaToMarkdown(node.data?.delta)}`);
        break;
      }
      case 'todo_list': {
        const mark = node.data?.checked ? 'x' : ' ';
        lines.push(`${pad}- [${mark}] ${deltaToMarkdown(node.data?.delta)}`);
        break;
      }
      case 'quote': {
        const text = deltaToMarkdown(node.data?.delta);
        for (const l of text.split('\n')) {
          lines.push(`> ${l}`);
        }
        lines.push('');
        break;
      }
      case 'divider': {
        lines.push('---');
        lines.push('');
        break;
      }
      case 'code': {
        const lang = String(node.data?.language ?? 'plaintext');
        const code =
          typeof node.data?.code === 'string'
            ? node.data.code
            : deltaToPlainText(node.data?.delta);
        lines.push(`\`\`\`${lang === 'plaintext' ? '' : lang}`);
        lines.push(code);
        lines.push('```');
        lines.push('');
        break;
      }
      case 'math_equation': {
        const formula = normalizeLatexFormula(
          String(node.data?.formula ?? deltaToPlainText(node.data?.delta)),
        );
        lines.push('$$');
        lines.push(formula);
        lines.push('$$');
        lines.push('');
        break;
      }
      case 'table': {
        const rows = extractTableRowsFromNode(node);
        if (rows.length > 0) {
          const header = rows[0];
          lines.push(`| ${header.map((c) => c.replace(/\|/g, '\\|')).join(' | ')} |`);
          lines.push(`| ${header.map(() => '---').join(' | ')} |`);
          for (let i = 1; i < rows.length; i++) {
            lines.push(`| ${rows[i].map((c) => c.replace(/\|/g, '\\|')).join(' | ')} |`);
          }
          lines.push('');
        }
        break;
      }
      case 'spreadsheet': {
        const wb = normalizeWorkbook(node.data);
        const sheet = wb.sheets[wb.activeIndex] ?? wb.sheets[0];
        if (sheet) {
          lines.push(`#### Spreadsheet: ${sheet.name}`);
          const maxR = Math.min(sheet.rows, 20);
          const maxC = Math.min(sheet.cols, 10);
          const headers = Array.from({ length: maxC }, (_, i) => colIndexToLabel(i));
          lines.push(`| ${headers.join(' | ')} |`);
          lines.push(`| ${headers.map(() => '---').join(' | ')} |`);
          for (let r = 1; r <= maxR; r++) {
            const rowVals = headers.map((col) =>
              String(evaluateSheetCell(sheet, `${col}${r}`)).replace(/\|/g, '\\|'),
            );
            if (rowVals.some((v) => v.trim() !== '')) {
              lines.push(`| ${rowVals.join(' | ')} |`);
            }
          }
          lines.push('');
        }
        break;
      }
      case 'drawing': {
        const strokeCount = Array.isArray(node.data?.strokes)
          ? node.data.strokes.length
          : 0;
        lines.push(`*[Drawing block: ${strokeCount} stroke${strokeCount === 1 ? '' : 's'}]*`);
        lines.push('');
        break;
      }
      case 'audio_clip': {
        const transcript = String(node.data?.transcript ?? '').trim();
        const dur = Math.round(Number(node.data?.durationMs ?? 0) / 1000);
        lines.push(
          `*[Audio clip (${dur}s)${transcript ? `: "${transcript}"` : ''}]*`,
        );
        lines.push('');
        break;
      }
      case 'image': {
        const url = String(node.data?.url ?? node.data?.drive_id ?? '');
        lines.push(`![Image](${url})`);
        lines.push('');
        break;
      }
      case 'html':
      case 'html_preview': {
        const raw = String(node.data?.html ?? '');
        lines.push('```html');
        lines.push(raw);
        lines.push('```');
        lines.push('');
        break;
      }
      default: {
        const fallback = deltaToMarkdown(node.data?.delta);
        if (fallback) lines.push(fallback);
        break;
      }
    }
  }

  return lines.join('\n').trim() + '\n';
}

/**
 * Parses Markdown text into an array of AppFlowyNode objects.
 */
export function markdownToNodes(markdown: string): AppFlowyNode[] {
  const nodes: AppFlowyNode[] = [];
  const rawLines = markdown.replace(/\r\n/g, '\n').split('\n');
  let i = 0;
  // Leading-space columns of the open list levels: a deeper column nests one level.
  let listColumns: number[] = [];
  const listIndent = (line: string): number => {
    const lead = (/^[ \t]*/.exec(line)?.[0] ?? '').replace(/\t/g, '    ').length;
    while (listColumns.length > 0 && lead < listColumns[listColumns.length - 1]) listColumns.pop();
    if (listColumns.length === 0 || lead > listColumns[listColumns.length - 1]) listColumns.push(lead);
    return listColumns.length - 1;
  };
  const withIndent = (data: AppFlowyNode['data'], indent: number) =>
    indent > 0 ? { ...data, indent } : data;

  while (i < rawLines.length) {
    const line = rawLines[i];
    const trimmed = line.trim();

    if (!trimmed) {
      i++;
      continue;
    }
    if (!/^([-*+]|\d+[.)])\s/.test(trimmed)) listColumns = [];

    // Fenced code block
    const fence = /^(`{3,}|~{3,})(.*)$/.exec(trimmed);
    if (fence) {
      const lang = fence[2].trim() || 'plaintext';
      i++;
      const codeLines: string[] = [];
      while (i < rawLines.length && !rawLines[i].trim().startsWith(fence[1])) {
        codeLines.push(rawLines[i]);
        i++;
      }
      if (i < rawLines.length) i++;
      const code = codeLines.join('\n');
      nodes.push({
        id: nanoid6(),
        type: 'code',
        data: { language: lang, code, delta: [{ insert: code }] },
      });
      continue;
    }

    // A line that is only an image
    const imageMatch = /^!\[([^\]]*)\]\(<?([^)\s>]+)>?(?:\s+"[^"]*")?\)$/.exec(trimmed);
    if (imageMatch) {
      nodes.push({
        id: nanoid6(),
        type: 'image',
        data: { url: imageMatch[2], width: 520, align: 'center' },
      });
      i++;
      continue;
    }

    // Block math $$...$$
    if (trimmed.startsWith('$$')) {
      if (trimmed.endsWith('$$') && trimmed.length > 4) {
        nodes.push({
          id: nanoid6(),
          type: 'math_equation',
          data: { formula: normalizeLatexFormula(trimmed.slice(2, -2)) },
        });
        i++;
        continue;
      }
      i++;
      const mathLines: string[] = [];
      while (i < rawLines.length && !rawLines[i].trim().startsWith('$$')) {
        mathLines.push(rawLines[i]);
        i++;
      }
      if (i < rawLines.length) i++;
      nodes.push({
        id: nanoid6(),
        type: 'math_equation',
        data: { formula: normalizeLatexFormula(mathLines.join('\n')) },
      });
      continue;
    }

    // Divider
    if (/^(-{3,}|\*{3,}|_{3,})$/.test(trimmed)) {
      nodes.push({ id: nanoid6(), type: 'divider', data: {} });
      i++;
      continue;
    }

    // Heading
    const headingMatch = /^(#{1,6})\s+(.+)$/.exec(trimmed);
    if (headingMatch) {
      nodes.push({
        id: nanoid6(),
        type: 'heading',
        data: {
          level: headingMatch[1].length,
          delta: parseInlineMarkdownToDelta(headingMatch[2]),
        },
      });
      i++;
      continue;
    }

    // Markdown Table
    if (
      trimmed.startsWith('|') &&
      i + 1 < rawLines.length &&
      /^\|\s*[-:]+/.test(rawLines[i + 1].trim())
    ) {
      const parseRow = (r: string) =>
        r
          .trim()
          .replace(/^\|/, '')
          .replace(/\|$/, '')
          .split('|')
          .map((c) => c.trim());
      const tableRows: string[][] = [parseRow(trimmed)];
      i += 2; // skip header & separator
      while (i < rawLines.length && rawLines[i].trim().startsWith('|')) {
        tableRows.push(parseRow(rawLines[i]));
        i++;
      }
      nodes.push(buildTableNodeFromRows(tableRows));
      continue;
    }

    // Todo list
    const todoMatch = /^[-*+]\s+\[([ xX])\]\s+(.*)$/.exec(trimmed);
    if (todoMatch) {
      nodes.push({
        id: nanoid6(),
        type: 'todo_list',
        data: withIndent(
          {
            checked: todoMatch[1].toLowerCase() === 'x',
            delta: parseInlineMarkdownToDelta(todoMatch[2]),
          },
          listIndent(line),
        ),
      });
      i++;
      continue;
    }

    // Bulleted list
    const bulletMatch = /^[-*+]\s+(.*)$/.exec(trimmed);
    if (bulletMatch) {
      nodes.push({
        id: nanoid6(),
        type: 'bulleted_list',
        data: withIndent(
          { delta: parseInlineMarkdownToDelta(bulletMatch[1]) },
          listIndent(line),
        ),
      });
      i++;
      continue;
    }

    // Numbered list
    const numMatch = /^(\d+)[.)]\s+(.*)$/.exec(trimmed);
    if (numMatch) {
      nodes.push({
        id: nanoid6(),
        type: 'numbered_list',
        data: withIndent(
          {
            number: parseInt(numMatch[1], 10),
            delta: parseInlineMarkdownToDelta(numMatch[2]),
          },
          listIndent(line),
        ),
      });
      i++;
      continue;
    }

    // Quote / GitHub Alert
    if (trimmed.startsWith('>')) {
      const quoteLines: string[] = [];
      while (i < rawLines.length && rawLines[i].trim().startsWith('>')) {
        quoteLines.push(rawLines[i].trim().replace(/^>\s?/, ''));
        i++;
      }
      const alertMatch = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(.*)$/i.exec(
        quoteLines[0] ?? '',
      );
      if (alertMatch) {
        const kind = alertMatch[1].toUpperCase();
        const title = kind.charAt(0) + kind.slice(1).toLowerCase();
        const body = [alertMatch[2], ...quoteLines.slice(1)]
          .filter(Boolean)
          .join('\n');
        nodes.push({
          id: nanoid6(),
          type: 'quote',
          data: {
            delta: [
              { insert: title, attributes: { bold: true } },
              ...(body ? [{ insert: `\n${body}` }] : []),
            ],
          },
        });
      } else {
        nodes.push({
          id: nanoid6(),
          type: 'quote',
          data: { delta: parseInlineMarkdownToDelta(quoteLines.join('\n')) },
        });
      }
      continue;
    }

    // Paragraph
    nodes.push({
      id: nanoid6(),
      type: 'paragraph',
      data: { delta: parseInlineMarkdownToDelta(trimmed) },
    });
    i++;
  }

  return nodes.length > 0
    ? nodes
    : [{ id: nanoid6(), type: 'paragraph', data: { delta: [] } }];
}

/**
 * Renders labelled blocks `[id:<6char>] ...` for the AI prompt (`NoteContext.renderBlocksForPrompt`).
 */
export function renderBlocksForPrompt(doc: AppFlowyDocument, maxChars = 48000): string {
  const lines: string[] = [];
  let total = 0;
  for (const node of doc.children) {
    const id = node.id ?? 'block';
    let body = '';
    switch (node.type) {
      case 'heading': {
        const lvl = Number(node.data?.level ?? 2);
        body = `${'#'.repeat(lvl)} ${deltaToPlainText(node.data?.delta)}`;
        break;
      }
      case 'bulleted_list':
        body = `- ${deltaToPlainText(node.data?.delta)}`;
        break;
      case 'numbered_list':
        body = `1. ${deltaToPlainText(node.data?.delta)}`;
        break;
      case 'todo_list':
        body = `- [${node.data?.checked ? 'x' : ' '}] ${deltaToPlainText(node.data?.delta)}`;
        break;
      case 'quote':
        body = `> ${deltaToPlainText(node.data?.delta)}`;
        break;
      case 'divider':
        body = '---';
        break;
      case 'code':
        body = `\`\`\`${node.data?.language ?? ''}\n${node.data?.code ?? deltaToPlainText(node.data?.delta)}\n\`\`\``;
        break;
      case 'math_equation':
        body = `$$${node.data?.formula ?? ''}$$`;
        break;
      case 'table': {
        const rows = extractTableRowsFromNode(node);
        body = rows.map((r) => `| ${r.join(' | ')} |`).join('\n');
        break;
      }
      case 'spreadsheet': {
        const wb = normalizeWorkbook(node.data);
        const s = wb.sheets[wb.activeIndex] ?? wb.sheets[0];
        body = `[spreadsheet: ${s?.name ?? 'Sheet1'}]`;
        break;
      }
      default:
        body = deltaToPlainText(node.data?.delta);
        break;
    }
    const line = `[id:${id}] ${body}`;
    if (total + line.length > maxChars) break;
    lines.push(line);
    total += line.length + 1;
  }
  return lines.join('\n');
}

// ── Spreadsheet Helpers & Evaluator ─────────────────────────────────────────

export function colIndexToLabel(index: number): string {
  let n = index;
  let label = '';
  while (n >= 0) {
    label = String.fromCharCode((n % 26) + 65) + label;
    n = Math.floor(n / 26) - 1;
  }
  return label;
}

export function labelToColIndex(label: string): number {
  let result = 0;
  const upper = label.toUpperCase();
  for (let i = 0; i < upper.length; i++) {
    result = result * 26 + (upper.charCodeAt(i) - 64);
  }
  return result - 1;
}

function normalizeCellsMap(rawCells?: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  if (!rawCells || typeof rawCells !== 'object') return out;
  for (const [k, v] of Object.entries(rawCells)) {
    const strVal = v == null ? '' : String(v);
    if (!strVal) continue;
    const rcMatch = /^(\d+),(\d+)$/.exec(k.trim());
    if (rcMatch) {
      const r = parseInt(rcMatch[1], 10);
      const c = parseInt(rcMatch[2], 10);
      out[`${colIndexToLabel(c)}${r + 1}`] = strVal;
    } else {
      out[k.trim().toUpperCase()] = strVal;
    }
  }
  return out;
}

export function normalizeWorkbook(data?: Record<string, unknown>): WorkbookData {
  let rawWb: unknown = data?.workbook ?? data?.data;
  if (typeof rawWb === 'string') {
    try {
      rawWb = JSON.parse(rawWb);
    } catch {
      rawWb = undefined;
    }
  }
  const wb = rawWb as (Partial<WorkbookData> & { active?: number }) | undefined;
  if (wb && Array.isArray(wb.sheets) && wb.sheets.length > 0) {
    const activeIdx = wb.activeIndex ?? wb.active ?? 0;
    return {
      activeIndex: Math.min(wb.sheets.length - 1, Math.max(0, Number(activeIdx))),
      sheets: wb.sheets.map((s, i) => ({
        name: s.name || `Sheet${i + 1}`,
        rows: Math.max(1, Number(s.rows ?? 8)),
        cols: Math.max(1, Number(s.cols ?? 6)),
        cells: normalizeCellsMap(s.cells as Record<string, unknown>),
      })),
    };
  }
  return {
    activeIndex: 0,
    sheets: [
      {
        name: 'Sheet1',
        rows: Math.max(1, Number(data?.rows ?? 8)),
        cols: Math.max(1, Number(data?.cols ?? 6)),
        cells: normalizeCellsMap(data?.cells as Record<string, unknown>),
      },
    ],
  };
}

export function expandCellRange(startRef: string, endRef: string): string[] {
  const m1 = /^([A-Z]+)(\d+)$/i.exec(startRef.trim());
  const m2 = /^([A-Z]+)(\d+)$/i.exec(endRef.trim());
  if (!m1 || !m2) return [];
  const c1 = labelToColIndex(m1[1]);
  const r1 = parseInt(m1[2], 10);
  const c2 = labelToColIndex(m2[1]);
  const r2 = parseInt(m2[2], 10);
  const refs: string[] = [];
  for (let r = Math.min(r1, r2); r <= Math.max(r1, r2); r++) {
    for (let c = Math.min(c1, c2); c <= Math.max(c1, c2); c++) {
      refs.push(`${colIndexToLabel(c)}${r}`);
    }
  }
  return refs;
}

export function evaluateSheetCell(
  sheet: SheetData,
  cellKey: string,
  visited: Set<string> = new Set(),
): string {
  const key = cellKey.toUpperCase();
  const raw = (sheet.cells[key] ?? '').trim();
  if (!raw.startsWith('=')) return raw;
  if (visited.has(key)) return '#CYCLE!';
  visited.add(key);

  const expr = raw.slice(1).trim();
  let hasCycle = false;
  const numVal = (ref: string): number => {
    const v = evaluateSheetCell(sheet, ref, new Set(visited));
    if (v === '#CYCLE!') {
      hasCycle = true;
      return 0;
    }
    const n = parseFloat(v);
    return Number.isFinite(n) ? n : 0;
  };

  // Range functions: SUM, AVERAGE, AVG, MIN, MAX, COUNT
  const fnReplaced = expr.replace(
    /\b(SUM|AVERAGE|AVG|MIN|MAX|COUNT)\s*\(\s*([^)]+)\s*\)/gi,
    (_, fnName: string, argsStr: string) => {
      const fn = fnName.toUpperCase();
      const nums: number[] = [];
      for (const part of argsStr.split(',')) {
        const p = part.trim();
        if (p.includes(':')) {
          const [a, b] = p.split(':');
          for (const ref of expandCellRange(a, b)) {
            const rawCell = (sheet.cells[ref] ?? '').trim();
            if (rawCell !== '') nums.push(numVal(ref));
          }
        } else if (/^[A-Z]+\d+$/i.test(p)) {
          const rawCell = (sheet.cells[p.toUpperCase()] ?? '').trim();
          if (rawCell !== '') nums.push(numVal(p));
        } else {
          const n = parseFloat(p);
          if (Number.isFinite(n)) nums.push(n);
        }
      }
      if (fn === 'COUNT') return String(nums.length);
      if (nums.length === 0) return '0';
      if (fn === 'SUM') return String(nums.reduce((a, b) => a + b, 0));
      if (fn === 'AVERAGE' || fn === 'AVG') {
        return String(nums.reduce((a, b) => a + b, 0) / nums.length);
      }
      if (fn === 'MIN') return String(Math.min(...nums));
      if (fn === 'MAX') return String(Math.max(...nums));
      return '0';
    },
  );

  // Replace individual cell references like A1, B2
  const arithmetic = fnReplaced.replace(/\b([A-Z]+\d+)\b/gi, (ref) =>
    String(numVal(ref)),
  );

  if (hasCycle) return '#CYCLE!';
  if (!/^[0-9+\-*/().\s]+$/.test(arithmetic)) {
    return '#ERR';
  }
  try {
    const val = Function(`"use strict"; return (${arithmetic});`)();
    if (typeof val === 'number' && Number.isFinite(val)) {
      return Number.isInteger(val) ? String(val) : String(Math.round(val * 10000) / 10000);
    }
    return '#ERR';
  } catch {
    return '#ERR';
  }
}

export function applyDeltaMarksToRange(
  delta: DeltaOp[],
  mark: keyof DeltaAttributes,
  value: unknown,
): DeltaOp[] {
  if (!delta || delta.length === 0) return [];
  return delta.map((op) => ({
    insert: op.insert,
    attributes: {
      ...(op.attributes ?? {}),
      [mark]: value,
    },
  }));
}

export function markdownToDocument(markdown: string): AppFlowyDocument {
  return {
    type: 'page',
    children: markdownToNodes(markdown),
  };
}

export function makeParagraphNode(text = ''): AppFlowyNode {
  return {
    id: nanoid6(),
    type: 'paragraph',
    data: { delta: text ? parseInlineMarkdownToDelta(text) : [] },
  };
}

export function makeHeadingNode(level: number, text = ''): AppFlowyNode {
  return {
    id: nanoid6(),
    type: 'heading',
    data: {
      level: Math.min(6, Math.max(1, level)),
      delta: text ? parseInlineMarkdownToDelta(text) : [],
    },
  };
}

export function makeListNode(
  type: 'bulleted_list' | 'numbered_list' | 'todo_list',
  text = '',
  checked = false,
): AppFlowyNode {
  return {
    id: nanoid6(),
    type,
    data: {
      ...(type === 'todo_list' ? { checked } : {}),
      delta: text ? parseInlineMarkdownToDelta(text) : [],
    },
  };
}

export function makeQuoteNode(text = ''): AppFlowyNode {
  return {
    id: nanoid6(),
    type: 'quote',
    data: { delta: text ? parseInlineMarkdownToDelta(text) : [] },
  };
}

export function makeCodeNode(code = '', language = 'python'): AppFlowyNode {
  return {
    id: nanoid6(),
    type: 'code',
    data: {
      language,
      code,
      delta: [{ insert: code }],
    },
  };
}

export function makeMathNode(formula = 'E = mc^2'): AppFlowyNode {
  return {
    id: nanoid6(),
    type: 'math_equation',
    data: { formula: normalizeLatexFormula(formula) },
  };
}

export function makeDividerNode(): AppFlowyNode {
  return {
    id: nanoid6(),
    type: 'divider',
    data: {},
  };
}

export function makeDrawingNode(
  strokes: import('./types').Stroke[] = [],
  height = 220,
): AppFlowyNode {
  return {
    id: nanoid6(),
    type: 'drawing',
    data: { strokes, height },
  };
}

export function makeSpreadsheetNode(workbook: WorkbookData): AppFlowyNode {
  return {
    id: nanoid6(),
    type: 'spreadsheet',
    data: { workbook },
  };
}

export function makeHtmlNode(
  html = '<div style="padding:16px;background:#f6f8fa;border-radius:8px;font-family:sans-serif;">\n  <h3 style="margin-top:0">Interactive HTML</h3>\n  <p>Render custom HTML, charts, embeds, or formatted widgets.</p>\n</div>',
): AppFlowyNode {
  return {
    id: nanoid6(),
    type: 'html',
    data: { html },
  };
}

export const makeTableNode = buildTableNodeFromRows;

export function defaultSettings(): import('./types').SettingsState {
  return {
    themeMode: 'system',
    fontScale: 1.0,
    canvasWidth: 'medium',
    autoCorrectMath: true,
    spellCheck: true,
    holdToRecord: false,
    voiceLocale: 'en_US',
    offlineMode: false,
    askOnHighlight: true,
  };
}

