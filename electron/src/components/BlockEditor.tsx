import React, { useEffect, useMemo, useRef, useState } from 'react';
import katex from 'katex';
import hljs from 'highlight.js';
import {
  Button,
  Checkbox,
  MenuHeader,
  MenuItem,
  PopUpButton,
  Spacer,
  type IconName,
} from '../macos/macos';
import type {
  AppFlowyNode,
  BlockAlign,
  DeltaAttributes,
  DeltaOp,
  PageContent,
  Stroke,
  WorkbookData,
} from '../shared/types';
import {
  buildTableNodeFromRows,
  colIndexToLabel,
  deltaToMarkdown,
  deltaToPlainText,
  documentToMarkdown,
  evaluateSheetCell,
  expandEmojiShortcodes,
  extractTableRowsFromNode,
  makeCodeNode,
  makeDividerNode,
  makeDrawingNode,
  makeHeadingNode,
  makeHtmlNode,
  makeListNode,
  makeMathNode,
  makeParagraphNode,
  makeQuoteNode,
  makeSpreadsheetNode,
  makeTableNode,
  markdownToNodes,
  normalizeLatexFormula,
  normalizeWorkbook,
  parseInlineMarkdownToDelta,
} from '../shared/document-codec';
import { nanoid6 } from '../shared/ids';
import { DrawingCanvasBlock } from './DrawingCanvasBlock';
import { MacFormatBar, type InsertBlockKind } from './MacFormatBar';

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
}

const SLASH_ITEMS: Array<{
  kind: InsertBlockKind;
  label: string;
  keywords: string;
  icon: IconName;
  shortcut?: string;
}> = [
  {
    kind: 'heading1',
    label: 'Heading 1',
    keywords: 'h1 title heading1',
    icon: 'book',
    shortcut: '⌃⌥1',
  },
  {
    kind: 'heading2',
    label: 'Heading 2',
    keywords: 'h2 subtitle heading2',
    icon: 'book',
    shortcut: '⌃⌥2',
  },
  {
    kind: 'heading3',
    label: 'Heading 3',
    keywords: 'h3 subheading heading3',
    icon: 'book',
    shortcut: '⌃⌥3',
  },
  {
    kind: 'bulleted_list',
    label: 'Bulleted List',
    keywords: 'bullet ul list',
    icon: 'list-bullet',
    shortcut: '⇧⌃8',
  },
  {
    kind: 'numbered_list',
    label: 'Numbered List',
    keywords: 'number ol list',
    icon: 'line-3-horizontal',
    shortcut: '⇧⌃7',
  },
  {
    kind: 'todo_list',
    label: 'Checklist / To-Do',
    keywords: 'todo check task',
    icon: 'checkmark-circle-fill',
    shortcut: '⇧⌃9',
  },
  {
    kind: 'quote',
    label: 'Quote Block',
    keywords: 'quote blockquote',
    icon: 'bubble-left',
    shortcut: '⇧⌃Q',
  },
  {
    kind: 'code',
    label: 'Code Block',
    keywords: 'code snippet pre',
    icon: 'cpu',
    shortcut: '⌃⌥C',
  },
  {
    kind: 'math_equation',
    label: 'Math Equation (LaTeX)',
    keywords: 'math latex katex formula equation',
    icon: 'command',
    shortcut: '⌃⌥M',
  },
  {
    kind: 'table',
    label: 'Table (3×3)',
    keywords: 'table grid',
    icon: 'square-grid',
  },
  {
    kind: 'spreadsheet',
    label: 'Spreadsheet (Formulas)',
    keywords: 'sheet excel spreadsheet formula sum',
    icon: 'chart-bar',
  },
  {
    kind: 'drawing',
    label: 'Drawing Canvas',
    keywords: 'draw sketch ink canvas pen',
    icon: 'pencil-tip-circle',
  },
  {
    kind: 'audio_clip',
    label: 'Audio Voice Clip',
    keywords: 'audio voice mic record',
    icon: 'mic',
  },
  {
    kind: 'image',
    label: 'Image…',
    keywords: 'image photo picture',
    icon: 'photo',
  },
  {
    kind: 'html',
    label: 'HTML Render Block',
    keywords: 'html iframe embed web markup render',
    icon: 'globe',
  },
  {
    kind: 'divider',
    label: 'Horizontal Divider',
    keywords: 'divider hr line',
    icon: 'minus',
  },
];

function ImageBlockView({
  node,
  onUpdate,
  onDelete,
  onInsertAfterMarkdown,
}: {
  node: AppFlowyNode;
  onUpdate: (next: AppFlowyNode) => void;
  onDelete: () => void;
  onInsertAfterMarkdown?: (md: string) => void;
}) {
  const url = String(node.data?.url ?? '');
  const driveId = String(node.data?.drive_id ?? '');
  const width = Number(node.data?.width ?? 520);
  const [resolvedSrc, setResolvedSrc] = useState<string | null>(null);
  const [ocrRunning, setOcrRunning] = useState(false);
  const [ocrMessage, setOcrMessage] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    window.mario.asset
      .resolveImage(url || undefined, driveId || undefined)
      .then((res) => {
        if (!cancelled) setResolvedSrc(res);
      })
      .catch(() => {
        if (!cancelled) setResolvedSrc(null);
      });
    return () => {
      cancelled = true;
    };
  }, [url, driveId]);

  const handleRunOcr = async () => {
    const target = resolvedSrc || url;
    if (!target) return;
    setOcrRunning(true);
    setOcrMessage(null);
    try {
      const res = await window.mario.ocr.runMinerU(target);
      if (res.success && res.markdown) {
        setOcrMessage('Extracted text with MinerU!');
        if (onInsertAfterMarkdown) {
          onInsertAfterMarkdown(res.markdown);
        }
      } else {
        setOcrMessage(res.error || 'No text recognized by MinerU');
      }
    } catch (err) {
      setOcrMessage(err instanceof Error ? err.message : String(err));
    } finally {
      setOcrRunning(false);
    }
  };

  return (
    <div className="mario-rich-card">
      <div className="mario-rich-card__header">
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span>Image</span>
          {ocrMessage && (
            <span
              className="mac-caption mac-label-secondary"
              style={{ fontSize: 11 }}
            >
              {ocrMessage}
            </span>
          )}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <Button
            size="small"
            variant="tinted"
            icon="bolt"
            disabled={ocrRunning || !resolvedSrc}
            onClick={handleRunOcr}
          >
            {ocrRunning ? 'MinerU OCR…' : 'OCR (MinerU)'}
          </Button>
          <Button
            size="small"
            variant="borderless"
            onClick={() =>
              onUpdate({
                ...node,
                data: {
                  ...node.data,
                  width: Math.max(180, width - 80),
                },
              })
            }
          >
            Smaller
          </Button>
          <Button
            size="small"
            variant="borderless"
            onClick={() =>
              onUpdate({
                ...node,
                data: {
                  ...node.data,
                  width: Math.min(760, width + 80),
                },
              })
            }
          >
            Larger
          </Button>
          <Button
            size="small"
            variant="borderless"
            icon="trash"
            label="Remove Image"
            onClick={onDelete}
          />
        </div>
      </div>
      <div style={{ padding: 12, textAlign: 'center' }}>
        {resolvedSrc ? (
          <img
            src={resolvedSrc}
            alt=""
            style={{
              maxWidth: '100%',
              width,
              borderRadius: 6,
            }}
          />
        ) : (
          <p className="mac-label-secondary" style={{ margin: 0 }}>
            {url || driveId ? 'Loading image…' : 'No image selected'}
          </p>
        )}
      </div>
    </div>
  );
}

