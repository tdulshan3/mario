import { app, BrowserWindow, dialog, ipcMain, Menu, shell, Tray, nativeImage } from 'electron';
import fs from 'node:fs';
import path from 'node:path';
import {
  AiArtifactData,
  CollaboratorRole,
  LlmEffort,
  LlmProviderConfig,
  LlmProviderKind,
  Notebook,
  NotePage,
  PageContent,
  Section,
  SettingsState,
} from '../src/shared/types';
import {
  AiArtifactStore,
  AssetCache,
  atomicWriteFile,
  KeyringStore,
  loadUserSkills,
  PageContentCache,
  SharedPreferencesStore,
} from './storage';
import { AuthServiceMain } from './auth';
import { DriveRestClient, FirestoreRestClient } from './cloud';
import { SyncEngine } from './sync';
import { AiServiceMain } from './ai';

const isDemo =
  process.env.MARIO_DEMO === 'true' ||
  process.env.MARIO_DEMO === '1' ||
  process.argv.includes('--demo');

app.setName('mario');
app.setDesktopName?.('mario.desktop');

// Services
const prefs = new SharedPreferencesStore();
const keyring = new KeyringStore();
const pageCache = new PageContentCache();
const assetCache = new AssetCache();
const aiArtifacts = new AiArtifactStore();
const auth = new AuthServiceMain(keyring, isDemo);
const firestore = new FirestoreRestClient(auth);
const drive = new DriveRestClient(auth);
const aiService = new AiServiceMain(prefs, keyring);

let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;

const syncEngine = new SyncEngine({
  auth,
  firestore,
  drive,
  pageCache,
  assetCache,
  aiArtifacts,
  onTreeChanged: () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('tree:changed', syncEngine.getTreeSnapshot());
    }
  },
});

// Apply initial offlineMode from preferences
const initialSettings = prefs.loadSettings();
syncEngine.setOfflineMode(initialSettings.offlineMode);

function createMainWindow(): void {
  const iconCandidates = [
    path.join(__dirname, '..', 'public', 'assets', 'logo', 'mario_mark.png'),
    path.join(__dirname, '..', 'dist', 'assets', 'logo', 'mario_mark.png'),
    path.join(__dirname, '..', '..', 'assets', 'logo', 'mario_mark.png'),
  ];
  const iconPath = iconCandidates.find((p) => fs.existsSync(p));

  mainWindow = new BrowserWindow({
    width: 1320,
    height: 840,
    minWidth: 800,
    minHeight: 600,
    title: 'Mario',
    icon: iconPath,
    autoHideMenuBar: true,
    backgroundColor: '#1e1e1e',
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      spellcheck: initialSettings.spellCheck,
    },
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      void shell.openExternal(url);
    }
    return { action: 'deny' };
  });

  const devServerUrl = process.env.VITE_DEV_SERVER_URL;
  if (devServerUrl) {
    void mainWindow.loadURL(devServerUrl);
  } else {
    const indexHtml = path.join(__dirname, '..', 'dist', 'index.html');
    void mainWindow.loadFile(indexHtml);
  }

  if (iconPath && !tray) {
    try {
      const img = nativeImage.createFromPath(iconPath).resize({ width: 18, height: 18 });
      tray = new Tray(img);
      tray.setToolTip('Mario — your notes, your world');
      const contextMenu = Menu.buildFromTemplate([
        {
          label: 'Show Mario',
          click: () => {
            mainWindow?.show();
            mainWindow?.focus();
          },
        },
        { type: 'separator' },
        {
          label: 'Quit Mario',
          click: () => app.quit(),
        },
      ]);
      tray.setContextMenu(contextMenu);
      tray.on('click', () => {
        mainWindow?.show();
        mainWindow?.focus();
      });
    } catch {
      // Tray optional on headless Xvfb
    }
  }
}

// ── IPC Handlers ────────────────────────────────────────────────────────────

