import { Extension, InputRule, Mark, Node, mergeAttributes, type Editor } from '@tiptap/core';
import Code from '@tiptap/extension-code';
import Heading from '@tiptap/extension-heading';
import type { Node as PmNode, NodeType } from '@tiptap/pm/model';
import { NodeSelection, Plugin, PluginKey, TextSelection, type EditorState, type Transaction } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';
import { ReactNodeViewRenderer } from '@tiptap/react';
import katex from 'katex';
import { EMOJI_MAP, findInlineMath, normalizeLatexFormula } from '../shared/document-codec';
import { nanoid6 } from '../shared/ids';
import { CodeBlockView, EmbedView, MathBlockView } from './node-views';

/** Lines that carry a marker: bullet, number or checkbox. */
export const LIST_TYPES = ['bulleted_list', 'numbered_list', 'todo_list'];
export const TEXT_BLOCKS = ['paragraph', 'heading', ...LIST_TYPES, 'quote'];
const INDENTABLE = [...TEXT_BLOCKS, 'codeBlock', 'math_block', 'embed'];
const ID_BLOCKS = [...INDENTABLE, 'horizontalRule', 'table'];
const MAX_INDENT = 8;

// ── Attributes every block shares ───────────────────────────────────────────

export const BlockAttributes = Extension.create({
  name: 'marioBlockAttributes',
  addGlobalAttributes() {
    return [
      {
        types: ID_BLOCKS,
        attributes: {
          // The AppFlowy block id: the AI agent addresses blocks by it.
          id: {
            default: null,
            keepOnSplit: false,
            parseHTML: (el) => el.getAttribute('data-block-id'),
            renderHTML: (a) => (a.id ? { 'data-block-id': a.id } : {}),
          },
          extra: { default: null, rendered: false, keepOnSplit: false },
        },
      },
      {
        types: INDENTABLE,
        attributes: {
          indent: {
            default: 0,
            parseHTML: (el) => Math.min(MAX_INDENT, Number(el.getAttribute('data-indent')) || 0),
            renderHTML: (a) =>
              a.indent ? { 'data-indent': String(a.indent), style: `--indent: ${a.indent}` } : {},
          },
        },
      },
      {
        types: TEXT_BLOCKS,
        attributes: {
          align: {
            default: null,
            parseHTML: (el) => {
              const v = el.style.textAlign;
              return v === 'center' || v === 'right' ? v : null;
            },
            renderHTML: (a) => (a.align ? { style: `text-align: ${a.align}` } : {}),
          },
        },
      },
    ];
  },
});

/** Keeps delta attributes the editor has no mark for (fonts, mentions…) through a save. */
export const AppFlowyAttrs = Mark.create({
  name: 'afAttrs',
  addAttributes() {
    return { data: { default: null, rendered: false } };
  },
  parseHTML() {
    return [];
  },
  renderHTML() {
    return ['span', 0];
  },
});

/** Inline code that can also be bold, italic or linked, as Markdown allows. */
export const MarioCode = Code.extend({ excludes: 'code' });

/** Headings keep their block id and indent when `#` turns a line into one. */
export const MarioHeading = Heading.extend({
  addInputRules() {
    return [];
  },
  addKeyboardShortcuts() {
    return {};
  },
});

// ── Lines with a marker ─────────────────────────────────────────────────────

function lineRender(cls: string) {
  return ({ HTMLAttributes }: { HTMLAttributes: Record<string, unknown> }) =>
    [
      'div',
      mergeAttributes(HTMLAttributes, { class: `mario-line ${cls}` }),
      ['div', { class: 'mario-line__content' }, 0],
    ] as const;
}

const isOrderedItem = (el: HTMLElement) =>
  el.getAttribute('data-list') === 'ol' || el.parentElement?.tagName === 'OL';
const isTaskItem = (el: HTMLElement) =>
  el.hasAttribute('data-checked') || !!el.querySelector(':scope > input[type="checkbox"]');

