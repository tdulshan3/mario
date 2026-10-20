import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { Editor, JSONContent } from '@tiptap/core';
import { Button, Icon, Spacer, TextField } from '../macos/macos';
import { documentToMarkdown, markdownToNodes } from '../shared/document-codec';
import { renderMarkdownHtml } from '../shared/markdown-render';
import { ASK_SYSTEM_PROMPT, buildAskUserPrompt, formatWebResults, htmlArtifactOf, shouldSearchWeb } from '../shared/ask-prompt';
import { newClientId } from '../shared/ids';
import { appflowyToPm, pmToAppflowy } from '../editor/pm-codec';
import { inlineAskAnchor, type InlineAskAnchor } from '../editor/inline-ask';
import { LiveThinking, type StreamState } from './ai-live';
import { clearActivity, failActivity, setActivity, updateArtifacts } from './ai-store';

/**
 * Inline Ask (Mario v1's in-page Ask, opened with “/ask”): a box after the line
 * you were on. It reads the notes above that line, or the passage you had
 * highlighted, and its answer can go straight into the page — below the line,
 * or in place of the highlight. Chats are saved to the notebook's Ask history,
 * the same list the AI panel shows.
 */

interface Run extends StreamState {
  id: string;
  question: string;
  status: 'running' | 'done' | 'stopped' | 'failed';
  error?: string;
}

export interface InlineAskBoxProps {
  editor: Editor;
  anchor: InlineAskAnchor;
  notebookId?: string;
  pageId?: string;
  pageTitle: string;
  onClose: () => void;
  onPreviewHtml?: (html: string) => void;
}

const CHANNEL = 'inline';

/** The page's blocks before `pos`, as Markdown. */
function notesAbove(editor: Editor, pos: number): string {
  try {
    const cut = editor.state.doc.cut(0, Math.min(pos, editor.state.doc.content.size));
    return documentToMarkdown(pmToAppflowy(cut.toJSON() as JSONContent)).trim();
  } catch {
    return editor.state.doc.textBetween(0, pos, '\n\n', ' ').trim();
  }
}

/** Markdown as editor blocks. */
function markdownBlocks(md: string): JSONContent[] {
  const blocks = (appflowyToPm({ type: 'page', children: markdownToNodes(md) }).content ?? []) as JSONContent[];
  // appflowyToPm ends a document with an empty line to type on; an insert doesn't need it.
  while (blocks.length > 1 && blocks[blocks.length - 1].type === 'paragraph' && !blocks[blocks.length - 1].content?.length) {
    blocks.pop();
  }
  return blocks;
}

