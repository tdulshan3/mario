import fs from 'node:fs';
import path from 'node:path';
import {
  Notebook,
  NotePage,
  PageContent,
  Section,
  SyncStatus,
  TreeSnapshot,
} from '../src/shared/types';
import { newClientId } from '../src/shared/ids';
import {
  DEMO_NOTEBOOKS,
  DEMO_PAGE_CONTENTS,
  DEMO_PAGES,
  DEMO_SECTIONS,
} from '../src/shared/demo-data';
import {
  AiArtifactStore,
  AssetCache,
  atomicWriteFile,
  getSupportDir,
  PageContentCache,
} from './storage';
import { AuthServiceMain } from './auth';
import { DriveRestClient, FirestoreRestClient } from './cloud';

export type OutboxOpKind =
  | 'set'
  | 'update'
  | 'promote'
  | 'deletePage'
  | 'deleteSection'
  | 'deleteNotebook';

export interface PendingOp {
  id: string;
  kind: OutboxOpKind;
  args: Record<string, unknown>;
  createdAt: string;
  attempts: number;
  lastError?: string;
}

export type OpFailureClass = 'retry' | 'drop';

export function classifyFailure(err: unknown): OpFailureClass {
  const msg = String(err ?? '').toLowerCase();
  if (
    msg.includes('ratelimit') ||
    msg.includes('rate limit') ||
    msg.includes('429') ||
    msg.includes('quota')
  ) {
    return 'retry';
  }
  if (msg.includes('not_found') || msg.includes('not found') || msg.includes('404')) {
    return 'drop';
  }
  if (
    msg.includes('permission_denied') ||
    msg.includes('permission denied') ||
    msg.includes('403')
  ) {
    return 'drop';
  }
  return 'retry';
}

export function remoteIsNewer(
  remote: PageContent | null | undefined,
  cached: PageContent | null | undefined,
): boolean {
  if (!remote || !remote.updatedAt) return false;
  if (!cached || !cached.updatedAt) return true;
  const rt = Date.parse(remote.updatedAt);
  const ct = Date.parse(cached.updatedAt);
  if (!Number.isFinite(rt)) return false;
  if (!Number.isFinite(ct)) return true;
  return rt > ct;
}

interface PendingOverlayEntry<T> {
  model: T | null; // null = deleted
  settledAt?: number;
}

export class SyncEngine {
  private readonly auth: AuthServiceMain;
  private readonly firestore: FirestoreRestClient;
  private readonly drive: DriveRestClient;
  private readonly pageCache: PageContentCache;
  private readonly assetCache: AssetCache;
  private readonly aiArtifacts: AiArtifactStore;
  private readonly onTreeChanged: () => void;

  private indexKeys: Record<string, unknown[]> = {};
  private outboxOps: PendingOp[] = [];
  private pendingNotebooks = new Map<string, PendingOverlayEntry<Notebook>>();
  private pendingSections = new Map<string, PendingOverlayEntry<Section>>();
  private pendingPages = new Map<string, PendingOverlayEntry<NotePage>>();
  private promotedLocalKeys = new Map<string, string>(); // `local:pg_...` -> `driveFileId`
  private demoContents = new Map<string, PageContent>();

  private offlineMode = false;
  private flushing = false;
  private strikes = 0;
  private lastError: string | null = null;
  private backoffTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(opts: {
    auth: AuthServiceMain;
    firestore: FirestoreRestClient;
    drive: DriveRestClient;
    pageCache: PageContentCache;
    assetCache: AssetCache;
    aiArtifacts: AiArtifactStore;
    onTreeChanged: () => void;
  }) {
    this.auth = opts.auth;
    this.firestore = opts.firestore;
    this.drive = opts.drive;
    this.pageCache = opts.pageCache;
    this.assetCache = opts.assetCache;
    this.aiArtifacts = opts.aiArtifacts;
    this.onTreeChanged = opts.onTreeChanged;

    if (this.auth.isDemo()) {
      this.seedDemoState();
    } else {
      this.loadSyncFiles();
    }
  }

  private get syncDir(): string {
    const d = path.join(getSupportDir(), 'sync');
    fs.mkdirSync(d, { recursive: true });
    return d;
  }

  private get indexPath(): string {
    return path.join(this.syncDir, 'index.json');
  }

  private get outboxPath(): string {
    return path.join(this.syncDir, 'outbox.json');
  }

