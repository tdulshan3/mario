import React, { useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { EditorContent, useEditor, useEditorState, type Editor } from '@tiptap/react';
import type { JSONContent } from '@tiptap/core';
import { NodeSelection } from '@tiptap/pm/state';
import StarterKit from '@tiptap/starter-kit';
import CodeBlockLowlight from '@tiptap/extension-code-block-lowlight';
import { Color, TextStyle } from '@tiptap/extension-text-style';
import Highlight from '@tiptap/extension-highlight';
import { TableKit } from '@tiptap/extension-table';
import { Placeholder } from '@tiptap/extensions';
import { common, createLowlight } from 'lowlight';
import {
  Alert,
  Button,
  ContextMenu,
  FieldGrid,
  MenuHeader,
  MenuItem,
  MenuSeparator,
  SegmentedControl,
  Sheet,
  Spacer,
  TextField,
  type IconName,
} from '../macos/macos';
import type { AiCommand, AppFlowyDocument, PageContent } from '../shared/types';
import { documentToMarkdown } from '../shared/document-codec';
import { buildPreviewDocument } from '../shared/markdown-render';
import { DrawingCanvasBlock } from './DrawingCanvasBlock';
import { appflowyToPm, pmToAppflowy } from '../editor/pm-codec';
import {
  AppFlowyAttrs,
  BlockAttributes,
  BulletedList,
  DocumentUpkeep,
  Embed,
  InlineMath,
  MarioCode,
  MarioHeading,
  MarioIndentKeys,
  MarioKeys,
  MarkdownShortcuts,
  MathBlock,
  NumberedList,
  Quote,
  TodoList,
  changeIndent,
  codeBlockNodeView,
  currentBlockStyle,
  moveBlock,
  setBlockStyle,
  type BlockStyle,
} from '../editor/extensions';
import { handleMarkdownPaste, insertMarkdown, normalizePastedHtml, serializeClipboardText } from '../editor/clipboard';
import { Ribbon, type InsertKind, type RibbonState } from '../editor/Ribbon';
import {
  WEB_SANDBOX,
  buildBlockWebDocument,
  buildPageWebDocument,
  isFullHtmlDocument,
  looksLikeHtmlSource,
  prepareWebDocument,
} from '../editor/web-page';
import { nanoid6 } from '../shared/ids';
import { InlineAsk, closeInlineAsk, inlineAskAnchor, inlineAskHost, openInlineAsk, type InlineAskAnchor } from '../editor/inline-ask';
import { InlineAskBox } from './InlineAskBox';
import { ErrorBoundary } from './ErrorBoundary';

export interface BlockEditorProps {
  pageTitle: string;
  onTitleChange: (title: string) => void;
  content: PageContent;
  onContentChange: (next: PageContent) => void;
  fontFamily: string;
  onFontFamilyChange: (font: string) => void;
  fontSize: number;
  onFontSizeChange: (size: number) => void;
  zoom: number;
  onZoomChange: (zoom: number) => void;
  spellcheck: boolean;
  saveStatus: 'saved' | 'saving' | 'dirty';
  rawHtmlOverride: string | null;
  onClearHtmlOverride: () => void;
  onExportMarkdown: () => void;
  onExportPdf: () => void;
  onOpenShare: () => void;
  /** Settings ▸ Page width. */
  canvasWidth?: 'narrow' | 'medium' | 'full';
  /** A passage the user highlighted and held (Flutter's "ask about a highlight"). */
  onHighlight?: (text: string) => void;
  /** The editor's AI slash commands: Summarise Above, Quiz Me (Ask AI opens in the page). */
  onAiCommand?: (command: Omit<AiCommand, 'nonce'>) => void;
  /** Where Inline Ask saves its chats. */
  notebookId?: string;
  pageId?: string;
  /** Inline Ask ▸ Preview HTML. */
  onPreviewHtml?: (html: string) => void;
}

const lowlight = createLowlight(common);

type AiSlashKind = 'ai_ask' | 'ai_summary' | 'ai_quiz';

const SLASH_ITEMS: Array<{ kind: InsertKind | BlockStyle | AiSlashKind; label: string; keywords: string; icon: IconName; shortcut?: string }> = [
  { kind: 'heading-1', label: 'Heading 1', keywords: 'h1 title', icon: 'book', shortcut: '⌃⌥1' },
  { kind: 'heading-2', label: 'Heading 2', keywords: 'h2 subtitle', icon: 'book', shortcut: '⌃⌥2' },
  { kind: 'heading-3', label: 'Heading 3', keywords: 'h3', icon: 'book', shortcut: '⌃⌥3' },
  { kind: 'bulleted_list', label: 'Bulleted List', keywords: 'bullet ul list', icon: 'list-bullet', shortcut: '⌃.' },
  { kind: 'numbered_list', label: 'Numbered List', keywords: 'number ol list', icon: 'line-3-horizontal', shortcut: '⌃/' },
  { kind: 'todo_list', label: 'To Do', keywords: 'todo check task checklist', icon: 'checkmark-circle-fill', shortcut: '⌃1' },
  { kind: 'quote', label: 'Quote', keywords: 'quote blockquote citation', icon: 'bubble-left', shortcut: '⇧⌃Q' },
  { kind: 'code', label: 'Code', keywords: 'code snippet pre', icon: 'cpu', shortcut: '⌃⌥C' },
  { kind: 'table', label: 'Table', keywords: 'table grid', icon: 'square-grid' },
  { kind: 'math_block', label: 'Equation', keywords: 'math latex katex formula equation', icon: 'command' },
  { kind: 'inline_math', label: 'Inline Equation', keywords: 'math inline latex', icon: 'command' },
  { kind: 'image', label: 'Picture…', keywords: 'image photo picture', icon: 'photo' },
  { kind: 'link', label: 'Link…', keywords: 'link url href', icon: 'link' },
  { kind: 'spreadsheet', label: 'Spreadsheet', keywords: 'sheet excel formula sum', icon: 'chart-bar' },
  { kind: 'drawing', label: 'Drawing Canvas', keywords: 'draw sketch ink pen', icon: 'pencil-tip-circle' },
  { kind: 'audio', label: 'Audio Recording', keywords: 'audio voice mic record', icon: 'mic' },
  { kind: 'html', label: 'HTML Block', keywords: 'html iframe embed web', icon: 'globe' },
  { kind: 'datetime', label: 'Date & Time', keywords: 'date time now today stamp', icon: 'calendar' },
  { kind: 'ai_ask', label: 'Ask AI', keywords: 'ask ai question chat mario', icon: 'bubble-left' },
  { kind: 'ai_summary', label: 'Summarise Above', keywords: 'summary summarise summarize tldr recap ai', icon: 'doc-text' },
  { kind: 'ai_quiz', label: 'Quiz Me', keywords: 'quiz test exam mcq revise ai', icon: 'questionmark-circle' },
  { kind: 'divider', label: 'Divider', keywords: 'divider hr line rule', icon: 'minus' },
];

const BLOCK_STYLES = new Set<string>(['paragraph', 'heading-1', 'heading-2', 'heading-3', 'heading-4', 'bulleted_list', 'numbered_list', 'todo_list', 'quote', 'code']);

const DEFAULT_HTML =
  '<div style="padding:16px;border-radius:8px;font-family:system-ui,sans-serif">\n  <h3 style="margin-top:0">Interactive HTML</h3>\n  <p>Render custom HTML, charts, embeds, or widgets.</p>\n</div>';

const isUntitled = (t: string) => !t.trim() || /^untitled( page)?$/i.test(t.trim());

/** The text of an HTML page's <title>, else its first <h1>. */
function htmlHeading(html: string): string | null {
  const m = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html) ?? /<h1[^>]*>([\s\S]*?)<\/h1>/i.exec(html);
  if (!m) return null;
  const text = new DOMParser().parseFromString(m[1], 'text/html').documentElement.textContent ?? '';
  return text.replace(/\s+/g, ' ').trim().slice(0, 120) || null;
}

