import React, { useState } from 'react';
import {
  Button,
  ContextMenu,
  Icon,
  MenuHeader,
  MenuItem,
  MenuSeparator,
  PullDownButton,
  SearchField,
  SidebarItem,
  SidebarSection,
  type IconName,
} from '../macos/macos';
import type {
  Notebook,
  NotePage,
  RecentSelectionState,
  Section,
  TreeSnapshot,
} from '../shared/types';
import {
  resolveNotebookSelection,
  resolveSectionSelection,
} from '../shared/recent-selection';

export const NOTEBOOK_COLORS = [
  '#3584e4',
  '#9141ac',
  '#2ec27e',
  '#e66100',
  '#e01b24',
  '#1c71d8',
  '#c061cb',
  '#26a269',
  '#f5c211',
  '#986a44',
];

export type SidebarPlace = 'recents' | 'notebook' | 'section' | 'page';

export interface MacSidebarNavProps {
  notebooks: Notebook[];
  sectionsByNotebook: Record<string, Section[]>;
  pagesByKey: Record<string, NotePage[]>;
  activePlace: SidebarPlace;
  selectedNotebookId: string | null;
  selectedSectionId: string | null;
  selectedPageId: string | null;
  recentSelection?: RecentSelectionState;
  searchQuery: string;
  onSearchQueryChange: (q: string) => void;
  /** Changes waiting to be uploaded, shown next to Sync Now. */
  syncPending: number;
  onSyncNow: () => void;
  onSelectRecents: () => void;
  onSelectNotebook: (notebookId: string) => void;
  onSelectSection: (notebookId: string, sectionId: string) => void;
  onSelectPage: (notebookId: string, sectionId: string, pageId: string) => void;
  onNewNotebook: () => void;
  onEditNotebook: (nb: Notebook) => void;
  onDeleteNotebook: (nb: Notebook) => void;
  onNewSection: (notebookId: string) => void;
  onEditSection: (sec: Section) => void;
  onDeleteSection: (sec: Section) => void;
  onNewPage: (notebookId: string, sectionId: string) => void;
  onRenamePage: (page: NotePage) => void;
  onDeletePage: (page: NotePage) => void;
  onExportPageMarkdown: (page: NotePage) => void;
  onExportPagePdf: (page: NotePage) => void;
  onReorderSections?: (notebookId: string, ordered: Section[]) => void;
  onReorderPages?: (notebookId: string, sectionId: string, ordered: NotePage[]) => void;
}

interface RowProps {
  icon: IconName;
  label: string;
  detail?: number;
  selected: boolean;
  onClick: () => void;
  menu: React.ReactNode;
  drag?: React.LiHTMLAttributes<HTMLLIElement>;
}

/** A kit sidebar row (`mac-sidebar__item`) that can also be dragged and right-clicked. */
function Row({ icon, label, detail, selected, onClick, menu, drag }: RowProps) {
  return (
    <li {...drag}>
      <ContextMenu menu={menu}>
        <button
          type="button"
          className="mac-sidebar__item"
          aria-current={selected ? 'page' : undefined}
          onClick={onClick}
        >
          <Icon name={icon} />
          <span className="mac-sidebar__label">{label}</span>
          {detail != null && detail > 0 && <span className="mac-sidebar__detail">{detail}</span>}
        </button>
      </ContextMenu>
    </li>
  );
}

/** Moves `fromId` to where `toId` is and renumbers `order`. */
function reorder<T extends { id: string; order: number }>(items: T[], fromId: string, toId: string): T[] | null {
  const next = [...items];
  const from = next.findIndex((x) => x.id === fromId);
  const to = next.findIndex((x) => x.id === toId);
  if (from < 0 || to < 0 || from === to) return null;
  const [moved] = next.splice(from, 1);
  next.splice(to, 0, moved);
  return next.map((item, idx) => ({ ...item, order: idx }));
}

/**
 * The sidebar shows one notebook at a time, as OneNote does: its sections, and
 * the pages of the open section one level in. Switching notebooks and the
 * notebook commands people use less (new, settings, sync, delete) live in the
 * notebook pull-down at the top.
 */