  private seedDemoState(): void {
    const uid = this.auth.getCurrentUser()?.uid || 'demo-user';
    this.indexKeys[`notebooks:${uid}`] = DEMO_NOTEBOOKS.map((n) => ({ ...n }));
    for (const [nbId, secs] of Object.entries(DEMO_SECTIONS)) {
      this.indexKeys[`sections:${nbId}`] = secs.map((s) => ({ ...s }));
    }
    for (const [key, pgs] of Object.entries(DEMO_PAGES)) {
      this.indexKeys[`pages:${key}`] = pgs.map((p) => ({ ...p }));
    }
    for (const [fileId, content] of Object.entries(DEMO_PAGE_CONTENTS)) {
      this.demoContents.set(fileId, JSON.parse(JSON.stringify(content)));
    }
  }

  private loadSyncFiles(): void {
    try {
      if (fs.existsSync(this.indexPath)) {
        const raw = JSON.parse(fs.readFileSync(this.indexPath, 'utf8'));
        if (raw?.keys && typeof raw.keys === 'object') {
          this.indexKeys = raw.keys as Record<string, unknown[]>;
        }
      }
    } catch {
      this.indexKeys = {};
    }

    try {
      if (fs.existsSync(this.outboxPath)) {
        const raw = JSON.parse(fs.readFileSync(this.outboxPath, 'utf8'));
        if (Array.isArray(raw?.ops)) {
          this.outboxOps = raw.ops as PendingOp[];
        }
      }
    } catch {
      this.outboxOps = [];
    }
  }

  private saveIndex(): void {
    if (this.auth.isDemo()) return;
    atomicWriteFile(this.indexPath, JSON.stringify({ keys: this.indexKeys }));
  }

  private saveOutbox(): void {
    if (this.auth.isDemo()) return;
    atomicWriteFile(this.outboxPath, JSON.stringify({ ops: this.outboxOps }));
  }

  setOfflineMode(offline: boolean): void {
    this.offlineMode = offline;
    if (!offline) {
      void this.flushOutbox();
    }
    this.onTreeChanged();
  }

  getSyncStatus(): SyncStatus {
    const dirtyCount = this.auth.isDemo() ? 0 : this.pageCache.listDirtyIds().length;
    return {
      pendingChanges: this.outboxOps.length + dirtyCount,
      syncing: this.flushing,
      lastError: this.lastError,
      offlineMode: this.offlineMode,
    };
  }

  private expireSettledOverlays(): void {
    const now = Date.now();
    const graceMs = 15000;
    for (const map of [
      this.pendingNotebooks,
      this.pendingSections,
      this.pendingPages,
    ]) {
      for (const [id, entry] of map.entries()) {
        if (entry.settledAt && now - entry.settledAt > graceMs) {
          map.delete(id);
        }
      }
    }
  }

  getTreeSnapshot(): TreeSnapshot {
    this.expireSettledOverlays();
    const uid = this.auth.getCurrentUser()?.uid || 'demo-user';
    const rawNotebooks = ((this.indexKeys[`notebooks:${uid}`] ?? []) as Notebook[]).map(
      (n) => ({ ...n }),
    );
    const nbMap = new Map<string, Notebook>();
    for (const nb of rawNotebooks) nbMap.set(nb.id, nb);
    for (const [id, p] of this.pendingNotebooks.entries()) {
      if (p.model === null) nbMap.delete(id);
      else nbMap.set(id, p.model);
    }
    const notebooks = Array.from(nbMap.values());

    const sectionsByNotebook: Record<string, Section[]> = {};
    const pagesBySection: Record<string, NotePage[]> = {};

    for (const nb of notebooks) {
      const rawSecs = ((this.indexKeys[`sections:${nb.id}`] ?? []) as Section[]).map(
        (s) => ({ ...s }),
      );
      const secMap = new Map<string, Section>();
      for (const s of rawSecs) secMap.set(s.id, s);
      for (const [id, p] of this.pendingSections.entries()) {
        if (p.model === null) {
          secMap.delete(id);
        } else if (p.model.notebookId === nb.id) {
          secMap.set(id, p.model);
        }
      }
      const sections = Array.from(secMap.values()).sort((a, b) => a.order - b.order);
      sectionsByNotebook[nb.id] = sections;

      for (const sec of sections) {
        const pageKey = `${nb.id}/${sec.id}`;
        const rawPages = ((this.indexKeys[`pages:${pageKey}`] ?? []) as NotePage[]).map(
          (pg) => ({ ...pg }),
        );
        const pgMap = new Map<string, NotePage>();
        for (const pg of rawPages) pgMap.set(pg.id, pg);
        for (const [id, p] of this.pendingPages.entries()) {
          if (p.model === null) {
            pgMap.delete(id);
          } else if (p.model.notebookId === nb.id && p.model.sectionId === sec.id) {
            pgMap.set(id, p.model);
          } else if (p.model.id === id && pgMap.has(id)) {
            // Moved to another section
            pgMap.delete(id);
          }
        }
        pagesBySection[pageKey] = Array.from(pgMap.values()).sort(
          (a, b) => a.order - b.order,
        );
      }
    }

    return {
      notebooks,
      sectionsByNotebook,
      pagesBySection,
      syncStatus: this.getSyncStatus(),
    };
  }

