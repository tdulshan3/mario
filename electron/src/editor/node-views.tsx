import React, { useEffect, useMemo, useRef, useState } from 'react';
import katex from 'katex';
import { NodeViewContent, NodeViewWrapper, useEditorState, type NodeViewProps } from '@tiptap/react';
import { Selection } from '@tiptap/pm/state';
import { Button, PopUpButton, SegmentedControl, Spacer, TextArea, cx } from '../macos/macos';
import {
  colIndexToLabel,
  evaluateSheetCell,
  markdownToNodes,
  normalizeLatexFormula,
  normalizeWorkbook,
} from '../shared/document-codec';
import type { Stroke, WorkbookData } from '../shared/types';
import { DrawingCanvasBlock } from '../components/DrawingCanvasBlock';
import { appflowyToPm } from './pm-codec';
import { WEB_SANDBOX, prepareWebDocument, requestBlockPreview } from './web-page';

/**
 * Blocks that aren't text. They carry no frame of their own: an equation is
 * just the equation, an image just the image. Selecting one (click, or arrow
 * onto it) draws the focus ring and floats its commands above it on a menu
 * material, the way Pages and Freeform show an object's controls.
 */

type Data = Record<string, unknown>;

function indentStyle(indent: unknown): React.CSSProperties | undefined {
  const n = Number(indent ?? 0);
  return n > 0 ? ({ '--indent': n } as React.CSSProperties) : undefined;
}