function registerIpcHandlers(): void {
  // Auth
  ipcMain.handle('auth:restore', async () => {
    const user = await auth.restoreSession();
    if (user && !auth.isDemo()) {
      void syncEngine.refreshFromServer();
      void syncEngine.flushOutbox();
    }
    return user;
  });

  ipcMain.handle('auth:signIn', async () => {
    const user = await auth.signInInteractive((url) => shell.openExternal(url));
    await syncEngine.refreshFromServer();
    void syncEngine.flushOutbox();
    return user;
  });

  ipcMain.handle('auth:signOut', async () => {
    await auth.signOut();
  });

  // Tree & Sync
  ipcMain.handle('tree:getSnapshot', () => syncEngine.getTreeSnapshot());
  ipcMain.handle('tree:refresh', () => syncEngine.refreshFromServer());
  ipcMain.handle('tree:syncNow', async () => {
    await syncEngine.flushOutbox();
    return syncEngine.refreshFromServer();
  });

  ipcMain.handle(
    'tree:createNotebook',
    (_, name: string, colorIndex?: number) =>
      syncEngine.createNotebook(name, colorIndex),
  );
  ipcMain.handle('tree:updateNotebook', (_, nb: Notebook) =>
    syncEngine.updateNotebook(nb),
  );
  ipcMain.handle('tree:deleteNotebook', (_, notebookId: string) =>
    syncEngine.deleteNotebook(notebookId),
  );

  ipcMain.handle(
    'tree:createSection',
    (_, notebookId: string, name: string, colorIndex?: number) =>
      syncEngine.createSection(notebookId, name, colorIndex),
  );
  ipcMain.handle('tree:updateSection', (_, sec: Section) =>
    syncEngine.updateSection(sec),
  );
  ipcMain.handle(
    'tree:deleteSection',
    (_, notebookId: string, sectionId: string) =>
      syncEngine.deleteSection(notebookId, sectionId),
  );

  ipcMain.handle(
    'tree:createPage',
    (
      _,
      notebookId: string,
      sectionId: string,
      title?: string,
      initialContent?: PageContent,
    ) => syncEngine.createPage(notebookId, sectionId, title, initialContent),
  );
  ipcMain.handle('tree:updatePage', (_, page: NotePage) =>
    syncEngine.updatePage(page),
  );
  ipcMain.handle(
    'tree:deletePage',
    (_, notebookId: string, sectionId: string, pageId: string) =>
      syncEngine.deletePage(notebookId, sectionId, pageId),
  );

  // Page Content
  ipcMain.handle(
    'page:loadContent',
    (_, pageId: string, driveFileId: string | null, title?: string) =>
      syncEngine.loadPageContent(pageId, driveFileId, title),
  );
  ipcMain.handle(
    'page:saveContent',
    (_, pageId: string, driveFileId: string | null, content: PageContent) =>
      syncEngine.savePageContent(pageId, driveFileId, content),
  );

  // Sharing
  ipcMain.handle(
    'share:inviteCollaborator',
    async (
      _,
      notebookId: string,
      email: string,
      role: CollaboratorRole,
    ) => {
      const cleanEmail = email.trim().toLowerCase();
      if (!cleanEmail || auth.isDemo()) return;
      await firestore.arrayUnion(`notebooks/${notebookId}`, 'collaborators', [
        { uid: '', email: cleanEmail, role },
      ]);
      await firestore.arrayUnion(`notebooks/${notebookId}`, 'invitedEmails', [
        cleanEmail,
      ]);
      await syncEngine.refreshFromServer();
    },
  );

  // Assets (Image picker & resolver)
  ipcMain.handle('asset:pickImage', async () => {
    if (!mainWindow) return null;
    const res = await dialog.showOpenDialog(mainWindow, {
      title: 'Insert Image',
      properties: ['openFile'],
      filters: [
        {
          name: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'],
        },
      ],
    });
    if (res.canceled || res.filePaths.length === 0) return null;
    const sourcePath = res.filePaths[0];
    const { localPath, sha256 } = assetCache.copyIntoImagesDir(sourcePath);
    const bytes = fs.readFileSync(localPath);
    const ext = path.extname(localPath).toLowerCase();
    const mime =
      ext === '.jpg' || ext === '.jpeg'
        ? 'image/jpeg'
        : ext === '.gif'
          ? 'image/gif'
          : ext === '.webp'
            ? 'image/webp'
            : ext === '.svg'
              ? 'image/svg+xml'
              : 'image/png';
    const dataUrl = `data:${mime};base64,${bytes.toString('base64')}`;

    // Check existing hash or upload in background
    const idx = assetCache.readIndex();
    let driveId = idx.hashes[sha256] || '';
    if (!driveId && !auth.isDemo() && auth.getCurrentUser()) {
      try {
        driveId = await drive.uploadBinaryAsset(
          `mario-asset-${sha256.slice(0, 16)}${ext || '.png'}`,
          mime,
          bytes,
        );
        idx.hashes[sha256] = driveId;
        idx.assets[driveId] = path.basename(localPath);
        assetCache.writeIndex(idx);
      } catch (err) {
        console.warn('Background image upload deferred:', err);
      }
    }

    return { localPath, driveId, dataUrl };
  });

  ipcMain.handle(
    'asset:resolveImage',
    async (_, url?: string, driveId?: string): Promise<string | null> => {
      if (url && (url.startsWith('data:') || url.startsWith('http://') || url.startsWith('https://'))) {
        return url;
      }
      const toDataUrl = (filePath: string): string => {
        const bytes = fs.readFileSync(filePath);
        const ext = path.extname(filePath).toLowerCase();
        const mime =
          ext === '.jpg' || ext === '.jpeg'
            ? 'image/jpeg'
            : ext === '.gif'
              ? 'image/gif'
              : ext === '.webp'
                ? 'image/webp'
                : ext === '.svg'
                  ? 'image/svg+xml'
                  : 'image/png';
        return `data:${mime};base64,${bytes.toString('base64')}`;
      };

      if (url && fs.existsSync(url)) {
        return toDataUrl(url);
      }
      if (driveId) {
        const cachedPath = assetCache.pathFor(driveId);
        if (cachedPath && fs.existsSync(cachedPath)) {
          return toDataUrl(cachedPath);
        }
        if (!auth.isDemo() && auth.getCurrentUser()) {
          try {
            const bytes = await drive.downloadBinaryAsset(driveId);
            const ext = url ? path.extname(url) || '.png' : '.png';
            const saved = assetCache.storeDownloaded(driveId, bytes, ext);
            return toDataUrl(saved);
          } catch {
            return null;
          }
        }
      }
      return null;
    },
  );

  // Settings
  ipcMain.handle('settings:load', () => prefs.loadSettings());
  ipcMain.handle('settings:save', (_, next: SettingsState) => {
    const saved = prefs.saveSettings(next);
    syncEngine.setOfflineMode(saved.offlineMode);
    return saved;
  });

  // AI & Agent
  ipcMain.handle('ai:getProviders', () => aiService.getProvidersState());
  ipcMain.handle(
    'ai:saveProvider',
    (
      _,
      config: LlmProviderConfig,
      apiKey?: string | null,
      setActive?: boolean,
    ) => aiService.saveProvider(config, apiKey, setActive),
  );
  ipcMain.handle('ai:deleteProvider', (_, id: string) =>
    aiService.deleteProvider(id),
  );
  ipcMain.handle('ai:setActiveProvider', (_, id: string) =>
    aiService.setActiveProvider(id),
  );
  ipcMain.handle(
    'ai:setProviderModel',
    (_, id: string, model: string, effort?: LlmEffort) =>
      aiService.setProviderModel(id, model, effort),
  );
  ipcMain.handle(
    'ai:setSerperConfig',
    (_, apiKey: string | null, enabled: boolean) =>
      aiService.setSerperConfig(apiKey, enabled),
  );
  ipcMain.handle(
    'ai:listModels',
    (
      _,
      config: {
        id?: string;
        kind: LlmProviderKind;
        baseUrl: string;
        apiKey?: string;
      },
    ) => aiService.listModelsForProvider(config),
  );
  ipcMain.handle('ai:discoverLocal', () => aiService.discoverLocalEndpoints());
  ipcMain.handle(
    'ai:chat',
    (
      _,
      opts: {
        systemPrompt: string;
        userPrompt: string;
        temperature?: number;
        effort?: LlmEffort;
      },
    ) => aiService.chatCompletion(opts),
  );
  ipcMain.handle(
    'ai:structured',
    (
      _,
      opts: {
        schemaName: string;
        schema: Record<string, unknown>;
        systemPrompt: string;
        userPrompt: string;
        temperature?: number;
      },
    ) => aiService.completeStructured(opts),
  );
  ipcMain.handle('ai:webSearch', (_, query: string) =>
    aiService.webSearch(query),
  );
  ipcMain.handle('ai:getUserSkills', () => loadUserSkills());
  ipcMain.handle('ai:readArtifacts', (_, notebookId: string) =>
    aiArtifacts.read(notebookId),
  );
  ipcMain.handle(
    'ai:writeArtifacts',
    (_, notebookId: string, data: AiArtifactData) =>
      aiArtifacts.write(notebookId, data),
  );

  // Export (Markdown & Native Chromium PDF)
  ipcMain.handle(
    'export:markdown',
    async (_, defaultFilename: string, markdownContent: string) => {
      if (!mainWindow) return false;
      const res = await dialog.showSaveDialog(mainWindow, {
        title: 'Export as Markdown',
        defaultPath: defaultFilename.endsWith('.md')
          ? defaultFilename
          : `${defaultFilename}.md`,
        filters: [{ name: 'Markdown', extensions: ['md'] }],
      });
      if (res.canceled || !res.filePath) return false;
      atomicWriteFile(res.filePath, markdownContent);
      return true;
    },
  );

  ipcMain.handle(
    'export:pdf',
    async (_, defaultFilename: string, htmlDocument: string) => {
      if (!mainWindow) return false;
      const res = await dialog.showSaveDialog(mainWindow, {
        title: 'Export as PDF',
        defaultPath: defaultFilename.endsWith('.pdf')
          ? defaultFilename
          : `${defaultFilename}.pdf`,
        filters: [{ name: 'PDF Document', extensions: ['pdf'] }],
      });
      if (res.canceled || !res.filePath) return false;

      const pdfWin = new BrowserWindow({
        show: false,
        width: 900,
        height: 1200,
        webPreferences: {
          contextIsolation: true,
          nodeIntegration: false,
        },
      });

      try {
        await pdfWin.loadURL(
          `data:text/html;charset=utf-8,${encodeURIComponent(htmlDocument)}`,
        );
        const pdfBytes = await pdfWin.webContents.printToPDF({
          printBackground: true,
          pageSize: 'A4',
          margins: { top: 0.6, bottom: 0.6, left: 0.6, right: 0.6 },
        });
        atomicWriteFile(res.filePath, pdfBytes);
        return true;
      } finally {
        pdfWin.destroy();
      }
    },
  );
}

