import React from 'react';
import type { Editor } from '@tiptap/react';
import {
  Button,
  MenuHeader,
  MenuItem,
  MenuSeparator,
  PopUpButton,
  PullDownButton,
  SegmentedControl,
  Spacer,
} from '../macos/macos';
import { setBlockAlign, setBlockStyle, toggleListStyle, changeIndent, type BlockStyle } from './extensions';

/**
 * The format bar under the toolbar, organised like OneNote's ribbon (Home,
 * Insert, Draw, View, and Table while the caret is in a table) and drawn the
 * way TextEdit draws its format bar: small pop-ups and toggle buttons whose
 * pressed state follows the selection.
 */

export type InsertKind =
  | 'table'
  | 'image'
  | 'math_block'
  | 'inline_math'
  | 'code'
  | 'divider'
  | 'todo'
  | 'quote'
  | 'spreadsheet'
  | 'drawing'
  | 'audio'
  | 'html'
  | 'datetime'
  | 'link';

export interface RibbonState {
  bold: boolean;
  italic: boolean;
  underline: boolean;
  strike: boolean;
  code: boolean;
  link: boolean;
  blockStyle: string;
  align: 'left' | 'center' | 'right';
  inTable: boolean;
  canUndo: boolean;
  canRedo: boolean;
}

export const TEXT_COLORS = [
  { label: 'Automatic', value: '' },
  { label: 'Blue', value: '#007aff' },
  { label: 'Purple', value: '#af52de' },
  { label: 'Pink', value: '#ff2d55' },
  { label: 'Red', value: '#ff3b30' },
  { label: 'Orange', value: '#ff9500' },
  { label: 'Yellow', value: '#ffcc00' },
  { label: 'Green', value: '#34c759' },
  { label: 'Teal', value: '#5ac8fa' },
  { label: 'Gray', value: '#8e8e93' },
];

export const HIGHLIGHT_COLORS = [
  { label: 'No Highlight', value: '' },
  { label: 'Yellow', value: 'rgba(255, 214, 10, 0.4)' },
  { label: 'Green', value: 'rgba(50, 215, 75, 0.32)' },
  { label: 'Blue', value: 'rgba(10, 132, 255, 0.3)' },
  { label: 'Pink', value: 'rgba(255, 55, 95, 0.3)' },
  { label: 'Purple', value: 'rgba(191, 90, 242, 0.3)' },
  { label: 'Orange', value: 'rgba(255, 159, 10, 0.32)' },
];

export const STYLE_OPTIONS: Array<{ value: BlockStyle; label: string; shortcut?: string; headerAbove?: string; separatorAbove?: boolean }> = [
  { value: 'paragraph', label: 'Body', shortcut: '⌃⌥0', headerAbove: 'Styles' },
  { value: 'heading-1', label: 'Heading 1', shortcut: '⌃⌥1' },
  { value: 'heading-2', label: 'Heading 2', shortcut: '⌃⌥2' },
  { value: 'heading-3', label: 'Heading 3', shortcut: '⌃⌥3' },
  { value: 'heading-4', label: 'Heading 4', shortcut: '⌃⌥4' },
  { value: 'bulleted_list', label: 'Bulleted List', shortcut: '⇧⌃8', separatorAbove: true },
  { value: 'numbered_list', label: 'Numbered List', shortcut: '⇧⌃7' },
  { value: 'todo_list', label: 'To Do', shortcut: '⌃1' },
  { value: 'quote', label: 'Quote', shortcut: '⇧⌃Q' },
  { value: 'code', label: 'Code', shortcut: '⌃⌥C' },
];

const ZOOM_PRESETS = [50, 75, 90, 100, 110, 125, 150, 175, 200];

export interface RibbonProps {
  editor: Editor;
  state: RibbonState;
  fontFamily: string;
  onFontFamilyChange: (font: string) => void;
  fontSize: number;
  onFontSizeChange: (size: number) => void;
  zoom: number;
  onZoomChange: (zoom: number) => void;
  drawMode: boolean;
  onToggleDrawMode: () => void;
  hasInk: boolean;
  onClearInk: () => void;
  htmlPreviewOpen: boolean;
  onToggleHtmlPreview: () => void;
  hasHtmlArtifact: boolean;
  saveStatus: 'saved' | 'saving' | 'dirty';
  wordCount: number;
  onInsert: (kind: InsertKind) => void;
  onOcrDocument: () => void;
  onExportMarkdown: () => void;
  onExportPdf: () => void;
  onOpenShare: () => void;
}