export const BulletedList = Node.create({
  name: 'bulleted_list',
  group: 'block',
  content: 'inline*',
  defining: true,
  parseHTML() {
    return [
      { tag: 'div.mario-line--bullet', contentElement: '.mario-line__content', priority: 60 },
      {
        tag: 'li',
        getAttrs: (el) => (isOrderedItem(el as HTMLElement) || isTaskItem(el as HTMLElement) ? false : null),
      },
    ];
  },
  renderHTML: lineRender('mario-line--bullet'),
});

export const NumberedList = Node.create({
  name: 'numbered_list',
  group: 'block',
  content: 'inline*',
  defining: true,
  addAttributes() {
    return {
      start: {
        default: null,
        parseHTML: (el) => Number(el.getAttribute('data-start')) || null,
        renderHTML: (a) => (a.start ? { 'data-start': String(a.start) } : {}),
      },
    };
  },
  parseHTML() {
    return [
      { tag: 'div.mario-line--numbered', contentElement: '.mario-line__content', priority: 60 },
      {
        tag: 'li',
        getAttrs: (el) => (isOrderedItem(el as HTMLElement) && !isTaskItem(el as HTMLElement) ? null : false),
      },
    ];
  },
  renderHTML: lineRender('mario-line--numbered'),
});

export const TodoList = Node.create({
  name: 'todo_list',
  group: 'block',
  content: 'inline*',
  defining: true,
  addAttributes() {
    return {
      checked: {
        default: false,
        parseHTML: (el) =>
          el.getAttribute('data-checked') === 'true' ||
          !!(el.querySelector(':scope > input[type="checkbox"]') as HTMLInputElement | null)?.checked,
        renderHTML: (a) => ({ 'data-checked': a.checked ? 'true' : 'false' }),
      },
    };
  },
  parseHTML() {
    return [
      { tag: 'div.mario-line--todo', contentElement: '.mario-line__content', priority: 60 },
      { tag: 'li', getAttrs: (el) => (isTaskItem(el as HTMLElement) ? null : false), priority: 55 },
    ];
  },
  renderHTML: lineRender('mario-line--todo'),
  addNodeView() {
    return ({ node, getPos, editor }) => {
      let current = node;
      const dom = document.createElement('div');
      const box = document.createElement('span');
      box.className = 'mario-todo__box';
      box.contentEditable = 'false';
      const input = document.createElement('input');
      input.type = 'checkbox';
      input.className = 'mac-checkbox';
      input.tabIndex = -1;
      input.setAttribute('aria-label', 'Done');
      box.append(input);
      const content = document.createElement('div');
      content.className = 'mario-line__content';
      dom.append(box, content);

      const apply = (n: PmNode) => {
        dom.className = `mario-line mario-line--todo${n.attrs.checked ? ' is-checked' : ''}`;
        dom.setAttribute('data-checked', n.attrs.checked ? 'true' : 'false');
        if (n.attrs.indent) {
          dom.setAttribute('data-indent', String(n.attrs.indent));
          dom.style.setProperty('--indent', String(n.attrs.indent));
        } else {
          dom.removeAttribute('data-indent');
          dom.style.removeProperty('--indent');
        }
        dom.style.textAlign = n.attrs.align ?? '';
        if (n.attrs.id) dom.setAttribute('data-block-id', n.attrs.id);
        input.checked = Boolean(n.attrs.checked);
      };
      apply(node);
      input.addEventListener('mousedown', (e) => e.preventDefault());
      input.addEventListener('change', () => {
        const pos = typeof getPos === 'function' ? getPos() : undefined;
        if (typeof pos !== 'number') return;
        editor.view.dispatch(
          editor.state.tr.setNodeMarkup(pos, undefined, { ...current.attrs, checked: input.checked }),
        );
      });
      return {
        dom,
        contentDOM: content,
        update: (n: PmNode) => {
          if (n.type !== current.type) return false;
          current = n;
          apply(n);
          return true;
        },
        stopEvent: (e: Event) => box.contains(e.target as globalThis.Node),
        ignoreMutation: (m) =>
          m.type !== 'selection' && (box.contains(m.target as globalThis.Node) || m.target === dom),
      };
    };
  },
});