/** The page's first heading — a heading line, or the title of a webpage pasted as an HTML block. */
function firstHeading(editor: Editor): string | null {
  let text: string | null = null;
  editor.state.doc.forEach((n) => {
    if (text !== null) return;
    if (n.type.name === 'heading' && n.textContent.trim()) text = n.textContent.trim();
    else if (n.type.name === 'embed' && n.attrs.kind === 'html') text = htmlHeading(String(n.attrs.data?.html ?? ''));
  });
  return text;
}

function fontStackFor(family: string): string {
  switch (family) {
    case 'Inter':
      return '"Inter", var(--mac-font)';
    case 'Serif':
      return 'Georgia, "Times New Roman", serif';
    case 'Monospace':
      return 'var(--mac-font-mono)';
    default:
      return 'var(--mac-font)';
  }
}

interface PreviewState {
  layout: 'full' | 'split';
  /** auto: the page's webpage when it has HTML, else the document. */
  source: 'auto' | 'web' | 'document';
  /** Preview one HTML block or HTML code block instead of the whole page. */
  blockId?: string;
}

/** `value`, held back until it has stopped changing for `delay` ms (0 = live). */
function useDebounced<T>(value: T, delay: number): T {
  const [held, setHeld] = useState(value);
  useEffect(() => {
    if (delay <= 0) {
      setHeld(value);
      return;
    }
    const t = setTimeout(() => setHeld(value), delay);
    return () => clearTimeout(t);
  }, [value, delay]);
  return delay <= 0 ? value : held;
}

interface SlashState {
  from: number;
  query: string;
  left: number;
  top: number;
  index: number;
}

