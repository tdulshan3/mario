import type { Editor, JSONContent } from '@tiptap/core';
import type { Slice } from '@tiptap/pm/model';
import { documentToMarkdown, markdownToNodes } from '../shared/document-codec';
import { appflowyToPm, pmToAppflowy } from './pm-codec';

/**
 * Pasting and copying. Markdown pasted as text (from VS Code, a terminal, an AI
 * chat) becomes real headings, lists, tables and math; HTML from a browser or
 * Word is parsed by the schema, with nested lists flattened into indent levels
 * first; a copy puts Markdown on the clipboard's text flavour.
 */

const MARKDOWN_HINT = /^(#{1,6}\s|```|~~~|\||\s*[-*+]\s|\s*\d+[.)]\s|\$\$|>|---\s*$)|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)|`[^`]+`/m;

export function looksLikeMarkdown(text: string): boolean {
  return MARKDOWN_HINT.test(text);
}

/** Inserts Markdown (or plain text) at the selection as blocks, or inline when it is one line. */
export function insertMarkdown(editor: Editor, text: string): boolean {
  const blocks = (appflowyToPm({ type: 'page', children: markdownToNodes(text) }).content ?? []) as JSONContent[];
  if (blocks.length === 0) return false;
  const single = blocks.length === 1 && blocks[0].type === 'paragraph';
  const $from = editor.state.selection.$from;
  if (single) {
    return editor.chain().focus().insertContent(blocks[0].content ?? []).run();
  }
  // Replace an empty line instead of leaving it behind above the pasted blocks.
  if ($from.depth === 1 && $from.parent.type.name === 'paragraph' && $from.parent.content.size === 0) {
    const start = $from.before(1);
    return editor
      .chain()
      .focus()
      .insertContentAt({ from: start, to: start + $from.parent.nodeSize }, blocks)
      .run();
  }
  return editor.chain().focus().insertContent(blocks).run();
}

export function handleMarkdownPaste(editor: Editor, event: ClipboardEvent): boolean {
  const cd = event.clipboardData;
  if (!cd) return false;
  if (editor.state.selection.$from.parent.type.spec.code) return false;
  const text = cd.getData('text/plain');
  const html = cd.getData('text/html');
  // Code editors put syntax-coloured HTML next to the text; the text is what was meant.
  const fromCodeEditor = cd.types.includes('vscode-editor-data');
  if (!text || (html && !fromCodeEditor)) return false;
  if (!text.includes('\n') && !looksLikeMarkdown(text)) return false;
  event.preventDefault();
  return insertMarkdown(editor, text);
}

/** Flattens nested HTML lists into one run of `<li data-indent>` and unwraps `<p>` in items and quotes. */
export function normalizePastedHtml(html: string): string {
  if (!/<(li|blockquote)\b/i.test(html)) return html;
  const doc = new DOMParser().parseFromString(html, 'text/html');
  const unwrapParagraphs = (el: Element) => {
    const ps = Array.from(el.querySelectorAll(':scope > p'));
    ps.forEach((p, i) => {
      const frag = doc.createDocumentFragment();
      if (i > 0) frag.append(doc.createElement('br'));
      frag.append(...Array.from(p.childNodes));
      p.replaceWith(frag);
    });
  };
  doc.querySelectorAll('li, blockquote').forEach(unwrapParagraphs);
  const topLists = Array.from(doc.querySelectorAll('ul, ol')).filter((l) => !l.parentElement?.closest('li'));
  for (const list of topLists) {
    const items: HTMLElement[] = [];
    const walk = (l: Element, depth: number) => {
      let n = l.tagName === 'OL' ? Number((l as HTMLOListElement).start || 1) : 1;
      for (const li of Array.from(l.children)) {
        if (li.tagName !== 'LI') continue;
        const nested = Array.from(li.children).filter((c) => c.tagName === 'UL' || c.tagName === 'OL');
        nested.forEach((c) => c.remove());
        const item = li as HTMLElement;
        item.setAttribute('data-indent', String(depth));
        item.setAttribute('data-list', l.tagName === 'OL' ? 'ol' : 'ul');
        if (l.tagName === 'OL' && item === l.firstElementChild && n > 1) item.setAttribute('data-start', String(n));
        items.push(item);
        n++;
        nested.forEach((c) => walk(c, depth + 1));
      }
    };
    walk(list, 0);
    const flat = doc.createElement('ul');
    flat.append(...items);
    list.replaceWith(flat);
  }
  return doc.body.innerHTML;
}

/** Copy as Markdown: a run of blocks keeps its structure; part of one line copies as its text. */
export function serializeClipboardText(slice: Slice): string {
  const plain = () => slice.content.textBetween(0, slice.content.size, '\n\n', '\n');
  const first = slice.content.firstChild;
  if (slice.content.childCount === 1 && first?.isTextblock && slice.openStart > 0) return plain();
  try {
    const json = { type: 'doc', content: slice.content.toJSON() as JSONContent[] };
    return documentToMarkdown(pmToAppflowy(json)).replace(/\n$/, '');
  } catch {
    return plain();
  }
}