type Tab = 'home' | 'insert' | 'draw' | 'view' | 'table';

export function Ribbon(props: RibbonProps) {
  const { editor, state } = props;
  const [tab, setTab] = React.useState<Tab>('home');
  const shownTab: Tab = tab === 'table' && !state.inTable ? 'home' : tab;
  const tabs = [
    { value: 'home', label: 'Home' },
    { value: 'insert', label: 'Insert' },
    { value: 'draw', label: 'Draw' },
    { value: 'view', label: 'View' },
    ...(state.inTable ? [{ value: 'table', label: 'Table' }] : []),
  ];
  const run = (fn: (chain: ReturnType<Editor['chain']>) => ReturnType<Editor['chain']>) => fn(editor.chain().focus()).run();

  return (
    <div className="mario-ribbon mac-size-small" role="toolbar" aria-label="Format">
      <div className="mario-ribbon__tabs">
        <SegmentedControl
          size="small"
          label="Ribbon"
          value={shownTab}
          onChange={(v) => setTab(v as Tab)}
          options={tabs}
        />
        <Spacer />
        <span className="mario-ribbon__status" aria-live="polite">
          {props.saveStatus === 'saving' ? 'Saving…' : props.saveStatus === 'dirty' ? 'Edited' : 'Saved'}
        </span>
        <PullDownButton size="small" label="Export">
          <MenuItem icon="doc-text" shortcut="⇧⌃M" onSelect={props.onExportMarkdown}>
            Markdown…
          </MenuItem>
          <MenuItem icon="printer" shortcut="⌃P" onSelect={props.onExportPdf}>
            PDF…
          </MenuItem>
        </PullDownButton>
        <Button size="small" icon="person-2" label="Share Notebook" onClick={props.onOpenShare} />
      </div>
      <div className="mario-ribbon__commands">
        {shownTab === 'home' && <HomeTab {...props} run={run} />}
        {shownTab === 'insert' && <InsertTab {...props} />}
        {shownTab === 'draw' && (
          <>
            <Button size="small" icon="pencil-tip-circle" pressed={props.drawMode} onClick={props.onToggleDrawMode}>
              Draw on Page
            </Button>
            <Button size="small" icon="plus-square" onClick={() => props.onInsert('drawing')}>
              Drawing Canvas
            </Button>
            <Button size="small" icon="trash" disabled={!props.hasInk} onClick={props.onClearInk}>
              Clear Page Ink
            </Button>
          </>
        )}
        {shownTab === 'view' && (
          <>
            <PopUpButton
              size="small"
              aria-label="Zoom"
              value={String(Math.round(props.zoom * 100))}
              onChange={(v) => props.onZoomChange(Number(v) / 100)}
              options={ZOOM_PRESETS.map((p, i) => ({
                value: String(p),
                label: `${p}%`,
                headerAbove: i === 0 ? 'Zoom' : undefined,
              }))}
            />
            <Button
              size="small"
              icon="globe"
              pressed={props.htmlPreviewOpen}
              variant={props.hasHtmlArtifact && !props.htmlPreviewOpen ? 'tinted' : 'bordered'}
              onClick={props.onToggleHtmlPreview}
            >
              Preview
            </Button>
            <span className="mario-ribbon__status">{props.wordCount.toLocaleString()} words</span>
          </>
        )}
        {shownTab === 'table' && <TableTab editor={editor} />}
      </div>
    </div>
  );
}

