import React from 'react';
import {
  Button,
  MenuHeader,
  MenuItem,
  MenuSeparator,
  PopUpButton,
  PullDownButton,
  Spacer,
} from '../macos/macos';
import type { BlockAlign } from '../shared/types';

export type InsertBlockKind =
  | 'paragraph'
  | 'heading1'
  | 'heading2'
  | 'heading3'
  | 'bulleted_list'
  | 'numbered_list'
  | 'todo_list'
  | 'quote'
  | 'code'
  | 'math_equation'
  | 'table'
  | 'spreadsheet'
  | 'drawing'
  | 'audio_clip'
  | 'divider'
  | 'image';

const TEXT_COLORS = [
  { label: 'Default', hex: '' },
  { label: 'Blue', hex: '#007aff' },
  { label: 'Purple', hex: '#af52de' },
  { label: 'Pink', hex: '#ff2d55' },
  { label: 'Red', hex: '#ff3b30' },
  { label: 'Orange', hex: '#ff9500' },
  { label: 'Yellow', hex: '#ffcc00' },
  { label: 'Green', hex: '#34c759' },
  { label: 'Teal', hex: '#5ac8fa' },
  { label: 'Gray', hex: '#8e8e93' },
];

const HIGHLIGHT_COLORS = [
  { label: 'None', hex: '' },
  { label: 'Yellow', hex: 'rgba(255, 214, 10, 0.35)' },
  { label: 'Green', hex: 'rgba(50, 215, 75, 0.30)' },
  { label: 'Blue', hex: 'rgba(10, 132, 255, 0.28)' },
  { label: 'Pink', hex: 'rgba(255, 55, 95, 0.28)' },
  { label: 'Purple', hex: 'rgba(191, 90, 242, 0.28)' },
  { label: 'Orange', hex: 'rgba(255, 159, 10, 0.30)' },
];

const ZOOM_PRESETS = [50, 75, 80, 90, 100, 110, 125, 150, 175, 200];

export interface MacFormatBarProps {
  activeBlockStyle: string;
  onBlockStyleChange: (style: string) => void;
  fontFamily: string;
  onFontFamilyChange: (font: string) => void;
  fontSize: number;
  onFontSizeChange: (size: number) => void;
  onToggleInlineFormat: (
    mark: 'bold' | 'italic' | 'underline' | 'strikethrough' | 'code',
  ) => void;
  onApplyTextColor: (hex: string) => void;
  onApplyHighlightColor: (hex: string) => void;
  activeAlign: BlockAlign;
  onAlignChange: (align: BlockAlign) => void;
  onInsertBlock: (kind: InsertBlockKind) => void;
  zoom: number;
  onZoomChange: (zoom: number) => void;
  canUndo?: boolean;
  canRedo?: boolean;
  onUndo?: () => void;
  onRedo?: () => void;
  drawMode: boolean;
  onToggleDrawMode: () => void;
  htmlPreviewOpen: boolean;
  onToggleHtmlPreview: () => void;
  hasHtmlArtifact: boolean;
  saveStatus: 'saved' | 'saving' | 'dirty';
  onExportMarkdown: () => void;
  onExportPdf: () => void;
  onOpenShare: () => void;
}