  knownPage(notebookId: string, pageId: string): NotePage | null {
    const pending = this.pendingPages.get(pageId);
    if (pending) {
      if (pending.model === null) return null;
      return pending.model;
    }
    for (const [k, v] of Object.entries(this.indexKeys)) {
      if (k.startsWith(`pages:${notebookId}/`)) {
        const found = (v as NotePage[]).find((p) => p.id === pageId);
        if (found) return found;
      }
    }
    return null;
  }

  // ── Refresh from Firestore Server ─────────────────────────────────────────

  async refreshFromServer(): Promise<TreeSnapshot> {
    const user = this.auth.getCurrentUser();
    if (!user || this.auth.isDemo() || this.offlineMode) {
      return this.getTreeSnapshot();
    }

    try {
      const nbDocs = await this.firestore.fetchCollection('notebooks', {
        where: { field: 'memberUids', arrayContains: user.uid },
      });

      const notebooks: Notebook[] = nbDocs.map((d) => ({
        id: d.id,
        name: String(d.data.name ?? 'Untitled'),
        ownerId: String(d.data.ownerId ?? user.uid),
        collaboratorUids: Array.isArray(d.data.collaboratorUids)
          ? (d.data.collaboratorUids as string[])
          : [],
        colorIndex: Number(d.data.colorIndex ?? 2),
        createdAt: String(d.data.createdAt ?? new Date().toISOString()),
        updatedAt: String(d.data.updatedAt ?? new Date().toISOString()),
        collaborators: Array.isArray(d.data.collaborators)
          ? (d.data.collaborators as Notebook['collaborators'])
          : undefined,
        invitedEmails: Array.isArray(d.data.invitedEmails)
          ? (d.data.invitedEmails as string[])
          : undefined,
      }));

      this.indexKeys[`notebooks:${user.uid}`] = notebooks;

      await Promise.all(
        notebooks.map(async (nb) => {
          const [secDocs, pageDocs] = await Promise.all([
            this.firestore.fetchCollection(`notebooks/${nb.id}/sections`, {
              orderBy: 'order',
            }),
            this.firestore.fetchCollection(`notebooks/${nb.id}/pages`),
          ]);

          const sections: Section[] = secDocs
            .map((d) => ({
              id: d.id,
              notebookId: nb.id,
              name: String(d.data.name ?? 'Untitled'),
              colorIndex: Number(d.data.colorIndex ?? 2),
              order: Number(d.data.order ?? 0),
            }))
            .sort((a, b) => a.order - b.order);

          this.indexKeys[`sections:${nb.id}`] = sections;

          const allPages: NotePage[] = pageDocs.map((d) => ({
            id: d.id,
            notebookId: nb.id,
            sectionId: String(d.data.sectionId ?? ''),
            title: String(d.data.title ?? 'Untitled page'),
            driveFileId:
              typeof d.data.driveFileId === 'string' && d.data.driveFileId
                ? d.data.driveFileId
                : null,
            order: Number(d.data.order ?? 0),
            indentLevel: Number(d.data.indentLevel ?? 0),
            createdAt: String(d.data.createdAt ?? new Date().toISOString()),
            updatedAt: String(d.data.updatedAt ?? new Date().toISOString()),
          }));

          for (const sec of sections) {
            const secPages = allPages
              .filter((p) => p.sectionId === sec.id)
              .sort((a, b) => a.order - b.order);
            this.indexKeys[`pages:${nb.id}/${sec.id}`] = secPages;
          }
        }),
      );

      this.saveIndex();
      this.onTreeChanged();
    } catch (err) {
      console.warn('refreshFromServer warning (serving cached local index):', err);
    }

    return this.getTreeSnapshot();
  }