function HomeTab({
  editor,
  state,
  fontFamily,
  onFontFamilyChange,
  fontSize,
  onFontSizeChange,
  onInsert,
  run,
}: RibbonProps & { run: (fn: (c: ReturnType<Editor['chain']>) => ReturnType<Editor['chain']>) => boolean }) {
  const styleValue = STYLE_OPTIONS.some((o) => o.value === state.blockStyle) ? state.blockStyle : 'paragraph';
  return (
    <>
      <Button size="small" icon="arrow-uturn-left" label="Undo (⌃Z)" disabled={!state.canUndo} onClick={() => run((c) => c.undo())} />
      <Button size="small" icon="arrow-uturn-right" label="Redo (⇧⌃Z)" disabled={!state.canRedo} onClick={() => run((c) => c.redo())} />
      <span className="mario-ribbon__sep" />
      <PopUpButton
        size="small"
        aria-label="Paragraph Style"
        value={styleValue}
        onChange={(v) => {
          setBlockStyle(editor, v as BlockStyle);
          editor.commands.focus();
        }}
        options={STYLE_OPTIONS}
      />
      <PopUpButton
        size="small"
        aria-label="Font"
        value={fontFamily}
        onChange={onFontFamilyChange}
        options={[
          { value: 'System', label: 'System', headerAbove: 'Font' },
          { value: 'Inter', label: 'Inter' },
          { value: 'Serif', label: 'Georgia' },
          { value: 'Monospace', label: 'SF Mono' },
        ]}
      />
      <PopUpButton
        size="small"
        aria-label="Text Size"
        value={String(fontSize)}
        onChange={(v) => onFontSizeChange(Number(v) || 14)}
        options={['11', '12', '13', '14', '15', '16', '18', '20', '24'].map((s, i) => ({
          value: s,
          label: `${s} pt`,
          headerAbove: i === 0 ? 'Text Size' : undefined,
        }))}
      />
      <span className="mario-ribbon__sep" />
      <Button size="small" label="Bold (⌃B)" pressed={state.bold} onClick={() => run((c) => c.toggleBold())}>
        <strong>B</strong>
      </Button>
      <Button size="small" label="Italic (⌃I)" pressed={state.italic} onClick={() => run((c) => c.toggleItalic())}>
        <em>I</em>
      </Button>
      <Button size="small" label="Underline (⌃U)" pressed={state.underline} onClick={() => run((c) => c.toggleUnderline())}>
        <u>U</u>
      </Button>
      <Button size="small" label="Strikethrough (⇧⌃X)" pressed={state.strike} onClick={() => run((c) => c.toggleStrike())}>
        <s>S</s>
      </Button>
      <Button size="small" label="Inline Code (⌃E)" pressed={state.code} onClick={() => run((c) => c.toggleCode())}>
        {'</>'}
      </Button>
      <Button
        size="small"
        icon="eyedropper"
        label="Text Color and Highlight"
        popover={
          <div className="mario-swatches">
            <p className="mac-text-subheadline mac-label-secondary">Text Color</p>
            <div className="mario-swatches__grid">
              {TEXT_COLORS.map((c) => (
                <button
                  key={c.label}
                  type="button"
                  title={c.label}
                  aria-label={c.label}
                  className="mario-swatch"
                  style={{ background: c.value || 'var(--mac-label-primary)' }}
                  onClick={() => run((ch) => (c.value ? ch.setColor(c.value) : ch.unsetColor()))}
                />
              ))}
            </div>
            <p className="mac-text-subheadline mac-label-secondary">Highlight</p>
            <div className="mario-swatches__grid">
              {HIGHLIGHT_COLORS.map((c) => (
                <button
                  key={c.label}
                  type="button"
                  title={c.label}
                  aria-label={c.label}
                  className={`mario-swatch${c.value ? '' : ' mario-swatch--none'}`}
                  style={{ background: c.value || undefined }}
                  onClick={() => run((ch) => (c.value ? ch.setHighlight({ color: c.value }) : ch.unsetHighlight()))}
                />
              ))}
            </div>
          </div>
        }
      />
      <Button size="small" icon="xmark" label="Clear Formatting (⇧⌃N)" onClick={() => run((c) => c.unsetAllMarks())} />
      <span className="mario-ribbon__sep" />
      <Button
        size="small"
        icon="list-bullet"
        label="Bullets (⌃.)"
        pressed={state.blockStyle === 'bulleted_list'}
        onClick={() => toggleListStyle(editor, 'bulleted_list') && editor.commands.focus()}
      />
      <Button
        size="small"
        label="Numbering (⌃/)"
        pressed={state.blockStyle === 'numbered_list'}
        onClick={() => toggleListStyle(editor, 'numbered_list') && editor.commands.focus()}
      >
        1.
      </Button>
      <Button
        size="small"
        icon="checkmark"
        label="To Do (⌃1)"
        pressed={state.blockStyle === 'todo_list'}
        onClick={() => toggleListStyle(editor, 'todo_list') && editor.commands.focus()}
      />
      <Button size="small" icon="arrow-left" label="Decrease Indent (⇧Tab)" onClick={() => changeIndent(editor, -1) && editor.commands.focus()} />
      <Button size="small" icon="arrow-right" label="Increase Indent (Tab)" onClick={() => changeIndent(editor, 1) && editor.commands.focus()} />
      <PopUpButton
        size="small"
        aria-label="Alignment"
        value={state.align}
        onChange={(v) => {
          setBlockAlign(editor, v as 'left' | 'center' | 'right');
          editor.commands.focus();
        }}
        options={[
          { value: 'left', label: 'Align Left', shortcut: '⇧⌃L', headerAbove: 'Alignment' },
          { value: 'center', label: 'Center', shortcut: '⇧⌃E' },
          { value: 'right', label: 'Align Right', shortcut: '⇧⌃R' },
        ]}
      />
      <Button size="small" icon="link" label="Link (⇧⌃K)" pressed={state.link} onClick={() => onInsert('link')} />
    </>
  );
}