export function BlockEditor({
  pageTitle,
  onTitleChange,
  content,
  onContentChange,
  fontFamily,
  onFontFamilyChange,
  fontSize,
  onFontSizeChange,
  zoom,
  onZoomChange,
  spellcheck,
  saveStatus,
  rawHtmlOverride,
  onClearHtmlOverride,
  onExportMarkdown,
  onExportPdf,
  onOpenShare,
  canvasWidth = 'medium',
  onHighlight,
  onAiCommand,
  notebookId,
  pageId,
  onPreviewHtml,
}: BlockEditorProps) {
  const contentRef = useRef(content);
  contentRef.current = content;
  const onContentChangeRef = useRef(onContentChange);
  onContentChangeRef.current = onContentChange;
  const onTitleChangeRef = useRef(onTitleChange);
  onTitleChangeRef.current = onTitleChange;
  const lastEmitted = useRef<AppFlowyDocument>(content.document);
  const onHighlightRef = useRef(onHighlight);
  onHighlightRef.current = onHighlight;
  const onAiCommandRef = useRef(onAiCommand);
  onAiCommandRef.current = onAiCommand;
  // A highlight counts once it has held still for half a second and is a
  // passage (12+ characters), not a word being fixed — as in Mario v1.
  const lastHighlight = useRef('');
  const highlightTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reportSelection = (ed: Editor) => {
    if (highlightTimer.current) clearTimeout(highlightTimer.current);
    const { from, to, empty } = ed.state.selection;
    if (empty) {
      lastHighlight.current = '';
      return;
    }
    const text = ed.state.doc.textBetween(from, to, '\n', ' ').trim();
    if (text.length < 12 || text === lastHighlight.current) return;
    highlightTimer.current = setTimeout(() => {
      lastHighlight.current = text;
      onHighlightRef.current?.(text);
    }, 500);
  };

  const [drawMode, setDrawMode] = useState(false);
  // The preview fills the editor pane by default (OneNote/Typora "reading view"); side by side on request.
  const [preview, setPreview] = useState<PreviewState | null>(
    rawHtmlOverride ? { layout: 'full', source: 'auto' } : null,
  );
  const [previewReload, setPreviewReload] = useState(0);
  const previewOpen = preview !== null;
  const [linkDialog, setLinkDialog] = useState<{ text: string; href: string; hasSelection: boolean } | null>(null);
  const [alert, setAlert] = useState<{ title: string; message: string } | null>(null);
  const [slash, setSlashState] = useState<SlashState | null>(null);
  // Inline Ask: the box in the page after the caret's line (“/ask”).
  const [inlineAsk, setInlineAsk] = useState<InlineAskAnchor | null>(null);
  const slashRef = useRef<SlashState | null>(null);
  const slashDismissedAt = useRef<number | null>(null);
  const setSlash = (next: SlashState | null) => {
    slashRef.current = next;
    setSlashState(next);
  };

  // ── Title (OneNote: an untitled page is named by its first heading) ───────
  const [title, setTitleState] = useState(pageTitle);
  const titleRef = useRef(pageTitle);
  const autoTitleRef = useRef<string | null>(null);
  const titleTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pendingTitle = useRef<string | null>(null);
  const setTitle = (t: string) => {
    titleRef.current = t;
    setTitleState(t);
  };
  const flushTitle = () => {
    if (titleTimer.current) clearTimeout(titleTimer.current);
    titleTimer.current = null;
    if (pendingTitle.current !== null) {
      const t = pendingTitle.current;
      pendingTitle.current = null;
      onTitleChangeRef.current(t);
    }
  };
  const commitTitleSoon = (t: string) => {
    pendingTitle.current = t;
    if (titleTimer.current) clearTimeout(titleTimer.current);
    titleTimer.current = setTimeout(flushTitle, 600);
  };
  useEffect(() => () => flushTitle(), []);
  useEffect(() => () => {
    if (highlightTimer.current) clearTimeout(highlightTimer.current);
  }, []);
  useEffect(() => {
    if (pendingTitle.current === null && pageTitle !== titleRef.current) setTitle(pageTitle);
  }, [pageTitle]);

  const syncTitleFromHeading = (ed: Editor) => {
    const heading = firstHeading(ed);
    const current = titleRef.current;
    if (!heading || heading === current) return;
    if (isUntitled(current) || (autoTitleRef.current !== null && current === autoTitleRef.current)) {
      autoTitleRef.current = heading;
      setTitle(heading);
      commitTitleSoon(heading);
    }
  };

  // ── Slash menu ────────────────────────────────────────────────────────────
  // Best first: a label that starts with what was typed ("/ask" → Ask AI), then a word
  // that does, then anything containing it ("task" → To Do).
  const slashMatches = (query: string) => {
    if (!query) return SLASH_ITEMS;
    const rank = (i: (typeof SLASH_ITEMS)[number]) => {
      const label = i.label.toLowerCase();
      if (label.startsWith(query)) return 0;
      if (`${label} ${i.keywords}`.split(/\s+/).some((w) => w.startsWith(query))) return 1;
      return label.includes(query) || i.keywords.includes(query) ? 2 : -1;
    };
    return SLASH_ITEMS.map((item, at) => ({ item, at, r: rank(item) }))
      .filter((x) => x.r >= 0)
      .sort((a, b) => a.r - b.r || a.at - b.at)
      .map((x) => x.item);
  };

  const updateSlash = (ed: Editor) => {
    const sel = ed.state.selection;
    const $f = sel.$from;
    if (!sel.empty || !$f.parent.isTextblock || $f.parent.type.spec.code) return setSlash(null);
    const before = $f.parent.textBetween(Math.max(0, $f.parentOffset - 40), $f.parentOffset, undefined, '￼');
    const m = /(?:^|\s)\/([\w-]*)$/.exec(before);
    if (!m) {
      slashDismissedAt.current = null;
      return setSlash(null);
    }
    const from = $f.pos - m[1].length - 1;
    if (slashDismissedAt.current === from || slashMatches(m[1].toLowerCase()).length === 0) return setSlash(null);
    const coords = ed.view.coordsAtPos(from);
    const prev = slashRef.current;
    setSlash({
      from,
      query: m[1].toLowerCase(),
      left: coords.left,
      top: coords.bottom + 4,
      index: prev && prev.from === from ? Math.min(prev.index, slashMatches(m[1].toLowerCase()).length - 1) : 0,
    });
  };

  const editorRef = useRef<Editor | null>(null);
  const editor: Editor | null = useEditor(
    {
      extensions: [
        StarterKit.configure({
          heading: false,
          bulletList: false,
          orderedList: false,
          listItem: false,
          listKeymap: false,
          blockquote: false,
          codeBlock: false,
          code: false,
          link: {
            openOnClick: false,
            autolink: true,
            linkOnPaste: true,
            defaultProtocol: 'https',
            HTMLAttributes: { rel: 'noopener noreferrer', target: null },
          },
          dropcursor: { color: 'var(--mac-accent)', width: 2 },
          undoRedo: { depth: 200 },
        }),
        MarioHeading.configure({ levels: [1, 2, 3, 4, 5, 6] }),
        MarioCode,
        CodeBlockLowlight.extend({ addNodeView: codeBlockNodeView }).configure({
          lowlight,
          defaultLanguage: 'plaintext',
          enableTabIndentation: true,
          tabSize: 2,
        }),
        BlockAttributes,
        BulletedList,
        NumberedList,
        TodoList,
        Quote,
        MathBlock,
        InlineMath,
        Embed,
        AppFlowyAttrs,
        TextStyle,
        Color,
        Highlight.configure({ multicolor: true }),
        TableKit.configure({ table: { resizable: true } }),
        Placeholder.configure({
          showOnlyCurrent: true,
          includeChildren: false,
          placeholder: ({ node, editor: ed }) => {
            switch (node.type.name) {
              case 'heading':
                return `Heading ${node.attrs.level}`;
              case 'paragraph':
                return ed.state.doc.childCount <= 1 ? 'Start writing, or type “/” for commands' : 'Type “/” for commands';
              case 'bulleted_list':
              case 'numbered_list':
                return 'List';
              case 'todo_list':
                return 'To do';
              case 'quote':
                return 'Quote';
              default:
                return '';
            }
          },
        }),
        DocumentUpkeep,
        InlineAsk,
        MarioKeys,
        MarioIndentKeys,
        MarkdownShortcuts,
      ],
      content: appflowyToPm(content.document),
      editorProps: {
        attributes: {
          class: 'mario-doc',
          spellcheck: String(spellcheck),
          'aria-label': 'Page',
          role: 'textbox',
          'aria-multiline': 'true',
        },
        transformPastedHTML: normalizePastedHtml,
        clipboardTextSerializer: serializeClipboardText,
        handlePaste: (_view, event): boolean => {
          const ed: Editor | null = editorRef.current;
          if (!ed) return false;
          const file = Array.from(event.clipboardData?.items ?? [])
            .find((i) => i.type.startsWith('image/'))
            ?.getAsFile();
          if (file) {
            event.preventDefault();
            void insertImageFile(ed, file);
            return true;
          }
          // HTML source becomes an HTML block that renders it; a whole page opens full size.
          const text = event.clipboardData?.getData('text/plain') ?? '';
          if (!ed.state.selection.$from.parent.type.spec.code && looksLikeHtmlSource(text)) {
            event.preventDefault();
            const id = nanoid6();
            insertBlock(ed, { type: 'embed', attrs: { id, kind: 'html', data: { html: text.trim() } } });
            if (isFullHtmlDocument(text)) setPreview({ layout: 'full', source: 'web', blockId: id });
            return true;
          }
          return handleMarkdownPaste(ed, event);
        },
        handleDrop: (_view, event) => {
          const ed = editorRef.current;
          const file = Array.from((event as DragEvent).dataTransfer?.files ?? []).find((f) => f.type.startsWith('image/'));
          if (!ed || !file) return false;
          event.preventDefault();
          void insertImageFile(ed, file);
          return true;
        },
        handleClick: (_view, _pos, event) => {
          // Links open with ⌘/Ctrl-click, in the browser; a plain click edits.
          const a = (event.target as HTMLElement | null)?.closest?.('a[href]') as HTMLAnchorElement | null;
          if (a && (event.metaKey || event.ctrlKey)) {
            window.open(a.href, '_blank', 'noopener');
            return true;
          }
          return false;
        },
        handleKeyDown: (_view, event) => {
          const s = slashRef.current;
          const ed = editorRef.current;
          if (!s || !ed) {
            if ((event.metaKey || event.ctrlKey) && event.shiftKey && event.key.toLowerCase() === 'k' && ed) {
              event.preventDefault();
              openLinkDialog(ed);
              return true;
            }
            return false;
          }
          const items = slashMatches(s.query);
          if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            const d = event.key === 'ArrowDown' ? 1 : -1;
            setSlash({ ...s, index: (s.index + d + items.length) % items.length });
            return true;
          }
          if (event.key === 'Enter' || event.key === 'Tab') {
            const item = items[s.index];
            if (item) runSlash(ed, s, item.kind);
            return true;
          }
          if (event.key === 'Escape') {
            slashDismissedAt.current = s.from;
            setSlash(null);
            return true;
          }
          return false;
        },
      },
      onUpdate: ({ editor: ed }) => {
        const doc = pmToAppflowy(ed.getJSON());
        lastEmitted.current = doc;
        onContentChangeRef.current({ ...contentRef.current, document: doc });
        syncTitleFromHeading(ed);
        updateSlash(ed);
        reportSelection(ed);
      },
      onSelectionUpdate: ({ editor: ed }) => {
        updateSlash(ed);
        reportSelection(ed);
      },
      onBlur: () => setSlash(null),
    },
    [],
  );
  editorRef.current = editor;

  // Opening a page whose title is still "Untitled" names it after its first heading.
  useEffect(() => {
    if (!editor) return;
    const heading = firstHeading(editor);
    if (heading && pageTitle === heading) autoTitleRef.current = heading;
    syncTitleFromHeading(editor);
  }, [editor]);

  // Content changed outside the editor (the AI agent, a sync): show it, without an undo step.
  useEffect(() => {
    if (!editor || editor.isDestroyed || content.document === lastEmitted.current) return;
    lastEmitted.current = content.document;
    editor
      .chain()
      .setMeta('addToHistory', false)
      .setContent(appflowyToPm(content.document), { emitUpdate: false })
      .run();
    syncTitleFromHeading(editor);
  }, [content.document, editor]);

  useEffect(() => {
    if (!editor || editor.isDestroyed) return;
    const props = editor.options.editorProps;
    editor.setOptions({
      editorProps: { ...props, attributes: { ...(props.attributes as Record<string, string>), spellcheck: String(spellcheck) } },
    });
  }, [editor, spellcheck]);

  useEffect(() => {
    if (rawHtmlOverride) setPreview({ layout: 'full', source: 'auto' });
  }, [rawHtmlOverride]);

  // An HTML block or HTML code block asked to be shown as a webpage.
  useEffect(() => {
    const onRequest = (e: Event) => {
      const blockId = (e as CustomEvent<{ blockId: string }>).detail?.blockId;
      if (blockId) setPreview({ layout: 'full', source: 'web', blockId });
    };
    window.addEventListener('mario-preview-block', onRequest);
    return () => window.removeEventListener('mario-preview-block', onRequest);
  }, []);

  // Escape leaves a full-pane preview.
  useEffect(() => {
    if (preview?.layout !== 'full') return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setPreview(null);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [preview?.layout]);

  const ribbonState = useEditorState({
    editor,
    selector: ({ editor: ed }): RibbonState & { words: number } => {
      if (!ed) {
        return { bold: false, italic: false, underline: false, strike: false, code: false, link: false, blockStyle: 'paragraph', align: 'left', inTable: false, canUndo: false, canRedo: false, words: 0 };
      }
      const parent = ed.state.selection.$from.parent;
      const text = ed.state.doc.textBetween(0, ed.state.doc.content.size, ' ', ' ');
      return {
        bold: ed.isActive('bold'),
        italic: ed.isActive('italic'),
        underline: ed.isActive('underline'),
        strike: ed.isActive('strike'),
        code: ed.isActive('code'),
        link: ed.isActive('link'),
        blockStyle: currentBlockStyle(ed.state),
        align: (parent.attrs.align as 'center' | 'right' | null) ?? 'left',
        inTable: ed.isActive('table'),
        canUndo: ed.can().undo(),
        canRedo: ed.can().redo(),
        words: text.trim() ? text.trim().split(/\s+/).length : 0,
      };
    },
  });

  // ── Inserting things (ribbon, slash menu, context menu) ───────────────────

  async function insertImageFile(ed: Editor, file: File) {
    const dataUrl = await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
    try {
      const saved = await window.mario.asset.savePastedImage(dataUrl);
      insertBlock(ed, { type: 'embed', attrs: { kind: 'image', data: { url: saved.assetPath, width: 520, align: 'center' } } });
    } catch (err) {
      setAlert({ title: 'The picture couldn’t be added.', message: err instanceof Error ? err.message : String(err) });
    }
  }

  /** Puts a block in place of an empty line, or after the line the caret is on. */
  function insertBlock(ed: Editor, json: JSONContent, selectNode = false): number {
    const sel = ed.state.selection;
    const $f = sel.$from;
    let pos: number;
    if ($f.depth < 1) {
      // A whole block is selected: the new one goes after it.
      pos = sel.to;
      ed.chain().focus().insertContentAt(pos, json).run();
    } else {
      const top = $f.node(1);
      const start = $f.before(1);
      const replace = top.type.name === 'paragraph' && top.content.size === 0;
      pos = replace ? start : start + top.nodeSize;
      const chain = ed.chain().focus();
      if (replace) chain.insertContentAt({ from: start, to: start + top.nodeSize }, json);
      else chain.insertContentAt(pos, json);
      chain.run();
    }
    if (selectNode && ed.state.doc.nodeAt(pos)) {
      ed.view.dispatch(ed.state.tr.setSelection(NodeSelection.create(ed.state.doc, pos)));
    }
    return pos;
  }

  /** Inline Ask after the caret's line, about the highlight when there is one. */
  function openAsk(ed: Editor) {
    openInlineAsk(ed);
    setInlineAsk(inlineAskAnchor(ed.state));
  }

  function closeAsk() {
    if (editor) closeInlineAsk(editor);
    setInlineAsk(null);
  }

  function openLinkDialog(ed: Editor) {
    const { from, to, empty } = ed.state.selection;
    const href = String(ed.getAttributes('link').href ?? '');
    setLinkDialog({ text: empty ? '' : ed.state.doc.textBetween(from, to, ' '), href, hasSelection: !empty });
  }

  async function performInsert(ed: Editor, kind: InsertKind | BlockStyle | AiSlashKind) {
    if (kind === 'ai_ask') {
      openAsk(ed);
      return;
    }
    if (kind === 'ai_summary' || kind === 'ai_quiz') {
      const above = ed.state.doc.textBetween(0, ed.state.selection.from, '\n\n', ' ').trim();
      onAiCommandRef.current?.(
        kind === 'ai_summary' ? { kind: 'summary', text: above } : { kind: 'quiz' },
      );
      return;
    }
    if (BLOCK_STYLES.has(kind)) {
      setBlockStyle(ed, kind as BlockStyle);
      ed.commands.focus();
      return;
    }
    switch (kind as InsertKind) {
      case 'table':
        ed.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: false }).run();
        return;
      case 'math_block':
        insertBlock(ed, { type: 'math_block', attrs: { formula: '' } }, true);
        return;
      case 'inline_math': {
        const pos = ed.state.selection.from;
        ed.chain().focus().insertContent('$$').setTextSelection(pos + 1).run();
        return;
      }
      case 'code': {
        // An empty line becomes the code block; a line with text gets one after it.
        const $f = ed.state.selection.$from;
        if ($f.parent.type.name === 'paragraph' && $f.parent.content.size === 0) {
          setBlockStyle(ed, 'code');
          ed.commands.focus();
        } else {
          const pos = insertBlock(ed, { type: 'codeBlock', attrs: { language: 'plaintext' } });
          ed.chain().focus().setTextSelection(pos + 1).run();
        }
        return;
      }
      case 'divider':
        ed.chain().focus().setHorizontalRule().run();
        return;
      case 'todo':
        setBlockStyle(ed, 'todo_list');
        return;
      case 'quote':
        setBlockStyle(ed, 'quote');
        return;
      case 'image': {
        const picked = await window.mario.asset.pickImage();
        if (picked) {
          insertBlock(ed, {
            type: 'embed',
            attrs: { kind: 'image', data: { url: picked.localPath, drive_id: picked.driveId, width: 520, align: 'center' } },
          });
        }
        return;
      }
      case 'spreadsheet':
        insertBlock(ed, {
          type: 'embed',
          attrs: {
            kind: 'spreadsheet',
            data: {
              workbook: {
                activeIndex: 0,
                sheets: [
                  {
                    name: 'Sheet1',
                    rows: 5,
                    cols: 4,
                    cells: { A1: 'Item', B1: 'Cost', A2: 'Server', B2: '120', A3: 'Storage', B3: '45', A4: 'Total', B4: '=SUM(B2:B3)' },
                  },
                ],
              },
            },
          },
        });
        return;
      case 'drawing':
        insertBlock(ed, { type: 'embed', attrs: { kind: 'drawing', data: { strokes: [], height: 220 } } }, true);
        return;
      case 'audio':
        insertBlock(ed, { type: 'embed', attrs: { kind: 'audio_clip', data: { path: '', durationMs: 0 } } }, true);
        return;
      case 'html':
        insertBlock(ed, { type: 'embed', attrs: { kind: 'html', data: { html: DEFAULT_HTML } } }, true);
        return;
      case 'datetime': {
        const now = new Date();
        const stamp = `${now.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })} ${now.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}`;
        ed.chain().focus().insertContent(stamp).run();
        return;
      }
      case 'link':
        openLinkDialog(ed);
        return;
    }
  }

  function runSlash(ed: Editor, s: SlashState, kind: InsertKind | BlockStyle | AiSlashKind) {
    setSlash(null);
    ed.chain().focus().deleteRange({ from: s.from, to: ed.state.selection.from }).run();
    void performInsert(ed, kind);
  }

  const applyLink = () => {
    if (!editor || !linkDialog) return;
    const href = linkDialog.href.trim();
    const chain = editor.chain().focus();
    if (!href) {
      chain.extendMarkRange('link').unsetLink().run();
    } else if (linkDialog.hasSelection) {
      chain.extendMarkRange('link').setLink({ href }).run();
    } else {
      const text = linkDialog.text.trim() || href;
      chain.insertContent({ type: 'text', text, marks: [{ type: 'link', attrs: { href } }] }).unsetMark('link').run();
    }
    setLinkDialog(null);
  };

  const runOcrDocument = async () => {
    try {
      const res = await window.mario.ocr.pickAndRunMinerU();
      if (res && res.success && res.markdown && editor) {
        editor.commands.focus('end');
        insertMarkdown(editor, res.markdown);
      } else if (res && !res.success) {
        setAlert({ title: 'MinerU couldn’t read the file.', message: res.error || 'No text was recognised.' });
      }
    } catch (err) {
      setAlert({ title: 'MinerU couldn’t read the file.', message: err instanceof Error ? err.message : String(err) });
    }
  };

  // While editing side by side, the webpage reloads after a pause, not on every key.
  const previewSourceDoc = useDebounced(content.document, preview?.layout === 'split' ? 500 : 0);
  const webDoc = useMemo(() => {
    if (!preview) return null;
    if (rawHtmlOverride) return prepareWebDocument({ html: [rawHtmlOverride] });
    if (preview.blockId) return buildBlockWebDocument(previewSourceDoc, preview.blockId);
    return buildPageWebDocument(previewSourceDoc);
  }, [preview, rawHtmlOverride, previewSourceDoc]);
  const previewSource: 'web' | 'document' = webDoc && preview?.source !== 'document' ? 'web' : 'document';
  const previewDoc = useMemo(() => {
    if (!preview) return '';
    if (previewSource === 'web' && webDoc) return webDoc;
    return buildPreviewDocument(title, documentToMarkdown(previewSourceDoc));
  }, [preview, previewSource, webDoc, title, previewSourceDoc]);

  const created = content.createdAt ? new Date(content.createdAt) : null;
  const stamp =
    created && !Number.isNaN(created.getTime())
      ? `${created.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}   ${created.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}`
      : null;

  const inTable = ribbonState?.inTable ?? false;
  const contextMenu = editor && (
    <>
      <MenuItem shortcut="⌃X" onSelect={() => { editor.commands.focus(); document.execCommand('cut'); }}>Cut</MenuItem>
      <MenuItem icon="bubble-left" onSelect={() => openAsk(editor)}>
        Ask Mario…
      </MenuItem>
      <MenuSeparator />
      <MenuItem shortcut="⌃C" onSelect={() => { editor.commands.focus(); document.execCommand('copy'); }}>Copy</MenuItem>
      <MenuItem
        shortcut="⌃V"
        onSelect={async () => {
          const text = await navigator.clipboard.readText().catch(() => '');
          if (text) insertMarkdown(editor, text);
        }}
      >
        Paste
      </MenuItem>
      <MenuSeparator />
      <MenuItem shortcut="⌃B" onSelect={() => editor.chain().focus().toggleBold().run()}>Bold</MenuItem>
      <MenuItem shortcut="⌃I" onSelect={() => editor.chain().focus().toggleItalic().run()}>Italic</MenuItem>
      <MenuItem shortcut="⌃U" onSelect={() => editor.chain().focus().toggleUnderline().run()}>Underline</MenuItem>
      <MenuItem shortcut="⇧⌃H" onSelect={() => editor.chain().focus().toggleHighlight({ color: 'rgba(255, 214, 10, 0.4)' }).run()}>Highlight</MenuItem>
      <MenuItem shortcut="⇧⌃K" onSelect={() => openLinkDialog(editor)}>Link…</MenuItem>
      <MenuItem shortcut="⇧⌃N" onSelect={() => editor.chain().focus().unsetAllMarks().run()}>Clear Formatting</MenuItem>
      <MenuSeparator />
      {inTable ? (
        <>
          <MenuHeader>Table</MenuHeader>
          <MenuItem onSelect={() => editor.chain().focus().addRowBefore().run()}>Insert Row Above</MenuItem>
          <MenuItem onSelect={() => editor.chain().focus().addRowAfter().run()}>Insert Row Below</MenuItem>
          <MenuItem onSelect={() => editor.chain().focus().addColumnBefore().run()}>Insert Column Left</MenuItem>
          <MenuItem onSelect={() => editor.chain().focus().addColumnAfter().run()}>Insert Column Right</MenuItem>
          <MenuItem onSelect={() => editor.chain().focus().deleteRow().run()}>Delete Row</MenuItem>
          <MenuItem onSelect={() => editor.chain().focus().deleteColumn().run()}>Delete Column</MenuItem>
          <MenuItem onSelect={() => editor.chain().focus().deleteTable().run()}>Delete Table</MenuItem>
        </>
      ) : (
        <>
          <MenuHeader>Turn Into</MenuHeader>
          <MenuItem onSelect={() => setBlockStyle(editor, 'paragraph')}>Body</MenuItem>
          <MenuItem onSelect={() => setBlockStyle(editor, 'heading-1')}>Heading 1</MenuItem>
          <MenuItem onSelect={() => setBlockStyle(editor, 'heading-2')}>Heading 2</MenuItem>
          <MenuItem onSelect={() => setBlockStyle(editor, 'heading-3')}>Heading 3</MenuItem>
          <MenuItem onSelect={() => setBlockStyle(editor, 'bulleted_list')}>Bulleted List</MenuItem>
          <MenuItem onSelect={() => setBlockStyle(editor, 'numbered_list')}>Numbered List</MenuItem>
          <MenuItem onSelect={() => setBlockStyle(editor, 'todo_list')}>To Do</MenuItem>
          <MenuItem onSelect={() => setBlockStyle(editor, 'quote')}>Quote</MenuItem>
          <MenuItem onSelect={() => setBlockStyle(editor, 'code')}>Code</MenuItem>
          <MenuSeparator />
          <MenuItem shortcut="⌥↑" onSelect={() => moveBlock(editor, -1)}>Move Up</MenuItem>
          <MenuItem shortcut="⌥↓" onSelect={() => moveBlock(editor, 1)}>Move Down</MenuItem>
          <MenuItem shortcut="⇥" onSelect={() => changeIndent(editor, 1)}>Indent</MenuItem>
          <MenuItem shortcut="⇧⇥" onSelect={() => changeIndent(editor, -1)}>Outdent</MenuItem>
        </>
      )}
    </>
  );

  if (!editor) return null;
  const slashItems = slash ? slashMatches(slash.query) : [];

  return (
    <div className="mario-editor-shell">
      <Ribbon
        editor={editor}
        state={ribbonState ?? ({} as RibbonState)}
        fontFamily={fontFamily}
        onFontFamilyChange={onFontFamilyChange}
        fontSize={fontSize}
        onFontSizeChange={onFontSizeChange}
        zoom={zoom}
        onZoomChange={onZoomChange}
        drawMode={drawMode}
        onToggleDrawMode={() => setDrawMode((d) => !d)}
        hasInk={(content.strokes?.length ?? 0) > 0}
        onClearInk={() => onContentChangeRef.current({ ...contentRef.current, document: lastEmitted.current, strokes: [] })}
        htmlPreviewOpen={previewOpen}
        onToggleHtmlPreview={() => setPreview((p) => (p ? null : { layout: 'full', source: 'auto' }))}
        hasHtmlArtifact={Boolean(rawHtmlOverride)}
        saveStatus={saveStatus}
        wordCount={ribbonState?.words ?? 0}
        onInsert={(kind) => void performInsert(editor, kind)}
        onOcrDocument={runOcrDocument}
        onExportMarkdown={onExportMarkdown}
        onExportPdf={onExportPdf}
        onOpenShare={onOpenShare}
      />

      <div className="mario-editor-split">
        <div className="mario-editor-scroll mac-scroll" hidden={preview?.layout === 'full'}>
          <div
            className="mario-page"
            data-width={canvasWidth}
            style={
              {
                '--mario-font': fontStackFor(fontFamily),
                '--mario-font-size': `${fontSize}px`,
                zoom,
              } as React.CSSProperties
            }
          >
            {drawMode && (
              <DrawingCanvasBlock
                overlay
                strokes={content.strokes ?? []}
                onChange={(strokes) =>
                  onContentChangeRef.current({ ...contentRef.current, document: lastEmitted.current, strokes })
                }
                onCloseOverlay={() => setDrawMode(false)}
              />
            )}
            <div className="mac-editor">
              <input
                className="mac-editor__title"
                aria-label="Page Title"
                placeholder="Untitled Page"
                value={isUntitled(title) ? '' : title}
                spellCheck={spellcheck}
                onChange={(e) => {
                  const t = e.target.value;
                  setTitle(t);
                  autoTitleRef.current = null;
                  commitTitleSoon(t.trim() ? t : 'Untitled Page');
                }}
                onBlur={() => {
                  if (isUntitled(titleRef.current)) syncTitleFromHeading(editor);
                  flushTitle();
                }}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === 'ArrowDown') {
                    e.preventDefault();
                    editor.commands.focus('start');
                  }
                }}
              />
              <div className="mario-page__meta">
                {stamp && <span>{stamp}</span>}
                {(content.strokes?.length ?? 0) > 0 && <span>{content.strokes?.length} ink strokes</span>}
              </div>
              <ContextMenu menu={contextMenu}>
                <EditorContent
                  editor={editor}
                  className="mario-doc-host"
                  style={{ fontFamily: 'var(--mario-font)', fontSize: 'var(--mario-font-size)' }}
                />
              </ContextMenu>
            </div>
          </div>
        </div>

        {preview && (
          <div
            className={`mario-preview mario-preview--${preview.layout}${previewSource === 'web' ? ' mario-preview--web' : ''}`}
          >
            <div className="mario-preview__bar">
              {webDoc && !preview.blockId && !rawHtmlOverride ? (
                <SegmentedControl
                  size="small"
                  label="Preview As"
                  value={previewSource}
                  onChange={(v) => setPreview({ ...preview, source: v as 'web' | 'document' })}
                  options={[
                    { value: 'web', label: 'Web Page' },
                    { value: 'document', label: 'Document' },
                  ]}
                />
              ) : (
                <span className="mac-text-subheadline mac-label-secondary">
                  {rawHtmlOverride ? 'Web page from the AI assistant' : preview.blockId ? 'HTML block' : 'Document'}
                </span>
              )}
              <Spacer />
              {rawHtmlOverride && (
                <Button size="small" variant="borderless" onClick={onClearHtmlOverride}>
                  Discard
                </Button>
              )}
              {previewSource === 'web' && (
                <Button
                  size="small"
                  variant="borderless"
                  icon="arrow-clockwise"
                  label="Reload"
                  onClick={() => setPreviewReload((n) => n + 1)}
                />
              )}
              <Button
                size="small"
                variant="borderless"
                icon="sidebar-right"
                label="Side by Side"
                pressed={preview.layout === 'split'}
                onClick={() => setPreview({ ...preview, layout: preview.layout === 'split' ? 'full' : 'split' })}
              />
              <Button size="small" onClick={() => setPreview(null)}>
                Done
              </Button>
            </div>
            <iframe
              key={previewReload}
              title="Preview"
              className="mario-preview__frame"
              sandbox={previewSource === 'web' ? WEB_SANDBOX : 'allow-popups'}
              srcDoc={previewDoc}
            />
          </div>
        )}
      </div>

      {inlineAsk &&
        inlineAskHost(editor) &&
        createPortal(
          <ErrorBoundary key={inlineAsk.nonce} title="Ask Mario ran into a problem" compact>
            <InlineAskBox
              editor={editor}
              anchor={inlineAsk}
              notebookId={notebookId}
              pageId={pageId}
              pageTitle={title}
              onClose={closeAsk}
              onPreviewHtml={onPreviewHtml}
            />
          </ErrorBoundary>,
          inlineAskHost(editor)!,
        )}

      {slash && slashItems.length > 0 && (
        <div
          className="mac-menu mario-slash-menu"
          role="menu"
          aria-label="Insert"
          style={{ left: slash.left, top: Math.min(slash.top, window.innerHeight - 320) }}
          onMouseDown={(e) => e.preventDefault()}
        >
          <MenuHeader>Insert</MenuHeader>
          {slashItems.map((item, i) => (
            <MenuItem
              key={item.kind}
              icon={item.icon}
              shortcut={item.shortcut}
              className={i === slash.index ? 'is-highlighted' : undefined}
              onSelect={() => runSlash(editor, slash, item.kind)}
            >
              {item.label}
            </MenuItem>
          ))}
        </div>
      )}

      <Sheet
        open={linkDialog != null}
        onClose={() => setLinkDialog(null)}
        title="Link"
        top={60}
        buttons={[
          { label: 'Cancel', role: 'cancel', onClick: () => setLinkDialog(null) },
          ...(linkDialog?.hasSelection && editor.isActive('link')
            ? [{ label: 'Remove Link', onClick: () => { editor.chain().focus().extendMarkRange('link').unsetLink().run(); setLinkDialog(null); } }]
            : []),
          { label: 'OK', role: 'default' as const, disabled: !linkDialog?.href.trim(), onClick: applyLink },
        ]}
      >
        {linkDialog && (
          <FieldGrid
            rows={[
              ...(linkDialog.hasSelection
                ? []
                : [
                    {
                      label: 'Text:',
                      control: (
                        <TextField
                          value={linkDialog.text}
                          placeholder="Shown in the page"
                          onChange={(text) => setLinkDialog({ ...linkDialog, text })}
                        />
                      ),
                    },
                  ]),
              {
                label: 'Address:',
                control: (
                  <TextField
                    autoFocus
                    type="url"
                    value={linkDialog.href}
                    placeholder="https://"
                    onChange={(href) => setLinkDialog({ ...linkDialog, href })}
                  />
                ),
              },
            ]}
          />
        )}
      </Sheet>

      <Alert
        open={alert != null}
        onClose={() => setAlert(null)}
        title={alert?.title ?? ''}
        message={alert?.message}
        buttons={[{ label: 'OK', role: 'default', onClick: () => setAlert(null) }]}
      />
    </div>
  );
}