/** The selected/active frame plus the floating command bar. */
function BlockFrame({
  selected,
  kind,
  indent,
  bar,
  barLabel,
  interactive = false,
  children,
}: {
  selected: boolean;
  kind: string;
  indent?: unknown;
  bar?: React.ReactNode;
  barLabel: string;
  /** The body takes its own pointer and key events (inputs, a canvas, players). */
  interactive?: boolean;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(false);
  useEffect(() => {
    if (!active) return;
    const onDown = (e: PointerEvent) => {
      if (!ref.current?.contains(e.target as Node)) setActive(false);
    };
    document.addEventListener('pointerdown', onDown, true);
    return () => document.removeEventListener('pointerdown', onDown, true);
  }, [active]);
  return (
    <NodeViewWrapper
      ref={ref}
      className={cx('mario-block', `mario-block--${kind}`, selected && 'is-selected', (selected || active) && 'is-active')}
      style={indentStyle(indent)}
      data-indent={Number(indent ?? 0) || undefined}
      onPointerDown={() => setActive(true)}
    >
      {bar && (
        <div className="mario-block-bar" contentEditable={false} role="toolbar" aria-label={barLabel}>
          {bar}
        </div>
      )}
      <div className="mario-block__body" data-interactive={interactive ? '' : undefined}>
        {children}
      </div>
    </NodeViewWrapper>
  );
}

/** Lets Enter on a selected block (see MarioKeys) open it for editing. */
function useEditRequest(onEdit: () => void) {
  const ref = useRef<HTMLDivElement | null>(null);
  const cb = useRef(onEdit);
  cb.current = onEdit;
  useEffect(() => {
    const host = ref.current?.closest('[data-node-view-wrapper]');
    if (!host) return;
    const handler = () => cb.current();
    host.addEventListener('mario-edit-block', handler);
    return () => host.removeEventListener('mario-edit-block', handler);
  }, []);
  return ref;
}

// ── Code ────────────────────────────────────────────────────────────────────

export const CODE_LANGUAGES = [
  'plaintext',
  'python',
  'javascript',
  'typescript',
  'bash',
  'json',
  'html',
  'css',
  'sql',
  'go',
  'rust',
  'java',
  'c',
  'cpp',
  'csharp',
  'dart',
  'kotlin',
  'swift',
  'ruby',
  'php',
  'yaml',
  'markdown',
];

export function CodeBlockView({ node, updateAttributes, editor, getPos }: NodeViewProps) {
  const lang = String(node.attrs.language || 'plaintext');
  const caretInside = useEditorState({
    editor,
    selector: ({ editor: e }) => {
      const pos = typeof getPos === 'function' ? getPos() : undefined;
      if (typeof pos !== 'number' || !e) return false;
      const { from, to } = e.state.selection;
      return from > pos && to < pos + node.nodeSize;
    },
  });
  const options = CODE_LANGUAGES.includes(lang) ? CODE_LANGUAGES : [lang, ...CODE_LANGUAGES];
  return (
    <NodeViewWrapper
      className={cx('mario-code', caretInside && 'is-active')}
      style={indentStyle(node.attrs.indent)}
      data-indent={Number(node.attrs.indent ?? 0) || undefined}
    >
      <div className="mario-code__bar" contentEditable={false}>
        {caretInside ? (
          <>
            <PopUpButton
              size="small"
              aria-label="Language"
              value={lang}
              onChange={(v) => updateAttributes({ language: v })}
              options={options.map((l) => ({ value: l, label: l === 'plaintext' ? 'Plain Text' : l }))}
            />
            <Spacer />
            {['html', 'htm', 'xhtml', 'svg'].includes(lang.toLowerCase()) && node.attrs.id && (
              <Button
                size="small"
                variant="borderless"
                icon="play"
                label="Preview as Web Page"
                onClick={() => requestBlockPreview(String(node.attrs.id))}
              />
            )}
            <Button
              size="small"
              variant="borderless"
              icon="doc-on-doc"
              label="Copy Code"
              onClick={() => void navigator.clipboard?.writeText(node.textContent)}
            />
          </>
        ) : (
          <span className="mario-code__lang">{lang === 'plaintext' ? '' : lang}</span>
        )}
      </div>
      <pre spellCheck={false}>
        <NodeViewContent<'code'> as="code" className={`hljs language-${lang}`} />
      </pre>
    </NodeViewWrapper>
  );
}

// ── Equation ────────────────────────────────────────────────────────────────

export function MathBlockView({ node, updateAttributes, selected, editor, getPos, deleteNode }: NodeViewProps) {
  const formula = String(node.attrs.formula ?? '');
  const [editing, setEditing] = useState(false);
  const ref = useEditRequest(() => setEditing(true));
  // A new, empty equation opens for typing as soon as it is selected.
  useEffect(() => {
    if (selected && !formula) setEditing(true);
  }, [selected, formula]);
  const html = useMemo(
    () =>
      katex.renderToString(normalizeLatexFormula(formula || '\\text{New equation}'), {
        displayMode: true,
        throwOnError: false,
      }),
    [formula],
  );
  const finish = () => {
    setEditing(false);
    const pos = typeof getPos === 'function' ? getPos() : undefined;
    if (typeof pos !== 'number') return;
    // The caret goes to the start of whatever follows the equation.
    const { state, view } = editor;
    view.dispatch(state.tr.setSelection(Selection.near(state.doc.resolve(pos + node.nodeSize), 1)));
    view.focus();
  };
  return (
    <BlockFrame
      selected={selected || editing}
      kind="math"
      indent={node.attrs.indent}
      barLabel="Equation"
      bar={
        <>
          <Button size="small" variant="borderless" icon="pencil" onClick={() => (editing ? finish() : setEditing(true))}>
            {editing ? 'Done' : 'Edit'}
          </Button>
          <Button size="small" variant="borderless" icon="trash" label="Delete Equation" onClick={deleteNode} />
        </>
      }
    >
      <div ref={ref}>
        <div
          className={cx('mario-math__render', !formula && 'mac-label-tertiary')}
          onDoubleClick={() => setEditing(true)}
          dangerouslySetInnerHTML={{ __html: html }}
        />
        {editing && (
          <div className="mario-math__source" contentEditable={false} data-interactive="">
            <TextArea
              className="mac-text-mono"
              aria-label="LaTeX"
              rows={Math.min(8, Math.max(2, formula.split('\n').length))}
              value={formula}
              autoFocus
              placeholder="\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}"
              onChange={(v) => updateAttributes({ formula: v })}
              onKeyDown={(e) => {
                if ((e.key === 'Enter' && !e.shiftKey) || e.key === 'Escape') {
                  e.preventDefault();
                  finish();
                }
              }}
            />
          </div>
        )}
      </div>
    </BlockFrame>
  );
}

// ── Embeds: image, HTML, audio, spreadsheet, drawing ────────────────────────

interface EmbedProps {
  blockId: string | null;
  data: Data;
  setData: (next: Data) => void;
  remove: () => void;
  selected: boolean;
  indent: unknown;
  insertMarkdownAfter: (md: string) => void;
}

export function EmbedView({ node, updateAttributes, deleteNode, selected, editor, getPos }: NodeViewProps) {
  const kind = String(node.attrs.kind);
  const data = (node.attrs.data ?? {}) as Data;
  const props: EmbedProps = {
    blockId: (node.attrs.id as string | null) ?? null,
    data,
    setData: (next) => updateAttributes({ data: next }),
    remove: deleteNode,
    selected,
    indent: node.attrs.indent,
    insertMarkdownAfter: (md) => {
      const pos = typeof getPos === 'function' ? getPos() : undefined;
      if (typeof pos !== 'number') return;
      const blocks = appflowyToPm({ type: 'page', children: markdownToNodes(md) }).content ?? [];
      editor.chain().focus().insertContentAt(pos + node.nodeSize, blocks).run();
    },
  };
  switch (kind) {
    case 'image':
      return <ImageEmbed {...props} />;
    case 'html':
    case 'html_preview':
      return <HtmlEmbed {...props} />;
    case 'audio_clip':
      return <AudioEmbed {...props} />;
    case 'spreadsheet':
      return <SpreadsheetEmbed {...props} />;
    case 'drawing':
      return (
        <BlockFrame selected={selected} kind="drawing" indent={props.indent} barLabel="Drawing" interactive>
          <DrawingCanvasBlock
            strokes={Array.isArray(data.strokes) ? (data.strokes as Stroke[]) : []}
            height={Number(data.height ?? 220)}
            onChange={(strokes, height) => props.setData({ ...data, strokes, height: height ?? data.height })}
            onDelete={deleteNode}
          />
        </BlockFrame>
      );
    default:
      return (
        <BlockFrame
          selected={selected}
          kind="unsupported"
          indent={props.indent}
          barLabel="Block"
          bar={<Button size="small" variant="borderless" icon="trash" label="Delete Block" onClick={deleteNode} />}
        >
          <p className="mario-embed-note">
            <span className="mac-icon mac-icon-square-dashed" aria-hidden="true" /> A “{kind}” block from another
            version of Mario. It is kept as it is.
          </p>
        </BlockFrame>
      );
  }
}

function ImageEmbed({ data, setData, remove, selected, indent, insertMarkdownAfter }: EmbedProps) {
  const url = String(data.url ?? '');
  const driveId = String(data.drive_id ?? '');
  const width = Number(data.width ?? 520);
  const align = data.align === 'left' || data.align === 'right' ? data.align : 'center';
  const [src, setSrc] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const [ocr, setOcr] = useState<'idle' | 'running'>('idle');
  const [status, setStatus] = useState<string | null>(null);
  const [dragWidth, setDragWidth] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    setFailed(false);
    window.mario.asset
      .resolveImage(url || undefined, driveId || undefined)
      .then((res) => {
        if (!cancelled) {
          setSrc(res);
          setFailed(!res);
        }
      })
      .catch(() => {
        if (!cancelled) setFailed(true);
      });
    return () => {
      cancelled = true;
    };
  }, [url, driveId]);

  const runOcr = async () => {
    if (!src) return;
    setOcr('running');
    setStatus('Reading text with MinerU…');
    try {
      const res = await window.mario.ocr.runMinerU(src);
      if (res.success && res.markdown) {
        insertMarkdownAfter(res.markdown);
        setStatus(null);
      } else setStatus(res.error || 'MinerU found no text in this image.');
    } catch (err) {
      setStatus(err instanceof Error ? err.message : String(err));
    } finally {
      setOcr('idle');
    }
  };

  const startResize = (e: React.PointerEvent) => {
    e.preventDefault();
    e.stopPropagation();
    const startX = e.clientX;
    const startW = width;
    const target = e.currentTarget as HTMLElement;
    target.setPointerCapture(e.pointerId);
    let last = startW;
    const move = (ev: PointerEvent) => {
      last = Math.round(Math.max(120, Math.min(1200, startW + (ev.clientX - startX) * (align === 'center' ? 2 : 1))));
      setDragWidth(last);
    };
    const up = () => {
      target.removeEventListener('pointermove', move);
      target.removeEventListener('pointerup', up);
      setDragWidth(null);
      setData({ ...data, width: last });
    };
    target.addEventListener('pointermove', move);
    target.addEventListener('pointerup', up);
  };

  const shownWidth = dragWidth ?? width;
  return (
    <BlockFrame
      selected={selected}
      kind="image"
      indent={indent}
      barLabel="Image"
      bar={
        <>
          <PopUpButton
            size="small"
            aria-label="Image Alignment"
            value={align}
            onChange={(v) => setData({ ...data, align: v })}
            options={[
              { value: 'left', label: 'Align Left' },
              { value: 'center', label: 'Center' },
              { value: 'right', label: 'Align Right' },
            ]}
          />
          <Button size="small" variant="borderless" icon="doc-text" disabled={!src || ocr === 'running'} onClick={runOcr}>
            {ocr === 'running' ? 'Reading…' : 'Copy Text (OCR)'}
          </Button>
          <Button size="small" variant="borderless" icon="trash" label="Delete Image" onClick={remove} />
        </>
      }
    >
      <div className="mario-image" style={{ textAlign: align }}>
        {src ? (
          <span className="mario-image__frame" style={{ width: shownWidth }}>
            <img src={src} alt="" draggable={false} />
            {selected && (
              <span
                className="mario-image__handle"
                role="separator"
                aria-label="Resize Image"
                contentEditable={false}
                onPointerDown={startResize}
              />
            )}
          </span>
        ) : (
          <span className="mario-embed-note">
            <span className="mac-icon mac-icon-photo" aria-hidden="true" />{' '}
            {failed ? 'This image isn’t available offline.' : 'Loading image…'}
          </span>
        )}
      </div>
      {status && <p className="mario-embed-status">{status}</p>}
    </BlockFrame>
  );
}