app.whenReady().then(() => {
  registerIpcHandlers();
  createMainWindow();

  const screenshotDir = process.env.MARIO_SCREENSHOT_DIR;
  if (screenshotDir && mainWindow) {
    fs.mkdirSync(screenshotDir, { recursive: true });
    mainWindow.webContents.once('did-finish-load', async () => {
      try {
        const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
        await sleep(1600);
        if (!mainWindow || mainWindow.isDestroyed()) return;

        // 1. Main editor + AI Ask tab (Dark mode)
        const shot1 = await mainWindow.webContents.capturePage();
        fs.writeFileSync(path.join(screenshotDir, '01-editor-dark.png'), shot1.toPNG());

        // 2. Click "Newton's Laws of Motion" in sidebar and "Do" tab in AI panel
        await mainWindow.webContents.executeJavaScript(`
          (() => {
            const btns = Array.from(document.querySelectorAll('button'));
            const newtonBtn = btns.find(el => el.textContent && el.textContent.includes("Newton's Laws"));
            if (newtonBtn) newtonBtn.click();
            const doRadio = document.querySelector('input[type="radio"][value="do"]');
            if (doRadio) doRadio.click();
          })()
        `);
        await sleep(700);
        const shot2 = await mainWindow.webContents.capturePage();
        fs.writeFileSync(path.join(screenshotDir, '02-blocks-scrolled.png'), shot2.toPNG());

        // 3. Open Settings modal and switch to AI & Models tab
        await mainWindow.webContents.executeJavaScript(`
          (() => {
            const settingsBtn = document.querySelector('button[title*="Settings"]');
            if (settingsBtn) settingsBtn.click();
          })()
        `);
        await sleep(400);
        await mainWindow.webContents.executeJavaScript(`
          (() => {
            const btns = Array.from(document.querySelectorAll('button'));
            const aiTabBtn = btns.find(el => el.textContent && el.textContent.includes('AI & Models'));
            if (aiTabBtn) aiTabBtn.click();
          })()
        `);
        await sleep(500);
        const shot3 = await mainWindow.webContents.capturePage();
        fs.writeFileSync(path.join(screenshotDir, '03-settings-modal.png'), shot3.toPNG());
      } catch (err) {
        console.error('Screenshot capture error:', err);
      } finally {
        app.quit();
      }
    });
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createMainWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