export function InlineAskBox({ editor, anchor, notebookId, pageId, pageTitle, onClose, onPreviewHtml }: InlineAskBoxProps) {
  // The highlighted passage the box was opened on, if any.
  const quote = useMemo(
    () => (anchor.to > anchor.from ? editor.state.doc.textBetween(anchor.from, anchor.to, '\n', ' ').trim() : ''),
    [anchor.nonce],
  );
  const [draft, setDraft] = useState('');
  const [run, setRun] = useState<Run | null>(null);
  const runRef = useRef<Run | null>(null);
  const frame = useRef<number | null>(null);
  const stopRef = useRef(false);
  const [model, setModel] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const boxRef = useRef<HTMLElement | null>(null);
  const focusInput = () => setTimeout(() => boxRef.current?.querySelector<HTMLInputElement>('.mario-inline-ask__composer input')?.focus(), 0);
  const running = run?.status === 'running';

  useEffect(() => {
    window.mario.ai
      .getProviders()
      .then((s) => {
        const p = s.providers.find((x) => x.id === s.activeId) ?? s.providers[0];
        setModel(p ? p.model || p.label : null);
      })
      .catch(() => setModel(null));
    focusInput();
    return () => {
      // Closing the box mid-answer stops it.
      if (runRef.current?.status === 'running') {
        stopRef.current = true;
        void window.mario.ai.abort(CHANNEL);
      }
      if (frame.current != null) cancelAnimationFrame(frame.current);
      clearActivity(CHANNEL);
    };
  }, []);

  const show = () => setRun(runRef.current ? { ...runRef.current } : null);
  const onDelta = (delta: { kind: 'thinking' | 'text'; text: string }) => {
    const cur = runRef.current;
    if (!cur) return;
    if (delta.kind === 'thinking') {
      if (cur.thinkingStart == null) setActivity(CHANNEL, 'Thinking');
      cur.thinking += delta.text;
      cur.thinkingStart ??= Date.now();
    } else {
      if (!cur.answer) setActivity(CHANNEL, 'Answering');
      if (cur.thinkingStart && !cur.thinkingEnd) cur.thinkingEnd = Date.now();
      cur.answer += delta.text;
    }
    if (frame.current == null) {
      frame.current = requestAnimationFrame(() => {
        frame.current = null;
        show();
      });
    }
  };

  const ask = async (question: string) => {
    const q = question.trim();
    if (!q || runRef.current?.status === 'running') return;
    stopRef.current = false;
    setNotice(null);
    setDraft('');
    const cur: Run = { id: newClientId('ask'), question: q, status: 'running', thinking: '', answer: '' };
    runRef.current = cur;
    show();
    setActivity(CHANNEL, 'Reading the note', quote ? 'your highlight' : 'the notes above');
    let failure: string | null = null;
    let sources: Array<{ title: string; link: string }> = [];
    try {
      const pos = inlineAskAnchor(editor.state)?.pos ?? anchor.pos;
      const notes = `## Page: ${pageTitle}\n${notesAbove(editor, pos)}`;
      let webContext = '';
      if (shouldSearchWeb(q, 'auto')) {
        setActivity(CHANNEL, 'Searching the web', q);
        const results = await window.mario.ai.webSearch(q).catch(() => []);
        sources = results.map((r) => ({ title: r.title, link: r.link }));
        webContext = formatWebResults(results);
      }
      setActivity(CHANNEL, 'Waiting for the model');
      const res = stopRef.current
        ? { text: '', reasoning: '', stopped: true }
        : await window.mario.ai.chatStream(
            {
              systemPrompt: ASK_SYSTEM_PROMPT,
              userPrompt: buildAskUserPrompt({ question: q, notes, passage: quote || null, webContext }),
              channel: CHANNEL,
            },
            onDelta,
          );
      cur.answer = (res.text || cur.answer).trim();
      cur.thinking = (res.reasoning || cur.thinking).trim();
      if (cur.thinkingStart && !cur.thinkingEnd) cur.thinkingEnd = Date.now();
      cur.status = res.stopped || stopRef.current ? 'stopped' : 'done';
    } catch (err) {
      if (stopRef.current) {
        cur.status = 'stopped';
      } else {
        failure = err instanceof Error ? err.message : String(err);
        cur.status = 'failed';
        cur.error = failure;
      }
    } finally {
      if (frame.current != null) cancelAnimationFrame(frame.current);
      frame.current = null;
      show();
      if (failure) failActivity(CHANNEL, failure);
      else clearActivity(CHANNEL);
      focusInput();
    }
    if (notebookId && (cur.answer || cur.status === 'stopped')) {
      const seconds = cur.thinkingStart
        ? Math.max(1, Math.round(((cur.thinkingEnd ?? Date.now()) - cur.thinkingStart) / 1000))
        : undefined;
      void updateArtifacts(notebookId, (prev) => ({
        ...prev,
        askHistory: [
          ...(prev.askHistory ?? []),
          {
            id: cur.id,
            pageId,
            question: q,
            answer: cur.answer
              ? cur.status === 'stopped'
                ? `${cur.answer}\n\n*Stopped.*`
                : cur.answer
              : '*Stopped before answering.*',
            ...(quote ? { quote } : {}),
            ...(sources.length ? { sources } : {}),
            ...(cur.thinking ? { thinking: cur.thinking, thinkingSeconds: seconds } : {}),
            createdAt: new Date().toISOString(),
          },
        ],
      }));
    }
  };

  const stop = () => {
    stopRef.current = true;
    void window.mario.ai.abort(CHANNEL);
  };

  const close = () => {
    if (running) stop();
    onClose();
  };

  /** Below the line the box was opened on, then the box closes. */
  const insertBelow = () => {
    const blocks = markdownBlocks(run?.answer ?? '');
    const at = inlineAskAnchor(editor.state);
    if (!blocks.length || !at) return;
    editor.chain().insertContentAt(at.pos, blocks).focus().run();
    onClose();
  };

  /** In place of the highlighted passage. One paragraph goes in as text; more as blocks. */
  const replaceSelection = () => {
    const blocks = markdownBlocks(run?.answer ?? '');
    const at = inlineAskAnchor(editor.state);
    if (!blocks.length || !at || at.to <= at.from) {
      setNotice('Nothing is highlighted to replace.');
      return;
    }
    const single = blocks.length === 1 && blocks[0].type === 'paragraph';
    editor
      .chain()
      .insertContentAt({ from: at.from, to: at.to }, single ? (blocks[0].content ?? []) : blocks)
      .focus()
      .run();
    onClose();
  };

  const html = run && !running ? htmlArtifactOf(run.answer) : undefined;
  const scope = quote ? 'read your highlight' : 'read the notes above';

  return (
    <section
      ref={boxRef}
      className="mario-inline-ask"
      aria-label="Ask Mario"
      onContextMenu={(e) => e.stopPropagation()}
      onKeyDown={(e) => {
        if (e.key === 'Escape') {
          e.preventDefault();
          e.stopPropagation();
          if (running) stop();
          else {
            close();
            editor.commands.focus();
          }
        }
      }}
    >
      <div className="mario-inline-ask__head">
        <Icon name="bubble-left" />
        <span className="mario-inline-ask__name">Mario</span>
        <span className="mario-inline-ask__meta">{model ? `${model} · ${scope}` : scope}</span>
        <Spacer />
        <Button size="small" variant="borderless" icon="xmark" label="Close (Esc)" onClick={close} />
      </div>

      {quote && !run && <div className="mario-inline-ask__quote">{quote.replace(/\s+/g, ' ')}</div>}

      {run && (
        <div className="mario-inline-ask__run">
          <p className="mario-inline-ask__question">{run.question}</p>
          {running && <LiveThinking live={run} />}
          {run.answer.trim() && (
            <div className="mario-md-body" dangerouslySetInnerHTML={{ __html: renderMarkdownHtml(run.answer.trimStart()) }} />
          )}
          {run.status === 'stopped' && <p className="mac-caption-1 mac-label-secondary">Stopped.</p>}
          {run.error && <p className="mac-footnote mac-label-red">{run.error}</p>}
          {notice && <p className="mac-footnote mac-label-red">{notice}</p>}
          <div className="mario-inline-ask__actions">
            {running ? (
              <Button size="small" icon="stop" onClick={stop}>
                Stop
              </Button>
            ) : (
              <>
                <Button size="small" variant="prominent" disabled={!run.answer.trim()} onClick={insertBelow}>
                  Insert Below
                </Button>
                {quote && (
                  <Button size="small" disabled={!run.answer.trim()} onClick={replaceSelection}>
                    Replace Selection
                  </Button>
                )}
                <Button size="small" onClick={() => void ask(run.question)}>
                  Ask Again
                </Button>
                {html && onPreviewHtml && (
                  <Button size="small" onClick={() => onPreviewHtml(html)}>
                    Preview HTML
                  </Button>
                )}
                <Button size="small" variant="borderless" onClick={close}>
                  Discard
                </Button>
              </>
            )}
          </div>
        </div>
      )}

      <div className="mario-inline-ask__composer">
        <TextField
          value={draft}
          disabled={running}
          onChange={setDraft}
          placeholder={quote ? 'Ask about the highlighted passage…' : run ? 'Ask something else…' : 'Ask Mario about this page…'}
          aria-label="Ask Mario"
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              void ask(draft);
            }
          }}
        />
        <span className="mario-inline-ask__hint" aria-hidden="true">
          <Icon name="return" />
        </span>
      </div>
    </section>
  );
}
