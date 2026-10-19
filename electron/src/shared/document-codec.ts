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

export function deltaToMarkdown(delta?: DeltaOp[]): string {
  if (!Array.isArray(delta) || delta.length === 0) return '';
  return delta
    .map((op) => {
      const text = typeof op.insert === 'string' ? op.insert : '';
      if (!text) return '';
      const a = op.attributes;
      if (!a) return text;
      let out = text;
      if (a.code) out = `\`${out}\``;
      if (a.bold) out = `**${out}**`;
      if (a.italic) out = `*${out}*`;
      if (a.strikethrough) out = `~~${out}~~`;
      if (a.underline) out = `<u>${out}</u>`;
      if (a.href) out = `[${out}](${a.href})`;
      return out;
    })
    .join('');
}

export function parseInlineMarkdownToDelta(line: string): DeltaOp[] {
  const expanded = expandEmojiShortcodes(line);
  if (!expanded) return [];
  const ops: DeltaOp[] = [];
  // Tokenize links, inline code, bold, italic, strikethrough
  const pattern =
    /(\[([^\]]+)\]\(([^)]+)\)|`([^`]+)`|\*\*([^*]+)\*\*|__([^_]+)__|~~([^~]+)~~|\*([^*]+)\*|_([^_]+)_)/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(expanded)) !== null) {
    if (match.index > lastIndex) {
      ops.push({ insert: expanded.slice(lastIndex, match.index) });
    }
    if (match[2] !== undefined && match[3] !== undefined) {
      ops.push({ insert: match[2], attributes: { href: match[3] } });
    } else if (match[4] !== undefined) {
      ops.push({ insert: match[4], attributes: { code: true } });
    } else if (match[5] !== undefined || match[6] !== undefined) {
      ops.push({ insert: match[5] ?? match[6], attributes: { bold: true } });
    } else if (match[7] !== undefined) {
      ops.push({ insert: match[7], attributes: { strikethrough: true } });
    } else if (match[8] !== undefined || match[9] !== undefined) {
      ops.push({ insert: match[8] ?? match[9], attributes: { italic: true } });
    }
    lastIndex = pattern.lastIndex;
  }
  if (lastIndex < expanded.length) {
    ops.push({ insert: expanded.slice(lastIndex) });
  }
  return ops.length > 0 ? ops : [{ insert: expanded }];
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
 * Converts a Mario/AppFlowy Document JSON into clean Markdown.
 * Fixes the Flutter bug where `/code` blocks threw `Delta is null` and where
 * `math_equation`, `drawing`, `spreadsheet`, and `audio_clip` were dropped!
 */
export function documentToMarkdown(docOrWrapper: AppFlowyDocument | PageContent): string {
  const doc: AppFlowyDocument =
    'document' in docOrWrapper ? docOrWrapper.document : docOrWrapper;
  const lines: string[] = [];

  for (const node of doc?.children ?? []) {
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
        lines.push(`- ${deltaToMarkdown(node.data?.delta)}`);
        break;
      }
      case 'numbered_list': {
        const num = node.data?.number ?? 1;
        lines.push(`${num}. ${deltaToMarkdown(node.data?.delta)}`);
        break;
      }
      case 'todo_list': {
        const mark = node.data?.checked ? 'x' : ' ';
        lines.push(`- [${mark}] ${deltaToMarkdown(node.data?.delta)}`);
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

  while (i < rawLines.length) {
    const line = rawLines[i];
    const trimmed = line.trim();

    if (!trimmed) {
      i++;
      continue;
    }

    // Fenced code block
    if (trimmed.startsWith('```')) {
      const lang = trimmed.slice(3).trim() || 'plaintext';
      i++;
      const codeLines: string[] = [];
      while (i < rawLines.length && !rawLines[i].trim().startsWith('```')) {
        codeLines.push(rawLines[i]);
        i++;
      }
      if (i < rawLines.length) i++;
      nodes.push({
        id: nanoid6(),
        type: 'code',
        data: { language: lang, code: codeLines.join('\n') },
      });
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
        data: {
          checked: todoMatch[1].toLowerCase() === 'x',
          delta: parseInlineMarkdownToDelta(todoMatch[2]),
        },
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
        data: { delta: parseInlineMarkdownToDelta(bulletMatch[1]) },
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
        data: {
          number: parseInt(numMatch[1], 10),
          delta: parseInlineMarkdownToDelta(numMatch[2]),
        },
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
      data: { delta: parseInlineMarkdownToDelta(line) },
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

