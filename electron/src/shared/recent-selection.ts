import type {
  NotePage,
  RecentPageEntry,
  RecentSelectionState,
  TreeSnapshot,
} from './types';

export interface SelectionTarget {
  notebookId: string | null;
  sectionId: string | null;
  pageId: string | null;
}

const MAX_RECENT_PAGES = 50;

export function emptyRecentSelection(): RecentSelectionState {
  return {
    notebookId: null,
    sectionId: null,
    pageId: null,
    byNotebook: {},
    bySection: {},
    recentPages: [],
  };
}

export function normalizeRecentSelection(raw: unknown): RecentSelectionState {
  if (!raw) return emptyRecentSelection();
  let obj: unknown = raw;
  if (typeof raw === 'string') {
    try {
      obj = JSON.parse(raw);
    } catch {
      return emptyRecentSelection();
    }
  }
  if (!obj || typeof obj !== 'object') return emptyRecentSelection();
  const r = obj as Record<string, unknown>;

  const notebookId =
    typeof r.notebookId === 'string' && r.notebookId ? r.notebookId : null;
  const sectionId =
    typeof r.sectionId === 'string' && r.sectionId ? r.sectionId : null;
  const pageId = typeof r.pageId === 'string' && r.pageId ? r.pageId : null;

  const byNotebook: Record<
    string,
    { sectionId: string | null; pageId: string | null }
  > = {};
  if (r.byNotebook && typeof r.byNotebook === 'object') {
    for (const [k, v] of Object.entries(
      r.byNotebook as Record<string, unknown>,
    )) {
      if (v && typeof v === 'object') {
        const entry = v as Record<string, unknown>;
        byNotebook[k] = {
          sectionId:
            typeof entry.sectionId === 'string' && entry.sectionId
              ? entry.sectionId
              : null,
          pageId:
            typeof entry.pageId === 'string' && entry.pageId
              ? entry.pageId
              : null,
        };
      }
    }
  }

  const bySection: Record<string, string> = {};
  if (r.bySection && typeof r.bySection === 'object') {
    for (const [k, v] of Object.entries(
      r.bySection as Record<string, unknown>,
    )) {
      if (typeof v === 'string' && v) {
        bySection[k] = v;
      }
    }
  }

  const recentPages: RecentPageEntry[] = [];
  if (Array.isArray(r.recentPages)) {
    for (const item of r.recentPages) {
      if (item && typeof item === 'object') {
        const it = item as Record<string, unknown>;
        if (
          typeof it.notebookId === 'string' &&
          it.notebookId &&
          typeof it.sectionId === 'string' &&
          it.sectionId &&
          typeof it.pageId === 'string' &&
          it.pageId
        ) {
          recentPages.push({
            notebookId: it.notebookId,
            sectionId: it.sectionId,
            pageId: it.pageId,
            openedAt:
              typeof it.openedAt === 'string' && it.openedAt
                ? it.openedAt
                : new Date(0).toISOString(),
          });
        }
      }
    }
  }

  return {
    notebookId,
    sectionId,
    pageId,
    byNotebook,
    bySection,
    recentPages: recentPages.slice(0, MAX_RECENT_PAGES),
  };
}

/**
 * Records a user navigation/selection into the recent selection state.
 */
export function recordRecentSelection(
  prev: RecentSelectionState | null | undefined,
  selection: SelectionTarget,
  nowIso = new Date().toISOString(),
): RecentSelectionState {
  const base = prev ? normalizeRecentSelection(prev) : emptyRecentSelection();
  const { notebookId, sectionId, pageId } = selection;

  const byNotebook = { ...base.byNotebook };
  const bySection = { ...base.bySection };
  let recentPages = [...base.recentPages];

  if (notebookId) {
    const prevNb = byNotebook[notebookId];
    byNotebook[notebookId] = {
      sectionId: sectionId ?? prevNb?.sectionId ?? null,
      pageId: pageId ?? (sectionId === prevNb?.sectionId ? prevNb?.pageId ?? null : null),
    };
  }

  if (notebookId && sectionId && pageId) {
    bySection[`${notebookId}/${sectionId}`] = pageId;
    recentPages = [
      { notebookId, sectionId, pageId, openedAt: nowIso },
      ...recentPages.filter((e) => e.pageId !== pageId),
    ].slice(0, MAX_RECENT_PAGES);
  }

  return {
    notebookId,
    sectionId,
    pageId,
    byNotebook,
    bySection,
    recentPages,
  };
}

function pageTimestamp(p: NotePage): number {
  const u = Date.parse(p.updatedAt || '');
  if (Number.isFinite(u)) return u;
  const c = Date.parse(p.createdAt || '');
  if (Number.isFinite(c)) return c;
  return 0;
}