export const Quote = Node.create({
  name: 'quote',
  group: 'block',
  content: 'inline*',
  defining: true,
  parseHTML() {
    return [{ tag: 'blockquote' }];
  },
  renderHTML({ HTMLAttributes }) {
    return ['blockquote', mergeAttributes(HTMLAttributes, { class: 'mario-quote' }), 0];
  },
});

// ── Math and embedded blocks ────────────────────────────────────────────────

export const MathBlock = Node.create({
  name: 'math_block',
  group: 'block',
  atom: true,
  selectable: true,
  draggable: true,
  addAttributes() {
    return {
      formula: {
        default: '',
        parseHTML: (el) => el.getAttribute('data-formula') ?? '',
        renderHTML: (a) => ({ 'data-formula': a.formula }),
      },
    };
  },
  parseHTML() {
    return [{ tag: 'div[data-type="math-block"]' }];
  },
  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { 'data-type': 'math-block' })];
  },
  renderText({ node }) {
    return `$$\n${node.attrs.formula}\n$$`;
  },
  addNodeView() {
    return ReactNodeViewRenderer(MathBlockView);
  },
});

export const InlineMath = Node.create({
  name: 'inlineMath',
  group: 'inline',
  inline: true,
  atom: true,
  selectable: true,
  addAttributes() {
    return {
      latex: { default: '', parseHTML: (el) => el.getAttribute('data-latex') ?? '' },
      display: { default: false, rendered: false },
      source: { default: 'dollar', rendered: false },
    };
  },
  parseHTML() {
    return [{ tag: 'span[data-type="inline-math"]' }];
  },
  renderHTML({ node, HTMLAttributes }) {
    return [
      'span',
      mergeAttributes(HTMLAttributes, { 'data-type': 'inline-math', 'data-latex': node.attrs.latex }),
      `$${node.attrs.latex}$`,
    ];
  },
  renderText({ node }) {
    return `$${node.attrs.latex}$`;
  },
  addNodeView() {
    return ({ node, getPos, editor }) => {
      const dom = document.createElement('span');
      dom.className = 'mario-inline-math';
      dom.contentEditable = 'false';
      const render = (n: PmNode) => {
        dom.innerHTML = katex.renderToString(normalizeLatexFormula(String(n.attrs.latex) || '\\square'), {
          displayMode: Boolean(n.attrs.display),
          throwOnError: false,
        });
        dom.title = `$${n.attrs.latex}$ — double-click to edit`;
      };
      render(node);
      // Editing a formula turns it back into its `$…$` source; leaving the line renders it again.
      dom.addEventListener('dblclick', (e) => {
        e.preventDefault();
        const pos = typeof getPos === 'function' ? getPos() : undefined;
        if (typeof pos !== 'number') return;
        const current = editor.state.doc.nodeAt(pos);
        if (!current) return;
        const source = `$${current.attrs.latex}$`;
        const tr = editor.state.tr.replaceWith(pos, pos + current.nodeSize, editor.schema.text(source, current.marks));
        tr.setSelection(TextSelection.create(tr.doc, pos + source.length - 1));
        editor.view.dispatch(tr);
        editor.view.focus();
      });
      return {
        dom,
        update: (n: PmNode) => {
          if (n.type.name !== 'inlineMath') return false;
          render(n);
          return true;
        },
        ignoreMutation: () => true,
      };
    };
  },
});

