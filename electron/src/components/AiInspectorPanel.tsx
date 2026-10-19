import React, { useEffect, useMemo, useRef, useState } from 'react';
import { marked } from 'marked';
import katex from 'katex';
import {
  Button,
  Column,
  EmptyState,
  Icon,
  Inspector,
  PopUpButton,
  Row,
  SegmentedControl,
  Spacer,
  Spinner,
  Stepper,
  TextArea,
} from '../macos/macos';
import type {
  AgentAction,
  AiArtifactData,
  AiTab,
  AppFlowyNode,
  GrammarSuggestion,
  LlmEffort,
  LlmProviderConfig,
  Notebook,
  NotePage,
  PageContent,
  QuizData,
  Section,
  WebSearchMode,
} from '../shared/types';
import {
  agentPlanSchema,
  grammarSchema,
  marioAgentPrompt,
  OBSERVING_KINDS,
  parseAgentPlan,
  quizSchema,
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
  normalizeLatexFormula,
  parseInlineMarkdownToDelta,
  renderBlocksForPrompt,
} from '../shared/document-codec';
import { newClientId } from '../shared/ids';

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
}

interface AgentStepLog {
  id: string;
  kind: string;
  summary: string;
  status: 'running' | 'done' | 'error';
}

function renderMarkdownWithKatex(md: string): string {
  if (!md) return '';
  const withDisplayMath = md.replace(/\$\$([\s\S]+?)\$\$/g, (_, tex) =>
    katex.renderToString(normalizeLatexFormula(String(tex).trim()), {
      displayMode: true,
      throwOnError: false,
    }),
  );
  const withInlineMath = withDisplayMath.replace(
    /\$([^$\n]+?)\$/g,
    (_, tex) =>
      katex.renderToString(normalizeLatexFormula(String(tex).trim()), {
        displayMode: false,
        throwOnError: false,
      }),
  );
  return String(marked.parse(withInlineMath, { async: false }));
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
}: AiInspectorPanelProps) {
  const [width, setWidth] = useState(328);
  const [tab, setTab] = useState<AiTab>('ask');
  const [providers, setProviders] = useState<LlmProviderConfig[]>([]);
  const [activeProviderId, setActiveProviderId] = useState<string | null>(null);
  const [availableModels, setAvailableModels] = useState<string[]>([]);
  const [webMode, setWebMode] = useState<WebSearchMode>('auto');
  const [promptText, setPromptText] = useState('');
  const [busy, setBusy] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // Per-notebook artifacts
  const [artifacts, setArtifacts] = useState<AiArtifactData>({
    askHistory: [],
    doHistory: [],
    quizzes: [],
  });
  const [quizCount, setQuizCount] = useState(5);
  const [quizAnswers, setQuizAnswers] = useState<Record<number, number>>({});
  const [grammarIssues, setGrammarIssues] = useState<GrammarSuggestion[]>([]);

  // Do-tab agent state
  const [agentHistory, setAgentHistory] = useState<
    Array<{
      prompt: string;
      summary: string;
      steps: AgentStepLog[];
    }>
  >([]);
  const [undoSnapshot, setUndoSnapshot] = useState<PageContent | null>(null);

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

  useEffect(() => {
    if (!activeProvider) {
      setAvailableModels([]);
      return;
    }
    let cancelled = false;
    window.mario.ai
      .listModels({
        id: activeProvider.id,
        kind: activeProvider.kind,
        baseUrl: activeProvider.baseUrl,
      })
      .then((models) => {
        if (!cancelled) {
          const merged = Array.from(
            new Set([activeProvider.model, ...models].filter(Boolean)),
          );
          setAvailableModels(merged);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setAvailableModels(activeProvider.model ? [activeProvider.model] : []);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [activeProvider?.id, activeProvider?.baseUrl, activeProvider?.model]);

  useEffect(() => {
    if (!notebook) {
      setArtifacts({ askHistory: [], doHistory: [], quizzes: [] });
      return;
    }
    window.mario.ai
      .readArtifacts(notebook.id)
      .then((data) => {
        setArtifacts({
          askHistory: data?.askHistory ?? [],
          doHistory: data?.doHistory ?? [],
          quizzes: data?.quizzes ?? [],
        });
        setQuizAnswers({});
      })
      .catch(() =>
        setArtifacts({ askHistory: [], doHistory: [], quizzes: [] }),
      );
  }, [notebook?.id]);

  const saveArtifacts = async (next: AiArtifactData) => {
    setArtifacts(next);
    if (notebook) {
      await window.mario.ai.writeArtifacts(notebook.id, next);
    }
  };

  const gatherNotebookContext = async (): Promise<string> => {
    if (!notebook) return '';
    const secs = sectionsByNotebook[notebook.id] ?? [];
    const chunks: string[] = [];
    for (const sec of secs) {
      const pgs = pagesByKey[`${notebook.id}/${sec.id}`] ?? [];
      for (const pg of pgs) {
        if (page && pg.id === page.id) {
          chunks.push(
            `## Page: ${pg.title} (Section: ${sec.name})\n${documentToMarkdown(
              latestContentRef.current.document,
            )}`,
          );
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
  const handleAskSubmit = async (customQuery?: string) => {
    const q = (customQuery ?? promptText).trim();
    if (!q || busy) return;
    if (!customQuery) setPromptText('');
    setBusy(true);
    setErrorMsg(null);

    try {
      const context = await gatherNotebookContext();
      let webContext = '';
      const shouldSearch =
        webMode === 'on' ||
        (webMode === 'auto' &&
          /\b(latest|news|2025|2026|search|web|current|price|release)\b/i.test(
            q,
          ));
      if (shouldSearch) {
        const results = await window.mario.ai.webSearch(q);
        if (results.length > 0) {
          webContext =
            '\n\nWeb Search Results:\n' +
            results
              .map((r, i) => `[${i + 1}] ${r.title} (${r.link})\n${r.snippet}`)
              .join('\n\n');
        }
      }

      const res = await window.mario.ai.chat({
        systemPrompt:
          'You are Mario AI, a concise, knowledgeable research and study assistant embedded inside the Mario note app. Answer using clean Markdown and LaTeX ($...$ or $$...$$). Ground your answer in the user’s notebook notes whenever relevant.',
        userPrompt: `Notebook Context:\n${
          context || '(Empty notebook)'
        }${webContext}\n\nUser Question: ${q}`,
      });

      const entry = {
        id: newClientId('ask'),
        pageId: page?.id,
        question: q,
        answer: res.text || '(No response)',
        createdAt: new Date().toISOString(),
      };
      await saveArtifacts({
        ...artifacts,
        askHistory: [...(artifacts.askHistory ?? []), entry],
      });
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
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
    if (busy) return;
    setBusy(true);
    setErrorMsg(null);
    try {
      const context = await gatherNotebookContext();
      const raw = await window.mario.ai.structured({
        schemaName: 'quiz',
        schema: quizSchema(quizCount),
        systemPrompt:
          'Generate a multiple-choice study quiz testing key concepts from the user’s notes. Return valid JSON matching the schema.',
        userPrompt: `Create ${quizCount} multiple-choice questions from these notes:\n\n${
          context || page?.title || 'General science and productivity'
        }`,
      });
      const quiz = raw as unknown as QuizData;
      if (Array.isArray(quiz.mcqs)) {
        setQuizAnswers({});
        const quizEntry = {
          id: newClientId('quiz'),
          pageId: page?.id,
          quiz,
          createdAt: new Date().toISOString(),
        };
        await saveArtifacts({
          ...artifacts,
          quizzes: [quizEntry, ...(artifacts.quizzes ?? [])],
        });
      }
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  // --- Writing Tab Handler ---
  const handleCheckWriting = async () => {
    if (busy || !page) return;
    setBusy(true);
    setErrorMsg(null);
    try {
      const md = documentToMarkdown(latestContentRef.current.document);
      const raw = await window.mario.ai.structured({
        schemaName: 'grammar_review',
        schema: grammarSchema,
        systemPrompt:
          'Review the user’s note for grammar, spelling, clarity, and conciseness. Return exact substrings from the text in `original` and improved text in `suggestion`.',
        userPrompt: md || page.title,
      });
      const suggestions = Array.isArray(raw.suggestions)
        ? (raw.suggestions as GrammarSuggestion[])
        : [];
      setGrammarIssues(suggestions);
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : String(err));
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

    switch (action.kind) {
      case 'paragraph': {
        const n = makeParagraphNode(action.text ?? '');
        nodes.splice(resolveInsertIndex(action.afterBlockId), 0, n);
        commit(nodes);
        return { summary: 'Inserted paragraph' };
      }
      case 'heading': {
        const n = makeHeadingNode(action.level ?? 2, action.text ?? '');
        nodes.splice(resolveInsertIndex(action.afterBlockId), 0, n);
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
        nodes.splice(resolveInsertIndex(action.afterBlockId), 0, ...created);
        commit(nodes);
        return { summary: `Inserted ${created.length} ${action.kind} item(s)` };
      }
      case 'quote': {
        const n = makeQuoteNode(action.text ?? '');
        nodes.splice(resolveInsertIndex(action.afterBlockId), 0, n);
        commit(nodes);
        return { summary: 'Inserted quote block' };
      }
      case 'divider': {
        const n = makeDividerNode();
        nodes.splice(resolveInsertIndex(action.afterBlockId), 0, n);
        commit(nodes);
        return { summary: 'Inserted divider' };
      }
      case 'code': {
        const n = makeCodeNode(action.text ?? '', action.language ?? 'python');
        nodes.splice(resolveInsertIndex(action.afterBlockId), 0, n);
        commit(nodes);
        return {
          summary: `Inserted ${action.language ?? 'code'} block`,
        };
      }
      case 'math': {
        const n = makeMathNode(action.text ?? '');
        nodes.splice(resolveInsertIndex(action.afterBlockId), 0, n);
        commit(nodes);
        return { summary: 'Inserted LaTeX equation' };
      }
      case 'table': {
        const n = makeTableNode(action.rows ?? [['', '']]);
        nodes.splice(resolveInsertIndex(action.afterBlockId), 0, n);
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
        nodes.splice(resolveInsertIndex(action.afterBlockId), 0, sb);
        commit(nodes);
        return { summary: `Inserted spreadsheet "${action.text || 'Sheet1'}"` };
      }
      case 'markdown': {
        const created = markdownToNodes(action.text ?? action.content ?? '');
        nodes.splice(resolveInsertIndex(action.afterBlockId), 0, ...created);
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

  const handleRunDoAgent = async () => {
    const goal = promptText.trim();
    if (!goal || busy) return;
    setPromptText('');
    setBusy(true);
    setErrorMsg(null);
    setUndoSnapshot(structuredClone(latestContentRef.current));

    const stepsLog: AgentStepLog[] = [];
    let finalSummary = '';

    try {
      const userSkills = await window.mario.ai.getUserSkills();
      const includeHtml =
        /\b(html|preview|widget|interactive|chart|diagram|mockup)\b/i.test(
          goal,
        );
      const systemPrompt = marioAgentPrompt(userSkills, includeHtml);
      const observations: string[] = [];

      for (let turn = 0; turn < 5; turn++) {
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

        const rawPlan = await window.mario.ai.structured({
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
        });

        const plan = parseAgentPlan(rawPlan, new Set(knownIds));
        if (plan.summary) finalSummary = plan.summary;

        if (plan.actions.length === 0) {
          break;
        }

        let needsFollowUpTurn = false;
        for (const act of plan.actions) {
          const stepId = `${turn}-${stepsLog.length}`;
          stepsLog.push({
            id: stepId,
            kind: act.kind,
            summary: `Running ${act.kind}…`,
            status: 'running',
          });
          setAgentHistory((prev) => [
            ...prev.filter((x) => x.prompt !== goal),
            {
              prompt: goal,
              summary: finalSummary,
              steps: [...stepsLog],
            },
          ]);

          const res = await executeSingleAction(act);
          stepsLog[stepsLog.length - 1] = {
            id: stepId,
            kind: act.kind,
            summary: res.summary,
            status: 'done',
          };
          if (res.observation || OBSERVING_KINDS.has(act.kind)) {
            if (res.observation) observations.push(res.observation);
            needsFollowUpTurn = !plan.done;
          }
        }

        if (!needsFollowUpTurn) {
          break;
        }
      }

      setAgentHistory((prev) => [
        ...prev.filter((x) => x.prompt !== goal),
        {
          prompt: goal,
          summary: finalSummary || 'Completed actions on your note.',
          steps: stepsLog,
        },
      ]);
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  const latestQuiz = artifacts.quizzes?.[0]?.quiz ?? null;

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
          <Row style={{ gap: 6 }}>
            {providers.length > 0 && activeProvider ? (
              <>
                <PopUpButton
                  size="small"
                  aria-label="AI Provider"
                  style={{ flex: 1, minWidth: 0 }}
                  value={activeProvider.id}
                  onChange={async (id) => {
                    const next = await window.mario.ai.setActiveProvider(id);
                    setProviders(next.providers);
                    setActiveProviderId(next.activeId);
                  }}
                  options={providers.map((p) => ({
                    value: p.id,
                    label: `${p.label} (${p.model || 'default'})`,
                  }))}
                />
                {availableModels.length > 1 && (
                  <PopUpButton
                    size="small"
                    aria-label="Model"
                    style={{ maxWidth: 115 }}
                    value={activeProvider.model}
                    onChange={async (m) => {
                      const next = await window.mario.ai.setProviderModel(
                        activeProvider.id,
                        m,
                        activeProvider.effort,
                      );
                      setProviders(next.providers);
                    }}
                    options={availableModels.map((m) => ({
                      value: m,
                      label: m,
                    }))}
                  />
                )}
                <PopUpButton
                  size="small"
                  aria-label="Reasoning Effort"
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
              </>
            ) : (
              <Button
                size="small"
                variant="tinted"
                icon="bolt"
                onClick={onOpenAiSettings}
              >
                Configure AI Provider…
              </Button>
            )}
          </Row>

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
        <div className="mario-ai-scroll mac-scroll">
          {errorMsg && (
            <div
              className="mac-groupbox"
              style={{ borderColor: 'var(--mac-red)' }}
            >
              <p className="mac-footnote mac-label-red" style={{ margin: 0 }}>
                {errorMsg}
              </p>
            </div>
          )}

          {tab === 'ask' && (
            <>
              {(artifacts.askHistory ?? []).length === 0 ? (
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
                (artifacts.askHistory ?? []).map((turn) => (
                  <React.Fragment key={turn.id}>
                    <div className="mario-chat-msg mario-chat-msg--user">
                      {turn.question}
                    </div>
                    <div className="mario-chat-msg mario-chat-msg--assistant">
                      <div
                        className="mario-md-body"
                        dangerouslySetInnerHTML={{
                          __html: renderMarkdownWithKatex(turn.answer),
                        }}
                      />
                    </div>
                  </React.Fragment>
                ))
              )}
              {busy && (
                <Row>
                  <Spinner label="Thinking" />
                  <span className="mac-caption-1 mac-label-secondary">
                    Thinking…
                  </span>
                </Row>
              )}
            </>
          )}

          {tab === 'quiz' && (
            <Column style={{ gap: 12 }}>
              <Row>
                <span className="mac-caption-1 mac-label-secondary">
                  Questions:
                </span>
                <Stepper
                  size="small"
                  min={3}
                  max={10}
                  value={quizCount}
                  onChange={setQuizCount}
                  label="Question Count"
                />
                <Spacer />
                <Button
                  size="small"
                  variant="prominent"
                  disabled={busy}
                  onClick={handleGenerateQuiz}
                >
                  {busy ? 'Generating…' : 'New Quiz'}
                </Button>
              </Row>

              {!latestQuiz ? (
                <EmptyState
                  icon="questionmark-circle"
                  title="Study Quiz"
                  message="Generate a multiple-choice quiz from your notebook notes."
                />
              ) : (
                latestQuiz.mcqs.map((q, qIdx) => {
                  const chosen = quizAnswers[qIdx];
                  return (
                    <div key={qIdx} className="mac-groupbox">
                      <p
                        style={{
                          margin: '0 0 8px 0',
                          fontWeight: 600,
                          fontSize: 13,
                        }}
                      >
                        {qIdx + 1}. {q.question}
                      </p>
                      <Column style={{ gap: 6 }}>
                        {q.options.map((opt, oIdx) => {
                          const isChosen = chosen === oIdx;
                          const isCorrect = q.correctIndex === oIdx;
                          return (
                            <Button
                              key={oIdx}
                              size="small"
                              variant={
                                chosen === undefined
                                  ? 'bordered'
                                  : isCorrect
                                  ? 'prominent'
                                  : isChosen
                                  ? 'destructive'
                                  : 'bordered'
                              }
                              style={{ justifyContent: 'flex-start' }}
                              onClick={() =>
                                setQuizAnswers((prev) => ({
                                  ...prev,
                                  [qIdx]: oIdx,
                                }))
                              }
                            >
                              {opt}
                            </Button>
                          );
                        })}
                      </Column>
                      {chosen !== undefined && q.explanation && (
                        <p
                          className="mac-caption-1 mac-label-secondary"
                          style={{ margin: '8px 0 0 0' }}
                        >
                          {q.explanation}
                        </p>
                      )}
                    </div>
                  );
                })
              )}
            </Column>
          )}

          {tab === 'write' && (
            <Column style={{ gap: 10 }}>
              <Row>
                <span className="mac-caption-1 mac-label-secondary">
                  Review grammar & style on current page
                </span>
                <Spacer />
                <Button
                  size="small"
                  variant="prominent"
                  disabled={busy || !page}
                  onClick={handleCheckWriting}
                >
                  {busy ? 'Checking…' : 'Check Page'}
                </Button>
              </Row>

              {grammarIssues.length === 0 ? (
                <EmptyState
                  icon="checkmark-circle-fill"
                  title="Writing Assistant"
                  message="Click “Check Page” to find grammar, spelling, and style improvements."
                />
              ) : (
                grammarIssues.map((iss, idx) => (
                  <div key={iss.id || idx} className="mac-groupbox">
                    <Row>
                      <span className="mac-caption-1 mac-label-secondary">
                        SUGGESTION
                      </span>
                      <Spacer />
                      <Button
                        size="small"
                        variant="tinted"
                        onClick={() => applyGrammarSuggestion(iss)}
                      >
                        Apply
                      </Button>
                    </Row>
                    <p style={{ margin: '6px 0 4px', fontSize: 12.5 }}>
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
                  </div>
                ))
              )}
            </Column>
          )}

          {tab === 'do' && (
            <Column style={{ gap: 10 }}>
              {undoSnapshot && (
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

              {agentHistory.length === 0 ? (
                <EmptyState
                  icon="bolt"
                  title="Mario Agent (“Do”)"
                  message="Ask Mario to insert sections, build study tables, add LaTeX equations, create spreadsheets with formulas, or reorganize notebooks."
                />
              ) : (
                agentHistory.map((run, rIdx) => (
                  <Column key={rIdx} style={{ gap: 6 }}>
                    <div className="mario-chat-msg mario-chat-msg--user">
                      {run.prompt}
                    </div>
                    {run.steps.map((step) => (
                      <div key={step.id} className="mario-agent-step">
                        <Icon
                          name={
                            step.status === 'done'
                              ? 'checkmark-circle-fill'
                              : 'bolt'
                          }
                        />
                        <div>
                          <strong>{step.kind}</strong>: {step.summary}
                        </div>
                      </div>
                    ))}
                    {run.summary && (
                      <div className="mario-chat-msg mario-chat-msg--assistant">
                        {run.summary}
                      </div>
                    )}
                  </Column>
                ))
              )}
              {busy && (
                <Row>
                  <Spinner label="Running agent" />
                  <span className="mac-caption-1 mac-label-secondary">
                    Planning & executing actions…
                  </span>
                </Row>
              )}
            </Column>
          )}
        </div>

        {/* Docked Two-Row Composer for Ask & Do tabs */}
        {(tab === 'ask' || tab === 'do') && (
          <div className="mario-ai-composer">
            <TextArea
              rows={2}
              value={promptText}
              onChange={setPromptText}
              placeholder={
                tab === 'do'
                  ? 'Tell Mario what to do on this page or notebook…'
                  : 'Ask a question about your notes…'
              }
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
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
                        saveArtifacts({ ...artifacts, askHistory: [] })
                      }
                    />
                  )}
                </>
              )}
              <Spacer />
              <Button
                size="small"
                variant="prominent"
                icon="paperplane"
                disabled={busy || !promptText.trim()}
                onClick={() =>
                  tab === 'do' ? handleRunDoAgent() : handleAskSubmit()
                }
              >
                {tab === 'do' ? 'Run' : 'Send'}
              </Button>
            </Row>
          </div>
        )}
      </Inspector>
    </div>
  );
}