function HtmlEmbed({ blockId, data, setData, remove, selected, indent }: EmbedProps) {
  const html = String(data.html ?? '');
  const [editing, setEditing] = useState(html.trim() === '');
  const [height, setHeight] = useState(160);
  const frameRef = useRef<HTMLIFrameElement>(null);
  const ref = useEditRequest(() => setEditing(true));
  const srcDoc = useMemo(() => prepareWebDocument({ html: [html] }, { reportHeight: true }), [html]);

  // The page inside reports its height, so the block shows all of it.
  useEffect(() => {
    const onMessage = (e: MessageEvent) => {
      if (e.source !== frameRef.current?.contentWindow) return;
      const h = Number((e.data as { marioFrameHeight?: unknown })?.marioFrameHeight);
      if (Number.isFinite(h)) setHeight(Math.max(60, Math.min(900, h)));
    };
    window.addEventListener('message', onMessage);
    return () => window.removeEventListener('message', onMessage);
  }, []);

  return (
    <BlockFrame
      selected={selected || editing}
      kind="html"
      indent={indent}
      barLabel="HTML"
      interactive
      bar={
        <>
          <Button size="small" variant="borderless" icon={editing ? 'eye' : 'pencil'} onClick={() => setEditing(!editing)}>
            {editing ? 'Show Page' : 'Edit HTML'}
          </Button>
          {blockId && (
            <Button
              size="small"
              variant="borderless"
              icon="play"
              label="Preview Full Size"
              onClick={() => requestBlockPreview(blockId)}
            />
          )}
          <Button size="small" variant="borderless" icon="trash" label="Delete HTML Block" onClick={remove} />
        </>
      }
    >
      <div ref={ref}>
        {editing ? (
          <TextArea
            className="mac-text-mono mario-html__source"
            aria-label="HTML"
            rows={Math.min(16, Math.max(5, html.split('\n').length))}
            value={html}
            spellCheck={false}
            placeholder="<div>HTML, an SVG chart or an embed…</div>"
            onChange={(v) => setData({ ...data, html: v })}
          />
        ) : (
          <iframe
            ref={frameRef}
            title="HTML Block"
            className="mario-html__frame"
            style={{ height }}
            srcDoc={srcDoc}
            sandbox={WEB_SANDBOX}
          />
        )}
      </div>
    </BlockFrame>
  );
}