export const Embed = Node.create({
  name: 'embed',
  group: 'block',
  atom: true,
  selectable: true,
  draggable: true,
  addAttributes() {
    return {
      kind: {
        default: 'unknown',
        parseHTML: (el) => el.getAttribute('data-kind') ?? 'unknown',
        renderHTML: (a) => ({ 'data-kind': a.kind }),
      },
      data: {
        default: {},
        parseHTML: (el) => {
          try {
            return JSON.parse(el.getAttribute('data-json') ?? '{}');
          } catch {
            return {};
          }
        },
        renderHTML: (a) => ({ 'data-json': JSON.stringify(a.data ?? {}) }),
      },
    };
  },
  parseHTML() {
    return [
      { tag: 'div[data-type="embed"]' },
      {
        tag: 'img[src]',
        getAttrs: (el) => ({
          kind: 'image',
          data: { url: (el as HTMLImageElement).getAttribute('src'), width: 520, align: 'center' },
        }),
      },
    ];
  },
  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { 'data-type': 'embed' })];
  },
  addNodeView() {
    // Canvases, cells and players keep their own pointer and key events.
    return ReactNodeViewRenderer(EmbedView, {
      stopEvent: ({ event }) =>
        !!(event.target as Element | null)?.closest?.('[data-interactive], .mario-block-bar'),
    });
  },
});

/** Code blocks render through a React view with the language pop-up and Copy. */
export const codeBlockNodeView = () => ReactNodeViewRenderer(CodeBlockView);

// ── Document upkeep: unique ids, list numbers, rendered math ────────────────

const numberingKey = new PluginKey<DecorationSet>('marioNumbering');

function numberDecorations(doc: PmNode): DecorationSet {
  const decos: Decoration[] = [];
  const counters: number[] = [];
  doc.forEach((node, offset) => {
    const indent = Number(node.attrs.indent ?? 0);
    if (node.type.name === 'numbered_list') {
      counters.length = Math.min(counters.length, indent + 1);
      const n = counters[indent] !== undefined ? counters[indent] + 1 : Number(node.attrs.start ?? 1) || 1;
      counters[indent] = n;
      decos.push(Decoration.node(offset, offset + node.nodeSize, { 'data-number': String(n) }));
    } else {
      // A bullet, a checkbox or a paragraph at this level ends the numbering at this level.
      counters.length = Math.min(counters.length, indent);
    }
  });
  return DecorationSet.create(doc, decos);
}

function rerenderMath(trs: readonly Transaction[], oldState: EditorState, state: EditorState): Transaction | null {
  const $old = oldState.selection.$from;
  if (!$old.parent.isTextblock || $old.parent.type.spec.code) return null;
  let start = $old.start();
  for (const t of trs) start = t.mapping.map(start);
  const $now = state.selection.$from;
  if ($now.parent.isTextblock && $now.start() === start) return null;
  if (start > state.doc.content.size) return null;
  const $b = state.doc.resolve(start);
  const block = $b.parent;
  if (!block.isTextblock || block.type.spec.code) return null;
  const mathType = state.schema.nodes.inlineMath;
  const repl: { from: number; to: number; node: PmNode }[] = [];
  block.forEach((child, offset) => {
    if (!child.isText || !child.text?.includes('$') || child.marks.some((m) => m.type.name === 'code')) return;
    for (const m of findInlineMath(child.text)) {
      repl.push({
        from: start + offset + m.start,
        to: start + offset + m.end,
        node: mathType.create({ latex: m.tex, display: m.display, source: 'dollar' }, null, child.marks),
      });
    }
  });
  if (repl.length === 0) return null;
  const tr = state.tr;
  for (const r of repl.reverse()) tr.replaceWith(r.from, r.to, r.node);
  return tr.setMeta('addToHistory', false);
}

