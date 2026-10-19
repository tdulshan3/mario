import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { marked } from 'marked';
import katex from 'katex';
import {
  Alert,
  Button,
  Column,
  FieldGrid,
  PopUpButton,
  Row,
  Sheet,
  TextField,
  Titlebar,
  ToolbarButton,
  ToolbarGroup,
  Window,
  WindowBody,
  WindowMain,
} from './macos/macos';
import type {
  AuthUser,
  CollaboratorRole,
  Notebook,
  NotePage,
  PageContent,
  Section,
  SettingsState,
  TreeSnapshot,
} from './shared/types';
import {
  defaultSettings,
  documentToMarkdown,
  emptyPageContent,
  normalizeLatexFormula,
} from './shared/document-codec';
import { LoginView } from './components/LoginView';
import {
  MacSidebarNav,
  NOTEBOOK_COLORS,
  type SidebarPlace,
} from './components/MacSidebarNav';
import { MacBrowserTable } from './components/MacBrowserTable';
import { BlockEditor } from './components/BlockEditor';
import { AiInspectorPanel } from './components/AiInspectorPanel';
import {
  SettingsWindow,
  type SettingsPane,
} from './components/SettingsWindow';
import { GlobalSearchSheet } from './components/GlobalSearchSheet';

function buildPrintableHtml(title: string, md: string): string {
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
  const bodyHtml = String(marked.parse(withInlineMath, { async: false }));
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>${title}</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Inter", "Segoe UI", sans-serif;
      color: #1d1d1f;
      max-width: 720px;
      margin: 0 auto;
      padding: 24px 32px;
      font-size: 14px;
      line-height: 22px;
    }
    h1 { font-size: 26px; margin-bottom: 12px; border-bottom: 1px solid #e5e5ea; padding-bottom: 6px; }
    h2 { font-size: 20px; margin-top: 18px; }
    h3 { font-size: 16px; margin-top: 14px; }
    pre { background: #f5f5f7; padding: 12px; border-radius: 6px; overflow-x: auto; font-size: 12px; }
    code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 12px; }
    blockquote { border-left: 3px solid #007aff; margin: 8px 0; padding-left: 12px; color: #555; }
    table { border-collapse: collapse; width: 100%; margin: 12px 0; }
    th, td { border: 1px solid #d2d2d7; padding: 6px 10px; text-align: left; }
    th { background: #f5f5f7; }
  </style>
</head>
<body>
  <h1>${title}</h1>
  ${bodyHtml}
</body>
</html>`;
}

export function App() {
  // Auth state
  const [user, setUser] = useState<AuthUser | null>(null);
  const [restoringAuth, setRestoringAuth] = useState(true);
  const [signingIn, setSigningIn] = useState(false);
  const [authError, setAuthError] = useState<string | null>(null);

  // Settings
  const [settings, setSettings] = useState<SettingsState>(defaultSettings);
  const [fontFamily, setFontFamily] = useState('System');
  const [zoom, setZoom] = useState(1);

  // Tree state
  const [tree, setTree] = useState<TreeSnapshot>({
    notebooks: [],
    sectionsByNotebook: {},
    pagesBySection: {},
    syncStatus: {
      pendingChanges: 0,
      syncing: false,
      offlineMode: false,
    },
  });

  // Navigation selection
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [inspectorOpen, setInspectorOpen] = useState(true);
  const [activePlace, setActivePlace] = useState<SidebarPlace>('page');
  const [selectedNotebookId, setSelectedNotebookId] = useState<string | null>(
    null,
  );
  const [selectedSectionId, setSelectedSectionId] = useState<string | null>(
    null,
  );
  const [selectedPageId, setSelectedPageId] = useState<string | null>(null);
  const [sidebarSearch, setSidebarSearch] = useState('');

  // Open page content
  const [pageContent, setPageContent] = useState<PageContent>(() =>
    emptyPageContent(),
  );
  const [saveStatus, setSaveStatus] = useState<'saved' | 'saving' | 'dirty'>(
    'saved',
  );
  const [rawHtmlOverride, setRawHtmlOverride] = useState<string | null>(null);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Sheets & Alerts
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settingsInitialPane, setSettingsInitialPane] =
    useState<SettingsPane>('appearance');
  const [searchSheetOpen, setSearchSheetOpen] = useState(false);

  // Notebook create/edit sheet
  const [nbDialog, setNbDialog] = useState<{
    mode: 'create' | 'edit';
    target?: Notebook;
    name: string;
    colorIndex: number;
  } | null>(null);

  // Section create/edit sheet
  const [secDialog, setSecDialog] = useState<{
    mode: 'create' | 'edit';
    notebookId: string;
    target?: Section;
    name: string;
    colorIndex: number;
  } | null>(null);

  // Page rename sheet
  const [renamePageDialog, setRenamePageDialog] = useState<{
    page: NotePage;
    title: string;
  } | null>(null);

  // Share notebook sheet
  const [shareDialogOpen, setShareDialogOpen] = useState(false);
  const [shareEmail, setShareEmail] = useState('');
  const [shareRole, setShareRole] = useState<CollaboratorRole>('editor');
  const [shareBusy, setShareBusy] = useState(false);

  // Delete confirmation alert
  const [deleteAlert, setDeleteAlert] = useState<{
    title: string;
    message: string;
    onConfirm: () => Promise<void>;
  } | null>(null);

  // Apply theme mode to documentElement
  useEffect(() => {
    const root = document.documentElement;
    if (settings.themeMode === 'night' || settings.themeMode === 'black') {
      root.dataset.theme = 'dark';
    } else if (
      settings.themeMode === 'light' ||
      settings.themeMode === 'white'
    ) {
      root.dataset.theme = 'light';
    } else {
      delete root.dataset.theme;
    }
  }, [settings.themeMode]);

  const applyTreeSelection = useCallback(
    (snap: TreeSnapshot, keepCurrent = true) => {
      setTree(snap);
      if (snap.notebooks.length === 0) return;

      setSelectedNotebookId((prevNbId) => {
        const validNb =
          (keepCurrent &&
            prevNbId &&
            snap.notebooks.find((n) => n.id === prevNbId)) ||
          snap.notebooks[0];
        if (!validNb) return null;

        const secs = snap.sectionsByNotebook[validNb.id] ?? [];
        setSelectedSectionId((prevSecId) => {
          const validSec =
            (keepCurrent &&
              prevSecId &&
              secs.find((s) => s.id === prevSecId)) ||
            secs[0];
          if (!validSec) return null;

          const pgs = snap.pagesBySection[`${validNb.id}/${validSec.id}`] ?? [];
          setSelectedPageId((prevPageId) => {
            const validPage =
              (keepCurrent &&
                prevPageId &&
                pgs.find((p) => p.id === prevPageId)) ||
              pgs[0];
            return validPage ? validPage.id : null;
          });
          return validSec.id;
        });

        return validNb.id;
      });
    },
    [],
  );

  // Initial boot: load settings + restore auth + load snapshot
  useEffect(() => {
    let unsubscribeTree: (() => void) | undefined;
    (async () => {
      try {
        const loadedSettings = await window.mario.settings.load();
        setSettings(loadedSettings);
        const restored = await window.mario.auth.restore();
        setUser(restored);
        if (restored) {
          const snap = await window.mario.tree.getSnapshot();
          applyTreeSelection(snap, false);
          unsubscribeTree = window.mario.tree.onChanged((nextSnap) => {
            setTree(nextSnap);
          });
        }
      } catch (err) {
        setAuthError(err instanceof Error ? err.message : String(err));
      } finally {
        setRestoringAuth(false);
      }
    })();
    return () => {
      unsubscribeTree?.();
    };
  }, [applyTreeSelection]);

  const selectedNotebook = useMemo(
    () => tree.notebooks.find((n) => n.id === selectedNotebookId) ?? null,
    [tree.notebooks, selectedNotebookId],
  );

  const selectedSection = useMemo(() => {
    if (!selectedNotebookId || !selectedSectionId) return null;
    const secs = tree.sectionsByNotebook[selectedNotebookId] ?? [];
    return secs.find((s) => s.id === selectedSectionId) ?? null;
  }, [tree.sectionsByNotebook, selectedNotebookId, selectedSectionId]);

  const selectedPage = useMemo(() => {
    if (!selectedNotebookId || !selectedSectionId || !selectedPageId)
      return null;
    const pgs =
      tree.pagesBySection[`${selectedNotebookId}/${selectedSectionId}`] ?? [];
    return pgs.find((p) => p.id === selectedPageId) ?? null;
  }, [
    tree.pagesBySection,
    selectedNotebookId,
    selectedSectionId,
    selectedPageId,
  ]);

  // Load page content whenever selectedPageId changes
  useEffect(() => {
    if (!selectedPage) {
      setPageContent(emptyPageContent());
      return;
    }
    let cancelled = false;
    setRawHtmlOverride(null);
    window.mario.page
      .loadContent(
        selectedPage.id,
        selectedPage.driveFileId,
        selectedPage.title,
      )
      .then((loaded) => {
        if (!cancelled) {
          setPageContent(loaded);
          setSaveStatus('saved');
        }
      });
    return () => {
      cancelled = true;
    };
  }, [selectedPage?.id]);

  // Save page content (debounced 350ms)
  const handlePageContentChange = useCallback(
    (next: PageContent) => {
      setPageContent(next);
      if (!selectedPage) return;
      setSaveStatus('dirty');
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      const targetPage = selectedPage;
      saveTimerRef.current = setTimeout(async () => {
        setSaveStatus('saving');
        await window.mario.page.saveContent(
          targetPage.id,
          targetPage.driveFileId,
          next,
        );
        const updatedPage: NotePage = {
          ...targetPage,
          updatedAt: new Date().toISOString(),
        };
        await window.mario.tree.updatePage(updatedPage);
        const snap = await window.mario.tree.getSnapshot();
        setTree(snap);
        setSaveStatus('saved');
      }, 350);
    },
    [selectedPage],
  );

  const handleTitleChange = async (newTitle: string) => {
    if (!selectedPage) return;
    const updated: NotePage = {
      ...selectedPage,
      title: newTitle,
      updatedAt: new Date().toISOString(),
    };
    await window.mario.tree.updatePage(updated);
    const snap = await window.mario.tree.getSnapshot();
    setTree(snap);
  };

  const handleSaveSettings = async (next: SettingsState) => {
    setSettings(next);
    await window.mario.settings.save(next);
  };

  const handleCreatePage = useCallback(
    async (
      notebookId: string,
      sectionId: string,
      title = 'Untitled Page',
      initialContent?: PageContent,
    ): Promise<NotePage> => {
      const created = await window.mario.tree.createPage(
        notebookId,
        sectionId,
        title,
        initialContent,
      );
      const snap = await window.mario.tree.getSnapshot();
      setTree(snap);
      setSelectedNotebookId(notebookId);
      setSelectedSectionId(sectionId);
      setSelectedPageId(created.id);
      setActivePlace('page');
      return created;
    },
    [],
  );

  // Global keyboard shortcuts
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      const cmd = e.metaKey || e.ctrlKey;
      if (!cmd) return;
      const k = e.key.toLowerCase();
      if (k === 'k') {
        e.preventDefault();
        setSearchSheetOpen((v) => !v);
      } else if (k === ',') {
        e.preventDefault();
        setSettingsInitialPane('appearance');
        setSettingsOpen(true);
      } else if (k === '\\') {
        e.preventDefault();
        setInspectorOpen((v) => !v);
      } else if (k === 'n' && e.altKey) {
        e.preventDefault();
        setNbDialog({
          mode: 'create',
          name: '',
          colorIndex: tree.notebooks.length % NOTEBOOK_COLORS.length,
        });
      } else if (k === 'n' && !e.altKey && !e.shiftKey) {
        e.preventDefault();
        const nbId = selectedNotebookId ?? tree.notebooks[0]?.id;
        const secId =
          selectedSectionId ??
          (nbId ? tree.sectionsByNotebook[nbId]?.[0]?.id : undefined);
        if (nbId && secId) {
          handleCreatePage(nbId, secId, 'Untitled Page');
        }
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [
    selectedNotebookId,
    selectedSectionId,
    tree.notebooks,
    tree.sectionsByNotebook,
    handleCreatePage,
  ]);

  const handleExportMarkdown = async (targetPage?: NotePage) => {
    const pg = targetPage ?? selectedPage;
    if (!pg) return;
    const loaded =
      pg.id === selectedPage?.id
        ? pageContent
        : await window.mario.page.loadContent(
            pg.id,
            pg.driveFileId,
            pg.title,
          );
    const md = `# ${pg.title || 'Untitled Page'}\n\n${documentToMarkdown(
      loaded.document,
    )}\n`;
    await window.mario.exportFile.markdown(pg.title || 'note', md);
  };

  const handleExportPdf = async (targetPage?: NotePage) => {
    const pg = targetPage ?? selectedPage;
    if (!pg) return;
    const loaded =
      pg.id === selectedPage?.id
        ? pageContent
        : await window.mario.page.loadContent(
            pg.id,
            pg.driveFileId,
            pg.title,
          );
    const md = documentToMarkdown(loaded.document);
    const html = buildPrintableHtml(pg.title || 'Untitled Page', md);
    await window.mario.exportFile.pdf(pg.title || 'note', html);
  };

  // Sign-In screen when not authenticated
  if (!user) {
    return (
      <LoginView
        restoring={restoringAuth}
        signingIn={signingIn}
        error={authError}
        onSignIn={async () => {
          setSigningIn(true);
          setAuthError(null);
          try {
            const signedIn = await window.mario.auth.signIn();
            setUser(signedIn);
            const snap = await window.mario.tree.getSnapshot();
            applyTreeSelection(snap, false);
          } catch (err) {
            setAuthError(err instanceof Error ? err.message : String(err));
          } finally {
            setSigningIn(false);
          }
        }}
      />
    );
  }

  // Compute Titlebar title & subtitle
  let windowTitle = 'Mario';
  let windowSubtitle = '';
  if (activePlace === 'recents') {
    windowTitle = 'Recents';
    windowSubtitle = 'All recently modified pages';
  } else if (activePlace === 'notebook' && selectedNotebook) {
    const secCount = (tree.sectionsByNotebook[selectedNotebook.id] ?? [])
      .length;
    windowTitle = selectedNotebook.name;
    windowSubtitle = `${secCount} ${secCount === 1 ? 'section' : 'sections'}`;
  } else if (
    activePlace === 'section' &&
    selectedNotebook &&
    selectedSection
  ) {
    const pgCount = (
      tree.pagesBySection[`${selectedNotebook.id}/${selectedSection.id}`] ?? []
    ).length;
    windowTitle = selectedSection.name;
    windowSubtitle = `${selectedNotebook.name} · ${pgCount} ${
      pgCount === 1 ? 'page' : 'pages'
    }`;
  } else if (
    activePlace === 'page' &&
    selectedNotebook &&
    selectedSection &&
    selectedPage
  ) {
    windowTitle = selectedPage.title || 'Untitled Page';
    windowSubtitle = `${selectedNotebook.name} › ${selectedSection.name}`;
  }

  const fontSizePt = Math.round(14 * (settings.fontScale || 1));

  return (
    <>
      <Window style={{ width: '100vw', height: '100vh', borderRadius: 0 }}>
        {sidebarOpen && (
          <MacSidebarNav
            notebooks={tree.notebooks}
            sectionsByNotebook={tree.sectionsByNotebook}
            pagesByKey={tree.pagesBySection}
            activePlace={activePlace}
            selectedNotebookId={selectedNotebookId}
            selectedSectionId={selectedSectionId}
            selectedPageId={selectedPageId}
            searchQuery={sidebarSearch}
            onSearchQueryChange={setSidebarSearch}
            onSelectRecents={() => setActivePlace('recents')}
            onSelectNotebook={(nbId) => {
              setSelectedNotebookId(nbId);
              const firstSec = tree.sectionsByNotebook[nbId]?.[0];
              if (firstSec) setSelectedSectionId(firstSec.id);
              setActivePlace('notebook');
            }}
            onSelectSection={(nbId, secId) => {
              setSelectedNotebookId(nbId);
              setSelectedSectionId(secId);
              setActivePlace('section');
            }}
            onSelectPage={(nbId, secId, pgId) => {
              setSelectedNotebookId(nbId);
              setSelectedSectionId(secId);
              setSelectedPageId(pgId);
              setActivePlace('page');
            }}
            onNewNotebook={() =>
              setNbDialog({
                mode: 'create',
                name: '',
                colorIndex: tree.notebooks.length % NOTEBOOK_COLORS.length,
              })
            }
            onEditNotebook={(nb) =>
              setNbDialog({
                mode: 'edit',
                target: nb,
                name: nb.name,
                colorIndex: nb.colorIndex,
              })
            }
            onDeleteNotebook={(nb) =>
              setDeleteAlert({
                title: `Delete Notebook “${nb.name}”?`,
                message:
                  'All sections and pages inside this notebook will be permanently deleted.',
                onConfirm: async () => {
                  await window.mario.tree.deleteNotebook(nb.id);
                  const snap = await window.mario.tree.getSnapshot();
                  applyTreeSelection(snap, false);
                },
              })
            }
            onNewSection={(nbId) =>
              setSecDialog({
                mode: 'create',
                notebookId: nbId,
                name: '',
                colorIndex:
                  (tree.sectionsByNotebook[nbId]?.length ?? 0) %
                  NOTEBOOK_COLORS.length,
              })
            }
            onEditSection={(sec) =>
              setSecDialog({
                mode: 'edit',
                notebookId: sec.notebookId,
                target: sec,
                name: sec.name,
                colorIndex: sec.colorIndex,
              })
            }
            onDeleteSection={(sec) =>
              setDeleteAlert({
                title: `Delete Section “${sec.name}”?`,
                message:
                  'All pages inside this section will be permanently deleted.',
                onConfirm: async () => {
                  await window.mario.tree.deleteSection(sec.notebookId, sec.id);
                  const snap = await window.mario.tree.getSnapshot();
                  applyTreeSelection(snap, false);
                },
              })
            }
            onNewPage={(nbId, secId) => handleCreatePage(nbId, secId)}
            onRenamePage={(pg) =>
              setRenamePageDialog({ page: pg, title: pg.title })
            }
            onDeletePage={(pg) =>
              setDeleteAlert({
                title: `Delete Page “${pg.title || 'Untitled Page'}”?`,
                message: 'This page will be permanently removed.',
                onConfirm: async () => {
                  await window.mario.tree.deletePage(
                    pg.notebookId,
                    pg.sectionId,
                    pg.id,
                  );
                  const snap = await window.mario.tree.getSnapshot();
                  applyTreeSelection(snap, false);
                },
              })
            }
            onExportPageMarkdown={(pg) => handleExportMarkdown(pg)}
            onExportPagePdf={(pg) => handleExportPdf(pg)}
            onReorderNotebooks={async (ordered) => {
              for (const nb of ordered) {
                await window.mario.tree.updateNotebook(nb);
              }
              const snap = await window.mario.tree.getSnapshot();
              setTree(snap);
            }}
            onReorderSections={async (_, ordered) => {
              for (const sec of ordered) {
                await window.mario.tree.updateSection(sec);
              }
              const snap = await window.mario.tree.getSnapshot();
              setTree(snap);
            }}
            onReorderPages={async (_, __, ordered) => {
              for (const pg of ordered) {
                await window.mario.tree.updatePage(pg);
              }
              const snap = await window.mario.tree.getSnapshot();
              setTree(snap);
            }}
            onOpenSettings={() => {
              setSettingsInitialPane('appearance');
              setSettingsOpen(true);
            }}
          />
        )}

        <WindowMain>
          <Titlebar
            title={windowTitle}
            subtitle={windowSubtitle}
            leading={
              <ToolbarButton
                icon="sidebar-left"
                label="Toggle Sidebar"
                pressed={sidebarOpen}
                onClick={() => setSidebarOpen((v) => !v)}
              />
            }
          >
            <ToolbarGroup>
              <ToolbarButton
                icon="square-and-pencil"
                label="New Page (Ctrl+N)"
                onClick={() => {
                  const nbId = selectedNotebookId ?? tree.notebooks[0]?.id;
                  const secId =
                    selectedSectionId ??
                    (nbId ? tree.sectionsByNotebook[nbId]?.[0]?.id : undefined);
                  if (nbId && secId) {
                    handleCreatePage(nbId, secId);
                  } else if (nbId) {
                    setSecDialog({
                      mode: 'create',
                      notebookId: nbId,
                      name: '',
                      colorIndex: 0,
                    });
                  } else {
                    setNbDialog({
                      mode: 'create',
                      name: '',
                      colorIndex: 0,
                    });
                  }
                }}
              />
              <ToolbarButton
                icon="folder"
                label="New Section"
                onClick={() => {
                  const nbId = selectedNotebookId ?? tree.notebooks[0]?.id;
                  if (nbId) {
                    setSecDialog({
                      mode: 'create',
                      notebookId: nbId,
                      name: '',
                      colorIndex:
                        (tree.sectionsByNotebook[nbId]?.length ?? 0) %
                        NOTEBOOK_COLORS.length,
                    });
                  }
                }}
              />
            </ToolbarGroup>

            <ToolbarButton
              icon="magnifyingglass"
              label="Go to Page (Ctrl+K)"
              onClick={() => setSearchSheetOpen(true)}
            />

            <ToolbarButton
              icon="arrow-clockwise"
              label={
                tree.syncStatus.pendingChanges > 0
                  ? `Sync (${tree.syncStatus.pendingChanges} pending)`
                  : 'Sync with Cloud'
              }
              onClick={async () => {
                const snap = await window.mario.tree.syncNow();
                setTree(snap);
              }}
            />

            <ToolbarButton
              icon="gear"
              label="Settings (Ctrl+,)"
              onClick={() => {
                setSettingsInitialPane('appearance');
                setSettingsOpen(true);
              }}
            />

            <ToolbarButton
              icon="sidebar-right"
              label="Toggle AI Assistant (Ctrl+\)"
              pressed={inspectorOpen}
              onClick={() => setInspectorOpen((v) => !v)}
            />
          </Titlebar>

          <WindowBody>
            {activePlace === 'page' && selectedPage ? (
              <BlockEditor
                pageTitle={selectedPage.title}
                onTitleChange={handleTitleChange}
                content={pageContent}
                onContentChange={handlePageContentChange}
                fontFamily={fontFamily}
                onFontFamilyChange={setFontFamily}
                fontSize={fontSizePt}
                onFontSizeChange={(sz) =>
                  handleSaveSettings({ ...settings, fontScale: sz / 14 })
                }
                zoom={zoom}
                onZoomChange={setZoom}
                spellcheck={settings.spellCheck}
                saveStatus={saveStatus}
                rawHtmlOverride={rawHtmlOverride}
                onClearHtmlOverride={() => setRawHtmlOverride(null)}
                onExportMarkdown={() => handleExportMarkdown()}
                onExportPdf={() => handleExportPdf()}
                onOpenShare={() => setShareDialogOpen(true)}
              />
            ) : (
              <MacBrowserTable
                place={activePlace}
                notebooks={tree.notebooks}
                sectionsByNotebook={tree.sectionsByNotebook}
                pagesByKey={tree.pagesBySection}
                selectedNotebook={selectedNotebook}
                selectedSection={selectedSection}
                onOpenPage={(nbId, secId, pgId) => {
                  setSelectedNotebookId(nbId);
                  setSelectedSectionId(secId);
                  setSelectedPageId(pgId);
                  setActivePlace('page');
                }}
                onOpenSection={(nbId, secId) => {
                  setSelectedNotebookId(nbId);
                  setSelectedSectionId(secId);
                  setActivePlace('section');
                }}
                onNewNotebook={() =>
                  setNbDialog({ mode: 'create', name: '', colorIndex: 0 })
                }
                onNewSection={(nbId) =>
                  setSecDialog({
                    mode: 'create',
                    notebookId: nbId,
                    name: '',
                    colorIndex: 0,
                  })
                }
                onNewPage={(nbId, secId) => handleCreatePage(nbId, secId)}
              />
            )}

            {inspectorOpen && (
              <AiInspectorPanel
                notebook={selectedNotebook}
                section={selectedSection}
                page={selectedPage}
                pageContent={pageContent}
                notebooks={tree.notebooks}
                sectionsByNotebook={tree.sectionsByNotebook}
                pagesByKey={tree.pagesBySection}
                onPageContentChange={handlePageContentChange}
                onRenameCurrentPage={handleTitleChange}
                onOpenPage={(nbId, secId, pgId) => {
                  setSelectedNotebookId(nbId);
                  setSelectedSectionId(secId);
                  setSelectedPageId(pgId);
                  setActivePlace('page');
                }}
                onCreateNotebook={async (name, colorIdx) => {
                  const nb = await window.mario.tree.createNotebook(
                    name,
                    colorIdx,
                  );
                  const snap = await window.mario.tree.getSnapshot();
                  setTree(snap);
                  return nb;
                }}
                onRenameNotebook={async (nb, newName) => {
                  await window.mario.tree.updateNotebook({
                    ...nb,
                    name: newName,
                  });
                  const snap = await window.mario.tree.getSnapshot();
                  setTree(snap);
                }}
                onDeleteNotebook={async (nbId) => {
                  await window.mario.tree.deleteNotebook(nbId);
                  const snap = await window.mario.tree.getSnapshot();
                  applyTreeSelection(snap, false);
                }}
                onCreateSection={async (nbId, name) => {
                  const sec = await window.mario.tree.createSection(nbId, name);
                  const snap = await window.mario.tree.getSnapshot();
                  setTree(snap);
                  return sec;
                }}
                onRenameSection={async (sec, newName) => {
                  await window.mario.tree.updateSection({
                    ...sec,
                    name: newName,
                  });
                  const snap = await window.mario.tree.getSnapshot();
                  setTree(snap);
                }}
                onDeleteSection={async (nbId, secId) => {
                  await window.mario.tree.deleteSection(nbId, secId);
                  const snap = await window.mario.tree.getSnapshot();
                  applyTreeSelection(snap, false);
                }}
                onCreatePage={handleCreatePage}
                onDeletePage={async (nbId, secId, pgId) => {
                  await window.mario.tree.deletePage(nbId, secId, pgId);
                  const snap = await window.mario.tree.getSnapshot();
                  applyTreeSelection(snap, false);
                }}
                onSetRawHtmlOverride={setRawHtmlOverride}
                onOpenAiSettings={() => {
                  setSettingsInitialPane('ai');
                  setSettingsOpen(true);
                }}
              />
            )}
          </WindowBody>
        </WindowMain>
      </Window>

      {/* Notebook Create / Edit Sheet */}
      <Sheet
        open={nbDialog != null}
        onClose={() => setNbDialog(null)}
        title={nbDialog?.mode === 'edit' ? 'Edit Notebook' : 'New Notebook'}
        top={60}
        buttons={[
          {
            label: 'Cancel',
            role: 'cancel',
            onClick: () => setNbDialog(null),
          },
          {
            label: nbDialog?.mode === 'edit' ? 'Save' : 'Create',
            role: 'default',
            disabled: !nbDialog?.name.trim(),
            onClick: async () => {
              if (!nbDialog || !nbDialog.name.trim()) return;
              if (nbDialog.mode === 'edit' && nbDialog.target) {
                await window.mario.tree.updateNotebook({
                  ...nbDialog.target,
                  name: nbDialog.name.trim(),
                  colorIndex: nbDialog.colorIndex,
                });
                const snap = await window.mario.tree.getSnapshot();
                setTree(snap);
              } else {
                const nb = await window.mario.tree.createNotebook(
                  nbDialog.name.trim(),
                  nbDialog.colorIndex,
                );
                const sec = await window.mario.tree.createSection(
                  nb.id,
                  'General',
                  0,
                );
                const pg = await window.mario.tree.createPage(
                  nb.id,
                  sec.id,
                  'Untitled Page',
                );
                const snap = await window.mario.tree.getSnapshot();
                setTree(snap);
                setSelectedNotebookId(nb.id);
                setSelectedSectionId(sec.id);
                setSelectedPageId(pg.id);
                setActivePlace('page');
              }
              setNbDialog(null);
            },
          },
        ]}
      >
        {nbDialog && (
          <FieldGrid
            rows={[
              {
                label: 'Name:',
                control: (
                  <TextField
                    autoFocus
                    value={nbDialog.name}
                    onChange={(name) => setNbDialog({ ...nbDialog, name })}
                    placeholder="e.g. Research Notes"
                  />
                ),
              },
              {
                label: 'Color:',
                control: (
                  <div className="mario-color-swatch-grid">
                    {NOTEBOOK_COLORS.map((hex, idx) => (
                      <button
                        key={hex}
                        type="button"
                        className={`mario-color-swatch ${
                          nbDialog.colorIndex === idx
                            ? 'mario-color-swatch--active'
                            : ''
                        }`}
                        style={{ background: hex }}
                        onClick={() =>
                          setNbDialog({ ...nbDialog, colorIndex: idx })
                        }
                      />
                    ))}
                  </div>
                ),
              },
            ]}
          />
        )}
      </Sheet>

      {/* Section Create / Edit Sheet */}
      <Sheet
        open={secDialog != null}
        onClose={() => setSecDialog(null)}
        title={secDialog?.mode === 'edit' ? 'Edit Section' : 'New Section'}
        top={60}
        buttons={[
          {
            label: 'Cancel',
            role: 'cancel',
            onClick: () => setSecDialog(null),
          },
          {
            label: secDialog?.mode === 'edit' ? 'Save' : 'Create',
            role: 'default',
            disabled: !secDialog?.name.trim(),
            onClick: async () => {
              if (!secDialog || !secDialog.name.trim()) return;
              if (secDialog.mode === 'edit' && secDialog.target) {
                await window.mario.tree.updateSection({
                  ...secDialog.target,
                  name: secDialog.name.trim(),
                  colorIndex: secDialog.colorIndex,
                });
                const snap = await window.mario.tree.getSnapshot();
                setTree(snap);
              } else {
                const sec = await window.mario.tree.createSection(
                  secDialog.notebookId,
                  secDialog.name.trim(),
                  secDialog.colorIndex,
                );
                const pg = await window.mario.tree.createPage(
                  secDialog.notebookId,
                  sec.id,
                  'Untitled Page',
                );
                const snap = await window.mario.tree.getSnapshot();
                setTree(snap);
                setSelectedNotebookId(secDialog.notebookId);
                setSelectedSectionId(sec.id);
                setSelectedPageId(pg.id);
                setActivePlace('page');
              }
              setSecDialog(null);
            },
          },
        ]}
      >
        {secDialog && (
          <FieldGrid
            rows={[
              {
                label: 'Section Name:',
                control: (
                  <TextField
                    autoFocus
                    value={secDialog.name}
                    onChange={(name) => setSecDialog({ ...secDialog, name })}
                    placeholder="e.g. Lecture Notes"
                  />
                ),
              },
              {
                label: 'Color:',
                control: (
                  <div className="mario-color-swatch-grid">
                    {NOTEBOOK_COLORS.map((hex, idx) => (
                      <button
                        key={hex}
                        type="button"
                        className={`mario-color-swatch ${
                          secDialog.colorIndex === idx
                            ? 'mario-color-swatch--active'
                            : ''
                        }`}
                        style={{ background: hex }}
                        onClick={() =>
                          setSecDialog({ ...secDialog, colorIndex: idx })
                        }
                      />
                    ))}
                  </div>
                ),
              },
            ]}
          />
        )}
      </Sheet>

      {/* Page Rename Sheet */}
      <Sheet
        open={renamePageDialog != null}
        onClose={() => setRenamePageDialog(null)}
        title="Rename Page"
        top={60}
        buttons={[
          {
            label: 'Cancel',
            role: 'cancel',
            onClick: () => setRenamePageDialog(null),
          },
          {
            label: 'Rename',
            role: 'default',
            disabled: !renamePageDialog?.title.trim(),
            onClick: async () => {
              if (!renamePageDialog) return;
              await window.mario.tree.updatePage({
                ...renamePageDialog.page,
                title: renamePageDialog.title.trim(),
                updatedAt: new Date().toISOString(),
              });
              const snap = await window.mario.tree.getSnapshot();
              setTree(snap);
              setRenamePageDialog(null);
            },
          },
        ]}
      >
        {renamePageDialog && (
          <FieldGrid
            rows={[
              {
                label: 'Page Title:',
                control: (
                  <TextField
                    autoFocus
                    value={renamePageDialog.title}
                    onChange={(title) =>
                      setRenamePageDialog({ ...renamePageDialog, title })
                    }
                  />
                ),
              },
            ]}
          />
        )}
      </Sheet>

      {/* Share Notebook Sheet */}
      <Sheet
        open={shareDialogOpen}
        onClose={() => setShareDialogOpen(false)}
        title={
          selectedNotebook
            ? `Share “${selectedNotebook.name}”`
            : 'Share Notebook'
        }
        top={60}
        buttons={[
          {
            label: 'Done',
            role: 'default',
            onClick: () => setShareDialogOpen(false),
          },
        ]}
      >
        {selectedNotebook && (
          <Column style={{ width: 420, gap: 12 }}>
            <Row style={{ gap: 8 }}>
              <TextField
                style={{ flex: 1 }}
                type="email"
                value={shareEmail}
                onChange={setShareEmail}
                placeholder="Collaborator email address…"
              />
              <PopUpButton
                size="small"
                value={shareRole}
                onChange={(v) => setShareRole(v as CollaboratorRole)}
                options={[
                  { value: 'editor', label: 'Can Edit' },
                  { value: 'viewer', label: 'View Only' },
                ]}
              />
              <Button
                size="small"
                variant="prominent"
                disabled={shareBusy || !shareEmail.trim()}
                onClick={async () => {
                  setShareBusy(true);
                  try {
                    await window.mario.share.inviteCollaborator(
                      selectedNotebook.id,
                      shareEmail.trim(),
                      shareRole,
                    );
                    setShareEmail('');
                    const snap = await window.mario.tree.getSnapshot();
                    setTree(snap);
                  } finally {
                    setShareBusy(false);
                  }
                }}
              >
                Invite
              </Button>
            </Row>

            <div className="mac-groupbox">
              <p
                className="mac-caption-1 mac-label-secondary"
                style={{ margin: '0 0 6px' }}
              >
                People with access
              </p>
              {(selectedNotebook.collaborators ?? []).length === 0 ? (
                <p
                  className="mac-footnote mac-label-secondary"
                  style={{ margin: 0 }}
                >
                  Private to you ({user.email})
                </p>
              ) : (
                (selectedNotebook.collaborators ?? []).map((c) => (
                  <Row key={c.uid || c.email}>
                    <span>{c.email}</span>
                    <span className="mac-caption-1 mac-label-secondary">
                      ({c.role})
                    </span>
                  </Row>
                ))
              )}
            </div>
          </Column>
        )}
      </Sheet>

      {/* Delete Confirmation Alert */}
      <Alert
        open={deleteAlert != null}
        onClose={() => setDeleteAlert(null)}
        title={deleteAlert?.title ?? 'Confirm Delete'}
        message={deleteAlert?.message}
        buttons={[
          {
            label: 'Cancel',
            role: 'cancel',
            onClick: () => setDeleteAlert(null),
          },
          {
            label: 'Delete',
            role: 'destructive',
            onClick: async () => {
              await deleteAlert?.onConfirm();
              setDeleteAlert(null);
            },
          },
        ]}
      />

      {/* Global Search (Ctrl+K) Sheet */}
      <GlobalSearchSheet
        open={searchSheetOpen}
        onClose={() => setSearchSheetOpen(false)}
        notebooks={tree.notebooks}
        sectionsByNotebook={tree.sectionsByNotebook}
        pagesByKey={tree.pagesBySection}
        onSelectPage={(nbId, secId, pgId) => {
          setSelectedNotebookId(nbId);
          setSelectedSectionId(secId);
          setSelectedPageId(pgId);
          setActivePlace('page');
        }}
        onQuickCreatePage={(title) => {
          const nbId = selectedNotebookId ?? tree.notebooks[0]?.id;
          const secId =
            selectedSectionId ??
            (nbId ? tree.sectionsByNotebook[nbId]?.[0]?.id : undefined);
          if (nbId && secId) {
            handleCreatePage(nbId, secId, title);
          }
        }}
      />

      {/* Settings Window */}
      <SettingsWindow
        open={settingsOpen}
        initialPane={settingsInitialPane}
        onClose={() => setSettingsOpen(false)}
        settings={settings}
        onSettingsChange={handleSaveSettings}
        user={user}
        pendingCount={tree.syncStatus.pendingChanges}
        isSyncing={tree.syncStatus.syncing}
        onSyncNow={async () => {
          const snap = await window.mario.tree.syncNow();
          setTree(snap);
        }}
        onSignOut={async () => {
          await window.mario.auth.signOut();
          setSettingsOpen(false);
          setUser(null);
        }}
        onProvidersChanged={() => {
          // Triggers AI panel refresh on next open
        }}
      />
    </>
  );
}
