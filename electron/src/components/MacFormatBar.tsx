import React from 'react';
import {
  Button,
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
  return (
    <div className="mario-format-bar" role="toolbar" aria-label="Formatting">
      <PopUpButton
        size="small"
        aria-label="Block Style"
        value={activeBlockStyle}
        onChange={onBlockStyleChange}
        options={[
          { value: 'paragraph', label: 'Body' },
          { value: 'heading-1', label: 'Heading 1' },
          { value: 'heading-2', label: 'Heading 2' },
          { value: 'heading-3', label: 'Heading 3' },
          { value: 'bulleted_list', label: 'Bulleted List' },
          { value: 'numbered_list', label: 'Numbered List' },
          { value: 'todo_list', label: 'Checklist' },
          { value: 'quote', label: 'Quote' },
          { value: 'code', label: 'Code Block' },
        ]}
      />

      <PopUpButton
        size="small"
        aria-label="Font Family"
        value={fontFamily}
        onChange={onFontFamilyChange}
        options={[
          { value: 'System', label: 'System' },
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
        options={['12', '13', '14', '15', '16', '18', '20', '24'].map((s) => ({
          value: s,
          label: `${s} pt`,
        }))}
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
        label="Strikethrough"
        onClick={() => onToggleInlineFormat('strikethrough')}
      >
        <s>S</s>
      </Button>
      <Button
        size="small"
        variant="bordered"
        label="Inline Code"
        onClick={() => onToggleInlineFormat('code')}
      >
        {'</>'}
      </Button>

      <Button
        size="small"
        variant="bordered"
        icon="eyedropper"
        label="Text Color"
        popover={
          <div>
            <p className="mac-caption-1 mac-label-secondary" style={{ margin: '0 0 6px' }}>
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
            <p className="mac-caption-1 mac-label-secondary" style={{ margin: '10px 0 6px' }}>
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
          { value: 'left', label: 'Align Left' },
          { value: 'center', label: 'Center' },
          { value: 'right', label: 'Align Right' },
          { value: 'justify', label: 'Justify' },
        ]}
      />

      <span className="mario-format-bar__sep" />

      <PullDownButton size="small" label="+ Insert">
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
        <MenuItem
          icon="command"
          onSelect={() => onInsertBlock('math_equation')}
        >
          Math Equation (LaTeX)
        </MenuItem>
        <MenuItem icon="doc-text" onSelect={() => onInsertBlock('code')}>
          Code Block
        </MenuItem>
        <MenuItem icon="mic" onSelect={() => onInsertBlock('audio_clip')}>
          Audio Voice Clip
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

      <PopUpButton
        size="small"
        aria-label="Zoom"
        value={String(Math.round(zoom * 100))}
        onChange={(v) => onZoomChange((Number(v) || 100) / 100)}
        options={[
          { value: '80', label: '80%' },
          { value: '90', label: '90%' },
          { value: '100', label: '100%' },
          { value: '110', label: '110%' },
          { value: '125', label: '125%' },
          { value: '150', label: '150%' },
        ]}
      />

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
        <MenuItem icon="doc-text" onSelect={onExportMarkdown}>
          Export as Markdown (.md)…
        </MenuItem>
        <MenuItem icon="printer" onSelect={onExportPdf}>
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
