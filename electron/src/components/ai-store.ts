import { useEffect, useState, useSyncExternalStore } from 'react';
import type { AiArtifactData } from '../shared/types';
import { normalizeArtifacts } from '../shared/quiz';

/**
 * State the AI panel and the page's inline Ask share. The panel unmounts when
 * the inspector is closed, so neither can own it.
 *
 * - Artifacts: a notebook's AI history (chats, Do runs, quizzes). Every change goes
 *   through `updateArtifacts`, which applies it to the latest copy, so a chat saved
 *   from the page is not overwritten by the panel's next save.
 * - Activity: what the model is doing right now, for the model bar's activity line.
 */

const EMPTY: AiArtifactData = { askHistory: [], doHistory: [], quizzes: [] };
const cache = new Map<string, AiArtifactData>();
const loading = new Map<string, Promise<AiArtifactData>>();
const listeners = new Set<(notebookId: string, data: AiArtifactData) => void>();
let writes: Promise<unknown> = Promise.resolve();

export function loadArtifacts(notebookId: string): Promise<AiArtifactData> {
  const cached = cache.get(notebookId);
  if (cached) return Promise.resolve(cached);
  let pending = loading.get(notebookId);
  if (!pending) {
    pending = window.mario.ai
      .readArtifacts(notebookId)
      .then((raw) => normalizeArtifacts(raw))
      .catch(() => EMPTY)
      .then((data) => {
        // A change made while it loaded wins.
        const now = cache.get(notebookId) ?? data;
        cache.set(notebookId, now);
        loading.delete(notebookId);
        return now;
      });
    loading.set(notebookId, pending);
  }
  return pending;
}

/** Applies `fn` to the notebook's latest history, tells every view, then saves. */
export async function updateArtifacts(
  notebookId: string,
  fn: (prev: AiArtifactData) => AiArtifactData,
): Promise<AiArtifactData> {
  const prev = cache.get(notebookId) ?? (await loadArtifacts(notebookId));
  const next = fn(prev);
  cache.set(notebookId, next);
  listeners.forEach((l) => l(notebookId, next));
  // Saves run one after another, so an older one never lands last.
  writes = writes
    .catch(() => undefined)
    .then(() => window.mario.ai.writeArtifacts(notebookId, cache.get(notebookId) ?? next));
  await writes.catch(() => undefined);
  return next;
}

export function subscribeArtifacts(listener: (notebookId: string, data: AiArtifactData) => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

// ── Activity ────────────────────────────────────────────────────────────────

export interface AiActivity {
  /** "Thinking", "Searching the web", "Marking". */
  label: string;
  /** "this page and 2 more", "2 of 3". */
  detail?: string;
  /** When this step started, for the elapsed time. */
  since: number;
  /** The run failed: `label` is the error. */
  failed?: boolean;
}

const activities = new Map<string, AiActivity & { at: number }>();
const activityListeners = new Set<() => void>();
let activitySnapshot: AiActivity | null = null;

function publishActivity() {
  let latest: (AiActivity & { at: number }) | null = null;
  for (const a of activities.values()) if (!latest || a.at > latest.at) latest = a;
  activitySnapshot = latest;
  activityListeners.forEach((l) => l());
}

/** What `source` ("panel", "inline") is doing. The elapsed time restarts only when the step changes. */
export function setActivity(source: string, label: string, detail?: string) {
  const cur = activities.get(source);
  const since = cur && !cur.failed && cur.label === label ? cur.since : Date.now();
  if (cur && cur.label === label && cur.detail === detail && !cur.failed) return;
  activities.set(source, { label, detail, since, at: Date.now() });
  publishActivity();
}

export function failActivity(source: string, message: string) {
  activities.set(source, { label: message, since: Date.now(), failed: true, at: Date.now() });
  publishActivity();
}

export function clearActivity(source: string) {
  if (!activities.delete(source)) return;
  publishActivity();
}

export function useAiActivity(): AiActivity | null {
  return useSyncExternalStore(
    (cb) => {
      activityListeners.add(cb);
      return () => activityListeners.delete(cb);
    },
    () => activitySnapshot,
  );
}

/** Now, every second while `on`: for elapsed times. */
export function useNow(on: boolean): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!on) return;
    setNow(Date.now());
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [on]);
  return now;
}

export function elapsedLabel(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 60) return `${s} s`;
  return `${Math.floor(s / 60)} min ${s % 60} s`;
}