export function MacSidebarNav({
  notebooks,
  sectionsByNotebook,
  pagesByKey,
  activePlace,
  selectedNotebookId,
  selectedSectionId,
  selectedPageId,
  recentSelection,
  searchQuery,
  onSearchQueryChange,
  syncPending,
  onSyncNow,
  onSelectRecents,
  onSelectNotebook,
  onSelectSection,
  onSelectPage,
  onNewNotebook,
  onEditNotebook,
  onDeleteNotebook,
  onNewSection,
  onEditSection,
  onDeleteSection,
  onNewPage,
  onRenamePage,
  onDeletePage,
  onExportPageMarkdown,
  onExportPagePdf,
  onReorderSections,
  onReorderPages,
}: MacSidebarNavProps) {
  const [dragSecId, setDragSecId] = useState<string | null>(null);
  const [dragPageId, setDragPageId] = useState<string | null>(null);

  const notebook = notebooks.find((n) => n.id === selectedNotebookId) ?? notebooks[0] ?? null;
  const sections = notebook ? (sectionsByNotebook[notebook.id] ?? []) : [];
  const pagesOf = (nbId: string, secId: string) => pagesByKey[`${nbId}/${secId}`] ?? [];
  const q = searchQuery.trim().toLowerCase();

  const snapForResolve: TreeSnapshot = {
    notebooks,
    sectionsByNotebook,
    pagesBySection: pagesByKey,
    syncStatus: { pendingChanges: syncPending, syncing: false, offlineMode: false },
  };

  /** Opening a section opens its recent page (or first page), as OneNote does. */
  const openSection = (nbId: string, sec: Section) => {
    const resolved = resolveSectionSelection(
      snapForResolve,
      nbId,
      sec.id,
      recentSelection,
    );
    if (resolved.pageId) onSelectPage(nbId, sec.id, resolved.pageId);
    else onSelectSection(nbId, sec.id);
  };

  const openNotebook = (nb: Notebook) => {
    const resolved = resolveNotebookSelection(
      snapForResolve,
      nb.id,
      recentSelection,
    );
    if (resolved.sectionId && resolved.pageId) {
      onSelectPage(nb.id, resolved.sectionId, resolved.pageId);
    } else if (resolved.sectionId) {
      onSelectSection(nb.id, resolved.sectionId);
    } else {
      onSelectNotebook(nb.id);
    }
  };

  const sectionInView = sections.some((s) => s.id === selectedSectionId);
  const newPageSection = sections.find((s) => s.id === selectedSectionId) ?? sections[0];

  return (
    // The kit sidebar's own markup, with a footer under the scrolling body.
    <nav className="mac-sidebar mario-sidebar" aria-label="Notebook">
      <div className="mac-sidebar__body mac-scroll">
        <div className="mario-notebook-picker">
          <PullDownButton
            aria-label="Notebook"
            className="mario-notebook-picker__button"
            label={
              <>
                <Icon name="book" /> {notebook?.name ?? 'No Notebook'}
              </>
            }
          >
            {notebooks.length > 0 && <MenuHeader>Notebooks</MenuHeader>}
            {notebooks.map((nb) => (
              <MenuItem key={nb.id} checked={nb.id === notebook?.id} onSelect={() => openNotebook(nb)}>
                {nb.name}
              </MenuItem>
            ))}
            {notebooks.length > 0 && <MenuSeparator />}
            <MenuItem icon="plus" shortcut="⌃⌥N" onSelect={onNewNotebook}>
              New Notebook…
            </MenuItem>
            {notebook && (
              <>
                <MenuItem icon="pencil" onSelect={() => onEditNotebook(notebook)}>
                  Notebook Settings…
                </MenuItem>
                <MenuItem icon="arrow-clockwise" shortcut="⌃S" onSelect={onSyncNow}>
                  {syncPending > 0 ? `Sync Now (${syncPending} waiting)` : 'Sync Now'}
                </MenuItem>
                <MenuSeparator />
                <MenuItem icon="trash" onSelect={() => onDeleteNotebook(notebook)}>
                  Delete Notebook…
                </MenuItem>
              </>
            )}
          </PullDownButton>
        </div>

        <div className="mario-sidebar-filter">
          <SearchField
            value={searchQuery}
            onChange={onSearchQueryChange}
            placeholder="Filter pages"
            label="Filter pages in this notebook"
          />
        </div>

        <SidebarSection>
          <SidebarItem icon="clock" label="Recents" selected={activePlace === 'recents'} onClick={onSelectRecents} />
        </SidebarSection>

        {notebook && (
          <SidebarSection title="Sections">
            {sections.map((sec) => {
              const pages = pagesOf(notebook.id, sec.id);
              const shownPages = q
                ? pages.filter((p) => (p.title || 'Untitled Page').toLowerCase().includes(q))
                : pages;
              if (q && shownPages.length === 0 && !sec.name.toLowerCase().includes(q)) return null;
              // The open section shows its pages; while filtering, every section with a match does.
              const open = q ? shownPages.length > 0 : sec.id === selectedSectionId || (!sectionInView && sec === sections[0]);
              return (
                <React.Fragment key={sec.id}>
                  <Row
                    icon="folder"
                    label={sec.name}
                    detail={pages.length}
                    selected={activePlace === 'section' && selectedSectionId === sec.id}
                    onClick={() => openSection(notebook.id, sec)}
                    drag={{
                      draggable: true,
                      onDragStart: () => setDragSecId(sec.id),
                      onDragOver: (e) => dragSecId && e.preventDefault(),
                      onDrop: () => {
                        const next = dragSecId ? reorder(sections, dragSecId, sec.id) : null;
                        if (next) onReorderSections?.(notebook.id, next);
                        setDragSecId(null);
                      },
                    }}
                    menu={
                      <>
                        <MenuItem icon="plus" onSelect={() => onNewPage(notebook.id, sec.id)}>
                          New Page
                        </MenuItem>
                        <MenuItem icon="pencil" onSelect={() => onEditSection(sec)}>
                          Section Settings…
                        </MenuItem>
                        <MenuSeparator />
                        <MenuItem icon="trash" onSelect={() => onDeleteSection(sec)}>
                          Delete Section…
                        </MenuItem>
                      </>
                    }
                  />
                  {open && shownPages.length > 0 && (
                    <li>
                      <ul className="mac-sidebar__list" style={{ '--mac-sidebar-level': '12px' } as React.CSSProperties}>
                        {shownPages.map((page) => (
                          <Row
                            key={page.id}
                            icon="doc-text"
                            label={page.title || 'Untitled Page'}
                            selected={activePlace === 'page' && selectedPageId === page.id}
                            onClick={() => onSelectPage(notebook.id, sec.id, page.id)}
                            drag={{
                              draggable: true,
                              onDragStart: () => setDragPageId(page.id),
                              onDragOver: (e) => dragPageId && e.preventDefault(),
                              onDrop: () => {
                                const next = dragPageId ? reorder(pages, dragPageId, page.id) : null;
                                if (next) onReorderPages?.(notebook.id, sec.id, next);
                                setDragPageId(null);
                              },
                            }}
                            menu={
                              <>
                                <MenuItem icon="pencil" onSelect={() => onRenamePage(page)}>
                                  Rename…
                                </MenuItem>
                                <MenuItem icon="square-and-arrow-up" onSelect={() => onExportPageMarkdown(page)}>
                                  Export as Markdown…
                                </MenuItem>
                                <MenuItem icon="printer" onSelect={() => onExportPagePdf(page)}>
                                  Export as PDF…
                                </MenuItem>
                                <MenuSeparator />
                                <MenuItem icon="trash" onSelect={() => onDeletePage(page)}>
                                  Delete Page…
                                </MenuItem>
                              </>
                            }
                          />
                        ))}
                      </ul>
                    </li>
                  )}
                </React.Fragment>
              );
            })}
          </SidebarSection>
        )}
      </div>

      {notebook && (
        <div className="mario-sidebar-footer">
          <Button
            variant="borderless"
            size="small"
            icon="square-and-pencil"
            disabled={!newPageSection}
            onClick={() => newPageSection && onNewPage(notebook.id, newPageSection.id)}
          >
            New Page
          </Button>
          <Button variant="borderless" size="small" icon="plus" onClick={() => onNewSection(notebook.id)}>
            New Section
          </Button>
        </div>
      )}
    </nav>
  );
}