/**
 * Locates a page in `snap`, checking the preferred `(notebookId, sectionId)` first
 * and then scanning all notebooks/sections (in case a page was moved).
 */
export function findValidPageLocation(
  snap: TreeSnapshot,
  pageId: string | null | undefined,
  preferredNbId?: string | null,
  preferredSecId?: string | null,
): { notebookId: string; sectionId: string; pageId: string } | null {
  if (!pageId) return null;

  if (
    preferredNbId &&
    preferredSecId &&
    snap.notebooks.some((n) => n.id === preferredNbId) &&
    (snap.sectionsByNotebook[preferredNbId] ?? []).some(
      (s) => s.id === preferredSecId,
    )
  ) {
    const pgs = snap.pagesBySection[`${preferredNbId}/${preferredSecId}`] ?? [];
    if (pgs.some((p) => p.id === pageId)) {
      return { notebookId: preferredNbId, sectionId: preferredSecId, pageId };
    }
  }

  for (const nb of snap.notebooks) {
    const secs = snap.sectionsByNotebook[nb.id] ?? [];
    for (const sec of secs) {
      const pgs = snap.pagesBySection[`${nb.id}/${sec.id}`] ?? [];
      if (pgs.some((p) => p.id === pageId)) {
        return { notebookId: nb.id, sectionId: sec.id, pageId };
      }
    }
  }

  return null;
}

/**
 * Finds the most recently modified page across an optional notebook filter or the whole snapshot.
 */
function findMostRecentPageInSnapshot(
  snap: TreeSnapshot,
  onlyNotebookId?: string,
): { notebookId: string; sectionId: string; pageId: string } | null {
  let best: {
    notebookId: string;
    sectionId: string;
    pageId: string;
    ts: number;
  } | null = null;

  const notebooks = onlyNotebookId
    ? snap.notebooks.filter((n) => n.id === onlyNotebookId)
    : snap.notebooks;

  for (const nb of notebooks) {
    const secs = snap.sectionsByNotebook[nb.id] ?? [];
    for (const sec of secs) {
      const pgs = snap.pagesBySection[`${nb.id}/${sec.id}`] ?? [];
      for (const pg of pgs) {
        const ts = pageTimestamp(pg);
        if (!best || ts > best.ts) {
          best = {
            notebookId: nb.id,
            sectionId: sec.id,
            pageId: pg.id,
            ts,
          };
        }
      }
    }
  }

  return best
    ? {
        notebookId: best.notebookId,
        sectionId: best.sectionId,
        pageId: best.pageId,
      }
    : null;
}

/**
 * Resolves which page to open when the user clicks a section in the sidebar.
 * Prefers the last-opened page in that section, falling back to its first page.
 */
export function resolveSectionSelection(
  snap: TreeSnapshot,
  notebookId: string,
  sectionId: string,
  recent?: RecentSelectionState | null,
): { notebookId: string; sectionId: string; pageId: string | null } {
  const pgs = snap.pagesBySection[`${notebookId}/${sectionId}`] ?? [];
  if (pgs.length === 0) {
    return { notebookId, sectionId, pageId: null };
  }

  const secKey = `${notebookId}/${sectionId}`;
  const rememberedPageId = recent?.bySection?.[secKey];
  if (rememberedPageId && pgs.some((p) => p.id === rememberedPageId)) {
    return { notebookId, sectionId, pageId: rememberedPageId };
  }

  if (recent?.recentPages) {
    for (const entry of recent.recentPages) {
      if (
        entry.notebookId === notebookId &&
        entry.sectionId === sectionId &&
        pgs.some((p) => p.id === entry.pageId)
      ) {
        return { notebookId, sectionId, pageId: entry.pageId };
      }
    }
  }

  return { notebookId, sectionId, pageId: pgs[0].id };
}

/**
 * Resolves which section and page to open when switching to a notebook.
 * Prefers the last-opened section & page in that notebook, then the most recently
 * modified page in that notebook, then its first non-empty section.
 */