export const DocumentUpkeep = Extension.create({
  name: 'marioDocumentUpkeep',
  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey('marioBlockIds'),
        appendTransaction: (trs, _old, state) => {
          if (!trs.some((t) => t.docChanged)) return null;
          const all = new Set<string>();
          state.doc.forEach((n) => {
            if (n.attrs.id) all.add(n.attrs.id);
          });
          const seen = new Set<string>();
          let tr: Transaction | null = null;
          state.doc.forEach((node, offset) => {
            if (!('id' in node.attrs)) return;
            const id = node.attrs.id as string | null;
            if (id && !seen.has(id)) {
              seen.add(id);
              return;
            }
            let next = nanoid6();
            while (all.has(next)) next = nanoid6();
            all.add(next);
            seen.add(next);
            tr = (tr ?? state.tr).setNodeAttribute(offset, 'id', next);
          });
          return tr ? (tr as Transaction).setMeta('addToHistory', false) : null;
        },
      }),
      new Plugin({
        key: numberingKey,
        state: {
          init: (_, state) => numberDecorations(state.doc),
          apply: (tr, old) => (tr.docChanged ? numberDecorations(tr.doc) : old),
        },
        props: {
          decorations(state) {
            return numberingKey.getState(state);
          },
        },
      }),
      new Plugin({ key: new PluginKey('marioMathRender'), appendTransaction: rerenderMath }),
    ];
  },
});

// ── Block commands (shared by the ribbon, the slash menu and shortcuts) ─────

/** Attributes of `node` that `type` also has; the id, indent and alignment survive. */
function carryAttrs(node: PmNode, type: NodeType, extra: Record<string, unknown> = {}) {
  const out: Record<string, unknown> = {};
  for (const k of ['id', 'indent', 'align']) {
    if (k in node.attrs && k in (type.spec.attrs ?? {})) out[k] = node.attrs[k];
  }
  for (const [k, v] of Object.entries(extra)) out[k] = v;
  return out;
}

export type BlockStyle =
  | 'paragraph'
  | 'heading-1'
  | 'heading-2'
  | 'heading-3'
  | 'heading-4'
  | 'bulleted_list'
  | 'numbered_list'
  | 'todo_list'
  | 'quote'
  | 'code';

/** The text blocks the selection touches (top level and inside table cells). */
function selectedTextblocks(state: EditorState): { node: PmNode; pos: number }[] {
  const { from, to } = state.selection;
  const out: { node: PmNode; pos: number }[] = [];
  state.doc.nodesBetween(from, to, (node, pos) => {
    if (node.isTextblock) {
      out.push({ node, pos });
      return false;
    }
    return true;
  });
  if (out.length === 0 && state.selection.$from.parent.isTextblock) {
    const $f = state.selection.$from;
    out.push({ node: $f.parent, pos: $f.before() });
  }
  return out;
}

export function currentBlockStyle(state: EditorState): BlockStyle | string {
  const parent = state.selection.$from.parent;
  if (parent.type.name === 'heading') return `heading-${parent.attrs.level}`;
  if (parent.type.name === 'codeBlock') return 'code';
  return parent.type.name;
}

export function setBlockStyle(editor: Editor, style: BlockStyle): boolean {
  const { state } = editor;
  const s = state.schema;
  const blocks = selectedTextblocks(state);
  if (blocks.length === 0) return false;
  const tr = state.tr;
  for (const { node, pos } of blocks.reverse()) {
    if (style === 'code') {
      if (node.type.name === 'codeBlock') continue;
      const text = node.textBetween(0, node.content.size, '\n', '\n');
      tr.replaceWith(
        pos,
        pos + node.nodeSize,
        s.nodes.codeBlock.create(carryAttrs(node, s.nodes.codeBlock, { language: 'plaintext' }), text ? s.text(text) : null),
      );
      continue;
    }
    const [typeName, extra] = style.startsWith('heading-')
      ? ['heading', { level: Number(style.split('-')[1]) || 1 }]
      : style === 'todo_list'
        ? ['todo_list', { checked: node.type.name === 'todo_list' ? node.attrs.checked : false }]
        : [style, {}];
    const type = s.nodes[typeName];
    if (!type) continue;
    if (node.type.name === 'codeBlock') {
      // Code back to text: one block per line.
      const lines = node.textContent.split('\n');
      const nodes = lines.map((line, i) =>
        type.create(i === 0 ? carryAttrs(node, type, extra) : { ...extra, indent: node.attrs.indent }, line ? s.text(line) : null),
      );
      tr.replaceWith(pos, pos + node.nodeSize, nodes);
      continue;
    }
    tr.setNodeMarkup(pos, type, carryAttrs(node, type, extra));
  }
  editor.view.dispatch(tr.scrollIntoView());
  return true;
}