  // ── CRUD Operations (Local-First + Outbox) ────────────────────────────────

  private enqueue(kind: OutboxOpKind, args: Record<string, unknown>): void {
    if (this.auth.isDemo()) return;
    this.outboxOps.push({
      id: newClientId('op'),
      kind,
      args,
      createdAt: new Date().toISOString(),
      attempts: 0,
    });
    this.saveOutbox();
    void this.flushOutbox();
  }

  private cancelPendingFor(docIds: Set<string>): void {
    const removableKinds = new Set<OutboxOpKind>(['set', 'update', 'promote']);
    this.outboxOps = this.outboxOps.filter((op) => {
      const docId = String(op.args.docId ?? '');
      return !(removableKinds.has(op.kind) && docIds.has(docId));
    });
    this.saveOutbox();
  }

  createNotebook(name: string, colorIndex = 2): Notebook {
    const uid = this.auth.getCurrentUser()?.uid || 'demo-user';
    const now = new Date().toISOString();
    const nb: Notebook = {
      id: newClientId('nb'),
      name: name.trim() || 'Untitled',
      ownerId: uid,
      collaboratorUids: [],
      colorIndex,
      createdAt: now,
      updatedAt: now,
    };

    this.pendingNotebooks.set(nb.id, { model: nb });
    const key = `notebooks:${uid}`;
    const existing = ((this.indexKeys[key] ?? []) as Notebook[]).filter(
      (x) => x.id !== nb.id,
    );
    this.indexKeys[key] = [...existing, nb];
    this.indexKeys[`sections:${nb.id}`] = [];
    this.saveIndex();

    const { id: _id, ...toMap } = nb;
    this.enqueue('set', {
      docId: nb.id,
      path: `notebooks/${nb.id}`,
      data: {
        ...toMap,
        memberUids: [nb.ownerId, ...nb.collaboratorUids],
      },
    });

    this.onTreeChanged();
    return nb;
  }

  updateNotebook(nb: Notebook): Notebook {
    const uid = this.auth.getCurrentUser()?.uid || 'demo-user';
    const updated: Notebook = {
      ...nb,
      updatedAt: new Date().toISOString(),
    };
    this.pendingNotebooks.set(updated.id, { model: updated });
    const key = `notebooks:${uid}`;
    const existing = (this.indexKeys[key] ?? []) as Notebook[];
    this.indexKeys[key] = existing.map((x) => (x.id === updated.id ? updated : x));
    this.saveIndex();

    const { id: _id, ...toMap } = updated;
    this.enqueue('update', {
      docId: updated.id,
      path: `notebooks/${updated.id}`,
      data: toMap,
    });

    this.onTreeChanged();
    return updated;
  }

  deleteNotebook(notebookId: string): void {
    const uid = this.auth.getCurrentUser()?.uid || 'demo-user';
    const snap = this.getTreeSnapshot();
    const sections = snap.sectionsByNotebook[notebookId] ?? [];
    const docIdsToCancel = new Set<string>([notebookId]);

    for (const sec of sections) {
      docIdsToCancel.add(sec.id);
      this.pendingSections.set(sec.id, { model: null });
      const pages = snap.pagesBySection[`${notebookId}/${sec.id}`] ?? [];
      for (const pg of pages) {
        docIdsToCancel.add(pg.id);
        this.pendingPages.set(pg.id, { model: null });
        this.pageCache.evict(`local:${pg.id}`);
        if (pg.driveFileId) this.pageCache.evict(pg.driveFileId);
      }
      delete this.indexKeys[`pages:${notebookId}/${sec.id}`];
    }

    this.pendingNotebooks.set(notebookId, { model: null });
    this.indexKeys[`notebooks:${uid}`] = (
      (this.indexKeys[`notebooks:${uid}`] ?? []) as Notebook[]
    ).filter((n) => n.id !== notebookId);
    delete this.indexKeys[`sections:${notebookId}`];
    this.aiArtifacts.forgetNotebook(notebookId);
    this.saveIndex();

    this.cancelPendingFor(docIdsToCancel);
    this.enqueue('deleteNotebook', {
      docId: notebookId,
      notebookId,
    });
    this.onTreeChanged();
  }

