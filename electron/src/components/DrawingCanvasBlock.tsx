import React, { useEffect, useRef, useState } from 'react';
import { Button, PopUpButton, SegmentedControl, Spacer } from '../macos/macos';
import type { Stroke, StrokeMode, StrokePoint } from '../shared/types';

const INK_COLORS = [
  { label: 'Black', argb: 0xff1e1e1e, css: '#1e1e1e' },
  { label: 'Blue', argb: 0xff007aff, css: '#007aff' },
  { label: 'Red', argb: 0xffff3b30, css: '#ff3b30' },
  { label: 'Green', argb: 0xff34c759, css: '#34c759' },
  { label: 'Orange', argb: 0xffff9500, css: '#ff9500' },
  { label: 'Purple', argb: 0xffaf52de, css: '#af52de' },
  { label: 'Yellow', argb: 0xffffcc00, css: '#ffcc00' },
];

export function argbToCss(argb: number, alphaOverride?: number): string {
  const u = argb >>> 0;
  const a = alphaOverride ?? ((u >>> 24) & 0xff) / 255;
  const r = (u >>> 16) & 0xff;
  const g = (u >>> 8) & 0xff;
  const b = u & 0xff;
  return `rgba(${r}, ${g}, ${b}, ${a.toFixed(2)})`;
}

export interface DrawingCanvasBlockProps {
  strokes: Stroke[];
  height?: number;
  overlay?: boolean;
  onChange: (strokes: Stroke[], height?: number) => void;
  onDelete?: () => void;
  onCloseOverlay?: () => void;
}