export function toggleListStyle(editor: Editor, style: 'bulleted_list' | 'numbered_list' | 'todo_list'): boolean {
  const blocks = selectedTextblocks(editor.state);
  const all = blocks.length > 0 && blocks.every((b) => b.node.type.name === style);
  return setBlockStyle(editor, all ? 'paragraph' : style);
}

export function setBlockAlign(editor: Editor, align: 'left' | 'center' | 'right'): boolean {
  const tr = editor.state.tr;
  for (const { node, pos } of selectedTextblocks(editor.state)) {
    if ('align' in node.attrs) tr.setNodeAttribute(pos, 'align', align === 'left' ? null : align);
  }
  editor.view.dispatch(tr);
  return true;
}

/** Indent or outdent the top-level blocks in the selection (Tab / Shift-Tab). */
export function changeIndent(editor: Editor, delta: 1 | -1): boolean {
  const { state } = editor;
  const { from, to, $from } = state.selection;
  if ($from.depth > 1) return false; // inside a table cell: Tab moves between cells
  const tr = state.tr;
  let prevIndent = -1;
  let changed = false;
  state.doc.forEach((node, offset) => {
    const end = offset + node.nodeSize;
    const touches = offset < Math.max(to, from + 1) && end > from;
    if (!touches) {
      if (end <= from) prevIndent = Number(node.attrs.indent ?? 0);
      return;
    }
    if (!('indent' in node.attrs)) {
      prevIndent = -1;
      return;
    }
    const indent = Number(node.attrs.indent ?? 0);
    const next =
      delta > 0 ? Math.max(indent, Math.min(indent + 1, prevIndent + 1, MAX_INDENT)) : Math.max(0, indent - 1);
    if (next !== indent) {
      tr.setNodeAttribute(offset, 'indent', next);
      changed = true;
    }
    prevIndent = next;
  });
  if (changed) editor.view.dispatch(tr);
  // Tab never leaves the editor: an indent that can't go further still counts as handled.
  return true;
}

/** Move the top-level block at the selection one place up or down (⌥↑ / ⌥↓). */
export function moveBlock(editor: Editor, dir: -1 | 1): boolean {
  const { state } = editor;
  const sel = state.selection;
  const isNodeSel = sel instanceof NodeSelection && sel.$from.depth === 0;
  if (!isNodeSel && sel.$from.depth !== 1) return false;
  const index = sel.$from.index(0);
  const target = index + dir;
  if (target < 0 || target >= state.doc.childCount) return false;
  const node = state.doc.child(index);
  const other = state.doc.child(target);
  let start = 0;
  for (let i = 0; i < index; i++) start += state.doc.child(i).nodeSize;
  const offFrom = sel.from - start;
  const offTo = sel.to - start;
  const tr = state.tr;
  let newStart: number;
  if (dir < 0) {
    newStart = start - other.nodeSize;
    tr.delete(start, start + node.nodeSize).insert(newStart, node);
  } else {
    tr.insert(start + node.nodeSize + other.nodeSize, node).delete(start, start + node.nodeSize);
    newStart = start + other.nodeSize;
  }
  tr.setSelection(
    isNodeSel
      ? NodeSelection.create(tr.doc, newStart)
      : TextSelection.create(tr.doc, newStart + offFrom, newStart + offTo),
  );
  editor.view.dispatch(tr.scrollIntoView());
  return true;
}

export function toggleTodoChecked(editor: Editor): boolean {
  const $f = editor.state.selection.$from;
  if ($f.parent.type.name !== 'todo_list') return false;
  editor.view.dispatch(editor.state.tr.setNodeAttribute($f.before(), 'checked', !$f.parent.attrs.checked));
  return true;
}