function HtmlBlockView({
  node,
  onUpdate,
  onDelete,
}: {
  node: AppFlowyNode;
  onUpdate: (next: AppFlowyNode) => void;
  onDelete: () => void;
}) {
  const [viewMode, setViewMode] = useState<'preview' | 'code'>('preview');
  const rawHtml = String(node.data?.html ?? '');

  return (
    <div className="mario-rich-card">
      <div className="mario-rich-card__header">
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span>HTML Render</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <Button
            size="small"
            variant={viewMode === 'preview' ? 'bordered' : 'tinted'}
            onClick={() =>
              setViewMode(viewMode === 'preview' ? 'code' : 'preview')
            }
          >
            {viewMode === 'preview' ? 'Edit HTML' : 'Live Preview'}
          </Button>
          <Button
            size="small"
            variant="borderless"
            icon="trash"
            label="Remove HTML Block"
            onClick={onDelete}
          />
        </div>
      </div>
      {viewMode === 'code' ? (
        <div style={{ padding: 12 }}>
          <textarea
            rows={6}
            style={{
              width: '100%',
              fontFamily: 'monospace',
              fontSize: 13,
              background: 'var(--mac-field-bg)',
              color: 'var(--mac-text-primary)',
              border: '1px solid var(--mac-separator)',
              borderRadius: 6,
              padding: 8,
              resize: 'vertical',
              boxSizing: 'border-box',
            }}
            value={rawHtml}
            onChange={(e) =>
              onUpdate({
                ...node,
                data: { ...node.data, html: e.target.value },
              })
            }
            placeholder="Write or paste <div>HTML code</div> here…"
          />
        </div>
      ) : (
        <div style={{ padding: 12 }}>
          <iframe
            title="HTML Render"
            srcDoc={
              rawHtml ||
              '<div style="font-family:sans-serif;color:#888;padding:12px;">Empty HTML block. Click Edit HTML to add markup.</div>'
            }
            sandbox="allow-scripts allow-forms allow-popups"
            style={{
              width: '100%',
              minHeight: 120,
              border: '1px solid var(--mac-separator)',
              borderRadius: 6,
              background: '#ffffff',
            }}
          />
        </div>
      )}
    </div>
  );
}

function AudioClipBlockView({
  node,
  onUpdate,
  onDelete,
}: {
  node: AppFlowyNode;
  onUpdate: (next: AppFlowyNode) => void;
  onDelete: () => void;
}) {
  const [recording, setRecording] = useState(false);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const dataUrl = String(node.data?.dataUrl ?? node.data?.path ?? '');
  const durationMs = Number(node.data?.durationMs ?? 0);
  const startedAtRef = useRef<number>(0);

  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const rec = new MediaRecorder(stream);
      chunksRef.current = [];
      rec.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data);
      };
      rec.onstop = () => {
        stream.getTracks().forEach((t) => t.stop());
        const blob = new Blob(chunksRef.current, { type: 'audio/webm' });
        const reader = new FileReader();
        const elapsed = Date.now() - startedAtRef.current;
        reader.onloadend = () => {
          onUpdate({
            ...node,
            data: {
              ...node.data,
              dataUrl: String(reader.result ?? ''),
              durationMs: elapsed,
            },
          });
        };
        reader.readAsDataURL(blob);
      };
      startedAtRef.current = Date.now();
      recorderRef.current = rec;
      rec.start();
      setRecording(true);
    } catch {
      setRecording(false);
    }
  };

  const stopRecording = () => {
    recorderRef.current?.stop();
    setRecording(false);
  };

  return (
    <div className="mario-rich-card">
      <div className="mario-rich-card__header">
        <span>
          Voice Clip{' '}
          {durationMs > 0 ? `(${(durationMs / 1000).toFixed(1)}s)` : ''}
        </span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          {recording ? (
            <Button
              size="small"
              variant="destructive"
              icon="stop"
              onClick={stopRecording}
            >
              Stop Recording
            </Button>
          ) : (
            <Button
              size="small"
              variant="bordered"
              icon="mic"
              onClick={startRecording}
            >
              {dataUrl ? 'Re-record' : 'Record Voice'}
            </Button>
          )}
          <Button
            size="small"
            variant="borderless"
            icon="trash"
            label="Delete Audio Clip"
            onClick={onDelete}
          />
        </div>
      </div>
      <div style={{ padding: 10 }}>
        {dataUrl ? (
          <audio
            controls
            src={dataUrl}
            style={{ width: '100%', height: 32 }}
          />
        ) : (
          <span className="mac-caption-1 mac-label-secondary">
            {recording
              ? 'Recording from microphone…'
              : 'Click "Record Voice" to capture an audio note.'}
          </span>
        )}
      </div>
    </div>
  );
}