export function DrawingCanvasBlock({
  strokes,
  height = 240,
  overlay = false,
  onChange,
  onDelete,
  onCloseOverlay,
}: DrawingCanvasBlockProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [mode, setMode] = useState<StrokeMode>('pen');
  const [colorArgb, setColorArgb] = useState<number>(INK_COLORS[1].argb);
  const [strokeWidth, setStrokeWidth] = useState<number>(3);
  const activePointsRef = useRef<StrokePoint[] | null>(null);
  const [, setTick] = useState(0);

  const renderStrokes = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return;
    if (
      canvas.width !== Math.round(rect.width * dpr) ||
      canvas.height !== Math.round(rect.height * dpr)
    ) {
      canvas.width = Math.round(rect.width * dpr);
      canvas.height = Math.round(rect.height * dpr);
    }
    ctx.save();
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, rect.width, rect.height);

    const allStrokes: Stroke[] = activePointsRef.current
      ? [
          ...strokes,
          {
            points: activePointsRef.current,
            color: colorArgb,
            width: mode === 'highlighter' ? strokeWidth * 3.5 : strokeWidth,
            mode,
          },
        ]
      : strokes;

    for (const s of allStrokes) {
      if (!s.points || s.points.length === 0) continue;
      ctx.save();
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.lineWidth = s.width || 3;
      if (s.mode === 'eraser') {
        ctx.globalCompositeOperation = 'destination-out';
        ctx.strokeStyle = 'rgba(0,0,0,1)';
      } else if (s.mode === 'highlighter') {
        ctx.globalCompositeOperation = 'source-over';
        ctx.strokeStyle = argbToCss(s.color, 0.35);
      } else {
        ctx.globalCompositeOperation = 'source-over';
        ctx.strokeStyle = argbToCss(s.color);
      }

      ctx.beginPath();
      const first = s.points[0];
      ctx.moveTo(first.x, first.y);
      for (let i = 1; i < s.points.length; i++) {
        const pt = s.points[i];
        ctx.lineTo(pt.x, pt.y);
      }
      if (s.points.length === 1) {
        ctx.lineTo(first.x + 0.1, first.y + 0.1);
      }
      ctx.stroke();
      ctx.restore();
    }
    ctx.restore();
  };

  useEffect(() => {
    renderStrokes();
  });

  const handlePointerDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    canvas.setPointerCapture(e.pointerId);
    const rect = canvas.getBoundingClientRect();
    activePointsRef.current = [
      {
        x: e.clientX - rect.left,
        y: e.clientY - rect.top,
        p: e.pressure || 0.5,
      },
    ];
    setTick((t) => t + 1);
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!activePointsRef.current) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    activePointsRef.current.push({
      x: e.clientX - rect.left,
      y: e.clientY - rect.top,
      p: e.pressure || 0.5,
    });
    renderStrokes();
  };

  const handlePointerUp = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!activePointsRef.current) return;
    const pts = activePointsRef.current;
    activePointsRef.current = null;
    try {
      canvasRef.current?.releasePointerCapture(e.pointerId);
    } catch {
      // ignore
    }
    if (pts.length > 0) {
      const nextStroke: Stroke = {
        points: pts,
        color: colorArgb,
        width: mode === 'highlighter' ? strokeWidth * 3.5 : strokeWidth,
        mode,
      };
      onChange([...strokes, nextStroke], height);
    }
  };

  const toolbar = (
    <div className="mario-rich-card__header">
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <SegmentedControl
          size="small"
          label="Ink Tool"
          value={mode}
          onChange={(v) => setMode(v as StrokeMode)}
          options={[
            { value: 'pen', label: 'Pen' },
            { value: 'highlighter', label: 'Highlight' },
            { value: 'eraser', label: 'Erase' },
          ]}
        />
        <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          {INK_COLORS.map((c) => (
            <button
              key={c.label}
              type="button"
              title={c.label}
              className={`mario-color-swatch ${
                colorArgb === c.argb ? 'mario-color-swatch--active' : ''
              }`}
              style={{ width: 16, height: 16, background: c.css }}
              onClick={() => setColorArgb(c.argb)}
            />
          ))}
        </div>
        <PopUpButton
          size="small"
          aria-label="Stroke Width"
          value={String(strokeWidth)}
          onChange={(v) => setStrokeWidth(Number(v) || 3)}
          options={[
            { value: '2', label: 'Fine (2px)' },
            { value: '3', label: 'Medium (3px)' },
            { value: '5', label: 'Bold (5px)' },
            { value: '8', label: 'Thick (8px)' },
          ]}
        />
      </div>
      <Spacer />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <Button
          size="small"
          variant="borderless"
          icon="arrow-uturn-left"
          label="Undo Stroke"
          disabled={strokes.length === 0}
          onClick={() => onChange(strokes.slice(0, -1), height)}
        />
        <Button
          size="small"
          variant="borderless"
          onClick={() => onChange([], height)}
          disabled={strokes.length === 0}
        >
          Clear
        </Button>
        {!overlay && (
          <Button
            size="small"
            variant="borderless"
            onClick={() => onChange(strokes, Math.min(640, height + 80))}
          >
            +Height
          </Button>
        )}
        {onDelete && (
          <Button
            size="small"
            variant="borderless"
            icon="trash"
            label="Remove Drawing Block"
            onClick={onDelete}
          />
        )}
        {overlay && onCloseOverlay && (
          <Button size="small" variant="prominent" onClick={onCloseOverlay}>
            Done Drawing
          </Button>
        )}
      </div>
    </div>
  );

  if (overlay) {
    return (
      <div className="mario-page-ink-overlay">
        <div
          style={{
            position: 'sticky',
            top: 0,
            zIndex: 25,
            background: 'var(--mac-window-bg)',
            borderBottom: '1px solid var(--mac-separator)',
          }}
        >
          {toolbar}
        </div>
        <canvas
          ref={canvasRef}
          className="mario-drawing-canvas"
          style={{ width: '100%', height: 'calc(100% - 36px)' }}
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
        />
      </div>
    );
  }

  return (
    <div className="mario-rich-card">
      {toolbar}
      <canvas
        ref={canvasRef}
        className="mario-drawing-canvas"
        style={{ height }}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
      />
    </div>
  );
}