/** Enter in a list or quote line: a new line of the same kind; on an empty one, step out. */
function splitLine(editor: Editor): boolean {
  const { state } = editor;
  const { $from } = state.selection;
  const node = $from.parent;
  if (![...LIST_TYPES, 'quote'].includes(node.type.name)) return false;
  if (node.content.size === 0) {
    if (node.attrs.indent > 0) return changeIndent(editor, -1);
    return setBlockStyle(editor, 'paragraph');
  }
  const tr = state.tr;
  if (!state.selection.empty) tr.deleteSelection();
  const pos = tr.mapping.map(state.selection.from);
  const $pos = tr.doc.resolve(pos);
  const marks = state.storedMarks || ($pos.parentOffset ? $pos.marks() : null);
  const attrs: Record<string, unknown> = { indent: node.attrs.indent, align: node.attrs.align };
  if (node.type.name === 'todo_list') attrs.checked = false;
  tr.split(pos, 1, [{ type: node.type, attrs }]);
  if (marks) tr.ensureMarks(marks);
  editor.view.dispatch(tr.scrollIntoView());
  return true;
}

/** Backspace at the start of a line: a list/quote/heading becomes body text, body text outdents. */
function backspaceAtStart(editor: Editor): boolean {
  const { state } = editor;
  const { $from, empty } = state.selection;
  if (!empty || $from.parentOffset !== 0 || $from.depth !== 1) return false;
  const node = $from.parent;
  if (node.type.name === 'paragraph') {
    return node.attrs.indent > 0 ? changeIndent(editor, -1) : false;
  }
  if (TEXT_BLOCKS.includes(node.type.name)) return setBlockStyle(editor, 'paragraph');
  return false;
}

/** Enter on a selected equation or embed opens it for editing. */
function editSelectedBlock(editor: Editor): boolean {
  const sel = editor.state.selection;
  if (!(sel instanceof NodeSelection)) return false;
  if (!['math_block', 'embed'].includes(sel.node.type.name)) return false;
  const dom = editor.view.nodeDOM(sel.from) as HTMLElement | null;
  const host = dom?.querySelector('[data-node-view-wrapper]') ?? dom;
  host?.dispatchEvent(new CustomEvent('mario-edit-block', { bubbles: false }));
  return true;
}

export const MarioKeys = Extension.create({
  name: 'marioKeys',
  priority: 1000,
  addKeyboardShortcuts() {
    const e = this.editor;
    return {
      Enter: () => editSelectedBlock(e) || splitLine(e),
      Backspace: () => backspaceAtStart(e),
      'Mod-Alt-0': () => setBlockStyle(e, 'paragraph'),
      'Mod-Alt-1': () => setBlockStyle(e, 'heading-1'),
      'Mod-Alt-2': () => setBlockStyle(e, 'heading-2'),
      'Mod-Alt-3': () => setBlockStyle(e, 'heading-3'),
      'Mod-Alt-4': () => setBlockStyle(e, 'heading-4'),
      'Mod-Alt-c': () => setBlockStyle(e, 'code'),
      'Mod-Shift-8': () => toggleListStyle(e, 'bulleted_list'),
      'Mod-Shift-7': () => toggleListStyle(e, 'numbered_list'),
      'Mod-Shift-9': () => toggleListStyle(e, 'todo_list'),
      'Mod-Shift-q': () => setBlockStyle(e, 'quote'),
      // OneNote's own: ⌃1 To Do, ⌃. bullets, ⌃/ numbering.
      'Mod-1': () => toggleListStyle(e, 'todo_list'),
      'Mod-.': () => toggleListStyle(e, 'bulleted_list'),
      'Mod-/': () => toggleListStyle(e, 'numbered_list'),
      'Mod-Enter': () => toggleTodoChecked(e),
      'Mod-Shift-x': () => e.chain().focus().toggleStrike().run(),
      'Mod-Shift-h': () => e.chain().focus().toggleHighlight({ color: 'rgba(255, 214, 10, 0.4)' }).run(),
      'Mod-Shift-n': () => e.chain().focus().unsetAllMarks().run(),
      'Mod-Shift-l': () => setBlockAlign(e, 'left'),
      'Mod-Shift-e': () => setBlockAlign(e, 'center'),
      'Mod-Shift-r': () => setBlockAlign(e, 'right'),
      'Alt-ArrowUp': () => moveBlock(e, -1),
      'Alt-ArrowDown': () => moveBlock(e, 1),
      'Alt-Shift-ArrowUp': () => moveBlock(e, -1),
      'Alt-Shift-ArrowDown': () => moveBlock(e, 1),
    };
  },
});

