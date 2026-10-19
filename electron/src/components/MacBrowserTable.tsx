import React, { useMemo, useState } from 'react';
import {
  Button,
  Content,
  EmptyState,
  Section as MacSection,
  Stack,
  Table,
  type RowId,
  type TableColumn,
} from '../macos/macos';
import type { Notebook, NotePage, Section } from '../shared/types';
import type { SidebarPlace } from './MacSidebarNav';

export interface MacBrowserTableProps {
  place: SidebarPlace;
  notebooks: Notebook[];
  sectionsByNotebook: Record<string, Section[]>;
  pagesByKey: Record<string, NotePage[]>;
  selectedNotebook: Notebook | null;
  selectedSection: Section | null;
  onOpenPage: (notebookId: string, sectionId: string, pageId: string) => void;
  onOpenSection: (notebookId: string, sectionId: string) => void;
  onNewNotebook: () => void;
  onNewSection: (notebookId: string) => void;
  onNewPage: (notebookId: string, sectionId: string) => void;
}

interface PageRow {
  id: string;
  title: string;
  notebookId: string;
  notebookName: string;
  sectionId: string;
  sectionName: string;
  updatedAt: string;
  updatedTimestamp: number;
}

interface SectionRow {
  id: string;
  name: string;
  notebookId: string;
  pageCount: number;
  updatedLabel: string;
  updatedTimestamp: number;
}

function formatRelativeDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  const now = new Date();
  const diffMs = now.getTime() - d.getTime();
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) return 'Just now';
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24 && d.getDate() === now.getDate()) {
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }
  return d.toLocaleDateString([], {
    month: 'short',
    day: 'numeric',
    year: d.getFullYear() !== now.getFullYear() ? 'numeric' : undefined,
  });
}