  createSection(notebookId: string, name: string, colorIndex = 2): Section {
    const snap = this.getTreeSnapshot();
    const curSections = snap.sectionsByNotebook[notebookId] ?? [];
    const maxOrder = curSections.reduce((m, s) => Math.max(m, s.order), -1);
    const sec: Section = {
      id: newClientId('sec'),
      notebookId,
      name: name.trim() || 'Untitled',
      colorIndex,
      order: maxOrder + 1,
    };

    this.pendingSections.set(sec.id, { model: sec });
    const key = `sections:${notebookId}`;
    const existing = ((this.indexKeys[key] ?? []) as Section[]).filter(
      (x) => x.id !== sec.id,
    );
    this.indexKeys[key] = [...existing, sec];
    this.indexKeys[`pages:${notebookId}/${sec.id}`] = [];
    this.saveIndex();

    const { id: _id, ...toMap } = sec;
    this.enqueue('set', {
      docId: sec.id,
      path: `notebooks/${notebookId}/sections/${sec.id}`,
      data: toMap,
    });

    this.onTreeChanged();
    return sec;
  }

  updateSection(sec: Section): Section {
    this.pendingSections.set(sec.id, { model: sec });
    const key = `sections:${sec.notebookId}`;
    const existing = (this.indexKeys[key] ?? []) as Section[];
    this.indexKeys[key] = existing.map((x) => (x.id === sec.id ? sec : x));
    this.saveIndex();

    const { id: _id, ...toMap } = sec;
    this.enqueue('update', {
      docId: sec.id,
      path: `notebooks/${sec.notebookId}/sections/${sec.id}`,
      data: toMap,
    });

    this.onTreeChanged();
    return sec;
  }

  deleteSection(notebookId: string, sectionId: string): void {
    const snap = this.getTreeSnapshot();
    const pages = snap.pagesBySection[`${notebookId}/${sectionId}`] ?? [];
    const docIdsToCancel = new Set<string>([sectionId]);

    for (const pg of pages) {
      docIdsToCancel.add(pg.id);
      this.pendingPages.set(pg.id, { model: null });
      this.pageCache.evict(`local:${pg.id}`);
      if (pg.driveFileId) this.pageCache.evict(pg.driveFileId);
      this.aiArtifacts.forgetPage(notebookId, pg.id);
    }

    this.pendingSections.set(sectionId, { model: null });
    this.indexKeys[`sections:${notebookId}`] = (
      (this.indexKeys[`sections:${notebookId}`] ?? []) as Section[]
    ).filter((s) => s.id !== sectionId);
    delete this.indexKeys[`pages:${notebookId}/${sectionId}`];
    this.saveIndex();

    this.cancelPendingFor(docIdsToCancel);
    this.enqueue('deleteSection', {
      docId: sectionId,
      notebookId,
      sectionId,
    });
    this.onTreeChanged();
  }

  createPage(
    notebookId: string,
    sectionId: string,
    title = 'Untitled page',
    initialContent?: PageContent,
  ): NotePage {
    const snap = this.getTreeSnapshot();
    const curPages = snap.pagesBySection[`${notebookId}/${sectionId}`] ?? [];
    const maxOrder = curPages.reduce((m, p) => Math.max(m, p.order), -1);
    const now = new Date().toISOString();
    const pageId = newClientId('pg');
    const localKey = `local:${pageId}`;

    const page: NotePage = {
      id: pageId,
      notebookId,
      sectionId,
      title: title.trim() || 'Untitled page',
      driveFileId: this.auth.isDemo() ? `demo-${pageId}` : null,
      order: maxOrder + 1,
      indentLevel: 0,
      createdAt: now,
      updatedAt: now,
    };

    const content = initialContent ?? this.pageCache.empty(page.title);
    if (this.auth.isDemo()) {
      this.demoContents.set(page.driveFileId!, content);
    } else {
      this.pageCache.writeContent(localKey, content);
      this.pageCache.markDirty(localKey);
    }

    this.pendingPages.set(page.id, { model: page });
    const key = `pages:${notebookId}/${sectionId}`;
    const existing = ((this.indexKeys[key] ?? []) as NotePage[]).filter(
      (x) => x.id !== page.id,
    );
    this.indexKeys[key] = [...existing, page];
    this.saveIndex();

    const { id: _id, ...toMap } = page;
    this.enqueue('set', {
      docId: page.id,
      path: `notebooks/${notebookId}/pages/${page.id}`,
      data: toMap,
    });
    this.enqueue('promote', {
      docId: page.id,
      notebookId,
      pageId: page.id,
      localKey,
      name: `page-${Date.now()}`,
    });

    this.onTreeChanged();
    return page;
  }

