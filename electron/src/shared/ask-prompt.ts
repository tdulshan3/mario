import type { WebSearchMode } from './types';

/** The Ask request, shared by the AI panel and the page's inline Ask so both answer alike. */

export const ASK_SYSTEM_PROMPT =
  'You are Mario AI, a concise, knowledgeable research and study assistant embedded inside the Mario note app. Answer using clean Markdown and LaTeX ($...$ or $$...$$). Ground your answer in the user’s notebook notes whenever relevant.';

/** Web: On always searches; Auto only for questions about something current. */
export function shouldSearchWeb(question: string, mode: WebSearchMode): boolean {
  if (mode === 'on') return true;
  if (mode === 'off') return false;
  return /\b(latest|news|2025|2026|search|web|current|price|release)\b/i.test(question);
}

export function formatWebResults(results: Array<{ title: string; link: string; snippet: string }>): string {
  if (results.length === 0) return '';
  return (
    '\n\nWeb Search Results (cite them as [n]):\n' +
    results.map((r, i) => `[${i + 1}] ${r.title} (${r.link})\n${r.snippet}`).join('\n\n')
  );
}

export function buildAskUserPrompt(opts: {
  question: string;
  notes: string;
  /** The highlighted passage the question is about. */
  passage?: string | null;
  webContext?: string;
}): string {
  const fence = "'".repeat(3);
  const passageBlock = opts.passage
    ? `\n\nThe user has highlighted this passage from the notes above, and the question is about it. Answer about this specifically, using the rest of the notes only as background:\n${fence}\n${opts.passage}\n${fence}`
    : '';
  return `Notes:\n${opts.notes || '(Empty notebook)'}${passageBlock}${opts.webContext ?? ''}\n\nQuestion: ${opts.question}`;
}

/** The first ```html block of an answer, for Preview HTML. */
export const htmlArtifactOf = (answer: string): string | undefined =>
  /```html\s*\n([\s\S]*?)```/i.exec(answer)?.[1];