export function MacBrowserTable({
  place,
  notebooks,
  sectionsByNotebook,
  pagesByKey,
  selectedNotebook,
  selectedSection,
  onOpenPage,
  onOpenSection,
  onNewNotebook,
  onNewSection,
  onNewPage,
}: MacBrowserTableProps) {
  const [selection, setSelection] = useState<RowId[]>([]);

  const allPages = useMemo<PageRow[]>(() => {
    const out: PageRow[] = [];
    for (const nb of notebooks) {
      const secs = sectionsByNotebook[nb.id] ?? [];
      for (const sec of secs) {
        const pgs = pagesByKey[`${nb.id}/${sec.id}`] ?? [];
        for (const p of pgs) {
          const ts = new Date(p.updatedAt).getTime() || 0;
          out.push({
            id: p.id,
            title: p.title || 'Untitled Page',
            notebookId: nb.id,
            notebookName: nb.name,
            sectionId: sec.id,
            sectionName: sec.name,
            updatedAt: formatRelativeDate(p.updatedAt),
            updatedTimestamp: ts,
          });
        }
      }
    }
    return out.sort((a, b) => b.updatedTimestamp - a.updatedTimestamp);
  }, [notebooks, sectionsByNotebook, pagesByKey]);

  const pageColumns = useMemo<TableColumn<PageRow>[]>(
    () => [
      {
        key: 'title',
        title: 'Title',
        sortable: true,
      },
      {
        key: 'sectionName',
        title: 'Section',
        width: 170,
        sortable: true,
      },
      {
        key: 'notebookName',
        title: 'Notebook',
        width: 170,
        sortable: true,
      },
      {
        key: 'updatedAt',
        title: 'Modified',
        width: 130,
        sortable: true,
        sortValue: (row) => row.updatedTimestamp,
      },
    ],
    [],
  );

  if (notebooks.length === 0) {
    return (
      <Content>
        <EmptyState
          icon="book"
          title="No Notebooks"
          message="Create a notebook to organize your sections and pages."
          actions={
            <Button variant="prominent" onClick={onNewNotebook}>
              New Notebook…
            </Button>
          }
        />
      </Content>
    );
  }

  if (place === 'recents') {
    if (allPages.length === 0) {
      const firstNb = notebooks[0];
      const firstSec = (sectionsByNotebook[firstNb.id] ?? [])[0];
      return (
        <Content>
          <EmptyState
            icon="clock"
            title="No Recent Pages"
            message="Pages you create or edit will appear here."
            actions={
              firstSec ? (
                <Button
                  variant="prominent"
                  onClick={() => onNewPage(firstNb.id, firstSec.id)}
                >
                  New Page
                </Button>
              ) : (
                <Button
                  variant="prominent"
                  onClick={() => onNewSection(firstNb.id)}
                >
                  New Section…
                </Button>
              )
            }
          />
        </Content>
      );
    }

    const now = new Date();
    const startOfToday = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate(),
    ).getTime();
    const startOfYesterday = startOfToday - 86400000;

    const todayRows = allPages.filter(
      (r) => r.updatedTimestamp >= startOfToday,
    );
    const yesterdayRows = allPages.filter(
      (r) =>
        r.updatedTimestamp >= startOfYesterday &&
        r.updatedTimestamp < startOfToday,
    );
    const earlierRows = allPages.filter(
      (r) => r.updatedTimestamp < startOfYesterday,
    );

    const renderGroup = (title: string, rows: PageRow[]) => {
      if (rows.length === 0) return null;
      return (
        <MacSection title={title}>
          <Table
            label={title}
            columns={pageColumns}
            rows={rows}
            selection={selection}
            onSelectionChange={setSelection}
            rowIcon={() => 'doc-text'}
            onRowAction={(row) =>
              onOpenPage(row.notebookId, row.sectionId, row.id)
            }
          />
        </MacSection>
      );
    };

    return (
      <Content>
        <Stack>
          {renderGroup('Today', todayRows)}
          {renderGroup('Yesterday', yesterdayRows)}
          {renderGroup('Earlier', earlierRows)}
        </Stack>
      </Content>
    );
  }

  if (place === 'notebook' && selectedNotebook) {
    const secs = sectionsByNotebook[selectedNotebook.id] ?? [];
    if (secs.length === 0) {
      return (
        <Content>
          <EmptyState
            icon="folder"
            title="No Sections"
            message={`Create a section in “${selectedNotebook.name}” to start taking notes.`}
            actions={
              <Button
                variant="prominent"
                onClick={() => onNewSection(selectedNotebook.id)}
              >
                New Section…
              </Button>
            }
          />
        </Content>
      );
    }

    const secRows: SectionRow[] = secs.map((s) => {
      const pgs = pagesByKey[`${selectedNotebook.id}/${s.id}`] ?? [];
      const latest = pgs.reduce((acc, p) => {
        const t = new Date(p.updatedAt).getTime() || 0;
        return t > acc ? t : acc;
      }, 0);
      return {
        id: s.id,
        name: s.name,
        notebookId: selectedNotebook.id,
        pageCount: pgs.length,
        updatedLabel:
          latest > 0 ? formatRelativeDate(new Date(latest).toISOString()) : '—',
        updatedTimestamp: latest,
      };
    });

    const secColumns: TableColumn<SectionRow>[] = [
      { key: 'name', title: 'Section', sortable: true },
      {
        key: 'pageCount',
        title: 'Pages',
        width: 100,
        numeric: true,
        sortable: true,
      },
      {
        key: 'updatedLabel',
        title: 'Last Updated',
        width: 150,
        sortable: true,
        sortValue: (r) => r.updatedTimestamp,
      },
    ];

    return (
      <Content flush>
        <Table
          label={selectedNotebook.name}
          columns={secColumns}
          rows={secRows}
          sticky
          selection={selection}
          onSelectionChange={setSelection}
          rowIcon={() => 'folder'}
          onRowAction={(row) => onOpenSection(row.notebookId, row.id)}
        />
      </Content>
    );
  }

  if (place === 'section' && selectedNotebook && selectedSection) {
    const pgs =
      pagesByKey[`${selectedNotebook.id}/${selectedSection.id}`] ?? [];
    if (pgs.length === 0) {
      return (
        <Content>
          <EmptyState
            icon="doc-text"
            title="No Pages"
            message={`Create a page in “${selectedSection.name}” with Ctrl+N.`}
            actions={
              <Button
                variant="prominent"
                onClick={() =>
                  onNewPage(selectedNotebook.id, selectedSection.id)
                }
              >
                New Page
              </Button>
            }
          />
        </Content>
      );
    }

    const rows: PageRow[] = pgs.map((p) => ({
      id: p.id,
      title: p.title || 'Untitled Page',
      notebookId: selectedNotebook.id,
      notebookName: selectedNotebook.name,
      sectionId: selectedSection.id,
      sectionName: selectedSection.name,
      updatedAt: formatRelativeDate(p.updatedAt),
      updatedTimestamp: new Date(p.updatedAt).getTime() || 0,
    }));

    return (
      <Content flush>
        <Table
          label={selectedSection.name}
          columns={pageColumns}
          rows={rows}
          sticky
          selection={selection}
          onSelectionChange={setSelection}
          rowIcon={() => 'doc-text'}
          onRowAction={(row) =>
            onOpenPage(row.notebookId, row.sectionId, row.id)
          }
        />
      </Content>
    );
  }

  return (
    <Content>
      <EmptyState
        icon="doc-text"
        title="No Selection"
        message="Select a notebook, section, or page from the sidebar."
      />
    </Content>
  );
}
