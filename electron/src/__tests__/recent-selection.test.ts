import { describe, expect, it } from 'vitest';
import {
  emptyRecentSelection,
  normalizeRecentSelection,
  recordRecentSelection,
  resolveInitialTreeSelection,
  resolveNotebookSelection,
  resolveSectionSelection,
} from '../shared/recent-selection';
import type { TreeSnapshot } from '../shared/types';

function makeSnapshot(): TreeSnapshot {
  return {
    notebooks: [
      {
        id: 'nb-empty',
        name: 'Empty Projects',
        ownerId: 'u1',
        collaboratorUids: [],
        colorIndex: 0,
        createdAt: '2026-10-01T00:00:00Z',
        updatedAt: '2026-10-01T00:00:00Z',
      },
      {
        id: 'nb-nelu',
        name: 'Nelu',
        ownerId: 'u1',
        collaboratorUids: [],
        colorIndex: 1,
        createdAt: '2026-10-10T00:00:00Z',
        updatedAt: '2026-10-22T00:00:00Z',
      },
      {
        id: 'nb-issues',
        name: 'Issues',
        ownerId: 'u1',
        collaboratorUids: [],
        colorIndex: 2,
        createdAt: '2026-06-01T00:00:00Z',
        updatedAt: '2026-06-01T00:00:00Z',
      },
    ],
    sectionsByNotebook: {
      'nb-empty': [],
      'nb-nelu': [
        {
          id: 'sec-general',
          notebookId: 'nb-nelu',
          name: 'General',
          colorIndex: 0,
          order: 0,
        },
        {
          id: 'sec-ops',
          notebookId: 'nb-nelu',
          name: 'Ops',
          colorIndex: 1,
          order: 1,
        },
      ],
      'nb-issues': [
        {
          id: 'sec-features',
          notebookId: 'nb-issues',
          name: 'Features',
          colorIndex: 2,
          order: 0,
        },
      ],
    },
    pagesBySection: {
      'nb-nelu/sec-general': [
        {
          id: 'pg-vm',
          notebookId: 'nb-nelu',
          sectionId: 'sec-general',
          title: 'Home lab vm setup',
          driveFileId: 'f1',
          order: 0,
          indentLevel: 0,
          createdAt: '2026-10-20T00:00:00Z',
          updatedAt: '2026-10-22T04:37:05Z',
        },
        {
          id: 'pg-dns',
          notebookId: 'nb-nelu',
          sectionId: 'sec-general',
          title: 'DNS config',
          driveFileId: 'f2',
          order: 1,
          indentLevel: 0,
          createdAt: '2026-10-21T00:00:00Z',
          updatedAt: '2026-10-21T10:00:00Z',
        },
      ],
      'nb-nelu/sec-ops': [
        {
          id: 'pg-deploy',
          notebookId: 'nb-nelu',
          sectionId: 'sec-ops',
          title: 'Deploy notes',
          driveFileId: 'f3',
          order: 0,
          indentLevel: 0,
          createdAt: '2026-10-18T00:00:00Z',
          updatedAt: '2026-10-18T12:00:00Z',
        },
      ],
      'nb-issues/sec-features': [
        {
          id: 'pg-enc',
          notebookId: 'nb-issues',
          sectionId: 'sec-features',
          title: 'Encrypted Pages',
          driveFileId: 'f4',
          order: 0,
          indentLevel: 0,
          createdAt: '2026-10-26T05:05:00Z',
          updatedAt: '2026-10-26T05:07:21Z',
        },
      ],
    },
    syncStatus: {
      pendingChanges: 0,
      syncing: false,
      offlineMode: false,
    },
  };
}

describe('Recent Selection & Startup Restoration', () => {
  it('opens the saved last-opened notebook, section, and page on startup', () => {
    const snap = makeSnapshot();
    let recent = emptyRecentSelection();
    recent = recordRecentSelection(
      recent,
      {
        notebookId: 'nb-nelu',
        sectionId: 'sec-general',
        pageId: 'pg-dns',
      },
      '2026-10-27T10:00:00Z',
    );

    const resolved = resolveInitialTreeSelection(snap, {
      keepCurrent: false,
      recent,
    });

    expect(resolved).toEqual({
      notebookId: 'nb-nelu',
      sectionId: 'sec-general',
      pageId: 'pg-dns',
    });
  });

  it('falls back to the previous MRU page if the last-opened page was deleted', () => {
    const snap = makeSnapshot();
    let recent = emptyRecentSelection();
    recent = recordRecentSelection(
      recent,
      {
        notebookId: 'nb-nelu',
        sectionId: 'sec-ops',
        pageId: 'pg-deploy',
      },
      '2026-10-27T09:00:00Z',
    );
    recent = recordRecentSelection(
      recent,
      {
        notebookId: 'nb-issues',
        sectionId: 'sec-features',
        pageId: 'pg-deleted-id',
      },
      '2026-10-27T10:00:00Z',
    );

    const resolved = resolveInitialTreeSelection(snap, {
      keepCurrent: false,
      recent,
    });

    expect(resolved).toEqual({
      notebookId: 'nb-nelu',
      sectionId: 'sec-ops',
      pageId: 'pg-deploy',
    });
  });

  it('skips empty first notebooks and opens the most recently modified page when no recent state is saved yet', () => {
    const snap = makeSnapshot();
    const resolved = resolveInitialTreeSelection(snap, {
      keepCurrent: false,
      recent: emptyRecentSelection(),
    });

    // Even though `nb-empty` is notebooks[0], `pg-enc` in `nb-issues/sec-features` is the most recently modified page.
    expect(resolved).toEqual({
      notebookId: 'nb-issues',
      sectionId: 'sec-features',
      pageId: 'pg-enc',
    });
  });

  it('remembers per-notebook and per-section active pages when switching notebooks or sections', () => {
    const snap = makeSnapshot();
    let recent = emptyRecentSelection();
    recent = recordRecentSelection(recent, {
      notebookId: 'nb-nelu',
      sectionId: 'sec-general',
      pageId: 'pg-dns',
    });
    recent = recordRecentSelection(recent, {
      notebookId: 'nb-issues',
      sectionId: 'sec-features',
      pageId: 'pg-enc',
    });

    expect(resolveNotebookSelection(snap, 'nb-nelu', recent)).toEqual({
      notebookId: 'nb-nelu',
      sectionId: 'sec-general',
      pageId: 'pg-dns',
    });

    expect(
      resolveSectionSelection(snap, 'nb-nelu', 'sec-general', recent),
    ).toEqual({
      notebookId: 'nb-nelu',
      sectionId: 'sec-general',
      pageId: 'pg-dns',
    });
  });

  it('round-trips through JSON normalization safely', () => {
    const recent = recordRecentSelection(emptyRecentSelection(), {
      notebookId: 'nb-nelu',
      sectionId: 'sec-general',
      pageId: 'pg-vm',
    });
    const parsed = normalizeRecentSelection(JSON.stringify(recent));
    expect(parsed.notebookId).toBe('nb-nelu');
    expect(parsed.sectionId).toBe('sec-general');
    expect(parsed.pageId).toBe('pg-vm');
    expect(parsed.bySection['nb-nelu/sec-general']).toBe('pg-vm');
    expect(parsed.recentPages).toHaveLength(1);
  });
});