export function resolveNotebookSelection(
  snap: TreeSnapshot,
  notebookId: string,
  recent?: RecentSelectionState | null,
): { notebookId: string; sectionId: string | null; pageId: string | null } {
  const secs = snap.sectionsByNotebook[notebookId] ?? [];
  if (secs.length === 0) {
    return { notebookId, sectionId: null, pageId: null };
  }

  const byNb = recent?.byNotebook?.[notebookId];
  if (byNb?.pageId) {
    const loc = findValidPageLocation(
      snap,
      byNb.pageId,
      notebookId,
      byNb.sectionId,
    );
    if (loc && loc.notebookId === notebookId) {
      return loc;
    }
  }

  if (recent?.recentPages) {
    for (const entry of recent.recentPages) {
      if (entry.notebookId === notebookId) {
        const loc = findValidPageLocation(
          snap,
          entry.pageId,
          notebookId,
          entry.sectionId,
        );
        if (loc && loc.notebookId === notebookId) {
          return loc;
        }
      }
    }
  }

  if (byNb?.sectionId && secs.some((s) => s.id === byNb.sectionId)) {
    const resolvedSec = resolveSectionSelection(
      snap,
      notebookId,
      byNb.sectionId,
      recent,
    );
    if (resolvedSec.pageId) return resolvedSec;
  }

  const mostRecentInNb = findMostRecentPageInSnapshot(snap, notebookId);
  if (mostRecentInNb) return mostRecentInNb;

  const firstWithPages =
    secs.find(
      (s) => (snap.pagesBySection[`${notebookId}/${s.id}`] ?? []).length > 0,
    ) ?? secs[0];

  return resolveSectionSelection(snap, notebookId, firstWithPages.id, recent);
}

/**
 * Resolves the notebook, section, and page to select when opening the app
 * or when reconciling tree changes.
 */
export function resolveInitialTreeSelection(
  snap: TreeSnapshot,
  opts?: {
    current?: SelectionTarget;
    keepCurrent?: boolean;
    recent?: RecentSelectionState | null;
  },
): SelectionTarget {
  if (snap.notebooks.length === 0) {
    return { notebookId: null, sectionId: null, pageId: null };
  }

  const keepCurrent = opts?.keepCurrent ?? false;
  const current = opts?.current;
  const recent = opts?.recent;

  // 1. Keep current selection if requested and still valid in the snapshot.
  if (keepCurrent && current?.notebookId) {
    if (current.pageId) {
      const validCurrentPage = findValidPageLocation(
        snap,
        current.pageId,
        current.notebookId,
        current.sectionId,
      );
      if (validCurrentPage) return validCurrentPage;
    }

    const validNb = snap.notebooks.find((n) => n.id === current.notebookId);
    if (validNb) {
      const secs = snap.sectionsByNotebook[validNb.id] ?? [];
      if (current.sectionId && secs.some((s) => s.id === current.sectionId)) {
        const resolvedSec = resolveSectionSelection(
          snap,
          validNb.id,
          current.sectionId,
          recent,
        );
        if (resolvedSec.pageId) return resolvedSec;
      }
      const resolvedNb = resolveNotebookSelection(snap, validNb.id, recent);
      if (resolvedNb.pageId) return resolvedNb;
    }
  }

  // 2. Restore the last opened page/section/notebook from persisted recent state.
  if (recent) {
    if (recent.pageId) {
      const exactOrMoved = findValidPageLocation(
        snap,
        recent.pageId,
        recent.notebookId,
        recent.sectionId,
      );
      if (exactOrMoved) return exactOrMoved;
    }

    for (const entry of recent.recentPages ?? []) {
      const found = findValidPageLocation(
        snap,
        entry.pageId,
        entry.notebookId,
        entry.sectionId,
      );
      if (found) return found;
    }

    if (
      recent.notebookId &&
      snap.notebooks.some((n) => n.id === recent.notebookId)
    ) {
      const secs = snap.sectionsByNotebook[recent.notebookId] ?? [];
      if (
        recent.sectionId &&
        secs.some((s) => s.id === recent.sectionId)
      ) {
        const secSel = resolveSectionSelection(
          snap,
          recent.notebookId,
          recent.sectionId,
          recent,
        );
        if (secSel.pageId) return secSel;
      }
      const nbSel = resolveNotebookSelection(snap, recent.notebookId, recent);
      if (nbSel.pageId) return nbSel;
    }
  }

  // 3. Fall back to the most recently modified page across all notebooks.
  const mostRecent = findMostRecentPageInSnapshot(snap);
  if (mostRecent) return mostRecent;

  // 4. No pages exist anywhere yet: pick the recent notebook/section or first notebook with sections.
  if (
    recent?.notebookId &&
    snap.notebooks.some((n) => n.id === recent.notebookId)
  ) {
    return resolveNotebookSelection(snap, recent.notebookId, recent);
  }

  const nbWithSections =
    snap.notebooks.find(
      (n) => (snap.sectionsByNotebook[n.id]?.length ?? 0) > 0,
    ) ?? snap.notebooks[0];
  const firstSec = (snap.sectionsByNotebook[nbWithSections.id] ?? [])[0];
  return {
    notebookId: nbWithSections.id,
    sectionId: firstSec ? firstSec.id : null,
    pageId: null,
  };
}