  /**
   * INVARIANT: updatePage must NEVER write `driveFileId: null` over a real id!
   */
  updatePage(page: NotePage): NotePage {
    const known = this.knownPage(page.notebookId, page.id);
    const promoted = this.promotedLocalKeys.get(`local:${page.id}`);
    const resolvedDriveId =
      page.driveFileId ?? known?.driveFileId ?? promoted ?? null;

    const updated: NotePage = {
      ...page,
      driveFileId: resolvedDriveId,
      updatedAt: new Date().toISOString(),
    };

    this.pendingPages.set(updated.id, { model: updated });

    // Remove from old section in indexKeys if sectionId changed
    for (const k of Object.keys(this.indexKeys)) {
      if (k.startsWith(`pages:${updated.notebookId}/`)) {
        this.indexKeys[k] = ((this.indexKeys[k] ?? []) as NotePage[]).filter(
          (p) => p.id !== updated.id,
        );
      }
    }
    const targetKey = `pages:${updated.notebookId}/${updated.sectionId}`;
    const targetList = (this.indexKeys[targetKey] ?? []) as NotePage[];
    this.indexKeys[targetKey] = [...targetList, updated].sort(
      (a, b) => a.order - b.order,
    );
    this.saveIndex();

    const { id: _id, ...toMap } = updated;
    const firestoreData: Record<string, unknown> = { ...toMap };
    if (firestoreData.driveFileId === null) {
      delete firestoreData.driveFileId;
    }

    this.enqueue('update', {
      docId: updated.id,
      path: `notebooks/${updated.notebookId}/pages/${updated.id}`,
      data: firestoreData,
    });

    this.onTreeChanged();
    return updated;
  }

  deletePage(notebookId: string, sectionId: string, pageId: string): void {
    const known = this.knownPage(notebookId, pageId);
    const fileId =
      known?.driveFileId ?? this.promotedLocalKeys.get(`local:${pageId}`) ?? undefined;

    this.pendingPages.set(pageId, { model: null });
    const key = `pages:${notebookId}/${sectionId}`;
    this.indexKeys[key] = ((this.indexKeys[key] ?? []) as NotePage[]).filter(
      (p) => p.id !== pageId,
    );
    this.pageCache.evict(`local:${pageId}`);
    if (fileId) this.pageCache.evict(fileId);
    this.aiArtifacts.forgetPage(notebookId, pageId);
    this.saveIndex();

    this.cancelPendingFor(new Set([pageId]));
    this.enqueue('deletePage', {
      docId: pageId,
      notebookId,
      pageId,
      ...(fileId ? { fileId } : {}),
    });
    this.onTreeChanged();
  }

  // ── Page Content Load / Save / Promote ────────────────────────────────────

  resolveContentKey(keyOrId: string): string {
    return this.promotedLocalKeys.get(keyOrId) ?? keyOrId;
  }

  async loadPageContent(
    pageId: string,
    driveFileId: string | null,
    title = 'Untitled page',
  ): Promise<PageContent> {
    if (this.auth.isDemo()) {
      const k = driveFileId || `local:${pageId}`;
      return (
        this.demoContents.get(k) ??
        DEMO_PAGE_CONTENTS[k] ??
        this.pageCache.empty(title)
      );
    }

    const rawKey = driveFileId || `local:${pageId}`;
    const resolvedKey = this.resolveContentKey(rawKey);

    if (resolvedKey.startsWith('local:')) {
      return (
        this.pageCache.readContent(resolvedKey) ?? this.pageCache.empty(title)
      );
    }

    const cached = this.pageCache.readContent(resolvedKey);
    if (cached) {
      if (!this.offlineMode) {
        void this.revalidateInBackground(resolvedKey, cached);
      }
      return cached;
    }

    if (!this.offlineMode) {
      try {
        const remote = await this.drive.readPageFile(resolvedKey);
        this.pageCache.writeContent(resolvedKey, remote);
        const tag = await this.drive.remoteModifiedTime(resolvedKey);
        if (tag) this.pageCache.writeTag(resolvedKey, tag);
        return remote;
      } catch (err) {
        console.warn(`Failed to download page ${resolvedKey}:`, err);
      }
    }

    return this.pageCache.empty(title);
  }

