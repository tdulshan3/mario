import React, { useLayoutEffect, useMemo, useRef } from 'react';
import { Spinner } from '../macos/macos';
import type { AiTab } from '../shared/types';
import { renderMarkdownHtml } from '../shared/markdown-render';

/** What a streamed reply has produced so far; `working` labels a structured task once it writes. */
export interface StreamState {
  thinking: string;
  answer: string;
  thinkingStart?: number;
  thinkingEnd?: number;
  working?: string;
  /** The tab whose request this is: only that tab shows it. */
  owner?: AiTab;
  /** For the model bar's activity line ("2 of 3"). */
  detail?: string;
}

export function LiveThinking({ live }: { live: StreamState }) {
  const boxRef = useRef<HTMLDivElement>(null);
  // Follow the stream only while the reader is at the bottom of the box.
  const stickRef = useRef(true);
  const answering = live.answer.trim().length > 0;
  const html = useMemo(() => renderMarkdownHtml(live.thinking.trimStart()), [live.thinking]);
  useLayoutEffect(() => {
    const box = boxRef.current;
    if (box && stickRef.current) box.scrollTop = box.scrollHeight;
  }, [html]);
  const seconds =
    live.thinkingStart != null
      ? Math.max(1, Math.round(((live.thinkingEnd ?? Date.now()) - live.thinkingStart) / 1000))
      : 0;
  if (answering && !live.thinking && !live.working) return null;
  // A structured task keeps its spinner while it writes its result (JSON, not shown).
  const spinning = !answering || Boolean(live.working);
  const status = !answering ? 'Thinking…' : (live.working ?? `Thought for ${seconds} s`);
  return (
    <div className="mario-live-thinking">
      <div className="mario-live-thinking__status">
        {spinning && <Spinner label={status} />}
        <span>{status}</span>
        {answering && live.working && live.thinking && (
          <span className="mario-live-thinking__time">thought for {seconds} s</span>
        )}
      </div>
      {live.thinking && (
        <div
          ref={boxRef}
          className="mario-thinking mario-md-body"
          onScroll={(e) => {
            const el = e.currentTarget;
            stickRef.current = el.scrollHeight - el.scrollTop - el.clientHeight < 24;
          }}
          dangerouslySetInnerHTML={{ __html: html }}
        />
      )}
    </div>
  );
}
