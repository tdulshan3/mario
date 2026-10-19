import React, { useState } from 'react';
import {
  Button,
  ContextMenu,
  Icon,
  MenuItem,
  MenuSeparator,
  SearchField,
  Sidebar,
  SidebarItem,
  SidebarSection,
} from '../macos/macos';
import type { Notebook, NotePage, Section } from '../shared/types';

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
  searchQuery: string;
  onSearchQueryChange: (q: string) => void;
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
  onReorderNotebooks?: (ordered: Notebook[]) => void;
  onReorderSections?: (notebookId: string, ordered: Section[]) => void;
  onReorderPages?: (
    notebookId: string,
    sectionId: string,
    ordered: NotePage[],
  ) => void;
  onOpenSettings: () => void;
}

export function MacSidebarNav({
  notebooks,
  sectionsByNotebook,
  pagesByKey,
  activePlace,
  selectedNotebookId,
  selectedSectionId,
  selectedPageId,
  searchQuery,
  onSearchQueryChange,
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
  onReorderNotebooks,
  onReorderSections,
  onReorderPages,
  onOpenSettings,
}: MacSidebarNavProps) {
  const [expandedNotebooks, setExpandedNotebooks] = useState<
    Record<string, boolean>
  >(() => {
    const init: Record<string, boolean> = {};
    for (const nb of notebooks) init[nb.id] = true;
    return init;
  });
  const [expandedSections, setExpandedSections] = useState<
    Record<string, boolean>
  >({});
  const [dragNbId, setDragNbId] = useState<string | null>(null);
  const [dragSecId, setDragSecId] = useState<string | null>(null);
  const [dragPageId, setDragPageId] = useState<string | null>(null);

  const q = searchQuery.trim().toLowerCase();

  const toggleNotebook = (nbId: string) => {
    setExpandedNotebooks((prev) => ({
      ...prev,
      [nbId]: !(prev[nbId] ?? true),
    }));
  };

  const toggleSection = (secId: string) => {
    setExpandedSections((prev) => ({
      ...prev,
      [secId]: !(prev[secId] ?? true),
    }));
  };

  return (
    <Sidebar
      width={248}
      label="Notebooks"
      style={{ display: 'flex', flexDirection: 'column' }}
    >
      <div style={{ padding: '10px 10px 4px' }}>
        <SearchField
          value={searchQuery}
          onChange={onSearchQueryChange}
          placeholder="Filter pages…"
          label="Filter pages"
        />
      </div>

      <SidebarSection>
        <SidebarItem
          icon="clock"
          label="Recents"
          selected={activePlace === 'recents'}
          onClick={onSelectRecents}
        />
      </SidebarSection>

      <SidebarSection title="Notebooks">
        {notebooks.map((nb) => {
          const sections = sectionsByNotebook[nb.id] ?? [];
          const nbOpen = (expandedNotebooks[nb.id] ?? true) || q.length > 0;

          const visibleSections = sections.filter((sec) => {
            if (!q) return true;
            if (
              nb.name.toLowerCase().includes(q) ||
              sec.name.toLowerCase().includes(q)
            ) {
              return true;
            }
            const pages = pagesByKey[`${nb.id}/${sec.id}`] ?? [];
            return pages.some((p) => p.title.toLowerCase().includes(q));
          });

          if (
            q &&
            !nb.name.toLowerCase().includes(q) &&
            visibleSections.length === 0
          ) {
            return null;
          }

          return (
            <React.Fragment key={nb.id}>
              <div
                draggable
                onDragStart={() => setDragNbId(nb.id)}
                onDragOver={(e) => e.preventDefault()}
                onDrop={() => {
                  if (!dragNbId || dragNbId === nb.id || !onReorderNotebooks)
                    return;
                  const next = [...notebooks];
                  const fromIdx = next.findIndex((x) => x.id === dragNbId);
                  const toIdx = next.findIndex((x) => x.id === nb.id);
                  if (fromIdx >= 0 && toIdx >= 0) {
                    const [moved] = next.splice(fromIdx, 1);
                    next.splice(toIdx, 0, moved);
                    onReorderNotebooks(
                      next.map((item, idx) => ({ ...item, order: idx })),
                    );
                  }
                  setDragNbId(null);
                }}
              >
                <ContextMenu
                  menu={
                    <>
                      <MenuItem
                        icon="plus"
                        onSelect={() => onNewSection(nb.id)}
                      >
                        New Section…
                      </MenuItem>
                      <MenuItem
                        icon="pencil"
                        onSelect={() => onEditNotebook(nb)}
                      >
                        Edit Notebook…
                      </MenuItem>
                      <MenuSeparator />
                      <MenuItem
                        icon="trash"
                        onSelect={() => onDeleteNotebook(nb)}
                      >
                        Delete Notebook…
                      </MenuItem>
                    </>
                  }
                >
                  <SidebarItem
                    icon={nbOpen ? 'disclosure-down' : 'disclosure-right'}
                    label={nb.name}
                    selected={
                      activePlace === 'notebook' &&
                      selectedNotebookId === nb.id
                    }
                    onClick={() => {
                      if (selectedNotebookId === nb.id) {
                        toggleNotebook(nb.id);
                      } else {
                        setExpandedNotebooks((p) => ({ ...p, [nb.id]: true }));
                        onSelectNotebook(nb.id);
                      }
                    }}
                  />
                </ContextMenu>
              </div>

              {nbOpen && (
                <div className="mario-sidebar-sublist">
                  {visibleSections.map((sec) => {
                    const key = `${nb.id}/${sec.id}`;
                    const pages = (pagesByKey[key] ?? []).filter(
                      (p) =>
                        !q ||
                        p.title.toLowerCase().includes(q) ||
                        sec.name.toLowerCase().includes(q) ||
                        nb.name.toLowerCase().includes(q),
                    );
                    const secOpen =
                      (expandedSections[sec.id] ?? true) || q.length > 0;

                    return (
                      <React.Fragment key={sec.id}>
                        <div
                          draggable
                          onDragStart={() => setDragSecId(sec.id)}
                          onDragOver={(e) => e.preventDefault()}
                          onDrop={() => {
                            if (
                              !dragSecId ||
                              dragSecId === sec.id ||
                              !onReorderSections
                            )
                              return;
                            const next = [...sections];
                            const fromIdx = next.findIndex(
                              (x) => x.id === dragSecId,
                            );
                            const toIdx = next.findIndex(
                              (x) => x.id === sec.id,
                            );
                            if (fromIdx >= 0 && toIdx >= 0) {
                              const [moved] = next.splice(fromIdx, 1);
                              next.splice(toIdx, 0, moved);
                              onReorderSections(
                                nb.id,
                                next.map((item, idx) => ({
                                  ...item,
                                  order: idx,
                                })),
                              );
                            }
                            setDragSecId(null);
                          }}
                        >
                          <ContextMenu
                            menu={
                              <>
                                <MenuItem
                                  icon="plus"
                                  onSelect={() => onNewPage(nb.id, sec.id)}
                                >
                                  New Page
                                </MenuItem>
                                <MenuItem
                                  icon="pencil"
                                  onSelect={() => onEditSection(sec)}
                                >
                                  Edit Section…
                                </MenuItem>
                                <MenuSeparator />
                                <MenuItem
                                  icon="trash"
                                  onSelect={() => onDeleteSection(sec)}
                                >
                                  Delete Section…
                                </MenuItem>
                              </>
                            }
                          >
                            <SidebarItem
                              icon="folder"
                              label={sec.name}
                              detail={pages.length > 0 ? pages.length : undefined}
                              selected={
                                activePlace === 'section' &&
                                selectedSectionId === sec.id
                              }
                              onClick={() => {
                                if (selectedSectionId === sec.id) {
                                  toggleSection(sec.id);
                                } else {
                                  setExpandedSections((p) => ({
                                    ...p,
                                    [sec.id]: true,
                                  }));
                                  onSelectSection(nb.id, sec.id);
                                }
                              }}
                            />
                          </ContextMenu>
                        </div>

                        {secOpen && pages.length > 0 && (
                          <div className="mario-sidebar-sublist">
                            {pages.map((page) => (
                              <div
                                key={page.id}
                                draggable
                                onDragStart={() => setDragPageId(page.id)}
                                onDragOver={(e) => e.preventDefault()}
                                onDrop={() => {
                                  if (
                                    !dragPageId ||
                                    dragPageId === page.id ||
                                    !onReorderPages
                                  )
                                    return;
                                  const allPages = [
                                    ...(pagesByKey[key] ?? []),
                                  ];
                                  const fromIdx = allPages.findIndex(
                                    (x) => x.id === dragPageId,
                                  );
                                  const toIdx = allPages.findIndex(
                                    (x) => x.id === page.id,
                                  );
                                  if (fromIdx >= 0 && toIdx >= 0) {
                                    const [moved] = allPages.splice(
                                      fromIdx,
                                      1,
                                    );
                                    allPages.splice(toIdx, 0, moved);
                                    onReorderPages(
                                      nb.id,
                                      sec.id,
                                      allPages.map((item, idx) => ({
                                        ...item,
                                        order: idx,
                                      })),
                                    );
                                  }
                                  setDragPageId(null);
                                }}
                              >
                                <ContextMenu
                                  menu={
                                    <>
                                      <MenuItem
                                        icon="pencil"
                                        onSelect={() => onRenamePage(page)}
                                      >
                                        Rename…
                                      </MenuItem>
                                      <MenuItem
                                        icon="square-and-arrow-up"
                                        onSelect={() =>
                                          onExportPageMarkdown(page)
                                        }
                                      >
                                        Export as Markdown…
                                      </MenuItem>
                                      <MenuItem
                                        icon="printer"
                                        onSelect={() => onExportPagePdf(page)}
                                      >
                                        Export as PDF…
                                      </MenuItem>
                                      <MenuSeparator />
                                      <MenuItem
                                        icon="trash"
                                        onSelect={() => onDeletePage(page)}
                                      >
                                        Delete Page…
                                      </MenuItem>
                                    </>
                                  }
                                >
                                  <SidebarItem
                                    icon="doc-text"
                                    label={page.title || 'Untitled Page'}
                                    selected={
                                      activePlace === 'page' &&
                                      selectedPageId === page.id
                                    }
                                    onClick={() =>
                                      onSelectPage(nb.id, sec.id, page.id)
                                    }
                                  />
                                </ContextMenu>
                              </div>
                            ))}
                          </div>
                        )}
                      </React.Fragment>
                    );
                  })}
                </div>
              )}
            </React.Fragment>
          );
        })}
      </SidebarSection>

      <div className="mario-sidebar-footer">
        <Button
          variant="borderless"
          size="small"
          icon="plus"
          onClick={onNewNotebook}
        >
          New Notebook
        </Button>
        <Button
          variant="borderless"
          size="small"
          icon="gear"
          label="Settings"
          onClick={onOpenSettings}
        />
      </div>
    </Sidebar>
  );
}