  private async revalidateInBackground(
    driveFileId: string,
    cached: PageContent,
  ): Promise<void> {
    try {
      const remoteTag = await this.drive.remoteModifiedTime(driveFileId);
      const cachedTag = this.pageCache.readTag(driveFileId);
      if (!remoteTag || remoteTag === cachedTag) return;

      const remote = await this.drive.readPageFile(driveFileId);
      if (remoteIsNewer(remote, cached)) {
        this.pageCache.writeContent(driveFileId, remote);
        this.onTreeChanged();
      }
      this.pageCache.writeTag(driveFileId, remoteTag);
    } catch {
      // background revalidation is best-effort
    }
  }

  async savePageContent(
    pageId: string,
    driveFileId: string | null,
    content: PageContent,
  ): Promise<void> {
    const stamped: PageContent = {
      ...content,
      updatedAt: new Date().toISOString(),
    };

    if (this.auth.isDemo()) {
      const k = driveFileId || `local:${pageId}`;
      this.demoContents.set(k, stamped);
      return;
    }

    const rawKey = driveFileId || `local:${pageId}`;
    const resolvedKey = this.resolveContentKey(rawKey);

    this.pageCache.writeContent(resolvedKey, stamped);
    this.pageCache.markDirty(resolvedKey);
    this.onTreeChanged();

    if (resolvedKey.startsWith('local:') || this.offlineMode) {
      return;
    }

    try {
      const modifiedTime = await this.drive.updatePageFile(resolvedKey, stamped);
      this.pageCache.writeTag(resolvedKey, modifiedTime);
      this.pageCache.clearDirty(resolvedKey);
      this.onTreeChanged();
    } catch (err) {
      console.warn(`Deferred dirty upload for ${resolvedKey}:`, err);
    }
  }

  async promoteLocalPage(localKey: string, name: string): Promise<string> {
    const existingPromoted = this.promotedLocalKeys.get(localKey);
    if (existingPromoted) return existingPromoted;

    const content =
      this.pageCache.readContent(localKey) ?? this.pageCache.empty('Untitled page');
    const { id: driveId, modifiedTime } = await this.drive.createPageFile(
      name,
      content,
    );

    this.pageCache.writeContent(driveId, content);
    this.pageCache.writeTag(driveId, modifiedTime);
    this.promotedLocalKeys.set(localKey, driveId);
    this.pageCache.evict(localKey);
    return driveId;
  }

  async uploadDirtyPages(): Promise<void> {
    if (this.auth.isDemo() || this.offlineMode) return;
    const dirtyIds = this.pageCache.listDirtyIds();
    for (const id of dirtyIds) {
      if (id.startsWith('local:')) continue;
      const content = this.pageCache.readContent(id);
      if (!content) {
        this.pageCache.clearDirty(id);
        continue;
      }
      try {
        const tag = await this.drive.updatePageFile(id, content);
        this.pageCache.writeTag(id, tag);
        this.pageCache.clearDirty(id);
      } catch {
        break; // Stop on first error
      }
    }
    this.onTreeChanged();
  }

  // ── Outbox Drain Loop ─────────────────────────────────────────────────────

  async flushOutbox(): Promise<void> {
    if (this.flushing || this.offlineMode || this.auth.isDemo()) return;
    if (!this.auth.getCurrentUser()) return;
    if (this.outboxOps.length === 0) {
      await this.uploadDirtyPages();
      return;
    }

    this.flushing = true;
    this.onTreeChanged();

    try {
      while (this.outboxOps.length > 0 && !this.offlineMode) {
        const op = this.outboxOps[0];
        try {
          await this.executeOutboxOp(op);
          this.outboxOps.shift();
          this.saveOutbox();
          this.markSettled(String(op.args.docId ?? ''));
          this.strikes = 0;
          this.lastError = null;
        } catch (err) {
          const classification = classifyFailure(err);
          if (classification === 'drop') {
            this.outboxOps.shift();
            this.saveOutbox();
            this.markSettled(String(op.args.docId ?? ''));
            continue;
          }
          op.attempts += 1;
          op.lastError = String(err);
          this.lastError = op.lastError;
          this.saveOutbox();
          this.scheduleBackoff();
          break;
        }
      }

      if (this.outboxOps.length === 0) {
        await this.uploadDirtyPages();
      }
    } finally {
      this.flushing = false;
      this.onTreeChanged();
    }
  }