function AudioEmbed({ data, setData, remove, selected, indent }: EmbedProps) {
  const [recording, setRecording] = useState(false);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const startedAt = useRef(0);
  const src = String(data.dataUrl ?? data.path ?? '');
  const seconds = Number(data.durationMs ?? 0) / 1000;

  const start = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const rec = new MediaRecorder(stream);
      chunksRef.current = [];
      rec.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data);
      };
      rec.onstop = () => {
        stream.getTracks().forEach((t) => t.stop());
        const elapsed = Date.now() - startedAt.current;
        const reader = new FileReader();
        reader.onloadend = () => setData({ ...data, dataUrl: String(reader.result ?? ''), durationMs: elapsed });
        reader.readAsDataURL(new Blob(chunksRef.current, { type: 'audio/webm' }));
      };
      startedAt.current = Date.now();
      recorderRef.current = rec;
      rec.start();
      setRecording(true);
    } catch {
      setRecording(false);
    }
  };
  const stop = () => {
    recorderRef.current?.stop();
    setRecording(false);
  };

  return (
    <BlockFrame
      selected={selected}
      kind="audio"
      indent={indent}
      barLabel="Audio"
      interactive
      bar={<Button size="small" variant="borderless" icon="trash" label="Delete Audio Clip" onClick={remove} />}
    >
      <div className="mario-audio">
        {recording ? (
          <Button size="small" variant="destructive" icon="stop" onClick={stop}>
            Stop
          </Button>
        ) : (
          <Button size="small" icon="mic" onClick={start}>
            {src ? 'Re-record' : 'Record'}
          </Button>
        )}
        {src ? (
          <audio controls src={src} className="mario-audio__player" />
        ) : (
          <span className="mario-embed-note">{recording ? 'Recording from the microphone…' : 'No recording yet.'}</span>
        )}
        {seconds > 0 && <span className="mario-embed-note">{seconds.toFixed(1)} s</span>}
      </div>
    </BlockFrame>
  );
}