function InsertTab({ onInsert, onOcrDocument }: RibbonProps) {
  return (
    <>
      <Button size="small" icon="square-grid" onClick={() => onInsert('table')}>
        Table
      </Button>
      <Button size="small" icon="photo" onClick={() => onInsert('image')}>
        Picture…
      </Button>
      <Button size="small" icon="link" onClick={() => onInsert('link')}>
        Link…
      </Button>
      <Button size="small" icon="command" onClick={() => onInsert('math_block')}>
        Equation
      </Button>
      <Button size="small" icon="cpu" onClick={() => onInsert('code')}>
        Code
      </Button>
      <Button size="small" icon="calendar" onClick={() => onInsert('datetime')}>
        Date &amp; Time
      </Button>
      <Button size="small" icon="minus" onClick={() => onInsert('divider')}>
        Divider
      </Button>
      <PullDownButton size="small" label="More">
        <MenuHeader>Insert</MenuHeader>
        <MenuItem icon="command" onSelect={() => onInsert('inline_math')}>
          Inline Equation
        </MenuItem>
        <MenuItem icon="chart-bar" onSelect={() => onInsert('spreadsheet')}>
          Spreadsheet
        </MenuItem>
        <MenuItem icon="pencil-tip-circle" onSelect={() => onInsert('drawing')}>
          Drawing Canvas
        </MenuItem>
        <MenuItem icon="mic" onSelect={() => onInsert('audio')}>
          Audio Recording
        </MenuItem>
        <MenuItem icon="globe" onSelect={() => onInsert('html')}>
          HTML Block
        </MenuItem>
        <MenuSeparator />
        <MenuItem icon="doc-text" onSelect={onOcrDocument}>
          Text from Image or PDF (MinerU)…
        </MenuItem>
      </PullDownButton>
    </>
  );
}

function TableTab({ editor }: { editor: Editor }) {
  const run = (fn: (c: ReturnType<Editor['chain']>) => ReturnType<Editor['chain']>) => fn(editor.chain().focus()).run();
  return (
    <>
      <PullDownButton size="small" label="Insert">
        <MenuItem onSelect={() => run((c) => c.addRowBefore())}>Row Above</MenuItem>
        <MenuItem onSelect={() => run((c) => c.addRowAfter())}>Row Below</MenuItem>
        <MenuSeparator />
        <MenuItem onSelect={() => run((c) => c.addColumnBefore())}>Column Left</MenuItem>
        <MenuItem onSelect={() => run((c) => c.addColumnAfter())}>Column Right</MenuItem>
      </PullDownButton>
      <PullDownButton size="small" label="Delete">
        <MenuItem onSelect={() => run((c) => c.deleteRow())}>Row</MenuItem>
        <MenuItem onSelect={() => run((c) => c.deleteColumn())}>Column</MenuItem>
        <MenuSeparator />
        <MenuItem icon="trash" onSelect={() => run((c) => c.deleteTable())}>
          Table
        </MenuItem>
      </PullDownButton>
      <Button size="small" icon="plus" onClick={() => run((c) => c.addRowAfter())}>
        Row
      </Button>
      <Button size="small" icon="plus" onClick={() => run((c) => c.addColumnAfter())}>
        Column
      </Button>
    </>
  );
}