  private markSettled(docId: string): void {
    if (!docId) return;
    const now = Date.now();
    for (const map of [
      this.pendingNotebooks,
      this.pendingSections,
      this.pendingPages,
    ]) {
      const entry = map.get(docId);
      if (entry) entry.settledAt = now;
    }
  }

  private scheduleBackoff(): void {
    if (this.backoffTimer) clearTimeout(this.backoffTimer);
    const delays = [15000, 30000, 60000, 120000, 300000];
    const delay = delays[Math.min(this.strikes, delays.length - 1)];
    this.strikes += 1;
    this.backoffTimer = setTimeout(() => {
      this.backoffTimer = null;
      void this.flushOutbox();
    }, delay);
  }

  private async executeOutboxOp(op: PendingOp): Promise<void> {
    switch (op.kind) {
      case 'set': {
        const docPath = String(op.args.path);
        const data = (op.args.data ?? {}) as Record<string, unknown>;
        await this.firestore.setDoc(docPath, data);
        break;
      }
      case 'update': {
        const docPath = String(op.args.path);
        const data = { ...((op.args.data ?? {}) as Record<string, unknown>) };
        if (data.driveFileId === null) {
          delete data.driveFileId;
        }
        await this.firestore.updateDoc(docPath, data);
        break;
      }
      case 'promote': {
        const notebookId = String(op.args.notebookId);
        const pageId = String(op.args.pageId);
        const localKey = String(op.args.localKey);
        const name = String(op.args.name || `page-${Date.now()}`);
        const fileId = await this.promoteLocalPage(localKey, name);
        await this.firestore.updateDoc(`notebooks/${notebookId}/pages/${pageId}`, {
          driveFileId: fileId,
        });
        const known = this.knownPage(notebookId, pageId);
        if (known) {
          const promotedPage: NotePage = { ...known, driveFileId: fileId };
          this.pendingPages.set(pageId, {
            model: promotedPage,
            settledAt: Date.now(),
          });
          const secKey = `pages:${notebookId}/${known.sectionId}`;
          this.indexKeys[secKey] = (
            (this.indexKeys[secKey] ?? []) as NotePage[]
          ).map((p) => (p.id === pageId ? promotedPage : p));
          this.saveIndex();
        }
        break;
      }
      case 'deletePage': {
        const notebookId = String(op.args.notebookId);
        const pageId = String(op.args.pageId);
        const fileId = op.args.fileId ? String(op.args.fileId) : null;
        if (fileId) {
          try {
            await this.drive.deleteFile(fileId);
          } catch {
            // best-effort
          }
        }
        await this.firestore.deleteDoc(`notebooks/${notebookId}/pages/${pageId}`);
        break;
      }
      case 'deleteSection': {
        const notebookId = String(op.args.notebookId);
        const sectionId = String(op.args.sectionId);
        const pages = await this.firestore.fetchCollection(
          `notebooks/${notebookId}/pages`,
          { where: { field: 'sectionId', isEqualTo: sectionId } },
        );
        for (const p of pages) {
          const fid = p.data.driveFileId ? String(p.data.driveFileId) : null;
          if (fid) {
            try {
              await this.drive.deleteFile(fid);
            } catch {
              // best-effort
            }
          }
          await this.firestore.deleteDoc(`notebooks/${notebookId}/pages/${p.id}`);
        }
        await this.firestore.deleteDoc(
          `notebooks/${notebookId}/sections/${sectionId}`,
        );
        break;
      }
      case 'deleteNotebook': {
        const notebookId = String(op.args.notebookId);
        const [pages, sections] = await Promise.all([
          this.firestore.fetchCollection(`notebooks/${notebookId}/pages`),
          this.firestore.fetchCollection(`notebooks/${notebookId}/sections`),
        ]);
        for (const p of pages) {
          const fid = p.data.driveFileId ? String(p.data.driveFileId) : null;
          if (fid) {
            try {
              await this.drive.deleteFile(fid);
            } catch {
              // best-effort
            }
          }
          await this.firestore.deleteDoc(`notebooks/${notebookId}/pages/${p.id}`);
        }
        for (const s of sections) {
          await this.firestore.deleteDoc(
            `notebooks/${notebookId}/sections/${s.id}`,
          );
        }
        await this.firestore.deleteDoc(`notebooks/${notebookId}`);
        break;
      }
    }
  }
}
