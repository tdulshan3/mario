import React, { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { renderInlineMarkdownHtml as renderInlineMd, renderMarkdownHtml } from '../shared/markdown-render';
import {
  Alert,
  Button,
  Column,
  Disclosure,
  RadioGroup,
  EmptyState,
  Form,
  FormRow,
  FormSection,
  GroupBox,
  Icon,
  Inspector,
  PopUpButton,
  ProgressBar,
  Row,
  SegmentedControl,
  Sheet,
  Spacer,
  Spinner,
  Stepper,
  Switch,
  TextArea,
} from '../macos/macos';
import type {
  AiCommand,
  AgentAction,
  AiArtifactData,
  AiTab,
  AppFlowyNode,
  GrammarSuggestion,
  LlmEffort,
  LlmProviderConfig,
  Notebook,
  NotePage,
  AgentPlan,
  PageContent,
  QuizEntry,
  QuizGrade,
  Section,
  WebSearchMode,
} from '../shared/types';
import {
  agentPlanSchema,
  grammarSchema,
  marioAgentPrompt,
  OBSERVING_KINDS,
  parseAgentPlan,
  describeAgentAction,
  planWrites,
} from '../shared/agent-schema';
import {
  colIndexToLabel,
  deltaToMarkdown,
  documentToMarkdown,
  makeCodeNode,
  makeDividerNode,
  makeHeadingNode,
  makeListNode,
  makeMathNode,
  makeParagraphNode,
  makeQuoteNode,
  makeSpreadsheetNode,
  makeTableNode,
  markdownToDocument,
  markdownToNodes,
  parseInlineMarkdownToDelta,
  renderBlocksForPrompt,
} from '../shared/document-codec';
import { newClientId } from '../shared/ids';
import {
  GRADING_SYSTEM_PROMPT,
  QUIZ_SYSTEM_PROMPT,
  blankGrade,
  formatMark,
  gradeMark,
  gradeSchema,
  gradingPrompt,
  parseGrade,
  quizSchema,
  quizScore,
  quizUserPrompt,
  validateQuiz,
} from '../shared/quiz';
import { ASK_SYSTEM_PROMPT, buildAskUserPrompt, formatWebResults, htmlArtifactOf, shouldSearchWeb } from '../shared/ask-prompt';
import { LiveThinking, type StreamState } from './ai-live';
import {
  clearActivity,
  elapsedLabel,
  failActivity,
  loadArtifacts,
  setActivity,
  subscribeArtifacts,
  updateArtifacts as updateStoredArtifacts,
  useAiActivity,
  useNow,
} from './ai-store';

export interface AiInspectorPanelProps {
  notebook: Notebook | null;
  section: Section | null;
  page: NotePage | null;
  pageContent: PageContent;
  notebooks: Notebook[];
  sectionsByNotebook: Record<string, Section[]>;
  pagesByKey: Record<string, NotePage[]>;
  onPageContentChange: (next: PageContent) => void;
  onRenameCurrentPage: (title: string) => Promise<void>;
  onOpenPage: (notebookId: string, sectionId: string, pageId: string) => void;
  onCreateNotebook: (name: string, colorIndex?: number) => Promise<Notebook>;
  onRenameNotebook: (nb: Notebook, name: string) => Promise<void>;
  onDeleteNotebook: (notebookId: string) => Promise<void>;
  onCreateSection: (notebookId: string, name: string) => Promise<Section>;
  onRenameSection: (sec: Section, name: string) => Promise<void>;
  onDeleteSection: (notebookId: string, sectionId: string) => Promise<void>;
  onCreatePage: (
    notebookId: string,
    sectionId: string,
    title?: string,
    initialContent?: PageContent,
  ) => Promise<NotePage>;
  onDeletePage: (
    notebookId: string,
    sectionId: string,
    pageId: string,
  ) => Promise<void>;
  onSetRawHtmlOverride: (html: string | null) => void;
  onOpenAiSettings: () => void;
  /** A passage highlighted in the page: the next question is about it. */
  quote?: string | null;
  onClearQuote?: () => void;
  /** The editor's AI slash commands (Ask AI, Summarise Above, Quiz Me). */
  command?: AiCommand | null;
}

interface LiveAsk {
  id: string;
  question: string;
  quote?: string;
  reading: 'running' | 'done';
  readDetail?: string;
  search?: { state: 'running' | 'done'; query: string; count: number };
  thinking: string;
  answer: string;
  startedAt: number;
  thinkingStart?: number;
  thinkingEnd?: number;
}

/**
 * The reply's thinking while it streams, like `ollama run`: a spinner and
 * "Thinking…", the reasoning scrolling by in grey, then "Thought for N s" once
 * the answer starts.
 */
/** "Reading the note", "Searching the web": the steps before the model starts, as in Mario v1. */
function LiveSteps({ live }: { live: LiveAsk }) {
  const step = (running: boolean, label: string, detail?: string) => (
    <div className="mario-ai-step">
      {running ? <Spinner label={label} /> : <Icon name="checkmark" />}
      <span className="mario-ai-step__label">{label}</span>
      {detail && <span className="mario-ai-step__detail">{detail}</span>}
    </div>
  );
  return (
    <div className="mario-ai-steps">
      {step(live.reading === 'running', live.reading === 'running' ? 'Reading the note…' : 'Read the note', live.readDetail)}
      {live.search &&
        step(
          live.search.state === 'running',
          live.search.state === 'running'
            ? 'Searching the web…'
            : live.search.count > 0
              ? 'Searched the web'
              : 'Searched the web — no results',
          live.search.state === 'running' ? live.search.query : live.search.count > 0 ? `read ${live.search.count} sites` : undefined,
        )}
    </div>
  );
}

function relativeTime(iso: string): string {
  const t = new Date(iso).getTime();
  if (!Number.isFinite(t)) return '';
  const sec = Math.round((Date.now() - t) / 1000);
  if (sec < 60) return 'just now';
  const min = Math.round(sec / 60);
  if (min < 60) return `${min} min ago`;
  const h = Math.round(min / 60);
  if (h < 24) return `${h} h ago`;
  const d = Math.round(h / 24);
  if (d < 7) return `${d} d ago`;
  return new Date(t).toLocaleDateString();
}

const MODEL_KEY_SEP = '\u0000';
const modelKey = (providerId: string, model: string) => `${providerId}${MODEL_KEY_SEP}${model}`;

/** A provider's name without a model id someone put in it ("Ollama · qwen3:8b" → "Ollama"). */
function providerName(p: { label: string; model: string }): string {
  const i = p.label.lastIndexOf(' · ');
  if (i > 0) {
    const tail = p.label.slice(i + 3).trim();
    if (tail === p.model || /[:/]/.test(tail)) return p.label.slice(0, i).trim();
  }
  return p.label;
}

/**
 * The model bar's second row, as in Mario v1: what the model is doing right now
 * and for how long ("Thinking · 12 s"), from the panel or the page's inline Ask.
 * Silent when nothing runs; red when the last run failed.
 */
function ModelActivityLine() {
  const act = useAiActivity();
  const now = useNow(Boolean(act && !act.failed));
  if (!act) return null;
  if (act.failed) {
    return (
      <div className="mario-ai-activity mario-ai-activity--failed" role="status">
        <Icon name="exclamationmark-triangle" />
        <span className="mario-ai-activity__text">{act.label}</span>
      </div>
    );
  }
  return (
    <div className="mario-ai-activity" role="status" aria-live="polite">
      <Spinner label={act.label} />
      <span className="mario-ai-activity__text">
        {act.label}
        {act.detail ? ` · ${act.detail}` : ''}
      </span>
      <span className="mario-ai-activity__time">{elapsedLabel(now - act.since)}</span>
    </div>
  );
}

interface AgentStepLog {
  id: string;
  kind: string;
  summary: string;
  status: 'running' | 'done' | 'error';
}


export function AiInspectorPanel({
  notebook,
  section,
  page,
  pageContent,
  notebooks,
  sectionsByNotebook,
  pagesByKey,
  onPageContentChange,
  onRenameCurrentPage,
  onOpenPage,
  onCreateNotebook,
  onCreateSection,
  onRenameSection,
  onCreatePage,
  onSetRawHtmlOverride,
  onOpenAiSettings,
  quote = null,
  onClearQuote = () => {},
  command = null,
}: AiInspectorPanelProps) {
  const [width, setWidth] = useState(328);
  const [tab, setTab] = useState<AiTab>('ask');
  const [providers, setProviders] = useState<LlmProviderConfig[]>([]);
  const [activeProviderId, setActiveProviderId] = useState<string | null>(null);
  // Installed / offered models of every provider, for the one model picker.
  const [modelsByProvider, setModelsByProvider] = useState<Record<string, string[]>>({});
  const [webMode, setWebMode] = useState<WebSearchMode>('auto');
  // Ask and Do keep their own drafts.
  const [drafts, setDrafts] = useState<{ ask: string; do: string }>({ ask: '', do: '' });
  const draftKey: 'ask' | 'do' = tab === 'do' ? 'do' : 'ask';
  const promptText = drafts[draftKey];
  const setPromptText = (v: string) => setDrafts((d) => ({ ...d, [draftKey]: v }));
  const [insertedIds, setInsertedIds] = useState<Set<string>>(() => new Set());
  const [confirm, setConfirm] = useState<{
    title: string;
    message: string;
    confirmLabel: string;
    onConfirm: () => void;
  } | null>(null);
  const [writingChecked, setWritingChecked] = useState(false);
  const [busy, setBusy] = useState(false);
  // Stop: set before aborting, so handlers know the error they get is the user's doing.
  const stopRef = useRef(false);
  // The Ask reply being streamed; rendered at the top of the conversation.
  const [live, setLive] = useState<LiveAsk | null>(null);
  const liveRef = useRef<LiveAsk | null>(null);
  const liveFrame = useRef<number | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const liveBubbleRef = useRef<HTMLDivElement>(null);
  // True while the end of the reply being streamed is on screen: the panel then follows it.
  const followRef = useRef(true);
  const liveBottomIn = (container: HTMLElement) => {
    const bubble = liveBubbleRef.current;
    if (!bubble) return 0;
    return bubble.getBoundingClientRect().bottom - container.getBoundingClientRect().top + container.scrollTop;
  };
  useLayoutEffect(() => {
    const container = scrollRef.current;
    if (!live || !container || !followRef.current) return;
    const bottom = liveBottomIn(container);
    if (bottom > container.scrollTop + container.clientHeight) {
      container.scrollTop = bottom - container.clientHeight + 12;
    }
  }, [live?.answer, live?.thinking]);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Per-notebook artifacts
  const [artifacts, setArtifacts] = useState<AiArtifactData>({
    askHistory: [],
    doHistory: [],
    quizzes: [],
  });
  const [mcqCount, setMcqCount] = useState(5);
  const [essayCount, setEssayCount] = useState(1);
  const [quizAnswers, setQuizAnswers] = useState<Record<number, number>>({});
  const [essayAnswers, setEssayAnswers] = useState<Record<number, string>>({});
  const [openQuizId, setOpenQuizId] = useState<string | null>(null);
  const [quizChecked, setQuizChecked] = useState(false);
  // Essays being marked: how far it has got.
  const [marking, setMarking] = useState<{ done: number; total: number } | null>(null);
  // The essay open in the larger editor sheet.
  const [essaySheet, setEssaySheet] = useState<number | null>(null);
  // Quiz, Writing and Do: the reasoning of the request running now, streamed.
  const [taskLive, setTaskLive] = useState<StreamState | null>(null);
  const taskLiveRef = useRef<StreamState | null>(null);
  const taskFrame = useRef<number | null>(null);
  const [grammarIssues, setGrammarIssues] = useState<GrammarSuggestion[]>([]);

  // The Do run in progress (finished runs are saved in artifacts.doHistory).
  const [doLive, setDoLive] = useState<{
    instruction: string;
    steps: AgentStepLog[];
    summary: string;
  } | null>(null);
  const [undoSnapshot, setUndoSnapshot] = useState<PageContent | null>(null);
  // Do ▸ Preview Before Writing: a plan that changes the page waits for Apply.
  const [previewBeforeWriting, setPreviewBeforeWriting] = useState(() => {
    try {
      return localStorage.getItem('mario.do.previewBeforeWriting') === '1';
    } catch {
      return false;
    }
  });
  const [pendingPlan, setPendingPlan] = useState<AgentPlan | null>(null);
  const pendingPlanResolve = useRef<((apply: boolean) => void) | null>(null);

  const draggingRef = useRef(false);
  const latestContentRef = useRef(pageContent);
  latestContentRef.current = pageContent;

  const activeProvider = useMemo(
    () =>
      providers.find((p) => p.id === activeProviderId) ?? providers[0] ?? null,
    [providers, activeProviderId],
  );

  const reloadProviders = async () => {
    try {
      const state = await window.mario.ai.getProviders();
      setProviders(state.providers);
      setActiveProviderId(state.activeId);
    } catch {
      // ignore
    }
  };

  useEffect(() => {
    reloadProviders();
  }, []);

  const providersKey = providers.map((p) => `${p.id}|${p.kind}|${p.baseUrl}|${p.model}`).join('\n');
  useEffect(() => {
    let cancelled = false;
    for (const p of providers) {
      window.mario.ai
        .listModels({ id: p.id, kind: p.kind, baseUrl: p.baseUrl })
        .catch(() => [] as string[])
        .then((models) => {
          if (cancelled) return;
          const merged = Array.from(new Set([p.model, ...models].filter(Boolean)));
          setModelsByProvider((prev) => ({ ...prev, [p.id]: merged }));
        });
    }
    return () => {
      cancelled = true;
    };
  }, [providersKey]);

  /**
   * Providers that point at the same server under the same name (two "Ollama"
   * entries, say) offer the same models: they are one group in the picker.
   */
  const modelGroups = useMemo(() => {
    const groups: Array<{ key: string; name: string; providers: LlmProviderConfig[]; models: string[] }> = [];
    for (const p of providers) {
      const name = providerName(p);
      const key = `${p.kind}|${p.baseUrl.trim().replace(/\/+$/, '').toLowerCase()}|${name.toLowerCase()}`;
      let g = groups.find((x) => x.key === key);
      if (!g) {
        g = { key, name, providers: [], models: [] };
        groups.push(g);
      }
      g.providers.push(p);
      const offered = modelsByProvider[p.id]?.length ? modelsByProvider[p.id] : [p.model];
      for (const m of [p.model, ...offered]) if (!g.models.includes(m)) g.models.push(m);
    }
    for (const g of groups) if (g.models.length > 1) g.models = g.models.filter(Boolean);
    return groups;
  }, [providers, modelsByProvider]);
  const activeGroup = modelGroups.find((g) => g.providers.some((p) => p.id === activeProvider?.id));

  // The notebook's AI history, read through the shared store: saved quizzes of every
  // shape Mario has written come back in one shape, and chats saved from the page show up here.
  useEffect(() => {
    const empty: AiArtifactData = { askHistory: [], doHistory: [], quizzes: [] };
    if (!notebook) {
      setArtifacts(empty);
      return;
    }
    let live = true;
    const id = notebook.id;
    void loadArtifacts(id).then((data) => {
      if (!live) return;
      artifactsRef.current = data;
      setArtifacts(data);
      setQuizAnswers({});
      setEssayAnswers({});
      setQuizChecked(false);
    });
    const unsubscribe = subscribeArtifacts((nbId, data) => {
      if (nbId !== id) return;
      artifactsRef.current = data;
      setArtifacts(data);
    });
    return () => {
      live = false;
      unsubscribe();
    };
  }, [notebook?.id]);

  const artifactsRef = useRef(artifacts);
  artifactsRef.current = artifacts;
  /** Saves from the latest history, not the one a long request started with. */
  const updateArtifacts = async (fn: (prev: AiArtifactData) => AiArtifactData) => {
    if (notebook) {
      await updateStoredArtifacts(notebook.id, fn);
    } else {
      const next = fn(artifactsRef.current);
      artifactsRef.current = next;
      setArtifacts(next);
    }
  };

  const gatherNotebookContext = async (): Promise<string> => {
    if (!notebook) return '';
    const secs = sectionsByNotebook[notebook.id] ?? [];
    const chunks: string[] = [];
    // The open page goes first, so the length cut below never drops it.
    if (page) {
      chunks.push(
        `## Page: ${page.title} (the page open now)\n${documentToMarkdown(latestContentRef.current.document)}`,
      );
    }
    for (const sec of secs) {
      const pgs = pagesByKey[`${notebook.id}/${sec.id}`] ?? [];
      for (const pg of pgs) {
        if (page && pg.id === page.id) {
          continue;
        } else {
          const loaded = await window.mario.page.loadContent(
            pg.id,
            pg.driveFileId,
            pg.title,
          );
          chunks.push(
            `## Page: ${pg.title} (Section: ${sec.name})\n${documentToMarkdown(
              loaded.document,
            )}`,
          );
        }
      }
    }
    return chunks.join('\n\n').slice(0, 18000);
  };

  // --- Ask Tab Handlers ---
  const handleStop = () => {
    stopRef.current = true;
    pendingPlanResolve.current?.(false);
    void window.mario.ai.abort('panel');
  };

  /** The model bar's activity line: what this panel's run is doing now. */
  const activity = (label: string, detail?: string) => setActivity('panel', label, detail);
  const endActivity = (error?: string | null) => (error ? failActivity('panel', error) : clearActivity('panel'));

  /** Streamed pieces are batched into one render per frame. */
  const pushDelta = (delta: { kind: 'thinking' | 'text'; text: string }) => {
    const cur = liveRef.current;
    if (!cur) return;
    if (delta.kind === 'thinking') {
      if (cur.thinkingStart == null) activity('Thinking');
      cur.thinking += delta.text;
      cur.thinkingStart ??= Date.now();
    } else {
      if (!cur.answer) activity('Answering');
      if (cur.thinkingStart && !cur.thinkingEnd) cur.thinkingEnd = Date.now();
      cur.answer += delta.text;
    }
    if (liveFrame.current == null) {
      liveFrame.current = requestAnimationFrame(() => {
        liveFrame.current = null;
        setLive(liveRef.current ? { ...liveRef.current } : null);
      });
    }
  };

  const patchLive = (patch: Partial<LiveAsk>) => {
    if (!liveRef.current) return;
    Object.assign(liveRef.current, patch);
    setLive({ ...liveRef.current });
  };

  const pushTaskDelta = (delta: { kind: 'thinking' | 'text'; text: string }) => {
    const cur = taskLiveRef.current;
    if (!cur) return;
    if (delta.kind === 'thinking') {
      if (cur.thinkingStart == null) activity('Thinking', cur.detail);
      cur.thinking += delta.text;
      cur.thinkingStart ??= Date.now();
    } else {
      if (!cur.answer) activity((cur.working ?? 'Writing').replace(/…$/, ''), cur.detail);
      if (cur.thinkingStart && !cur.thinkingEnd) cur.thinkingEnd = Date.now();
      cur.answer += delta.text;
    }
    if (taskFrame.current == null) {
      taskFrame.current = requestAnimationFrame(() => {
        taskFrame.current = null;
        setTaskLive(taskLiveRef.current ? { ...taskLiveRef.current } : null);
      });
    }
  };

  /** A structured request whose reasoning streams into the tab, labelled `working` while it writes. */
  const streamStructured = async (
    opts: { schemaName: string; schema: Record<string, unknown>; systemPrompt: string; userPrompt: string; temperature?: number },
    working: string,
    owner: AiTab,
    detail?: string,
  ): Promise<{ result: Record<string, unknown>; thinking: string; seconds?: number }> => {
    const state: StreamState = { thinking: '', answer: '', working, owner, detail };
    taskLiveRef.current = state;
    setTaskLive({ ...state });
    activity(working.replace(/…$/, ''), detail);
    try {
      const result = await window.mario.ai.structuredStream({ ...opts, channel: 'panel' }, pushTaskDelta);
      const cur = taskLiveRef.current ?? state;
      return {
        result,
        thinking: cur.thinking.trim(),
        seconds: cur.thinkingStart
          ? Math.max(1, Math.round(((cur.thinkingEnd ?? Date.now()) - cur.thinkingStart) / 1000))
          : undefined,
      };
    } finally {
      if (taskFrame.current != null) cancelAnimationFrame(taskFrame.current);
      taskFrame.current = null;
      taskLiveRef.current = null;
      setTaskLive(null);
    }
  };

  const focusComposer = () =>
    setTimeout(() => document.querySelector<HTMLTextAreaElement>('.mario-ai-composer textarea')?.focus(), 30);

  /**
   * Ask. `opts.context` replaces the notebook as the material (Summarise Above);
   * `opts.passage` is the highlight the question is about (default: the one
   * attached above the composer, which a run then clears, as in Mario v1).
   */
  const handleAskSubmit = async (
    customQuery?: string,
    opts: { context?: string; passage?: string | null } = {},
  ) => {
    const q = (customQuery ?? promptText).trim();
    if (!q || busy) return;
    if (!customQuery) setPromptText('');
    const passage = opts.passage !== undefined ? opts.passage : quote;
    if (quote) onClearQuote();
    stopRef.current = false;
    setBusy(true);
    setErrorMsg(null);
    const turn: LiveAsk = {
      id: newClientId('ask'),
      question: q,
      quote: passage ?? undefined,
      thinking: '',
      answer: '',
      startedAt: Date.now(),
      reading: 'running',
    };
    liveRef.current = turn;
    followRef.current = true;
    scrollRef.current?.scrollTo({ top: 0 });
    setLive({ ...turn });

    activity('Reading the note');
    let failure: string | null = null;
    try {
      const context = opts.context ?? (await gatherNotebookContext());
      const pageCount = notebook
        ? (sectionsByNotebook[notebook.id] ?? []).reduce(
            (n, sec) => n + (pagesByKey[`${notebook.id}/${sec.id}`]?.length ?? 0),
            0,
          )
        : 0;
      patchLive({
        reading: 'done',
        readDetail: passage
          ? 'focused on the highlighted passage'
          : opts.context !== undefined
            ? 'the notes above the cursor'
            : pageCount > 1
              ? `this page and ${pageCount - 1} more in the notebook`
              : 'this page',
      });

      let webContext = '';
      let sources: Array<{ title: string; link: string }> = [];
      if (shouldSearchWeb(q, webMode) && !stopRef.current) {
        patchLive({ search: { state: 'running', query: q, count: 0 } });
        activity('Searching the web', q);
        const results = await window.mario.ai.webSearch(q);
        sources = results.map((r) => ({ title: r.title, link: r.link }));
        patchLive({ search: { state: 'done', query: q, count: results.length } });
        webContext = formatWebResults(results);
      }

      activity('Waiting for the model');
      const res = stopRef.current
        ? { text: '', reasoning: '', stopped: true }
        : await window.mario.ai.chatStream(
            {
              systemPrompt: ASK_SYSTEM_PROMPT,
              userPrompt: buildAskUserPrompt({ question: q, notes: context, passage, webContext }),
              channel: 'panel',
            },
            pushDelta,
          );

      const cur = liveRef.current ?? turn;
      const answer = (res.text || cur.answer).trim();
      const thinking = (res.reasoning || cur.thinking).trim();
      const entry = {
        id: turn.id,
        pageId: page?.id,
        question: q,
        answer: answer
          ? res.stopped
            ? `${answer}\n\n*Stopped.*`
            : answer
          : res.stopped
            ? '*Stopped before answering.*'
            : '(No response)',
        ...(passage ? { quote: passage } : {}),
        ...(sources.length ? { sources } : {}),
        ...(thinking
          ? {
              thinking,
              thinkingSeconds: cur.thinkingStart
                ? Math.max(1, Math.round(((cur.thinkingEnd ?? Date.now()) - cur.thinkingStart) / 1000))
                : undefined,
            }
          : {}),
        createdAt: new Date().toISOString(),
      };
      await updateArtifacts((prev) => ({
        ...prev,
        askHistory: [...(prev.askHistory ?? []), entry],
      }));
    } catch (err) {
      if (!stopRef.current) {
        failure = err instanceof Error ? err.message : String(err);
        setErrorMsg(failure);
      }
    } finally {
      if (liveFrame.current != null) cancelAnimationFrame(liveFrame.current);
      liveFrame.current = null;
      liveRef.current = null;
      setLive(null);
      setBusy(false);
      endActivity(failure);
    }
  };

  // Highlighting a passage opens Ask about it.
  useEffect(() => {
    if (quote) setTab('ask');
  }, [quote]);

  // The editor's AI slash commands.
  useEffect(() => {
    if (!command) return;
    if (command.kind === 'quiz') {
      setTab('quiz');
    } else if (command.kind === 'summary') {
      setTab('ask');
      void handleAskSubmit('Summarise these notes: the key takeaways, then any action items.', {
        context: command.text || undefined,
      });
    } else {
      setTab('ask');
      if (command.text) void handleAskSubmit(command.text);
      else focusComposer();
    }
  }, [command?.nonce]);

  type AskEntry = AiArtifactData['askHistory'][number];

  const insertAnswer = (entry: AskEntry) => {
    if (!page) return;
    const parts: string[] = [];
    if (entry.quote) parts.push(entry.quote.split('\n').map((l) => `> ${l}`).join('\n'));
    parts.push(`**${entry.question.replace(/([*_`])/g, '\\$1')}**`);
    parts.push(entry.answer.replace(/\n\n\*Stopped\.\*$/, ''));
    if (entry.sources?.length) {
      parts.push(entry.sources.map((src, i) => `${i + 1}. [${src.title}](${src.link})`).join('\n'));
    }
    const nodes = markdownToNodes(parts.join('\n\n'));
    const cur = latestContentRef.current;
    onPageContentChange({
      ...cur,
      // An empty line first, so the answer never runs into a quote or list above it.
      document: {
        type: 'page',
        children: [...(cur.document.children ?? []), { type: 'paragraph', data: { delta: [] } }, ...nodes],
      },
    });
    setInsertedIds((prev) => new Set(prev).add(entry.id));
  };

  const deleteAnswer = (entry: AskEntry) =>
    setConfirm({
      title: 'Delete this chat?',
      message: 'It is removed from this notebook’s AI history. The page itself is not changed.',
      confirmLabel: 'Delete',
      onConfirm: () =>
        void updateArtifacts((prev) => ({
          ...prev,
          askHistory: (prev.askHistory ?? []).filter((x) => x.id !== entry.id),
        })),
    });

  /** Copy, insert, ask again, preview, delete — under every answer. */
  const answerActions = (entry: AskEntry) => {
    const html = htmlArtifactOf(entry.answer);
    const inserted = insertedIds.has(entry.id);
    const meta = [
      relativeTime(entry.createdAt),
      page && entry.pageId && entry.pageId !== page.id ? 'another page' : '',
      entry.sources?.length ? 'web' : '',
    ]
      .filter(Boolean)
      .join(' · ');
    return (
      <div className="mario-answer-actions">
        <span className="mario-answer-actions__meta">{meta}</span>
        <Spacer />
        {html && (
          <Button size="small" variant="borderless" icon="play" label="Preview HTML" onClick={() => onSetRawHtmlOverride(html)} />
        )}
        <Button
          size="small"
          variant="borderless"
          icon={inserted ? 'checkmark' : 'square-and-arrow-down'}
          label={inserted ? 'Inserted into the Page' : page ? 'Insert into Page' : 'Open a page to insert into it'}
          disabled={!page || inserted}
          onClick={() => insertAnswer(entry)}
        />
        <Button
          size="small"
          variant="borderless"
          icon="doc-on-doc"
          label="Copy Answer"
          onClick={() => void navigator.clipboard?.writeText(entry.answer)}
        />
        <Button
          size="small"
          variant="borderless"
          icon="arrow-clockwise"
          label="Ask Again"
          disabled={busy}
          onClick={() => void handleAskSubmit(entry.question, { passage: entry.quote ?? null })}
        />
        <Button size="small" variant="borderless" icon="trash" label="Delete This Chat" onClick={() => deleteAnswer(entry)} />
      </div>
    );
  };

  const handleSummarise = async () => {
    await handleAskSubmit(
      page
        ? `Summarise the current page "${page.title}" with key takeaways and action items.`
        : 'Summarise all notes in this notebook.',
    );
  };

  // --- Quiz Tab Handler ---
  const handleGenerateQuiz = async () => {
    if (busy || mcqCount + essayCount === 0) return;
    stopRef.current = false;
    setBusy(true);
    setErrorMsg(null);
    activity('Reading the notes');
    let failure: string | null = null;
    try {
      const context = await gatherNotebookContext();
      const { result: raw } = await streamStructured(
        {
          schemaName: 'quiz',
          schema: quizSchema(mcqCount, essayCount),
          systemPrompt: QUIZ_SYSTEM_PROMPT,
          userPrompt: quizUserPrompt(context || page?.title || 'General study notes', mcqCount, essayCount),
        },
        'Writing the quiz…',
        'quiz',
      );
      const { quiz, dropped } = validateQuiz(raw);
      if (quiz.mcqs.length + quiz.essays.length === 0) {
        throw new Error(
          dropped.length
            ? `None of the model’s questions could be marked (${Array.from(new Set(dropped)).join(', ')}). Try again.`
            : 'The model did not write any questions. Try again.',
        );
      }
      setQuizAnswers({});
      setEssayAnswers({});
      setQuizChecked(false);
      const quizEntry: QuizEntry = {
        id: newClientId('quiz'),
        pageId: page?.id,
        quiz,
        createdAt: new Date().toISOString(),
      };
      setOpenQuizId(quizEntry.id);
      await updateArtifacts((prev) => ({
        ...prev,
        quizzes: [quizEntry, ...(prev.quizzes ?? [])],
      }));
    } catch (err) {
      if (!stopRef.current) {
        failure = err instanceof Error ? err.message : String(err);
        setErrorMsg(failure);
      }
    } finally {
      setBusy(false);
      endActivity(failure);
    }
  };

  /**
   * Check Answers / Submit for Marking. Multiple choice is marked here; each written
   * essay goes to the model against its rubric, and its mark is a draft the student can change.
   * Stop keeps the marks made so far.
   */
  const submitQuiz = async (onlyUnmarked = false) => {
    const entry = openQuizEntry;
    if (!entry || busy) return;
    const { quiz } = entry;
    const grades: Record<number, QuizGrade> = onlyUnmarked ? { ...(entry.essayGrades ?? {}) } : {};
    const toMark = quiz.essays
      .map((essay, i) => ({ essay, i, answer: (essayAnswers[i] ?? '').trim() }))
      .filter(({ i }) => !(onlyUnmarked && grades[i]));
    const save = (checkedAt = new Date().toISOString()) => {
      const score = quizScore(quiz, quizAnswers, grades);
      return updateArtifacts((prev) => ({
        ...prev,
        quizzes: (prev.quizzes ?? []).map((q) =>
          q.id === entry.id
            ? { ...q, answers: quizAnswers, essayAnswers, essayGrades: { ...grades }, score: score.awarded, outOf: score.outOf, checkedAt }
            : q,
        ),
      }));
    };
    for (const { essay, i, answer } of toMark) if (!answer) grades[i] = blankGrade(essay);
    const written = toMark.filter(({ answer }) => answer);
    if (written.length === 0) {
      await save();
      setQuizChecked(true);
      return;
    }

    stopRef.current = false;
    setBusy(true);
    setErrorMsg(null);
    let failure: string | null = null;
    try {
      for (let k = 0; k < written.length && !stopRef.current; k++) {
        const { essay, i, answer } = written[k];
        setMarking({ done: k, total: written.length });
        const { result } = await streamStructured(
          {
            schemaName: 'grade',
            schema: gradeSchema,
            systemPrompt: GRADING_SYSTEM_PROMPT,
            userPrompt: gradingPrompt(essay, answer),
            temperature: 0.1,
          },
          'Marking…',
          'quiz',
          `${k + 1} of ${written.length}`,
        );
        grades[i] = parseGrade(result, essay);
      }
    } catch (err) {
      if (!stopRef.current) {
        failure = err instanceof Error ? err.message : String(err);
        setErrorMsg(failure);
      }
    } finally {
      setMarking(null);
      await save();
      setQuizChecked(true);
      setBusy(false);
      endActivity(failure);
    }
  };

  /** The student's own mark for an essay, replacing the model's draft. */
  const overrideEssayMark = (essayIndex: number, mark: number) => {
    const entry = openQuizEntry;
    const grade = entry?.essayGrades?.[essayIndex];
    if (!entry || !grade) return;
    const grades = { ...entry.essayGrades, [essayIndex]: { ...grade, override: mark } };
    const score = quizScore(entry.quiz, entry.answers ?? quizAnswers, grades);
    void updateArtifacts((prev) => ({
      ...prev,
      quizzes: (prev.quizzes ?? []).map((q) =>
        q.id === entry.id ? { ...q, essayGrades: grades, score: score.awarded, outOf: score.outOf } : q,
      ),
    }));
  };

  // --- Writing Tab Handler ---
  const handleCheckWriting = async () => {
    if (busy || !page) return;
    stopRef.current = false;
    setBusy(true);
    setErrorMsg(null);
    try {
      const md = documentToMarkdown(latestContentRef.current.document);
      const { result: raw } = await streamStructured(
        {
          schemaName: 'grammar_review',
          schema: grammarSchema,
          systemPrompt:
            'Review the user’s note for grammar, spelling, clarity, and conciseness. Return exact substrings from the text in `original` and improved text in `suggestion`.',
          userPrompt: md || page.title,
        },
        'Checking the writing…',
        'write',
      );
      const suggestions = Array.isArray(raw.suggestions)
        ? (raw.suggestions as GrammarSuggestion[])
        : [];
      setGrammarIssues(suggestions);
      setWritingChecked(true);
      endActivity();
    } catch (err) {
      const failure = stopRef.current ? null : err instanceof Error ? err.message : String(err);
      if (failure) setErrorMsg(failure);
      endActivity(failure);
    } finally {
      setBusy(false);
    }
  };

  const applyGrammarSuggestion = (issue: GrammarSuggestion) => {
    const nextChildren = latestContentRef.current.document.children.map(
      (node) => {
        const md = deltaToMarkdown(node.data?.delta);
        if (!md.includes(issue.original)) return node;
        const replaced = md.replace(issue.original, issue.suggestion);
        return {
          ...node,
          data: {
            ...node.data,
            delta: parseInlineMarkdownToDelta(replaced),
          },
        };
      },
    );
    onPageContentChange({
      ...latestContentRef.current,
      document: { type: 'page', children: nextChildren },
    });
    setGrammarIssues((prev) => prev.filter((x) => x !== issue));
  };

  // --- Do Tab (Mario Agent Loop) ---
  // Inserts in one plan that name the same anchor follow each other in plan order,
  // instead of each landing straight after the anchor (which reverses them).
  const insertChainRef = useRef(new Map<string, string>());

  const executeSingleAction = async (
    action: AgentAction,
  ): Promise<{ summary: string; observation?: string }> => {
    const curDoc = latestContentRef.current.document;
    const nodes = [...(curDoc.children ?? [])];
    const commit = (nextNodes: AppFlowyNode[]) => {
      const next: PageContent = {
        ...latestContentRef.current,
        document: { type: 'page', children: nextNodes },
      };
      latestContentRef.current = next;
      onPageContentChange(next);
    };

    const resolveInsertIndex = (afterBlockId?: string): number => {
      if (afterBlockId) {
        const i = nodes.findIndex((n) => n.id === afterBlockId);
        return i >= 0 ? i + 1 : nodes.length;
      }
      return nodes.length;
    };
    const insert = (afterBlockId: string | undefined, created: AppFlowyNode[]) => {
      const chained = afterBlockId ? insertChainRef.current.get(afterBlockId) : undefined;
      const anchor = chained && nodes.some((n) => n.id === chained) ? chained : afterBlockId;
      nodes.splice(resolveInsertIndex(anchor), 0, ...created);
      const last = created[created.length - 1];
      if (afterBlockId && last?.id) insertChainRef.current.set(afterBlockId, last.id);
    };

    switch (action.kind) {
      case 'paragraph': {
        const n = makeParagraphNode(action.text ?? '');
        insert(action.afterBlockId, [n]);
        commit(nodes);
        return { summary: 'Inserted paragraph' };
      }
      case 'heading': {
        const n = makeHeadingNode(action.level ?? 2, action.text ?? '');
        insert(action.afterBlockId, [n]);
        commit(nodes);
        return { summary: `Inserted heading "${action.text ?? ''}"` };
      }
      case 'bullets':
      case 'numbered':
      case 'todo': {
        const listType =
          action.kind === 'bullets'
            ? 'bulleted_list'
            : action.kind === 'numbered'
            ? 'numbered_list'
            : 'todo_list';
        const created = (action.items ?? []).map((it) =>
          makeListNode(listType, it, false),
        );
        insert(action.afterBlockId, created);
        commit(nodes);
        return { summary: `Inserted ${created.length} ${action.kind} item(s)` };
      }
      case 'quote': {
        const n = makeQuoteNode(action.text ?? '');
        insert(action.afterBlockId, [n]);
        commit(nodes);
        return { summary: 'Inserted quote block' };
      }
      case 'divider': {
        const n = makeDividerNode();
        insert(action.afterBlockId, [n]);
        commit(nodes);
        return { summary: 'Inserted divider' };
      }
      case 'code': {
        const n = makeCodeNode(action.text ?? '', action.language ?? 'python');
        insert(action.afterBlockId, [n]);
        commit(nodes);
        return {
          summary: `Inserted ${action.language ?? 'code'} block`,
        };
      }
      case 'math': {
        const n = makeMathNode(action.text ?? '');
        insert(action.afterBlockId, [n]);
        commit(nodes);
        return { summary: 'Inserted LaTeX equation' };
      }
      case 'table': {
        const n = makeTableNode(action.rows ?? [['', '']]);
        insert(action.afterBlockId, [n]);
        commit(nodes);
        return {
          summary: `Inserted ${(action.rows ?? []).length}-row table`,
        };
      }
      case 'spreadsheet': {
        const rows = action.rows ?? [];
        const cells: Record<string, string> = {};
        let maxCols = 3;
        rows.forEach((r, ri) => {
          maxCols = Math.max(maxCols, r.length);
          r.forEach((c, ci) => {
            if (c !== '') cells[`${colIndexToLabel(ci)}${ri + 1}`] = String(c);
          });
        });
        const sb = makeSpreadsheetNode({
          activeIndex: 0,
          sheets: [
            {
              name: action.text || 'Sheet1',
              rows: Math.max(4, rows.length + 1),
              cols: maxCols,
              cells,
            },
          ],
        });
        insert(action.afterBlockId, [sb]);
        commit(nodes);
        return { summary: `Inserted spreadsheet "${action.text || 'Sheet1'}"` };
      }
      case 'markdown': {
        const created = markdownToNodes(action.text ?? action.content ?? '');
        insert(action.afterBlockId, created);
        commit(nodes);
        return { summary: `Inserted ${created.length} Markdown block(s)` };
      }
      case 'replace_block': {
        const created = markdownToNodes(action.text ?? '');
        const i = nodes.findIndex((n) => n.id === action.blockId);
        if (i >= 0 && created.length > 0) {
          created[0].id = action.blockId;
          nodes.splice(i, 1, ...created);
          commit(nodes);
          return { summary: `Updated block [${action.blockId}]` };
        }
        return { summary: `Block [${action.blockId}] not found` };
      }
      case 'delete_block': {
        const next = nodes.filter((n) => n.id !== action.blockId);
        commit(next);
        return { summary: `Deleted block [${action.blockId}]` };
      }
      case 'move_block': {
        const fromIdx = nodes.findIndex((n) => n.id === action.blockId);
        if (fromIdx >= 0) {
          const [moved] = nodes.splice(fromIdx, 1);
          const toIdx = resolveInsertIndex(action.afterBlockId);
          nodes.splice(toIdx, 0, moved);
          commit(nodes);
        }
        return { summary: `Moved block [${action.blockId}]` };
      }
      case 'html': {
        onSetRawHtmlOverride(action.text ?? action.content ?? '');
        return { summary: 'Rendered interactive HTML preview' };
      }
      case 'rename_page': {
        await onRenameCurrentPage(action.text ?? 'Untitled Page');
        return { summary: `Renamed page to "${action.text}"` };
      }
      case 'write_page': {
        const md = action.content ?? action.text ?? '';
        const newNodes = markdownToNodes(md);
        if (action.mode === 'replace') {
          commit(newNodes);
        } else if (action.mode === 'prepend') {
          commit([...newNodes, ...nodes]);
        } else {
          commit([...nodes, ...newNodes]);
        }
        return { summary: `Wrote ${newNodes.length} block(s) to page` };
      }
      case 'web_search': {
        const q = action.text ?? '';
        const results = await window.mario.ai.webSearch(q);
        const formatted =
          results.length === 0
            ? 'No results found.'
            : results
                .map((r, i) => `[${i + 1}] ${r.title} (${r.link})\n${r.snippet}`)
                .join('\n\n');
        return {
          summary: `Searched web for "${q}" (${results.length} results)`,
          observation: `web_search("${q}"):\n${formatted}`,
        };
      }
      case 'list_notebooks': {
        const list = notebooks
          .map((n) => {
            const secs = (sectionsByNotebook[n.id] ?? [])
              .map((s) => s.name)
              .join(', ');
            return `- ${n.name} (id: ${n.id}) [Sections: ${secs}]`;
          })
          .join('\n');
        return {
          summary: `Listed ${notebooks.length} notebooks`,
          observation: `Notebooks:\n${list}`,
        };
      }
      case 'list_pages': {
        const nb =
          notebooks.find(
            (n) =>
              n.id === action.notebook ||
              n.name.toLowerCase() === (action.notebook ?? '').toLowerCase(),
          ) ?? notebook;
        const secs = nb ? sectionsByNotebook[nb.id] ?? [] : [];
        const sec =
          secs.find(
            (s) =>
              s.id === action.section ||
              s.name.toLowerCase() === (action.section ?? '').toLowerCase(),
          ) ?? section;
        const pgs = nb && sec ? pagesByKey[`${nb.id}/${sec.id}`] ?? [] : [];
        const list = pgs.map((p) => `- ${p.title} (id: ${p.id})`).join('\n');
        return {
          summary: `Listed ${pgs.length} pages`,
          observation: `Pages:\n${list}`,
        };
      }
      case 'read_page': {
        const target = (action.page ?? action.text ?? '').toLowerCase();
        for (const nb of notebooks) {
          for (const sec of sectionsByNotebook[nb.id] ?? []) {
            for (const pg of pagesByKey[`${nb.id}/${sec.id}`] ?? []) {
              if (pg.id === target || pg.title.toLowerCase() === target) {
                const loaded = await window.mario.page.loadContent(
                  pg.id,
                  pg.driveFileId,
                  pg.title,
                );
                const md = documentToMarkdown(loaded.document);
                return {
                  summary: `Read page "${pg.title}"`,
                  observation: `Page "${pg.title}" (${pg.id}):\n${md}`,
                };
              }
            }
          }
        }
        return {
          summary: `Page "${target}" not found`,
          observation: `Page "${target}" not found.`,
        };
      }
      case 'search_notes': {
        const q = (action.text ?? '').toLowerCase();
        const hits: string[] = [];
        for (const nb of notebooks) {
          for (const sec of sectionsByNotebook[nb.id] ?? []) {
            for (const pg of pagesByKey[`${nb.id}/${sec.id}`] ?? []) {
              const loaded = await window.mario.page.loadContent(
                pg.id,
                pg.driveFileId,
                pg.title,
              );
              const md = documentToMarkdown(loaded.document);
              if (
                pg.title.toLowerCase().includes(q) ||
                md.toLowerCase().includes(q)
              ) {
                hits.push(
                  `- ${nb.name} / ${sec.name} / ${pg.title} (${pg.id}): ${md
                    .slice(0, 200)
                    .replace(/\n+/g, ' ')}`,
                );
              }
            }
          }
        }
        return {
          summary: `Searched notes for "${q}" (${hits.length} matches)`,
          observation:
            hits.length > 0 ? hits.join('\n') : 'No matching notes found.',
        };
      }
      case 'create_notebook': {
        const created = await onCreateNotebook(action.text ?? 'New Notebook');
        return {
          summary: `Created notebook "${created.name}"`,
          observation: `Created notebook id=${created.id}`,
        };
      }
      case 'create_section': {
        const nb =
          notebooks.find(
            (n) =>
              n.id === action.notebook ||
              n.name.toLowerCase() === (action.notebook ?? '').toLowerCase(),
          ) ?? notebook;
        if (nb) {
          const sec = await onCreateSection(
            nb.id,
            action.text ?? action.section ?? 'New Section',
          );
          return {
            summary: `Created section "${sec.name}"`,
            observation: `Created section id=${sec.id}`,
          };
        }
        return { summary: 'No target notebook found' };
      }
      case 'rename_section': {
        if (section && action.text) {
          await onRenameSection(section, action.text);
        }
        return { summary: `Renamed section to "${action.text}"` };
      }
      case 'create_page': {
        const targetNb =
          notebooks.find(
            (n) =>
              n.id === action.notebook ||
              n.name.toLowerCase() === (action.notebook ?? '').toLowerCase(),
          ) ?? notebook;
        const secs = targetNb ? sectionsByNotebook[targetNb.id] ?? [] : [];
        const targetSec =
          secs.find(
            (s) =>
              s.id === action.section ||
              s.name.toLowerCase() === (action.section ?? '').toLowerCase(),
          ) ??
          section ??
          secs[0];
        if (targetNb && targetSec) {
          const title = action.page ?? action.text ?? 'Untitled Page';
          const initDoc: PageContent | undefined = action.content
            ? {
                title,
                document: markdownToDocument(action.content),
              }
            : undefined;
          const created = await onCreatePage(
            targetNb.id,
            targetSec.id,
            title,
            initDoc,
          );
          onOpenPage(targetNb.id, targetSec.id, created.id);
          return {
            summary: `Created page "${created.title}"`,
            observation: `Created page id=${created.id}`,
          };
        }
        return { summary: 'No target section found for create_page' };
      }
      case 'open_page': {
        const target = (action.page ?? action.text ?? '').toLowerCase();
        for (const nb of notebooks) {
          for (const sec of sectionsByNotebook[nb.id] ?? []) {
            for (const pg of pagesByKey[`${nb.id}/${sec.id}`] ?? []) {
              if (pg.id === target || pg.title.toLowerCase() === target) {
                onOpenPage(nb.id, sec.id, pg.id);
                return { summary: `Opened page "${pg.title}"` };
              }
            }
          }
        }
        return { summary: `Page "${target}" not found` };
      }
      case 'ask_user':
      case 'setting':
      default:
        return { summary: action.text ?? `Completed ${action.kind}` };
    }
  };

  const handleRunDoAgent = async (customGoal?: string) => {
    const goal = (customGoal ?? promptText).trim();
    if (!goal || busy) return;
    if (!customGoal) setPromptText('');
    stopRef.current = false;
    setBusy(true);
    setErrorMsg(null);
    setUndoSnapshot(structuredClone(latestContentRef.current));
    scrollRef.current?.scrollTo({ top: 0 });

    const stepsLog: AgentStepLog[] = [];
    let finalSummary = '';
    const thoughts: string[] = [];
    let thinkingSeconds = 0;
    let failed: string | null = null;
    let discarded = false;
    const show = () => setDoLive({ instruction: goal, steps: [...stepsLog], summary: finalSummary });
    show();
    activity('Reading the page');

    try {
      const userSkills = await window.mario.ai.getUserSkills();
      const includeHtml =
        /\b(html|preview|widget|interactive|chart|diagram|mockup)\b/i.test(
          goal,
        );
      const systemPrompt = marioAgentPrompt(userSkills, includeHtml);
      const observations: string[] = [];

      for (let turn = 0; turn < 5 && !stopRef.current; turn++) {
        const curNodes = latestContentRef.current.document.children ?? [];
        const knownIds = curNodes
          .map((n) => n.id)
          .filter((id): id is string => Boolean(id));
        const pagePrompt = renderBlocksForPrompt(
          latestContentRef.current.document,
        );

        const obsSection =
          observations.length > 0
            ? `\n\nPrevious Tool Observations:\n${observations.join('\n\n')}\n\nNow produce the final actions or summary.`
            : '';

        const planned = await streamStructured(
          {
            schemaName: 'agent_plan',
            schema: agentPlanSchema,
            systemPrompt,
            userPrompt: `Active Notebook: ${notebook?.name ?? 'None'} (${
              notebook?.id ?? ''
            })\nActive Section: ${section?.name ?? 'None'} (${
              section?.id ?? ''
            })\nActive Page Title: ${
              page?.title ?? 'Untitled'
            }\n\nCurrent Page Blocks:\n${pagePrompt}${obsSection}\n\nUser Instruction: ${goal}`,
          },
          turn === 0 ? 'Planning the changes…' : 'Planning the next step…',
          'do',
        );
        if (stopRef.current) break;
        if (planned.thinking) thoughts.push(planned.thinking);
        thinkingSeconds += planned.seconds ?? 0;

        const plan = parseAgentPlan(planned.result, new Set(knownIds));
        if (plan.summary) finalSummary = plan.summary;
        show();

        if (plan.actions.length === 0) {
          break;
        }

        // Preview Before Writing: nothing is changed until the plan is approved.
        if (previewBeforeWriting && planWrites(plan.actions)) {
          activity('Waiting for you', 'review the preview, then apply or discard');
          setPendingPlan(plan);
          const apply = await new Promise<boolean>((resolve) => {
            pendingPlanResolve.current = resolve;
          });
          pendingPlanResolve.current = null;
          setPendingPlan(null);
          if (!apply) {
            discarded = true;
            break;
          }
        }

        let needsFollowUpTurn = false;
        insertChainRef.current.clear();
        for (const act of plan.actions) {
          if (stopRef.current) break;
          const stepId = `${turn}-${stepsLog.length}`;
          stepsLog.push({
            id: stepId,
            kind: act.kind,
            summary: `Running ${act.kind}…`,
            status: 'running',
          });
          show();
          activity(
            'Applying',
            `${plan.actions.indexOf(act) + 1} of ${plan.actions.length} — ${describeAgentAction(act, blockText).text}`,
          );

          const res = await executeSingleAction(act);
          stepsLog[stepsLog.length - 1] = {
            id: stepId,
            kind: act.kind,
            summary: res.summary,
            status: 'done',
          };
          show();
          if (res.observation || OBSERVING_KINDS.has(act.kind)) {
            if (res.observation) observations.push(res.observation);
            needsFollowUpTurn = !plan.done;
          }
        }

        if (!needsFollowUpTurn) {
          break;
        }
      }
    } catch (err) {
      if (!stopRef.current) {
        failed = err instanceof Error ? err.message : String(err);
        setErrorMsg(failed);
      }
    } finally {
      const summary = stopRef.current
        ? 'Stopped.'
        : failed
          ? `Failed: ${failed}`
          : discarded
            ? 'Preview discarded. No changes were applied.'
            : finalSummary || (stepsLog.length ? 'Completed actions on your note.' : 'Nothing to change.');
      if (discarded && stepsLog.length === 0) setUndoSnapshot(null);
      const run = {
        id: newClientId('do'),
        pageId: page?.id,
        instruction: goal,
        summary,
        steps: stepsLog.map((st) => `${st.kind}: ${st.summary}`),
        ...(thoughts.length ? { thinking: thoughts.join('\n\n---\n\n'), thinkingSeconds: thinkingSeconds || undefined } : {}),
        createdAt: new Date().toISOString(),
      };
      void updateArtifacts((prev) => ({ ...prev, doHistory: [...(prev.doHistory ?? []), run] }));
      setDoLive(null);
      setPendingPlan(null);
      setBusy(false);
      endActivity(failed);
    }
  };

  /** A block's text, for describing an action that names it. */
  const blockText = (id: string): string | undefined => {
    const node = (latestContentRef.current.document.children ?? []).find((n) => n.id === id);
    if (!node) return undefined;
    const text = (node.data?.delta ?? [])
      .map((op) => (typeof op.insert === 'string' ? op.insert : ''))
      .join('')
      .trim();
    return text || node.type.replace(/_/g, ' ');
  };

  const orderedDoHistory = useMemo(() => {
    const newestFirst = [...(artifacts.doHistory ?? [])].reverse();
    if (!page) return newestFirst;
    return [...newestFirst.filter((e) => e.pageId === page.id), ...newestFirst.filter((e) => e.pageId !== page.id)];
  }, [artifacts.doHistory, page?.id]);

  const openQuizEntry =
    (artifacts.quizzes ?? []).find((q) => q.id === openQuizId) ?? (artifacts.quizzes ?? [])[0] ?? null;
  const openQuiz = openQuizEntry?.quiz ?? null;

  const openQuizGrades = openQuizEntry?.essayGrades ?? {};
  const openQuizScore = openQuiz ? quizScore(openQuiz, quizAnswers, openQuizGrades) : null;
  const answeredCount =
    Object.keys(quizAnswers).length + Object.values(essayAnswers).filter((a) => a.trim()).length;
  const orderedAskHistory = useMemo(() => {
    const newestFirst = [...(artifacts.askHistory ?? [])].reverse();
    if (!page) return newestFirst;
    return [...newestFirst.filter((e) => e.pageId === page.id), ...newestFirst.filter((e) => e.pageId !== page.id)];
  }, [artifacts.askHistory, page?.id]);

  return (
    <div className="mario-inspector-wrap">
      <div
        className="mario-inspector-resizer"
        onPointerDown={(e) => {
          e.preventDefault();
          draggingRef.current = true;
          const startX = e.clientX;
          const startW = width;
          const onMove = (ev: PointerEvent) => {
            if (!draggingRef.current) return;
            const delta = startX - ev.clientX;
            setWidth(Math.max(260, Math.min(540, startW + delta)));
          };
          const onUp = () => {
            draggingRef.current = false;
            window.removeEventListener('pointermove', onMove);
            window.removeEventListener('pointerup', onUp);
          };
          window.addEventListener('pointermove', onMove);
          window.addEventListener('pointerup', onUp);
        }}
      />

      <Inspector width={width} label="AI Assistant" className="mario-ai-pane">
        <div className="mario-ai-header">
          {providers.length > 0 && activeProvider ? (
            <div className="mario-ai-models">
              {/* One model picker: the models of every provider, grouped under the provider's name. */}
              <PopUpButton
                size="small"
                aria-label="Model"
                title={`${activeGroup?.name ?? providerName(activeProvider)} · ${activeProvider.model || 'default model'}`}
                className="mario-ai-models__model"
                value={modelKey(activeGroup?.key ?? activeProvider.id, activeProvider.model)}
                onChange={async (key) => {
                  const [groupKey, model] = key.split(MODEL_KEY_SEP);
                  const group = modelGroups.find((g) => g.key === groupKey);
                  if (!group) return;
                  // Stay on the active provider when it serves this group; else one that already uses the model.
                  const target =
                    group.providers.find((p) => p.id === activeProvider.id) ??
                    group.providers.find((p) => p.model === model) ??
                    group.providers[0];
                  if (target.id !== activeProvider.id) {
                    const next = await window.mario.ai.setActiveProvider(target.id);
                    setProviders(next.providers);
                    setActiveProviderId(next.activeId);
                  }
                  if (model && model !== target.model) {
                    const next = await window.mario.ai.setProviderModel(target.id, model, target.effort);
                    setProviders(next.providers);
                  }
                }}
                options={modelGroups.flatMap((g, i) =>
                  g.models.map((m, j) => ({
                    value: modelKey(g.key, m),
                    label: m || 'Default model',
                    headerAbove: j === 0 ? g.name : undefined,
                    separatorAbove: j === 0 && i > 0,
                  })),
                )}
              />
              <PopUpButton
                size="small"
                aria-label="Reasoning Effort"
                title="Reasoning effort"
                className="mario-ai-models__effort"
                value={activeProvider.effort}
                onChange={async (eff) => {
                  const next = await window.mario.ai.setProviderModel(
                    activeProvider.id,
                    activeProvider.model,
                    eff as LlmEffort,
                  );
                  setProviders(next.providers);
                }}
                options={[
                  { value: 'off', label: 'Off' },
                  { value: 'low', label: 'Low' },
                  { value: 'medium', label: 'Med' },
                  { value: 'high', label: 'High' },
                ]}
              />
            </div>
          ) : (
            <Row>
              <Button
                size="small"
                variant="tinted"
                icon="bolt"
                onClick={onOpenAiSettings}
              >
                Configure AI Provider…
              </Button>
            </Row>
          )}

          <ModelActivityLine />

          <SegmentedControl
            size="small"
            equal
            label="AI Mode"
            value={tab}
            onChange={(v) => setTab(v as AiTab)}
            options={[
              { value: 'ask', label: 'Ask' },
              { value: 'quiz', label: 'Quiz' },
              { value: 'write', label: 'Writing' },
              { value: 'do', label: 'Do' },
            ]}
          />
        </div>

        {/* Scrollable Body per Tab */}
        <div
          ref={scrollRef}
          className="mario-ai-scroll mac-scroll"
          onScroll={(e) => {
            if (!liveRef.current) return;
            const el = e.currentTarget;
            followRef.current = liveBottomIn(el) <= el.scrollTop + el.clientHeight + 40;
          }}
        >
          {errorMsg && (
            <div
              className="mac-groupbox"
              style={{ borderColor: 'var(--mac-accent-red)' }}
            >
              <p className="mac-footnote mac-label-red" style={{ margin: 0 }}>
                {errorMsg}
              </p>
            </div>
          )}

          {tab === 'ask' && (
            <>
              {/* The exchange in progress comes first, its thinking on top, as `ollama run` prints it. */}
              {live && (
                <>
                  <div className="mario-chat-msg mario-chat-msg--user">
                    {live.quote && <div className="mario-chat-quote">{live.quote}</div>}
                    {live.question}
                  </div>
                  <div ref={liveBubbleRef} className="mario-chat-msg mario-chat-msg--assistant">
                    <LiveSteps live={live} />
                    {live.reading === 'done' && live.search?.state !== 'running' && <LiveThinking live={live} />}
                    {live.answer.trim() && (
                      <div
                        className="mario-md-body"
                        dangerouslySetInnerHTML={{ __html: renderMarkdownHtml(live.answer.trimStart()) }}
                      />
                    )}
                  </div>
                </>
              )}
              {(artifacts.askHistory ?? []).length === 0 && !live ? (
                <EmptyState
                  icon="bubble-left"
                  title="Ask Mario AI"
                  message="Ask questions across this notebook or summarise the active page."
                  actions={
                    <Button
                      size="small"
                      variant="bordered"
                      onClick={handleSummarise}
                      disabled={busy}
                    >
                      Summarise Page
                    </Button>
                  }
                />
              ) : (
                <>
                  {orderedAskHistory.length > 0 && <h3 className="mario-ai-list-title">Earlier Questions</h3>}
                  {/* The chat list: this page's chats first, newest first; the newest is open. */}
                  {orderedAskHistory.map((turn, idx) => (
                    <div key={turn.id} className="mario-ai-item">
                      <Disclosure
                        defaultOpen={idx === 0}
                        title={
                          <span className="mario-ai-item__head">
                            <span className="mario-ai-item__title">{turn.question}</span>
                            <span className="mario-ai-item__meta">
                              {[
                                relativeTime(turn.createdAt),
                                page && turn.pageId && turn.pageId !== page.id ? 'another page' : '',
                                turn.quote ? 'about a highlight' : '',
                                turn.sources?.length ? 'web' : '',
                              ]
                                .filter(Boolean)
                                .join(' · ')}
                            </span>
                          </span>
                        }
                      >
                        <div className="mario-chat-msg mario-chat-msg--assistant">
                          {turn.quote && <div className="mario-chat-quote mario-chat-quote--plain">{turn.quote}</div>}
                          {turn.thinking && (
                            <div className="mario-thoughts">
                              <Disclosure title={turn.thinkingSeconds ? `Thought for ${turn.thinkingSeconds} s` : 'Thoughts'}>
                                <div
                                  className="mario-thinking mario-md-body"
                                  dangerouslySetInnerHTML={{ __html: renderMarkdownHtml(turn.thinking) }}
                                />
                              </Disclosure>
                            </div>
                          )}
                          <div className="mario-md-body" dangerouslySetInnerHTML={{ __html: renderMarkdownHtml(turn.answer) }} />
                          {turn.sources && turn.sources.length > 0 && (
                            <div className="mario-thoughts">
                              <Disclosure
                                title={`Answered using ${turn.sources.length} web source${turn.sources.length === 1 ? '' : 's'}`}
                              >
                                <ol className="mario-sources">
                                  {turn.sources.map((src, i) => (
                                    <li key={i}>
                                      <a href={src.link} target="_blank" rel="noopener noreferrer">
                                        {src.title || src.link}
                                      </a>
                                    </li>
                                  ))}
                                </ol>
                              </Disclosure>
                            </div>
                          )}
                          {answerActions(turn)}
                        </div>
                      </Disclosure>
                    </div>
                  ))}
                </>
              )}
            </>
          )}

          {tab === 'quiz' && (
            <Column style={{ gap: 12 }}>
              <Form className="mario-quiz-setup">
                <FormSection title="New Quiz">
                  <FormRow label="Multiple Choice">
                    <Stepper size="small" min={0} max={20} value={mcqCount} onChange={setMcqCount} label="Multiple-choice questions" />
                  </FormRow>
                  <FormRow label="Essay Questions" subtitle="Marked by the model as a draft">
                    <Stepper size="small" min={0} max={5} value={essayCount} onChange={setEssayCount} label="Essay questions" />
                  </FormRow>
                </FormSection>
              </Form>
              <Row>
                <Spacer />
                {busy && !marking ? (
                  <Button size="small" icon="stop" onClick={handleStop}>
                    Stop
                  </Button>
                ) : (
                  <Button
                    size="small"
                    variant="prominent"
                    disabled={busy || mcqCount + essayCount === 0}
                    onClick={handleGenerateQuiz}
                  >
                    Generate Quiz
                  </Button>
                )}
              </Row>

              {taskLive?.owner === 'quiz' && !marking && (
                <div className="mario-chat-msg mario-chat-msg--assistant">
                  <LiveThinking live={taskLive} />
                </div>
              )}

              {openQuiz && openQuizEntry ? (
                <div className="mario-quiz">
                  <div className="mario-quiz__head">
                    <span className="mario-quiz__title">{openQuiz.title || 'Quiz'}</span>
                    <span className="mario-ai-item__meta">
                      {[
                        `${openQuiz.mcqs.length + openQuiz.essays.length} questions`,
                        openQuiz.essays.length ? `${openQuiz.essays.length} essay${openQuiz.essays.length === 1 ? '' : 's'}` : '',
                        relativeTime(openQuizEntry.createdAt),
                      ]
                        .filter(Boolean)
                        .join(' · ')}
                    </span>
                  </div>

                  {quizChecked && openQuizScore && (
                    <GroupBox className="mario-quiz__banner">
                      <div className="mario-quiz__banner-row">
                        <span className="mario-quiz__banner-mark">{formatMark(openQuizScore.awarded)}</span>
                        <span className="mario-quiz__banner-of">/ {openQuizScore.outOf}</span>
                        <Spacer />
                        <span className="mario-quiz__banner-pct">
                          {openQuizScore.outOf ? Math.round((openQuizScore.awarded / openQuizScore.outOf) * 100) : 0}%
                        </span>
                      </div>
                      <ProgressBar
                        value={openQuizScore.awarded}
                        max={Math.max(1, openQuizScore.outOf)}
                        label="Score"
                      />
                      {openQuizScore.provisional && (
                        <p className="mac-caption-1 mac-label-secondary mario-quiz__note">
                          Essay marks are a draft from the model, not a result. Check the rubric points below and change any
                          mark you disagree with.
                        </p>
                      )}
                    </GroupBox>
                  )}

                  {openQuiz.mcqs.map((q, qIdx) => {
                    const chosen = quizAnswers[qIdx];
                    const right = chosen === q.correctIndex;
                    return (
                      <div key={`m${qIdx}`} className="mac-groupbox mario-quiz__question">
                        <p className="mario-quiz__prompt">
                          <span className="mario-quiz__number">{qIdx + 1}.</span>
                          <span dangerouslySetInnerHTML={{ __html: renderInlineMd(q.question) }} />
                        </p>
                        <RadioGroup
                          label={`Question ${qIdx + 1}`}
                          value={chosen === undefined ? undefined : String(chosen)}
                          disabled={quizChecked || busy}
                          onChange={(v) => setQuizAnswers((prev) => ({ ...prev, [qIdx]: Number(v) }))}
                          options={q.options.map((opt, oIdx) => ({ value: String(oIdx), label: opt }))}
                        />
                        {quizChecked && (
                          <p className="mario-quiz__result">
                            {right ? (
                              <span className="mac-label-green">
                                <Icon name="checkmark-circle-fill" /> Correct
                              </span>
                            ) : (
                              <span className="mac-label-red">
                                <Icon name="xmark-circle-fill" /> {chosen === undefined ? 'Not answered' : 'Incorrect'}
                              </span>
                            )}
                            {!right && <span> — the answer is “{q.options[q.correctIndex]}”.</span>}
                          </p>
                        )}
                        {quizChecked && q.explanation && (
                          <p className="mac-caption-1 mac-label-secondary" style={{ margin: '4px 0 0' }}>
                            {q.explanation}
                          </p>
                        )}
                      </div>
                    );
                  })}

                  {openQuiz.essays.map((essay, eIdx) => {
                    const n = openQuiz.mcqs.length + eIdx + 1;
                    const grade = openQuizGrades[eIdx];
                    const answer = essayAnswers[eIdx] ?? '';
                    const mark = grade ? gradeMark(grade) : null;
                    const markTone =
                      mark == null ? '' : mark >= grade!.outOf ? 'mac-label-green' : mark <= 0 ? 'mac-label-red' : 'mac-label-orange';
                    return (
                      <div key={`e${eIdx}`} className="mac-groupbox mario-quiz__question">
                        <p className="mario-quiz__prompt">
                          <span className="mario-quiz__number">{n}.</span>
                          <span dangerouslySetInnerHTML={{ __html: renderInlineMd(essay.question) }} />
                          <Spacer />
                          {quizChecked && grade ? (
                            <span className={`mario-quiz__mark ${markTone}`}>
                              {formatMark(mark!)}/{grade.outOf}
                            </span>
                          ) : (
                            <span className="mac-caption-1 mac-label-secondary">{essay.marks} mark{essay.marks === 1 ? '' : 's'}</span>
                          )}
                        </p>
                        {quizChecked ? (
                          <>
                            <div className="mario-quiz__essay-answer">{answer.trim() || '(no answer)'}</div>
                            {grade ? (
                              <>
                                {grade.feedback && <p className="mario-quiz__feedback">{grade.feedback}</p>}
                                {(grade.matchedPoints.length > 0 || grade.missedPoints.length > 0) && (
                                  <ul className="mario-quiz__rubric">
                                    {grade.matchedPoints.map((pt, i) => (
                                      <li key={`y${i}`} className="mario-quiz__rubric-line">
                                        <span className="mac-label-green"><Icon name="checkmark" /></span>
                                        <span>{pt}</span>
                                      </li>
                                    ))}
                                    {grade.missedPoints.map((pt, i) => (
                                      <li key={`n${i}`} className="mario-quiz__rubric-line mac-label-secondary">
                                        <Icon name="minus" />
                                        <span>{pt}</span>
                                      </li>
                                    ))}
                                  </ul>
                                )}
                                {grade.provisional && (
                                  <Row style={{ gap: 8 }}>
                                    <span className="mac-caption-1 mac-label-secondary">
                                      {grade.override != null ? 'Your mark:' : 'Draft mark — change it:'}
                                    </span>
                                    <PopUpButton
                                      size="small"
                                      aria-label={`Mark for question ${n}`}
                                      value={String(gradeMark(grade))}
                                      onChange={(v) => overrideEssayMark(eIdx, Number(v))}
                                      options={Array.from(
                                        new Set([
                                          ...Array.from({ length: grade.outOf + 1 }, (_, m) => m),
                                          gradeMark(grade),
                                        ]),
                                      )
                                        .sort((a, b) => a - b)
                                        .map((m) => ({ value: String(m), label: formatMark(m) }))}
                                    />
                                  </Row>
                                )}
                              </>
                            ) : (
                              <p className="mac-caption-1 mac-label-secondary" style={{ margin: 0 }}>
                                Not marked yet.
                              </p>
                            )}
                          </>
                        ) : (
                          <>
                            <TextArea
                              rows={6}
                              value={answer}
                              disabled={busy}
                              placeholder="Write your answer…"
                              aria-label={`Answer to question ${n}`}
                              onChange={(v) => setEssayAnswers((prev) => ({ ...prev, [eIdx]: v }))}
                            />
                            <Row>
                              <Spacer />
                              <Button size="small" variant="borderless" disabled={busy} onClick={() => setEssaySheet(eIdx)}>
                                Write in a Larger Editor…
                              </Button>
                            </Row>
                          </>
                        )}
                      </div>
                    );
                  })}

                  {marking ? (
                    <GroupBox className="mario-quiz__marking">
                      <Row style={{ gap: 8 }}>
                        <Spinner label="Marking" />
                        <span>
                          Marking {marking.done + 1} of {marking.total}
                        </span>
                      </Row>
                      <ProgressBar value={marking.done} max={marking.total} label="Marking" />
                      {taskLive?.owner === 'quiz' && <LiveThinking live={taskLive} />}
                      <Row>
                        <Spacer />
                        <Button size="small" icon="stop" onClick={handleStop}>
                          Stop and Show What Is Marked
                        </Button>
                      </Row>
                    </GroupBox>
                  ) : (
                    <Row>
                      {quizChecked ? (
                        <span className="mac-caption-1 mac-label-secondary">Saved with this notebook</span>
                      ) : (
                        <span className="mac-caption-1 mac-label-secondary">
                          {answeredCount} of {openQuiz.mcqs.length + openQuiz.essays.length} answered
                        </span>
                      )}
                      <Spacer />
                      {quizChecked ? (
                        <>
                          {openQuiz.essays.some((_, i) => !openQuizGrades[i]) && (
                            <Button size="small" disabled={busy} onClick={() => void submitQuiz(true)}>
                              Mark the Rest
                            </Button>
                          )}
                          <Button
                            size="small"
                            disabled={busy}
                            onClick={() => {
                              setQuizAnswers({});
                              setEssayAnswers({});
                              setQuizChecked(false);
                            }}
                          >
                            Retake
                          </Button>
                        </>
                      ) : (
                        <Button
                          size="small"
                          variant="prominent"
                          disabled={busy || answeredCount === 0}
                          onClick={() => void submitQuiz()}
                        >
                          {openQuiz.essays.length > 0 ? 'Submit for Marking' : 'Check Answers'}
                        </Button>
                      )}
                    </Row>
                  )}
                </div>
              ) : (
                taskLive?.owner !== 'quiz' && (
                  <EmptyState
                    icon="questionmark-circle"
                    title="Study Quiz"
                    message="Generate multiple-choice and essay questions from your notebook notes."
                  />
                )
              )}

              {(artifacts.quizzes ?? []).length > 0 && (
                <>
                  <h3 className="mario-ai-list-title">Saved Quizzes</h3>
                  <ul className="mario-ai-rows">
                    {(artifacts.quizzes ?? []).map((entry) => {
                      const total = entry.quiz.mcqs.length + entry.quiz.essays.length;
                      return (
                        <li key={entry.id} className="mario-ai-row">
                          <button
                            type="button"
                            className="mario-ai-row__open"
                            disabled={busy}
                            aria-current={entry.id === openQuizEntry?.id ? 'true' : undefined}
                            onClick={() => {
                              setOpenQuizId(entry.id);
                              setQuizAnswers(entry.answers ?? {});
                              setEssayAnswers(entry.essayAnswers ?? {});
                              setQuizChecked(entry.checkedAt != null || entry.score != null);
                            }}
                          >
                            <span className="mario-ai-item__title">{entry.quiz.title || 'Quiz'}</span>
                            <span className="mario-ai-item__meta">
                              {[
                                `${total} question${total === 1 ? '' : 's'}`,
                                entry.score != null
                                  ? `scored ${formatMark(entry.score)} of ${entry.outOf ?? entry.quiz.mcqs.length}`
                                  : 'not taken',
                                relativeTime(entry.createdAt),
                              ].join(' · ')}
                            </span>
                          </button>
                          <Button
                            size="small"
                            variant="borderless"
                            icon="trash"
                            label="Delete This Quiz"
                            disabled={busy}
                            onClick={() =>
                              setConfirm({
                                title: 'Delete this quiz?',
                                message: 'It is removed from this notebook’s saved quizzes.',
                                confirmLabel: 'Delete',
                                onConfirm: () =>
                                  void updateArtifacts((prev) => ({
                                    ...prev,
                                    quizzes: (prev.quizzes ?? []).filter((q) => q.id !== entry.id),
                                  })),
                              })
                            }
                          />
                        </li>
                      );
                    })}
                  </ul>
                </>
              )}
            </Column>
          )}

          {tab === 'write' && (
            <Column style={{ gap: 10 }}>
              <Row>
                <span className="mac-caption-1 mac-label-secondary">
                  {writingChecked && grammarIssues.length > 0
                    ? `${grammarIssues.length} left`
                    : 'Grammar, spelling and style on this page'}
                </span>
                <Spacer />
                {busy ? (
                  <Button size="small" icon="stop" onClick={handleStop}>
                    Stop
                  </Button>
                ) : (
                  <Button size="small" variant="prominent" disabled={!page} onClick={handleCheckWriting}>
                    {writingChecked ? 'Check Again' : 'Check This Page'}
                  </Button>
                )}
              </Row>

              {taskLive?.owner === 'write' && (
                <div className="mario-chat-msg mario-chat-msg--assistant">
                  <LiveThinking live={taskLive} />
                </div>
              )}

              {grammarIssues.length === 0 ? (
                taskLive?.owner === 'write' ? null : writingChecked && !busy ? (
                  <EmptyState
                    icon="checkmark-circle-fill"
                    title="Nothing to Fix"
                    message="No grammar, spelling or style problems were found on this page."
                  />
                ) : (
                  <EmptyState
                    icon="checkmark-circle-fill"
                    title="Writing Assistant"
                    message="“Check This Page” finds grammar, spelling and style improvements."
                  />
                )
              ) : (
                grammarIssues.map((iss, idx) => (
                  <div key={iss.id || idx} className="mac-groupbox">
                    <p style={{ margin: '0 0 4px', fontSize: 12.5 }}>
                      <del className="mac-label-red">{iss.original}</del> →{' '}
                      <ins
                        className="mac-label-green"
                        style={{ textDecoration: 'none', fontWeight: 600 }}
                      >
                        {iss.suggestion}
                      </ins>
                    </p>
                    <p
                      className="mac-caption-1 mac-label-secondary"
                      style={{ margin: 0 }}
                    >
                      {iss.explanation}
                    </p>
                    <Row style={{ marginTop: 8 }}>
                      <Spacer />
                      <Button
                        size="small"
                        onClick={() => setGrammarIssues((prev) => prev.filter((x) => x !== iss))}
                      >
                        Ignore
                      </Button>
                      <Button size="small" variant="tinted" onClick={() => applyGrammarSuggestion(iss)}>
                        Accept
                      </Button>
                    </Row>
                  </div>
                ))
              )}
            </Column>
          )}

          {tab === 'do' && (
            <Column style={{ gap: 10 }}>
              <Form className="mario-do-options">
                <FormSection>
                  <FormRow label="Preview Before Writing" subtitle="Approve each change to the page first">
                    <Switch
                      checked={previewBeforeWriting}
                      onChange={(on) => {
                        setPreviewBeforeWriting(on);
                        try {
                          localStorage.setItem('mario.do.previewBeforeWriting', on ? '1' : '0');
                        } catch {
                          // The switch still works for this session.
                        }
                      }}
                    />
                  </FormRow>
                </FormSection>
              </Form>
              {page && !busy && (
                <div className="mario-do-presets" role="group" aria-label="Act on This Page">
                  <span className="mac-caption-1 mac-label-secondary">Act on This Page</span>
                  <div className="mario-do-presets__buttons">
                    <Button
                      size="small"
                      onClick={() =>
                        void handleRunDoAgent(
                          'Find every task, to-do or action item on this page and add them as a checklist at the end of the page.',
                        )
                      }
                    >
                      Pull Out the To-Dos
                    </Button>
                    <Button
                      size="small"
                      onClick={() =>
                        void handleRunDoAgent('Turn the key facts on this page into a clear, well-organised table added to the page.')
                      }
                    >
                      Make a Table
                    </Button>
                    <Button
                      size="small"
                      onClick={() => {
                        setPromptText('Translate this page into ');
                        focusComposer();
                      }}
                    >
                      Translate…
                    </Button>
                    <Button
                      size="small"
                      onClick={() =>
                        void handleRunDoAgent(
                          'Tighten the writing on this page: make it clearer and more concise without losing any meaning or facts.',
                        )
                      }
                    >
                      Tighten the Writing
                    </Button>
                  </div>
                </div>
              )}
              {undoSnapshot && !busy && (
                <Row>
                  <span className="mac-caption-1 mac-label-secondary">
                    Agent modified this page
                  </span>
                  <Spacer />
                  <Button
                    size="small"
                    variant="bordered"
                    icon="arrow-uturn-left"
                    onClick={() => {
                      onPageContentChange(undoSnapshot);
                      setUndoSnapshot(null);
                    }}
                  >
                    Undo Agent Changes
                  </Button>
                </Row>
              )}

              {doLive && (
                <>
                  <div className="mario-chat-msg mario-chat-msg--user">{doLive.instruction}</div>
                  <div className="mario-chat-msg mario-chat-msg--assistant">
                    {taskLive?.owner === 'do' ? (
                      <LiveThinking live={taskLive} />
                    ) : (
                      doLive.steps.length === 0 &&
                      !pendingPlan && (
                        <div className="mario-live-thinking__status">
                          <Spinner label="Working" /> <span>Reading the page…</span>
                        </div>
                      )
                    )}
                    {doLive.steps.length > 0 && (
                      <div className="mario-ai-steps">
                        {doLive.steps.map((step) => (
                          <div key={step.id} className="mario-ai-step">
                            {step.status === 'running' ? <Spinner label={step.kind} /> : <Icon name="checkmark" />}
                            <span className="mario-ai-step__label">{step.kind}</span>
                            <span className="mario-ai-step__detail">{step.summary}</span>
                          </div>
                        ))}
                      </div>
                    )}
                    {doLive.summary && <p className="mario-do-summary">{doLive.summary}</p>}
                    {pendingPlan && (
                      <GroupBox className="mario-plan-preview" aria-label="Preview">
                        <p className="mario-plan-preview__title">Preview — nothing has changed yet</p>
                        <ul className="mario-plan-preview__list">
                          {pendingPlan.actions.map((act, i) => {
                            const d = describeAgentAction(act, blockText);
                            return (
                              <li key={i} className="mario-plan-preview__item">
                                <span className={d.destructive ? 'mac-label-orange' : 'mac-label-tertiary'}>
                                  <Icon name={d.destructive ? 'exclamationmark-triangle' : 'chevron-right'} />
                                </span>
                                <span>{d.text}</span>
                              </li>
                            );
                          })}
                        </ul>
                        <Row style={{ gap: 8 }}>
                          <Spacer />
                          <Button size="small" onClick={() => pendingPlanResolve.current?.(false)}>
                            Discard
                          </Button>
                          <Button
                            size="small"
                            variant="prominent"
                            icon="checkmark"
                            disabled={!page}
                            onClick={() => pendingPlanResolve.current?.(true)}
                          >
                            Apply Changes
                          </Button>
                        </Row>
                      </GroupBox>
                    )}
                  </div>
                </>
              )}
              {orderedDoHistory.length === 0 && !doLive ? (
                <EmptyState
                  icon="bolt"
                  title="Mario Agent (“Do”)"
                  message="Ask Mario to insert sections, build study tables, add LaTeX equations, create spreadsheets with formulas, or reorganize notebooks."
                />
              ) : (
                <>
                  {orderedDoHistory.length > 0 && <h3 className="mario-ai-list-title">Earlier Instructions</h3>}
                  {orderedDoHistory.map((run, idx) => (
                    <div key={run.id} className="mario-ai-item">
                      <Disclosure
                        defaultOpen={idx === 0 && !doLive}
                        title={
                          <span className="mario-ai-item__head">
                            <span className="mario-ai-item__title">{run.instruction}</span>
                            <span className="mario-ai-item__meta">
                              {[
                                relativeTime(run.createdAt),
                                page && run.pageId && run.pageId !== page.id ? 'another page' : '',
                                `${run.steps.length} step${run.steps.length === 1 ? '' : 's'}`,
                              ]
                                .filter(Boolean)
                                .join(' · ')}
                            </span>
                          </span>
                        }
                      >
                        <div className="mario-chat-msg mario-chat-msg--assistant">
                          {run.thinking && (
                            <div className="mario-thoughts">
                              <Disclosure title={run.thinkingSeconds ? `Thought for ${run.thinkingSeconds} s` : 'Thoughts'}>
                                <div
                                  className="mario-thinking mario-md-body"
                                  dangerouslySetInnerHTML={{ __html: renderMarkdownHtml(run.thinking) }}
                                />
                              </Disclosure>
                            </div>
                          )}
                          {run.steps.length > 0 && (
                            <div className="mario-ai-steps">
                              {run.steps.map((line, i) => {
                                const [kind, ...rest] = line.split(': ');
                                return (
                                  <div key={i} className="mario-ai-step">
                                    <Icon name="checkmark" />
                                    <span className="mario-ai-step__label">{kind}</span>
                                    <span className="mario-ai-step__detail">{rest.join(': ')}</span>
                                  </div>
                                );
                              })}
                            </div>
                          )}
                          <p className="mario-do-summary">{run.summary}</p>
                          <div className="mario-answer-actions">
                            <Spacer />
                            <Button
                              size="small"
                              variant="borderless"
                              icon="arrow-clockwise"
                              label="Run Again"
                              disabled={busy}
                              onClick={() => void handleRunDoAgent(run.instruction)}
                            />
                            <Button
                              size="small"
                              variant="borderless"
                              icon="trash"
                              label="Delete This Run"
                              onClick={() =>
                                setConfirm({
                                  title: 'Delete this instruction?',
                                  message: 'It is removed from this notebook’s Do history. The page is not changed.',
                                  confirmLabel: 'Delete',
                                  onConfirm: () =>
                                    void updateArtifacts((prev) => ({
                                      ...prev,
                                      doHistory: (prev.doHistory ?? []).filter((x) => x.id !== run.id),
                                    })),
                                })
                              }
                            />
                          </div>
                        </div>
                      </Disclosure>
                    </div>
                  ))}
                </>
              )}
            </Column>
          )}
        </div>

        {/* Docked Two-Row Composer for Ask & Do tabs */}
        {(tab === 'ask' || tab === 'do') && (
          <div className="mario-ai-composer">
            {tab === 'ask' && quote && (
              <div className="mario-ai-quote">
                <div className="mario-ai-quote__text">
                  <span className="mario-ai-quote__title">Asking About Your Highlight</span>
                  <span className="mario-ai-quote__passage">{quote.replace(/\s+/g, ' ')}</span>
                </div>
                <Button
                  size="small"
                  variant="borderless"
                  icon="xmark"
                  label="Ask about the whole page instead"
                  onClick={onClearQuote}
                />
              </div>
            )}
            <TextArea
              rows={2}
              value={promptText}
              onChange={setPromptText}
              placeholder={
                busy
                  ? 'Working on it…'
                  : tab === 'do'
                    ? page
                      ? 'Change this page…'
                      : 'Tell Mario what to do in this notebook…'
                    : quote
                      ? 'Ask about the highlighted passage…'
                      : page
                        ? 'Ask about this page…'
                        : 'Ask about this notebook…'
              }
              onKeyDown={(e) => {
                if (e.key === 'Escape' && busy) {
                  e.preventDefault();
                  handleStop();
                } else if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  if (tab === 'do') handleRunDoAgent();
                  else handleAskSubmit();
                }
              }}
            />
            <Row style={{ gap: 6 }}>
              {tab === 'ask' && (
                <>
                  <PopUpButton
                    size="small"
                    aria-label="Web Search Mode"
                    value={webMode}
                    onChange={(v) => setWebMode(v as WebSearchMode)}
                    options={[
                      { value: 'auto', label: 'Web: Auto' },
                      { value: 'on', label: 'Web: On' },
                      { value: 'off', label: 'Web: Off' },
                    ]}
                  />
                  <Button
                    size="small"
                    variant="bordered"
                    disabled={busy}
                    onClick={handleSummarise}
                  >
                    Summarise
                  </Button>
                  {(artifacts.askHistory ?? []).length > 0 && (
                    <Button
                      size="small"
                      variant="borderless"
                      icon="trash"
                      label="Clear Chat"
                      onClick={() =>
                        setConfirm({
                          title: 'Clear every chat in this notebook?',
                          message: 'The AI history of this notebook is removed. Your pages are not changed.',
                          confirmLabel: 'Clear',
                          onConfirm: () => void updateArtifacts((prev) => ({ ...prev, askHistory: [] })),
                        })
                      }
                    />
                  )}
                </>
              )}
              <Spacer />
              {busy ? (
                <Button size="small" icon="stop" label="Stop (Esc)" onClick={handleStop}>
                  Stop
                </Button>
              ) : (
                <Button
                  size="small"
                  variant="prominent"
                  icon="paperplane"
                  disabled={!promptText.trim()}
                  onClick={() =>
                    tab === 'do' ? handleRunDoAgent() : handleAskSubmit()
                  }
                >
                  {tab === 'do' ? 'Run' : 'Send'}
                </Button>
              )}
            </Row>
          </div>
        )}
      </Inspector>
      <Sheet
        open={essaySheet != null}
        onClose={() => setEssaySheet(null)}
        title="Your Answer"
        top={60}
        buttons={[{ label: 'Done', role: 'default', onClick: () => setEssaySheet(null) }]}
      >
        {essaySheet != null && openQuiz?.essays[essaySheet] && (
          <div className="mario-essay-sheet">
            <p
              className="mario-quiz__prompt"
              dangerouslySetInnerHTML={{ __html: renderInlineMd(openQuiz.essays[essaySheet].question) }}
            />
            <TextArea
              rows={18}
              autoFocus
              value={essayAnswers[essaySheet] ?? ''}
              placeholder="Write your answer…"
              aria-label="Answer"
              onChange={(v) => setEssayAnswers((prev) => ({ ...prev, [essaySheet]: v }))}
            />
          </div>
        )}
      </Sheet>
      <Alert
        open={confirm != null}
        onClose={() => setConfirm(null)}
        title={confirm?.title ?? ''}
        message={confirm?.message}
        buttons={[
          { label: 'Cancel', role: 'cancel', onClick: () => setConfirm(null) },
          {
            label: confirm?.confirmLabel ?? 'OK',
            role: 'destructive',
            onClick: () => {
              confirm?.onConfirm();
              setConfirm(null);
            },
          },
        ]}
      />
    </div>
  );
}