function SpreadsheetEmbed({ data, setData, remove, selected, indent }: EmbedProps) {
  const workbook: WorkbookData = useMemo(() => normalizeWorkbook(data), [data]);
  const [editingCell, setEditingCell] = useState<string | null>(null);
  const active = Math.min(Math.max(0, workbook.activeIndex || 0), workbook.sheets.length - 1);
  const sheet = workbook.sheets[active] ?? { name: 'Sheet1', rows: 5, cols: 4, cells: {} };

  const commit = (next: WorkbookData) => {
    const { data: _legacy, ...rest } = data;
    setData({ ...rest, workbook: next });
  };
  const updateSheet = (patch: Partial<typeof sheet>) =>
    commit({ ...workbook, sheets: workbook.sheets.map((s, i) => (i === active ? { ...s, ...patch } : s)) });
  const setCell = (ref: string, value: string) => {
    const cells = { ...sheet.cells };
    if (value) cells[ref] = value;
    else delete cells[ref];
    updateSheet({ cells });
  };

  return (
    <BlockFrame
      selected={selected}
      kind="sheet"
      indent={indent}
      barLabel="Spreadsheet"
      interactive
      bar={
        <>
          <Button size="small" variant="borderless" icon="plus" onClick={() => updateSheet({ rows: sheet.rows + 1 })}>
            Row
          </Button>
          <Button
            size="small"
            variant="borderless"
            icon="plus"
            onClick={() => updateSheet({ cols: Math.min(26, sheet.cols + 1) })}
          >
            Column
          </Button>
          <Button size="small" variant="borderless" icon="trash" label="Delete Spreadsheet" onClick={remove} />
        </>
      }
    >
      <div className="mario-sheet">
        <div className="mario-sheet__scroll">
          <table className="mario-grid">
            <thead>
              <tr>
                <th className="mario-grid__corner" />
                {Array.from({ length: sheet.cols }, (_, c) => (
                  <th key={c}>{colIndexToLabel(c)}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {Array.from({ length: sheet.rows }, (_, r) => (
                <tr key={r}>
                  <th>{r + 1}</th>
                  {Array.from({ length: sheet.cols }, (__, c) => {
                    const ref = `${colIndexToLabel(c)}${r + 1}`;
                    const raw = sheet.cells[ref] ?? '';
                    const shown = editingCell === ref ? raw : evaluateSheetCell(sheet, ref);
                    return (
                      <td key={c}>
                        <input
                          className="mario-grid__cell"
                          aria-label={ref}
                          value={shown}
                          onFocus={() => setEditingCell(ref)}
                          onBlur={() => setEditingCell(null)}
                          onChange={(e) => setCell(ref, e.target.value)}
                        />
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="mario-sheet__tabs">
          <SegmentedControl
            size="small"
            label="Sheets"
            value={String(active)}
            onChange={(v) => commit({ ...workbook, activeIndex: Number(v) })}
            options={workbook.sheets.map((s, i) => ({ value: String(i), label: s.name }))}
          />
          <Button
            size="small"
            variant="borderless"
            icon="plus"
            label="New Sheet"
            onClick={() =>
              commit({
                activeIndex: workbook.sheets.length,
                sheets: [...workbook.sheets, { name: `Sheet${workbook.sheets.length + 1}`, rows: 5, cols: 4, cells: {} }],
              })
            }
          />
        </div>
      </div>
    </BlockFrame>
  );
}