/** Tab / Shift-Tab indent. Low priority, so tables and code blocks handle Tab first. */
export const MarioIndentKeys = Extension.create({
  name: 'marioIndentKeys',
  priority: 50,
  addKeyboardShortcuts() {
    return {
      Tab: () => changeIndent(this.editor, 1),
      'Shift-Tab': () => changeIndent(this.editor, -1),
    };
  },
});

// ── Markdown typed as you go ────────────────────────────────────────────────

function lineRule(find: RegExp, typeName: string, attrs?: (m: RegExpMatchArray) => Record<string, unknown>) {
  return new InputRule({
    find,
    handler: ({ state, range, match }) => {
      const $start = state.doc.resolve(range.from);
      const node = $start.parent;
      if (!node.isTextblock || node.type.spec.code) return null;
      const type = state.schema.nodes[typeName];
      state.tr
        .delete(range.from, range.to)
        .setNodeMarkup($start.before(), type, carryAttrs(node, type, attrs?.(match) ?? {}));
    },
  });
}

export const MarkdownShortcuts = Extension.create({
  name: 'marioMarkdownShortcuts',
  addInputRules() {
    const schema = this.editor.schema;
    return [
      lineRule(/^(#{1,6})\s$/, 'heading', (m) => ({ level: m[1].length })),
      lineRule(/^\s*([-+*])\s$/, 'bulleted_list'),
      lineRule(/^(\d+)[.)]\s$/, 'numbered_list', (m) => {
        const n = Number(m[1]);
        return { start: n > 1 ? n : null };
      }),
      lineRule(/^\s*\[([ xX]?)\]\s$/, 'todo_list', (m) => ({ checked: m[1].toLowerCase() === 'x' })),
      lineRule(/^>\s$/, 'quote'),
      new InputRule({
        find: /^\$\$\s$/,
        handler: ({ state, range }) => {
          const $start = state.doc.resolve(range.from);
          if ($start.depth !== 1) return null;
          const math = schema.nodes.math_block.create({ formula: '', indent: $start.parent.attrs.indent ?? 0 });
          const tr = state.tr.replaceWith($start.before(), $start.after(), math);
          tr.setSelection(NodeSelection.create(tr.doc, $start.before()));
        },
      }),
      new InputRule({
        find: /(^|[^\\$])\$([^\s$](?:[^$\n]*?[^\s$\\])?)\$$/,
        handler: ({ state, range, match }) => {
          const $from = state.doc.resolve(range.from);
          if ($from.parent.type.spec.code || $from.marks().some((m) => m.type.name === 'code')) return null;
          const from = range.from + match[1].length;
          state.tr.replaceWith(
            from,
            range.to,
            schema.nodes.inlineMath.create({ latex: match[2], display: false, source: 'dollar' }),
          );
        },
      }),
      new InputRule({
        find: /\[([^\]]+)\]\(([^)\s]+)\)$/,
        handler: ({ state, range, match }) => {
          const link = schema.marks.link.create({ href: match[2] });
          state.tr.replaceWith(range.from, range.to, schema.text(match[1], [link])).removeStoredMark(schema.marks.link);
        },
      }),
      new InputRule({
        find: /:([a-z0-9_+-]+):$/i,
        handler: ({ state, range, match }) => {
          const emoji = EMOJI_MAP[match[1].toLowerCase()];
          if (!emoji) return null;
          state.tr.insertText(emoji, range.from, range.to);
        },
      }),
    ];
  },
});