export function MacFormatBar({
  activeBlockStyle,
  onBlockStyleChange,
  fontFamily,
  onFontFamilyChange,
  fontSize,
  onFontSizeChange,
  onToggleInlineFormat,
  onApplyTextColor,
  onApplyHighlightColor,
  activeAlign,
  onAlignChange,
  onInsertBlock,
  zoom,
  onZoomChange,
  canUndo = false,
  canRedo = false,
  onUndo,
  onRedo,
  drawMode,
  onToggleDrawMode,
  htmlPreviewOpen,
  onToggleHtmlPreview,
  hasHtmlArtifact,
  saveStatus,
  onExportMarkdown,
  onExportPdf,
  onOpenShare,
}: MacFormatBarProps) {
  const zoomPct = Math.round(zoom * 100);

  return (
    <div className="mario-format-bar" role="toolbar" aria-label="Formatting">
      {onUndo && (
        <Button
          size="small"
          variant="bordered"
          icon="arrow-uturn-left"
          label="Undo (Ctrl+Z)"
          disabled={!canUndo}
          onClick={onUndo}
        />
      )}
      {onRedo && (
        <Button
          size="small"
          variant="bordered"
          icon="arrow-uturn-right"
          label="Redo (Ctrl+Shift+Z)"
          disabled={!canRedo}
          onClick={onRedo}
        />
      )}

      {(onUndo || onRedo) && <span className="mario-format-bar__sep" />}

      <PopUpButton
        size="small"
        aria-label="Block Style"
        value={activeBlockStyle}
        onChange={onBlockStyleChange}
        options={[
          {
            value: 'paragraph',
            label: 'Body',
            icon: 'doc-text',
            shortcut: '⌃⌥0',
            headerAbove: 'Typography',
          },
          {
            value: 'heading-1',
            label: 'Heading 1',
            icon: 'book',
            shortcut: '⌃⌥1',
          },
          {
            value: 'heading-2',
            label: 'Heading 2',
            icon: 'book',
            shortcut: '⌃⌥2',
          },
          {
            value: 'heading-3',
            label: 'Heading 3',
            icon: 'book',
            shortcut: '⌃⌥3',
          },
          {
            value: 'bulleted_list',
            label: 'Bulleted List',
            icon: 'list-bullet',
            shortcut: '⇧⌃8',
            separatorAbove: true,
            headerAbove: 'Lists & Blocks',
          },
          {
            value: 'numbered_list',
            label: 'Numbered List',
            icon: 'line-3-horizontal',
            shortcut: '⇧⌃7',
          },
          {
            value: 'todo_list',
            label: 'Checklist',
            icon: 'checkmark-circle-fill',
            shortcut: '⇧⌃9',
          },
          {
            value: 'quote',
            label: 'Quote',
            icon: 'bubble-left',
            shortcut: '⇧⌃Q',
          },
          {
            value: 'code',
            label: 'Code Block',
            icon: 'cpu',
            shortcut: '⌃⌥C',
          },
        ]}
      />

      <PopUpButton
        size="small"
        aria-label="Font Family"
        value={fontFamily}
        onChange={onFontFamilyChange}
        options={[
          { value: 'System', label: 'System', headerAbove: 'Font Family' },
          { value: 'Inter', label: 'Inter' },
          { value: 'Serif', label: 'Georgia' },
          { value: 'Monospace', label: 'SF Mono' },
        ]}
      />

      <PopUpButton
        size="small"
        aria-label="Font Size"
        value={String(fontSize)}
        onChange={(v) => onFontSizeChange(Number(v) || 14)}
        options={['11', '12', '13', '14', '15', '16', '18', '20', '24'].map(
          (s, idx) => ({
            value: s,
            label: `${s} pt`,
            headerAbove: idx === 0 ? 'Text Size' : undefined,
          }),
        )}
      />

      <span className="mario-format-bar__sep" />

      <Button
        size="small"
        variant="bordered"
        label="Bold (Ctrl+B)"
        onClick={() => onToggleInlineFormat('bold')}
      >
        <strong>B</strong>
      </Button>
      <Button
        size="small"
        variant="bordered"
        label="Italic (Ctrl+I)"
        onClick={() => onToggleInlineFormat('italic')}
      >
        <em>I</em>
      </Button>
      <Button
        size="small"
        variant="bordered"
        label="Underline (Ctrl+U)"
        onClick={() => onToggleInlineFormat('underline')}
      >
        <u>U</u>
      </Button>
      <Button
        size="small"
        variant="bordered"
        label="Strikethrough (Ctrl+Shift+X)"
        onClick={() => onToggleInlineFormat('strikethrough')}
      >
        <s>S</s>
      </Button>
      <Button
        size="small"
        variant="bordered"
        label="Inline Code (Ctrl+E)"
        onClick={() => onToggleInlineFormat('code')}
      >
        {'</>'}
      </Button>

      <Button
        size="small"
        variant="bordered"
        icon="eyedropper"
        label="Text Color & Highlight"
        popover={
          <div>
            <p
              className="mac-caption-1 mac-label-secondary"
              style={{ margin: '0 0 6px' }}
            >
              Text Color
            </p>
            <div className="mario-color-swatch-grid">
              {TEXT_COLORS.map((c) => (
                <button
                  key={c.label}
                  type="button"
                  title={c.label}
                  className="mario-color-swatch"
                  style={{
                    background: c.hex || 'var(--mac-label)',
                  }}
                  onClick={() => onApplyTextColor(c.hex)}
                />
              ))}
            </div>
            <p
              className="mac-caption-1 mac-label-secondary"
              style={{ margin: '10px 0 6px' }}
            >
              Highlight
            </p>
            <div className="mario-color-swatch-grid">
              {HIGHLIGHT_COLORS.map((c) => (
                <button
                  key={c.label}
                  type="button"
                  title={c.label}
                  className="mario-color-swatch"
                  style={{
                    background: c.hex || 'transparent',
                  }}
                  onClick={() => onApplyHighlightColor(c.hex)}
                />
              ))}
            </div>
          </div>
        }
      />

      <PopUpButton
        size="small"
        aria-label="Alignment"
        value={activeAlign}
        onChange={(v) => onAlignChange(v as BlockAlign)}
        options={[
          {
            value: 'left',
            label: 'Align Left',
            shortcut: '⇧⌃L',
            headerAbove: 'Alignment',
          },
          { value: 'center', label: 'Center', shortcut: '⇧⌃E' },
          { value: 'right', label: 'Align Right', shortcut: '⇧⌃R' },
          { value: 'justify', label: 'Justify', shortcut: '⇧⌃J' },
        ]}
      />

      <span className="mario-format-bar__sep" />

      <PullDownButton size="small" label="+ Insert">
        <MenuHeader>Rich Media & Data</MenuHeader>
        <MenuItem icon="photo" onSelect={() => onInsertBlock('image')}>
          Image…
        </MenuItem>
        <MenuItem icon="square-grid" onSelect={() => onInsertBlock('table')}>
          Table (3×3)
        </MenuItem>
        <MenuItem icon="chart-bar" onSelect={() => onInsertBlock('spreadsheet')}>
          Spreadsheet (Formulas)
        </MenuItem>
        <MenuItem
          icon="pencil-tip-circle"
          onSelect={() => onInsertBlock('drawing')}
        >
          Drawing Canvas
        </MenuItem>
        <MenuItem icon="mic" onSelect={() => onInsertBlock('audio_clip')}>
          Audio Voice Clip
        </MenuItem>
        <MenuSeparator />
        <MenuHeader>Technical & Structure</MenuHeader>
        <MenuItem
          icon="command"
          shortcut="⌃⌥M"
          onSelect={() => onInsertBlock('math_equation')}
        >
          Math Equation (LaTeX)
        </MenuItem>
        <MenuItem
          icon="cpu"
          shortcut="⌃⌥C"
          onSelect={() => onInsertBlock('code')}
        >
          Code Block
        </MenuItem>
        <MenuItem
          icon="checkmark-circle-fill"
          shortcut="⇧⌃9"
          onSelect={() => onInsertBlock('todo_list')}
        >
          Checklist Item
        </MenuItem>
        <MenuItem
          icon="bubble-left"
          shortcut="⇧⌃Q"
          onSelect={() => onInsertBlock('quote')}
        >
          Quote Block
        </MenuItem>
        <MenuSeparator />
        <MenuItem icon="minus" onSelect={() => onInsertBlock('divider')}>
          Horizontal Divider
        </MenuItem>
      </PullDownButton>

      <Button
        size="small"
        variant="bordered"
        icon="pencil-tip-circle"
        pressed={drawMode}
        onClick={onToggleDrawMode}
      >
        Draw
      </Button>

      <Button
        size="small"
        variant={hasHtmlArtifact ? 'tinted' : 'bordered'}
        icon="globe"
        pressed={htmlPreviewOpen}
        onClick={onToggleHtmlPreview}
      >
        HTML Preview
      </Button>

      <Spacer />

      <PullDownButton size="small" label={`${zoomPct}%`} aria-label="Zoom">
        <MenuHeader>Canvas Zoom</MenuHeader>
        <MenuItem
          icon="plus-circle"
          shortcut="⌃+"
          onSelect={() =>
            onZoomChange(Math.min(2, Math.round((zoom + 0.1) * 100) / 100))
          }
        >
          Zoom In
        </MenuItem>
        <MenuItem
          icon="minus-circle"
          shortcut="⌃-"
          onSelect={() =>
            onZoomChange(Math.max(0.5, Math.round((zoom - 0.1) * 100) / 100))
          }
        >
          Zoom Out
        </MenuItem>
        <MenuItem
          icon="magnifyingglass"
          shortcut="⌃0"
          onSelect={() => onZoomChange(1)}
        >
          Actual Size (100%)
        </MenuItem>
        <MenuSeparator />
        <MenuHeader>Scale Preset</MenuHeader>
        {ZOOM_PRESETS.map((pct) => (
          <MenuItem
            key={pct}
            checked={zoomPct === pct}
            onSelect={() => onZoomChange(pct / 100)}
          >
            {pct}%
          </MenuItem>
        ))}
      </PullDownButton>

      <span
        className="mac-caption-1 mac-label-secondary"
        style={{ minWidth: 46, textAlign: 'right' }}
      >
        {saveStatus === 'saving'
          ? 'Saving…'
          : saveStatus === 'dirty'
          ? 'Edited'
          : 'Saved'}
      </span>

      <PullDownButton size="small" label="Export">
        <MenuHeader>Export Current Page</MenuHeader>
        <MenuItem
          icon="doc-text"
          shortcut="⇧⌃M"
          onSelect={onExportMarkdown}
        >
          Export as Markdown (.md)…
        </MenuItem>
        <MenuItem icon="printer" shortcut="⌃P" onSelect={onExportPdf}>
          Export as PDF (.pdf)…
        </MenuItem>
      </PullDownButton>

      <Button
        size="small"
        variant="bordered"
        icon="person-2"
        label="Share Notebook"
        onClick={onOpenShare}
      />
    </div>
  );
}