function SpreadsheetBlockView({
  node,
  onUpdate,
  onDelete,
}: {
  node: AppFlowyNode;
  onUpdate: (next: AppFlowyNode) => void;
  onDelete: () => void;
}) {
  const workbook: WorkbookData = useMemo(
    () => normalizeWorkbook(node.data),
    [node.data],
  );

  const [editingCell, setEditingCell] = useState<string | null>(null);
  const activeIdx = Math.min(
    Math.max(0, workbook.activeIndex || 0),
    workbook.sheets.length - 1,
  );
  const sheet = workbook.sheets[activeIdx] ?? {
    name: 'Sheet1',
    rows: 5,
    cols: 4,
    cells: {},
  };

  const commitWorkbook = (next: WorkbookData) => {
    onUpdate({
      ...node,
      data: {
        ...node.data,
        workbook: next,
      },
    });
  };

  const setCell = (key: string, val: string) => {
    const nextCells = { ...sheet.cells };
    if (!val) delete nextCells[key];
    else nextCells[key] = val;
    const nextSheets = workbook.sheets.map((s, i) =>
      i === activeIdx ? { ...s, cells: nextCells } : s,
    );
    commitWorkbook({ ...workbook, sheets: nextSheets });
  };

  const addSheet = () => {
    const nextSheets = [
      ...workbook.sheets,
      {
        name: `Sheet${workbook.sheets.length + 1}`,
        rows: 5,
        cols: 4,
        cells: {},
      },
    ];
    commitWorkbook({
      ...workbook,
      activeIndex: nextSheets.length - 1,
      sheets: nextSheets,
    });
  };

  return (
    <div className="mario-rich-card">
      <div className="mario-rich-card__header">
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span>Spreadsheet</span>
          {workbook.sheets.map((s, idx) => (
            <Button
              key={idx}
              size="small"
              variant={idx === activeIdx ? 'tinted' : 'borderless'}
              onClick={() => commitWorkbook({ ...workbook, activeIndex: idx })}
            >
              {s.name}
            </Button>
          ))}
          <Button
            size="small"
            variant="borderless"
            icon="plus"
            label="New Sheet"
            onClick={addSheet}
          />
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <Button
            size="small"
            variant="borderless"
            onClick={() => {
              const nextSheets = workbook.sheets.map((s, i) =>
                i === activeIdx ? { ...s, rows: s.rows + 1 } : s,
              );
              commitWorkbook({ ...workbook, sheets: nextSheets });
            }}
          >
            +Row
          </Button>
          <Button
            size="small"
            variant="borderless"
            onClick={() => {
              const nextSheets = workbook.sheets.map((s, i) =>
                i === activeIdx ? { ...s, cols: Math.min(12, s.cols + 1) } : s,
              );
              commitWorkbook({ ...workbook, sheets: nextSheets });
            }}
          >
            +Col
          </Button>
          <Button
            size="small"
            variant="borderless"
            icon="trash"
            label="Delete Spreadsheet"
            onClick={onDelete}
          />
        </div>
      </div>
      <div style={{ overflowX: 'auto' }}>
        <table className="mario-sheet-table">
          <thead>
            <tr>
              <th style={{ width: 32, minWidth: 32 }}>#</th>
              {Array.from({ length: sheet.cols }).map((_, c) => (
                <th key={c}>{colIndexToLabel(c)}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {Array.from({ length: sheet.rows }).map((_, r) => (
              <tr key={r}>
                <th>{r + 1}</th>
                {Array.from({ length: sheet.cols }).map((__, c) => {
                  const cellRef = `${colIndexToLabel(c)}${r + 1}`;
                  const raw = sheet.cells[cellRef] ?? '';
                  const isEditing = editingCell === cellRef;
                  const display = isEditing
                    ? raw
                    : evaluateSheetCell(sheet, cellRef);
                  return (
                    <td key={c}>
                      <input
                        className="mario-sheet-cell-input"
                        value={display}
                        placeholder={isEditing ? '=SUM(A1:A3)' : ''}
                        onFocus={() => setEditingCell(cellRef)}
                        onBlur={() => setEditingCell(null)}
                        onChange={(e) => setCell(cellRef, e.target.value)}
                      />
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
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
}: BlockEditorProps) {
  const nodes = content.document?.children ?? [];
  const [focusedBlockId, setFocusedBlockId] = useState<string | null>(
    nodes[0]?.id ?? null,
  );
  const [drawMode, setDrawMode] = useState(false);
  const [htmlPreviewOpen, setHtmlPreviewOpen] = useState(false);
  const [slashState, setSlashState] = useState<{
    blockId: string;
    query: string;
    x: number;
    y: number;
  } | null>(null);
  const inputRefs = useRef<
    Record<string, HTMLTextAreaElement | HTMLInputElement | null>
  >({});
  const undoStackRef = useRef<PageContent[]>([]);
  const redoStackRef = useRef<PageContent[]>([]);
  const [, setHistoryTick] = useState(0);

  useEffect(() => {
    if (rawHtmlOverride) {
      setHtmlPreviewOpen(true);
    }
  }, [rawHtmlOverride]);

  const focusedNode = useMemo(
    () => nodes.find((n) => n.id === focusedBlockId) ?? nodes[0] ?? null,
    [nodes, focusedBlockId],
  );

  const activeBlockStyle = useMemo(() => {
    if (!focusedNode) return 'paragraph';
    if (focusedNode.type === 'heading') {
      return `heading-${Number(focusedNode.data?.level ?? 1)}`;
    }
    return focusedNode.type;
  }, [focusedNode]);

  const activeAlign: BlockAlign =
    (focusedNode?.data?.align as BlockAlign) ?? 'left';

  const commitContent = (nextContent: PageContent) => {
    const prevStack = undoStackRef.current;
    if (prevStack.length >= 60) prevStack.shift();
    prevStack.push(content);
    redoStackRef.current = [];
    setHistoryTick((t) => t + 1);
    onContentChange(nextContent);
  };

  const handleUndo = () => {
    const prev = undoStackRef.current.pop();
    if (!prev) return;
    redoStackRef.current.push(content);
    setHistoryTick((t) => t + 1);
    onContentChange(prev);
  };

  const handleRedo = () => {
    const next = redoStackRef.current.pop();
    if (!next) return;
    undoStackRef.current.push(content);
    setHistoryTick((t) => t + 1);
    onContentChange(next);
  };

  const commitNodes = (nextNodes: AppFlowyNode[]) => {
    const safeNodes =
      nextNodes.length > 0 ? nextNodes : [makeParagraphNode('')];
    commitContent({
      ...content,
      document: {
        type: 'page',
        children: safeNodes,
      },
    });
  };

  const moveBlock = (id: string | undefined, delta: -1 | 1) => {
    if (!id) return;
    const idx = nodes.findIndex((n) => n.id === id);
    const targetIdx = idx + delta;
    if (idx < 0 || targetIdx < 0 || targetIdx >= nodes.length) return;
    const next = [...nodes];
    const [moved] = next.splice(idx, 1);
    if (!moved) return;
    next.splice(targetIdx, 0, moved);
    commitNodes(next);
    setFocusedBlockId(id);
    setTimeout(() => inputRefs.current[id]?.focus(), 10);
  };

  const updateNode = (
    id: string | undefined,
    updater: (prev: AppFlowyNode) => AppFlowyNode,
  ) => {
    if (!id) return;
    commitNodes(nodes.map((n) => (n.id === id ? updater(n) : n)));
  };

  const deleteNode = (id: string | undefined) => {
    if (!id) return;
    const idx = nodes.findIndex((n) => n.id === id);
    const next = nodes.filter((n) => n.id !== id);
    commitNodes(next);
    const target = next[Math.max(0, idx - 1)];
    if (target?.id) {
      const targetId = target.id;
      setFocusedBlockId(targetId);
      setTimeout(() => inputRefs.current[targetId]?.focus(), 10);
    }
  };

  const insertAfter = (afterId: string | null, newNode: AppFlowyNode) => {
    const ensuredId = newNode.id ?? nanoid6();
    const nodeWithId: AppFlowyNode = { ...newNode, id: ensuredId };
    if (!afterId) {
      commitNodes([...nodes, nodeWithId]);
    } else {
      const idx = nodes.findIndex((n) => n.id === afterId);
      if (idx < 0) {
        commitNodes([...nodes, nodeWithId]);
      } else {
        const next = [...nodes];
        next.splice(idx + 1, 0, nodeWithId);
        commitNodes(next);
      }
    }
    setFocusedBlockId(ensuredId);
    setTimeout(() => inputRefs.current[ensuredId]?.focus(), 15);
  };

  const createNodeForKind = async (
    kind: InsertBlockKind,
  ): Promise<AppFlowyNode | null> => {
    switch (kind) {
      case 'paragraph':
        return makeParagraphNode('');
      case 'heading1':
        return makeHeadingNode(1, '');
      case 'heading2':
        return makeHeadingNode(2, '');
      case 'heading3':
        return makeHeadingNode(3, '');
      case 'bulleted_list':
        return makeListNode('bulleted_list', '');
      case 'numbered_list':
        return makeListNode('numbered_list', '');
      case 'todo_list':
        return makeListNode('todo_list', '', false);
      case 'quote':
        return makeQuoteNode('');
      case 'code':
        return makeCodeNode('', 'python');
      case 'math_equation':
        return makeMathNode('E = mc^2');
      case 'table':
        return makeTableNode([
          ['Column 1', 'Column 2', 'Column 3'],
          ['', '', ''],
          ['', '', ''],
        ]);
      case 'spreadsheet':
        return makeSpreadsheetNode({
          activeIndex: 0,
          sheets: [
            {
              name: 'Sheet1',
              rows: 5,
              cols: 4,
              cells: {
                A1: 'Item',
                B1: 'Cost',
                A2: 'Server',
                B2: '120',
                A3: 'Storage',
                B3: '45',
                A4: 'Total',
                B4: '=SUM(B2:B3)',
              },
            },
          ],
        });
      case 'drawing':
        return makeDrawingNode([], 220);
      case 'audio_clip':
        return {
          id: nanoid6(),
          type: 'audio_clip',
          data: { path: '', durationMs: 0 },
        };
      case 'divider':
        return makeDividerNode();
      case 'html':
        return makeHtmlNode();
      case 'image': {
        const picked = await window.mario.asset.pickImage();
        if (!picked) return null;
        return {
          id: nanoid6(),
          type: 'image',
          data: {
            url: picked.localPath,
            drive_id: picked.driveId,
            width: 520,
            align: 'center',
          },
        };
      }
    }
  };

  const handleInsertBlock = async (
    kind: InsertBlockKind,
    replaceBlockId?: string,
  ) => {
    setSlashState(null);
    const created = await createNodeForKind(kind);
    if (!created) return;
    if (replaceBlockId) {
      commitNodes(
        nodes.map((n) =>
          n.id === replaceBlockId ? { ...created, id: n.id } : n,
        ),
      );
      setFocusedBlockId(replaceBlockId);
      setTimeout(() => inputRefs.current[replaceBlockId]?.focus(), 15);
    } else {
      insertAfter(focusedBlockId, created);
    }
  };

  const handleBlockStyleChange = (style: string) => {
    if (!focusedNode?.id) return;
    const text = deltaToPlainText(focusedNode.data?.delta);
    updateNode(focusedNode.id, (prev) => {
      if (style.startsWith('heading-')) {
        const level = Number(style.split('-')[1]) || 1;
        return {
          ...prev,
          type: 'heading',
          data: {
            ...prev.data,
            level,
            delta: prev.data?.delta ?? [{ insert: text }],
          },
        };
      }
      if (style === 'code') {
        return {
          ...prev,
          type: 'code',
          data: {
            language: 'python',
            code: text,
            delta: [{ insert: text }],
          },
        };
      }
      if (style === 'todo_list') {
        return {
          ...prev,
          type: 'todo_list',
          data: {
            ...prev.data,
            checked: Boolean(prev.data?.checked),
            delta: prev.data?.delta ?? [{ insert: text }],
          },
        };
      }
      return {
        ...prev,
        type: style,
        data: {
          ...prev.data,
          delta: prev.data?.delta ?? [{ insert: text }],
        },
      };
    });
  };

  const applyInlineSelectionMark = (
    mark: 'bold' | 'italic' | 'underline' | 'strikethrough' | 'code',
  ) => {
    if (!focusedNode?.id) return;
    const el = inputRefs.current[focusedNode.id];
    const raw = deltaToMarkdown(focusedNode.data?.delta);
    const wrapMap: Record<typeof mark, [string, string]> = {
      bold: ['**', '**'],
      italic: ['*', '*'],
      underline: ['<u>', '</u>'],
      strikethrough: ['~~', '~~'],
      code: ['`', '`'],
    };
    const [open, close] = wrapMap[mark];
    if (
      el &&
      el.selectionStart != null &&
      el.selectionEnd != null &&
      el.selectionEnd > el.selectionStart
    ) {
      const start = el.selectionStart;
      const end = el.selectionEnd;
      const selected = raw.slice(start, end);
      const nextText = `${raw.slice(0, start)}${open}${selected}${close}${raw.slice(end)}`;
      updateNode(focusedNode.id, (prev) => ({
        ...prev,
        data: {
          ...prev.data,
          delta: parseInlineMarkdownToDelta(nextText),
        },
      }));
      return;
    }
    updateNode(focusedNode.id, (prev) => {
      const delta = prev.data?.delta ?? [
        { insert: deltaToPlainText(prev.data?.delta) },
      ];
      const allMarked = delta.every((op) => op.attributes?.[mark]);
      const nextDelta: DeltaOp[] = delta.map((op) => ({
        insert: op.insert,
        attributes: {
          ...op.attributes,
          [mark]: !allMarked,
        },
      }));
      return {
        ...prev,
        data: {
          ...prev.data,
          delta: nextDelta,
        },
      };
    });
  };

  const applyBlockColor = (attrKey: 'text_color' | 'bg_color', hex: string) => {
    if (!focusedNode?.id) return;
    updateNode(focusedNode.id, (prev) => {
      const delta = prev.data?.delta ?? [
        { insert: deltaToPlainText(prev.data?.delta) },
      ];
      const nextDelta: DeltaOp[] = delta.map((op) => {
        const nextAttrs: DeltaAttributes = { ...op.attributes };
        if (!hex) delete nextAttrs[attrKey];
        else nextAttrs[attrKey] = hex;
        return { insert: op.insert, attributes: nextAttrs };
      });
      return {
        ...prev,
        data: {
          ...prev.data,
          delta: nextDelta,
        },
      };
    });
  };

  const handleAlignChange = (align: BlockAlign) => {
    if (!focusedNode?.id) return;
    const cleanAlign = align === 'justify' ? 'left' : align;
    updateNode(focusedNode.id, (prev) => ({
      ...prev,
      data: {
        ...prev.data,
        align: cleanAlign,
      },
    }));
  };

  const stats = useMemo(() => {
    const md = documentToMarkdown(content.document);
    const words = md
      .trim()
      .split(/\s+/)
      .filter(Boolean).length;
    return { words, blocks: nodes.length };
  }, [content.document, nodes.length]);

  const fontStack = useMemo(() => {
    switch (fontFamily) {
      case 'Inter':
        return '"Inter", -apple-system, BlinkMacSystemFont, sans-serif';
      case 'Serif':
        return 'Georgia, "Times New Roman", serif';
      case 'Monospace':
        return 'ui-monospace, "SF Mono", Menlo, Consolas, monospace';
      default:
        return 'inherit';
    }
  }, [fontFamily]);

  const renderFormattedDeltaPreview = (node: AppFlowyNode) => {
    const ops = node.data?.delta ?? [];
    if (ops.length === 0) {
      return (
        <span className="mac-label-tertiary">
          {node.type === 'heading'
            ? `Heading ${node.data?.level ?? 1}`
            : 'Type "/" for commands…'}
        </span>
      );
    }
    return ops.map((op, i) => {
      const text = op.insert ?? '';
      const a = op.attributes ?? {};
      const parts = text.split(/(\$[^$\n]+\$)/g);
      const rendered = parts.map((part, pIdx) => {
        if (part.startsWith('$') && part.endsWith('$') && part.length > 2) {
          const tex = part.slice(1, -1);
          const html = katex.renderToString(normalizeLatexFormula(tex), {
            displayMode: false,
            throwOnError: false,
          });
          return <span key={pIdx} dangerouslySetInnerHTML={{ __html: html }} />;
        }
        return <React.Fragment key={pIdx}>{part}</React.Fragment>;
      });

      const style: React.CSSProperties = {
        fontWeight: a.bold ? 600 : undefined,
        fontStyle: a.italic ? 'italic' : undefined,
        textDecoration:
          [
            a.underline ? 'underline' : '',
            a.strikethrough ? 'line-through' : '',
          ]
            .filter(Boolean)
            .join(' ') || undefined,
        color: (a.text_color as string) || undefined,
        backgroundColor: (a.bg_color as string) || undefined,
      };

      if (a.code) {
        return (
          <code key={i} className="mario-inline-code" style={style}>
            {rendered}
          </code>
        );
      }
      if (a.href) {
        return (
          <a
            key={i}
            href={a.href}
            style={{ ...style, color: 'var(--mac-accent)' }}
            onClick={(e) => e.stopPropagation()}
          >
            {rendered}
          </a>
        );
      }
      return (
        <span key={i} style={style}>
          {rendered}
        </span>
      );
    });
  };

  const previewHtmlDoc = useMemo(() => {
    if (rawHtmlOverride) return rawHtmlOverride;
    const htmlCodeBlock = nodes.find(
      (n) =>
        n.type === 'code' &&
        String(n.data?.language ?? '').toLowerCase() === 'html',
    );
    if (htmlCodeBlock) {
      return String(
        htmlCodeBlock.data?.code ??
          deltaToPlainText(htmlCodeBlock.data?.delta),
      );
    }
    const md = documentToMarkdown(content.document);
    return `<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system,BlinkMacSystemFont,"Inter",sans-serif;padding:24px 32px;line-height:1.6;color:#1d1d1f;max-width:740px;margin:0 auto}pre{background:#f5f5f7;padding:12px;border-radius:6px;overflow:auto}</style></head><body><h1>${pageTitle}</h1><pre style="white-space:pre-wrap;font-family:inherit;background:transparent;padding:0">${md.replace(/</g, '&lt;')}</pre></body></html>`;
  }, [rawHtmlOverride, nodes, content.document, pageTitle]);

  let numberedIndex = 0;

  return (
    <div
      className="mario-editor-shell"
      onKeyDown={(e) => {
        const cmd = e.metaKey || e.ctrlKey;
        if (!cmd) return;
        const k = e.key.toLowerCase();
        if (k === 'z' && !e.shiftKey && !e.altKey) {
          if (undoStackRef.current.length > 0) {
            e.preventDefault();
            handleUndo();
          }
        } else if (
          (k === 'z' && e.shiftKey && !e.altKey) ||
          (k === 'y' && !e.shiftKey && !e.altKey)
        ) {
          if (redoStackRef.current.length > 0) {
            e.preventDefault();
            handleRedo();
          }
        }
      }}
    >
      <MacFormatBar
        activeBlockStyle={activeBlockStyle}
        onBlockStyleChange={handleBlockStyleChange}
        fontFamily={fontFamily}
        onFontFamilyChange={onFontFamilyChange}
        fontSize={fontSize}
        onFontSizeChange={onFontSizeChange}
        onToggleInlineFormat={applyInlineSelectionMark}
        onApplyTextColor={(hex) => applyBlockColor('text_color', hex)}
        onApplyHighlightColor={(hex) => applyBlockColor('bg_color', hex)}
        activeAlign={activeAlign}
        onAlignChange={handleAlignChange}
        onInsertBlock={(kind) => handleInsertBlock(kind)}
        zoom={zoom}
        onZoomChange={onZoomChange}
        canUndo={undoStackRef.current.length > 0}
        canRedo={redoStackRef.current.length > 0}
        onUndo={handleUndo}
        onRedo={handleRedo}
        drawMode={drawMode}
        onToggleDrawMode={() => setDrawMode((d) => !d)}
        htmlPreviewOpen={htmlPreviewOpen}
        onToggleHtmlPreview={() => setHtmlPreviewOpen((v) => !v)}
        hasHtmlArtifact={Boolean(rawHtmlOverride)}
        saveStatus={saveStatus}
        onExportMarkdown={onExportMarkdown}
        onExportPdf={onExportPdf}
        onOpenShare={onOpenShare}
        onOcrMinerU={async () => {
          try {
            const res = await window.mario.ocr.pickAndRunMinerU();
            if (res && res.success && res.markdown) {
              const parsed = markdownToNodes(res.markdown);
              if (parsed.length > 0) {
                const nextNodes = [...nodes, ...parsed];
                commitNodes(nextNodes);
              }
            } else if (res && !res.success) {
              alert(`MinerU OCR failed: ${res.error || 'Unknown error'}`);
            }
          } catch (err) {
            alert(`MinerU OCR error: ${err instanceof Error ? err.message : String(err)}`);
          }
        }}
      />

      <div className="mario-editor-split">
        <div
          className="mario-editor-scroll mac-scroll"
          style={{
            fontFamily: fontStack,
            fontSize: `${fontSize}px`,
            zoom,
          }}
        >
          <div className="mario-editor-canvas-wrap">
            {drawMode && (
              <DrawingCanvasBlock
                overlay
                strokes={content.strokes ?? []}
                onChange={(nextStrokes) =>
                  onContentChange({
                    ...content,
                    strokes: nextStrokes,
                  })
                }
                onCloseOverlay={() => setDrawMode(false)}
              />
            )}

            <input
              className="mario-page-title-input"
              value={pageTitle}
              placeholder="Untitled Page"
              spellCheck={spellcheck}
              onChange={(e) => onTitleChange(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  const first = nodes[0];
                  if (first?.id) {
                    setFocusedBlockId(first.id);
                    inputRefs.current[first.id]?.focus();
                  }
                }
              }}
            />

            <div className="mario-page-meta">
              <span>{stats.words} words</span>
              <span>·</span>
              <span>{stats.blocks} blocks</span>
              {(content.strokes?.length ?? 0) > 0 && (
                <>
                  <span>·</span>
                  <span>{content.strokes?.length} ink strokes</span>
                </>
              )}
            </div>

            <div
              className="mario-blocks"
              onClick={(e) => {
                if (e.target === e.currentTarget && nodes.length > 0) {
                  const last = nodes[nodes.length - 1];
                  if (last?.id) {
                    setFocusedBlockId(last.id);
                    inputRefs.current[last.id]?.focus();
                  }
                }
              }}
            >
              {nodes.map((node, index) => {
                const nodeId = node.id ?? `blk_${index}`;
                if (node.type === 'numbered_list') {
                  numberedIndex += 1;
                } else {
                  numberedIndex = 0;
                }
                const currentNumber = numberedIndex;
                const isFocused = focusedBlockId === nodeId;
                const align = (node.data?.align as BlockAlign) ?? 'left';

                // 1. Divider block
                if (node.type === 'divider') {
                  return (
                    <div
                      key={nodeId}
                      className={`mario-block-row ${
                        isFocused ? 'mario-block-row--focused' : ''
                      }`}
                      onClick={() => setFocusedBlockId(nodeId)}
                    >
                      <div className="mario-block-gutter">
                        <button
                          type="button"
                          className="mario-block-gutter__btn"
                          title="Delete Divider"
                          onClick={() => deleteNode(nodeId)}
                        >
                          ×
                        </button>
                      </div>
                      <div
                        className="mario-block-body"
                        style={{ padding: '6px 0' }}
                      >
                        <hr className="mac-divider" />
                      </div>
                    </div>
                  );
                }

                // 2. Code block
                if (node.type === 'code') {
                  const lang = String(node.data?.language ?? 'python');
                  const rawCode = String(
                    node.data?.code ?? deltaToPlainText(node.data?.delta),
                  );
                  let highlighted = '';
                  try {
                    highlighted = hljs.getLanguage(lang)
                      ? hljs.highlight(rawCode, { language: lang }).value
                      : hljs.highlightAuto(rawCode).value;
                  } catch {
                    highlighted = rawCode;
                  }

                  return (
                    <div
                      key={nodeId}
                      className="mario-rich-card"
                      onClick={() => setFocusedBlockId(nodeId)}
                    >
                      <div className="mario-rich-card__header">
                        <PopUpButton
                          size="small"
                          aria-label="Language"
                          value={lang}
                          onChange={(nextLang) =>
                            updateNode(nodeId, (prev) => ({
                              ...prev,
                              data: {
                                ...prev.data,
                                language: nextLang,
                              },
                            }))
                          }
                          options={[
                            'python',
                            'javascript',
                            'typescript',
                            'bash',
                            'dart',
                            'rust',
                            'go',
                            'sql',
                            'json',
                            'html',
                            'css',
                            'markdown',
                          ]}
                        />
                        <Spacer />
                        <Button
                          size="small"
                          variant="borderless"
                          icon="doc-on-doc"
                          onClick={() => navigator.clipboard?.writeText(rawCode)}
                        >
                          Copy
                        </Button>
                        <Button
                          size="small"
                          variant="borderless"
                          icon="trash"
                          label="Delete Code Block"
                          onClick={() => deleteNode(nodeId)}
                        />
                      </div>
                      {isFocused || rawCode.trim().length === 0 ? (
                        <textarea
                          ref={(el) => {
                            inputRefs.current[nodeId] = el;
                          }}
                          className="mario-code-textarea"
                          rows={Math.max(3, rawCode.split('\n').length)}
                          value={rawCode}
                          spellCheck={false}
                          placeholder="Write or paste code…"
                          onFocus={() => setFocusedBlockId(nodeId)}
                          onBlur={() => {
                            if (focusedBlockId === nodeId) {
                              setFocusedBlockId(null);
                            }
                          }}
                          onChange={(e) => {
                            const val = e.target.value;
                            updateNode(nodeId, (prev) => ({
                              ...prev,
                              data: {
                                ...prev.data,
                                code: val,
                                delta: [{ insert: val }],
                              },
                            }));
                          }}
                        />
                      ) : (
                        <pre
                          onClick={() => {
                            setFocusedBlockId(nodeId);
                            setTimeout(() => inputRefs.current[nodeId]?.focus(), 10);
                          }}
                          style={{
                            margin: 0,
                            padding: '10px 12px',
                            fontSize: 13,
                            lineHeight: '19px',
                            fontFamily: 'var(--mac-font-mono)',
                            overflowX: 'auto',
                            cursor: 'text',
                          }}
                        >
                          <code
                            dangerouslySetInnerHTML={{ __html: highlighted }}
                          />
                        </pre>
                      )}
                    </div>
                  );
                }

                // 3. Math Equation block
                if (node.type === 'math_equation') {
                  const formula = String(node.data?.formula ?? '');
                  const html = katex.renderToString(
                    normalizeLatexFormula(formula || '\\text{Empty equation}'),
                    {
                      displayMode: true,
                      throwOnError: false,
                    },
                  );
                  return (
                    <div
                      key={nodeId}
                      className="mario-rich-card"
                      onClick={() => setFocusedBlockId(nodeId)}
                    >
                      <div className="mario-rich-card__header">
                        <span>LaTeX Equation</span>
                        <Button
                          size="small"
                          variant="borderless"
                          icon="trash"
                          label="Delete Equation"
                          onClick={() => deleteNode(nodeId)}
                        />
                      </div>
                      <div
                        className="mario-math-preview"
                        dangerouslySetInnerHTML={{ __html: html }}
                      />
                      {isFocused && (
                        <input
                          ref={(el) => {
                            inputRefs.current[nodeId] = el;
                          }}
                          className="mario-code-textarea"
                          style={{
                            borderTop: '1px solid var(--mac-separator)',
                          }}
                          value={formula}
                          placeholder="e.g. \int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}"
                          onChange={(e) =>
                            updateNode(nodeId, (prev) => ({
                              ...prev,
                              data: {
                                ...prev.data,
                                formula: e.target.value,
                              },
                            }))
                          }
                        />
                      )}
                    </div>
                  );
                }

                // 4. Table block
                if (node.type === 'table') {
                  const matrix = extractTableRowsFromNode(node);
                  const rowsCount = matrix.length;
                  const colsCount = matrix[0]?.length ?? 3;

                  const updateCell = (r: number, c: number, val: string) => {
                    const nextMatrix = matrix.map((row, ri) =>
                      ri === r
                        ? row.map((cell, ci) => (ci === c ? val : cell))
                        : [...row],
                    );
                    updateNode(nodeId, () => ({
                      ...buildTableNodeFromRows(nextMatrix),
                      id: nodeId,
                    }));
                  };

                  return (
                    <div
                      key={nodeId}
                      className="mario-rich-card"
                      onClick={() => setFocusedBlockId(nodeId)}
                    >
                      <div className="mario-rich-card__header">
                        <span>
                          Table ({rowsCount}×{colsCount})
                        </span>
                        <div style={{ display: 'flex', gap: 6 }}>
                          <Button
                            size="small"
                            variant="borderless"
                            onClick={() => {
                              const nextMatrix = [
                                ...matrix,
                                Array.from({ length: colsCount }, () => ''),
                              ];
                              updateNode(nodeId, () => ({
                                ...buildTableNodeFromRows(nextMatrix),
                                id: nodeId,
                              }));
                            }}
                          >
                            +Row
                          </Button>
                          <Button
                            size="small"
                            variant="borderless"
                            onClick={() => {
                              const nextMatrix = matrix.map((r) => [...r, '']);
                              updateNode(nodeId, () => ({
                                ...buildTableNodeFromRows(nextMatrix),
                                id: nodeId,
                              }));
                            }}
                          >
                            +Col
                          </Button>
                          <Button
                            size="small"
                            variant="borderless"
                            icon="trash"
                            label="Delete Table"
                            onClick={() => deleteNode(nodeId)}
                          />
                        </div>
                      </div>
                      <div style={{ overflowX: 'auto' }}>
                        <table className="mario-sheet-table">
                          <tbody>
                            {matrix.map((row, r) => (
                              <tr key={r}>
                                {row.map((cell, c) => (
                                  <td key={c}>
                                    <input
                                      className="mario-sheet-cell-input"
                                      style={{
                                        fontWeight: r === 0 ? 600 : 400,
                                      }}
                                      value={cell}
                                      onChange={(e) =>
                                        updateCell(r, c, e.target.value)
                                      }
                                    />
                                  </td>
                                ))}
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    </div>
                  );
                }

                // 5. Spreadsheet block
                if (node.type === 'spreadsheet') {
                  return (
                    <SpreadsheetBlockView
                      key={nodeId}
                      node={node}
                      onUpdate={(next) => updateNode(nodeId, () => next)}
                      onDelete={() => deleteNode(nodeId)}
                    />
                  );
                }

                // 6. Drawing block
                if (node.type === 'drawing') {
                  const strokes: Stroke[] = Array.isArray(node.data?.strokes)
                    ? (node.data.strokes as Stroke[])
                    : [];
                  const h = Number(node.data?.height ?? 220);
                  return (
                    <DrawingCanvasBlock
                      key={nodeId}
                      strokes={strokes}
                      height={h}
                      onChange={(nextStrokes, nextHeight) =>
                        updateNode(nodeId, (prev) => ({
                          ...prev,
                          data: {
                            ...prev.data,
                            strokes: nextStrokes,
                            height: nextHeight ?? h,
                          },
                        }))
                      }
                      onDelete={() => deleteNode(nodeId)}
                    />
                  );
                }

                // 7. Audio clip block
                if (node.type === 'audio_clip') {
                  return (
                    <AudioClipBlockView
                      key={nodeId}
                      node={node}
                      onUpdate={(next) => updateNode(nodeId, () => next)}
                      onDelete={() => deleteNode(nodeId)}
                    />
                  );
                }

                // 8. Image block
                if (node.type === 'image') {
                  return (
                    <ImageBlockView
                      key={nodeId}
                      node={node}
                      onUpdate={(next) => updateNode(nodeId, () => next)}
                      onDelete={() => deleteNode(nodeId)}
                      onInsertAfterMarkdown={(md) => {
                        const parsed = markdownToNodes(md);
                        if (parsed.length > 0) {
                          const nextNodes = [...nodes];
                          nextNodes.splice(index + 1, 0, ...parsed);
                          commitNodes(nextNodes);
                        }
                      }}
                    />
                  );
                }

                // 8b. HTML Render block
                if (node.type === 'html' || node.type === 'html_preview') {
                  return (
                    <HtmlBlockView
                      key={nodeId}
                      node={node}
                      onUpdate={(next) => updateNode(nodeId, () => next)}
                      onDelete={() => deleteNode(nodeId)}
                    />
                  );
                }

                // 9. Textual blocks: paragraph, heading, bulleted_list, numbered_list, todo_list, quote
                const rawMd = deltaToMarkdown(node.data?.delta);
                const level = Number(node.data?.level ?? 1);
                const headingClass =
                  node.type === 'heading' ? `mario-heading-${level}` : '';

                const handleTextChange = (rawVal: string) => {
                  const val = expandEmojiShortcodes(rawVal);

                  if (val.startsWith('/') && !val.includes(' ')) {
                    const el = inputRefs.current[nodeId];
                    const rect = el?.getBoundingClientRect();
                    setSlashState({
                      blockId: nodeId,
                      query: val.slice(1).toLowerCase(),
                      x: rect ? rect.left : 280,
                      y: rect ? rect.bottom + 4 : 200,
                    });
                  } else if (slashState?.blockId === nodeId) {
                    setSlashState(null);
                  }

                  if (node.type === 'paragraph') {
                    if (val === '# ') {
                      updateNode(nodeId, (p) => ({
                        ...p,
                        type: 'heading',
                        data: { level: 1, delta: [] },
                      }));
                      return;
                    }
                    if (val === '## ') {
                      updateNode(nodeId, (p) => ({
                        ...p,
                        type: 'heading',
                        data: { level: 2, delta: [] },
                      }));
                      return;
                    }
                    if (val === '### ') {
                      updateNode(nodeId, (p) => ({
                        ...p,
                        type: 'heading',
                        data: { level: 3, delta: [] },
                      }));
                      return;
                    }
                    if (val === '- ' || val === '* ') {
                      updateNode(nodeId, (p) => ({
                        ...p,
                        type: 'bulleted_list',
                        data: { delta: [] },
                      }));
                      return;
                    }
                    if (val === '1. ') {
                      updateNode(nodeId, (p) => ({
                        ...p,
                        type: 'numbered_list',
                        data: { delta: [] },
                      }));
                      return;
                    }
                    if (val === '[] ' || val === '[ ] ') {
                      updateNode(nodeId, (p) => ({
                        ...p,
                        type: 'todo_list',
                        data: { checked: false, delta: [] },
                      }));
                      return;
                    }
                    if (val === '[x] ') {
                      updateNode(nodeId, (p) => ({
                        ...p,
                        type: 'todo_list',
                        data: { checked: true, delta: [] },
                      }));
                      return;
                    }
                    if (val === '> ') {
                      updateNode(nodeId, (p) => ({
                        ...p,
                        type: 'quote',
                        data: { delta: [] },
                      }));
                      return;
                    }
                    if (val === '---') {
                      updateNode(nodeId, (p) => ({
                        ...p,
                        type: 'divider',
                        data: {},
                      }));
                      insertAfter(nodeId, makeParagraphNode(''));
                      return;
                    }
                    if (val.startsWith('```')) {
                      const lang = val.slice(3).trim() || 'python';
                      updateNode(nodeId, (p) => ({
                        ...p,
                        type: 'code',
                        data: {
                          language: lang,
                          code: '',
                          delta: [{ insert: '' }],
                        },
                      }));
                      return;
                    }
                  }

                  updateNode(nodeId, (prev) => ({
                    ...prev,
                    data: {
                      ...prev.data,
                      delta: parseInlineMarkdownToDelta(val),
                    },
                  }));
                };

                const handleKeyDown = (
                  e: React.KeyboardEvent<HTMLTextAreaElement | HTMLInputElement>,
                ) => {
                  if (slashState && slashState.blockId === nodeId) {
                    if (e.key === 'Escape') {
                      e.preventDefault();
                      setSlashState(null);
                      return;
                    }
                    if (e.key === 'Enter') {
                      const matches = SLASH_ITEMS.filter(
                        (item) =>
                          item.label.toLowerCase().includes(slashState.query) ||
                          item.keywords.includes(slashState.query),
                      );
                      if (matches[0]) {
                        e.preventDefault();
                        handleInsertBlock(matches[0].kind, nodeId);
                        return;
                      }
                    }
                  }

                  const cmd = e.metaKey || e.ctrlKey;
                  const k = e.key.toLowerCase();

                  if (cmd && !e.altKey && !e.shiftKey && k === 'b') {
                    e.preventDefault();
                    applyInlineSelectionMark('bold');
                    return;
                  }
                  if (cmd && !e.altKey && !e.shiftKey && k === 'i') {
                    e.preventDefault();
                    applyInlineSelectionMark('italic');
                    return;
                  }
                  if (cmd && !e.altKey && !e.shiftKey && k === 'u') {
                    e.preventDefault();
                    applyInlineSelectionMark('underline');
                    return;
                  }
                  if (cmd && !e.altKey && e.shiftKey && k === 'x') {
                    e.preventDefault();
                    applyInlineSelectionMark('strikethrough');
                    return;
                  }
                  if (cmd && !e.altKey && !e.shiftKey && k === 'e') {
                    e.preventDefault();
                    applyInlineSelectionMark('code');
                    return;
                  }

                  // Block style shortcuts (Ctrl+Alt+0/1/2/3/C/M, Ctrl+Shift+7/8/9/Q)
                  if (cmd && e.altKey && !e.shiftKey) {
                    if (k === '0') {
                      e.preventDefault();
                      handleBlockStyleChange('paragraph');
                      return;
                    }
                    if (k === '1') {
                      e.preventDefault();
                      handleBlockStyleChange('heading-1');
                      return;
                    }
                    if (k === '2') {
                      e.preventDefault();
                      handleBlockStyleChange('heading-2');
                      return;
                    }
                    if (k === '3') {
                      e.preventDefault();
                      handleBlockStyleChange('heading-3');
                      return;
                    }
                    if (k === 'c') {
                      e.preventDefault();
                      handleBlockStyleChange('code');
                      return;
                    }
                    if (k === 'm') {
                      e.preventDefault();
                      handleInsertBlock('math_equation');
                      return;
                    }
                  }

                  if (cmd && e.shiftKey && !e.altKey) {
                    if (e.code === 'Digit8' || k === '8' || k === '*') {
                      e.preventDefault();
                      handleBlockStyleChange('bulleted_list');
                      return;
                    }
                    if (e.code === 'Digit7' || k === '7' || k === '&') {
                      e.preventDefault();
                      handleBlockStyleChange('numbered_list');
                      return;
                    }
                    if (e.code === 'Digit9' || k === '9' || k === '(') {
                      e.preventDefault();
                      handleBlockStyleChange('todo_list');
                      return;
                    }
                    if (k === 'q') {
                      e.preventDefault();
                      handleBlockStyleChange('quote');
                      return;
                    }
                    if (k === 'l') {
                      e.preventDefault();
                      handleAlignChange('left');
                      return;
                    }
                    if (k === 'e') {
                      e.preventDefault();
                      handleAlignChange('center');
                      return;
                    }
                    if (k === 'r') {
                      e.preventDefault();
                      handleAlignChange('right');
                      return;
                    }
                    if (k === 'j') {
                      e.preventDefault();
                      handleAlignChange('justify');
                      return;
                    }
                  }

                  // Ctrl+Enter toggles checklist item
                  if (cmd && e.key === 'Enter') {
                    e.preventDefault();
                    if (node.type === 'todo_list') {
                      updateNode(nodeId, (prev) => ({
                        ...prev,
                        data: {
                          ...prev.data,
                          checked: !Boolean(prev.data?.checked),
                        },
                      }));
                    } else {
                      insertAfter(nodeId, makeParagraphNode(''));
                    }
                    return;
                  }

                  // Alt+ArrowUp / Alt+ArrowDown moves the focused block up or down
                  if (e.altKey && !cmd && e.key === 'ArrowUp') {
                    e.preventDefault();
                    moveBlock(nodeId, -1);
                    return;
                  }
                  if (e.altKey && !cmd && e.key === 'ArrowDown') {
                    e.preventDefault();
                    moveBlock(nodeId, 1);
                    return;
                  }

                  if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    setSlashState(null);
                    const isList =
                      node.type === 'bulleted_list' ||
                      node.type === 'numbered_list' ||
                      node.type === 'todo_list';
                    if (isList && rawMd.trim() === '') {
                      updateNode(nodeId, (prev) => ({
                        ...prev,
                        type: 'paragraph',
                        data: { delta: [] },
                      }));
                      return;
                    }
                    const nextNode = isList
                      ? makeListNode(
                          node.type as
                            | 'bulleted_list'
                            | 'numbered_list'
                            | 'todo_list',
                          '',
                          false,
                        )
                      : makeParagraphNode('');
                    insertAfter(nodeId, nextNode);
                    return;
                  }

                  if (e.key === 'Backspace' && rawMd === '') {
                    e.preventDefault();
                    setSlashState(null);
                    if (node.type !== 'paragraph') {
                      updateNode(nodeId, (prev) => ({
                        ...prev,
                        type: 'paragraph',
                        data: { delta: [] },
                      }));
                    } else if (nodes.length > 1) {
                      deleteNode(nodeId);
                    }
                    return;
                  }

                  if (e.key === 'ArrowUp' && index > 0) {
                    const prev = nodes[index - 1];
                    if (prev?.id && inputRefs.current[prev.id]) {
                      e.preventDefault();
                      setFocusedBlockId(prev.id);
                      inputRefs.current[prev.id]?.focus();
                    }
                  }
                  if (e.key === 'ArrowDown' && index < nodes.length - 1) {
                    const next = nodes[index + 1];
                    if (next?.id && inputRefs.current[next.id]) {
                      e.preventDefault();
                      setFocusedBlockId(next.id);
                      inputRefs.current[next.id]?.focus();
                    }
                  }
                };

                const handlePaste = (
                  e: React.ClipboardEvent<HTMLTextAreaElement>,
                ) => {
                  const items = e.clipboardData?.items;
                  if (items) {
                    for (let i = 0; i < items.length; i++) {
                      const item = items[i];
                      if (item.type.indexOf('image') !== -1) {
                        const file = item.getAsFile();
                        if (file) {
                          e.preventDefault();
                          const reader = new FileReader();
                          reader.onload = async () => {
                            const dataUrl = reader.result as string;
                            try {
                              const saved =
                                await window.mario.asset.savePastedImage(
                                  dataUrl,
                                );
                              const imgNode: AppFlowyNode = {
                                id: nanoid6(),
                                type: 'image',
                                data: {
                                  url: saved.assetPath,
                                  width: 520,
                                  align: 'center',
                                },
                              };
                              insertAfter(nodeId, imgNode);
                            } catch (err) {
                              console.error('Failed to save pasted image', err);
                            }
                          };
                          reader.readAsDataURL(file);
                          return;
                        }
                      }
                    }
                  }

                  const text = e.clipboardData?.getData('text/plain') ?? '';
                  if (
                    text.includes('\n') ||
                    /^(\#{1,6}\s|```|\||\*\s|-\s|\d+\.\s|\$\$|>)/m.test(text)
                  ) {
                    e.preventDefault();
                    const parsed = markdownToNodes(text);
                    if (parsed.length > 0) {
                      const currentNode = nodes[index];
                      const currentText = deltaToMarkdown(
                        currentNode?.data?.delta,
                      );
                      if (!currentText.trim()) {
                        const nextNodes = [...nodes];
                        nextNodes.splice(index, 1, ...parsed);
                        commitNodes(nextNodes);
                        const last = parsed[parsed.length - 1];
                        const lastId = last?.id;
                        if (lastId) {
                          setFocusedBlockId(lastId);
                          setTimeout(
                            () => inputRefs.current[lastId]?.focus(),
                            15,
                          );
                        }
                      } else {
                        const nextNodes = [...nodes];
                        nextNodes.splice(index + 1, 0, ...parsed);
                        commitNodes(nextNodes);
                        const last = parsed[parsed.length - 1];
                        const lastId = last?.id;
                        if (lastId) {
                          setFocusedBlockId(lastId);
                          setTimeout(
                            () => inputRefs.current[lastId]?.focus(),
                            15,
                          );
                        }
                      }
                    }
                  }
                };

                const textInput = (
                  <textarea
                    ref={(el) => {
                      inputRefs.current[nodeId] = el;
                      if (el) {
                        el.style.height = 'auto';
                        el.style.height = `${Math.max(26, el.scrollHeight)}px`;
                      }
                    }}
                    rows={1}
                    className={`mario-editable ${headingClass}`}
                    style={{
                      width: '100%',
                      border: 'none',
                      outline: 'none',
                      background: 'transparent',
                      color: 'inherit',
                      font: 'inherit',
                      resize: 'none',
                      overflow: 'hidden',
                      lineHeight: 1.5,
                      padding: 0,
                      margin: 0,
                      display: 'block',
                      textAlign: align,
                      textDecoration:
                        node.type === 'todo_list' && node.data?.checked
                          ? 'line-through'
                          : undefined,
                      opacity:
                        node.type === 'todo_list' && node.data?.checked
                          ? 0.6
                          : 1,
                    }}
                    value={rawMd}
                    placeholder={
                      index === 0 && nodes.length === 1
                        ? 'Type "/" for commands or start writing…'
                        : ''
                    }
                    spellCheck={spellcheck}
                    onFocus={() => setFocusedBlockId(nodeId)}
                    onChange={(e) => {
                      const el = e.target;
                      el.style.height = 'auto';
                      el.style.height = `${Math.max(26, el.scrollHeight)}px`;
                      handleTextChange(el.value);
                    }}
                    onKeyDown={handleKeyDown}
                    onPaste={handlePaste}
                  />
                );

                return (
                  <div
                    key={nodeId}
                    className={`mario-block-row ${
                      isFocused ? 'mario-block-row--focused' : ''
                    }`}
                    onClick={() => {
                      setFocusedBlockId(nodeId);
                      setTimeout(() => inputRefs.current[nodeId]?.focus(), 0);
                    }}
                  >

                    <div
                      className={`mario-block-body ${
                        node.type === 'quote' ? 'mario-quote-block' : ''
                      }`}
                      style={{ textAlign: align }}
                    >
                      {node.type === 'bulleted_list' ? (
                        <div className="mario-list-row">
                          <span className="mario-list-marker">•</span>
                          <div style={{ flex: 1 }}>
                            {isFocused
                              ? textInput
                              : renderFormattedDeltaPreview(node)}
                          </div>
                        </div>
                      ) : node.type === 'numbered_list' ? (
                        <div className="mario-list-row">
                          <span className="mario-list-marker">
                            {currentNumber}.
                          </span>
                          <div style={{ flex: 1 }}>
                            {isFocused
                              ? textInput
                              : renderFormattedDeltaPreview(node)}
                          </div>
                        </div>
                      ) : node.type === 'todo_list' ? (
                        <div className="mario-list-row">
                          <span
                            style={{ paddingTop: 2 }}
                            onClick={(e) => e.stopPropagation()}
                          >
                            <Checkbox
                              checked={Boolean(node.data?.checked)}
                              onChange={(checked) =>
                                updateNode(nodeId, (prev) => ({
                                  ...prev,
                                  data: {
                                    ...prev.data,
                                    checked,
                                  },
                                }))
                              }
                            />
                          </span>
                          <div style={{ flex: 1 }}>
                            {isFocused
                              ? textInput
                              : renderFormattedDeltaPreview(node)}
                          </div>
                        </div>
                      ) : isFocused ? (
                        textInput
                      ) : (
                        <div className={`mario-editable ${headingClass}`}>
                          {renderFormattedDeltaPreview(node)}
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {htmlPreviewOpen && (
          <div className="mario-html-preview-pane">
            <div className="mario-rich-card__header">
              <span>
                {rawHtmlOverride
                  ? 'Interactive HTML Artifact (AI)'
                  : 'Live HTML Preview'}
              </span>
              <div style={{ display: 'flex', gap: 6 }}>
                {rawHtmlOverride && (
                  <Button
                    size="small"
                    variant="borderless"
                    onClick={onClearHtmlOverride}
                  >
                    Reset Artifact
                  </Button>
                )}
                <Button
                  size="small"
                  variant="borderless"
                  icon="xmark"
                  label="Close HTML Preview"
                  onClick={() => setHtmlPreviewOpen(false)}
                />
              </div>
            </div>
            <iframe
              title="HTML Preview"
              className="mario-html-preview-iframe"
              sandbox="allow-scripts"
              srcDoc={previewHtmlDoc}
            />
          </div>
        )}
      </div>

      {slashState && (
        <div
          className="mac-menu mario-slash-menu"
          style={{ left: slashState.x, top: slashState.y }}
          role="menu"
        >
          <MenuHeader>Insert Block</MenuHeader>
          {SLASH_ITEMS.filter(
            (item) =>
              !slashState.query ||
              item.label.toLowerCase().includes(slashState.query) ||
              item.keywords.includes(slashState.query),
          ).map((item) => (
            <MenuItem
              key={item.kind}
              icon={item.icon}
              shortcut={item.shortcut}
              onSelect={() => handleInsertBlock(item.kind, slashState.blockId)}
            >
              {item.label}
            </MenuItem>
          ))}
        </div>
      )}
    </div>
  );
}
