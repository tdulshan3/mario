import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  AiArtifactData,
  CanvasWidth,
  LlmProviderConfig,
  MarioThemeMode,
  PageContent,
  RecentSelectionState,
  SettingsState,
} from '../src/shared/types';
import { safeFilename } from '../src/shared/ids';
import { emptyPageContent } from '../src/shared/document-codec';
import { normalizeRecentSelection } from '../src/shared/recent-selection';

export const APP_ID = 'com.marionote.app.mario';

export function getSupportDir(): string {
  const xdg = process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share');
  const dir = path.join(xdg, APP_ID);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

export function getDocumentsDir(): string {
  const xdg = process.env.XDG_DOCUMENTS_DIR || path.join(os.homedir(), 'Documents');
  fs.mkdirSync(xdg, { recursive: true });
  return xdg;
}

let writeSeq = 0;
export function atomicWriteFile(targetPath: string, data: string | Buffer): void {
  const dir = path.dirname(targetPath);
  fs.mkdirSync(dir, { recursive: true });
  const tmpPath = `${targetPath}.tmp.${process.pid}.${++writeSeq}`;
  fs.writeFileSync(tmpPath, data, typeof data === 'string' ? { encoding: 'utf8' } : undefined);
  fs.renameSync(tmpPath, targetPath);
}

// ── SharedPreferences (compatible with Flutter Linux shared_preferences.json) ─

export class SharedPreferencesStore {
  private get filePath(): string {
    return path.join(getSupportDir(), 'shared_preferences.json');
  }

  readAll(): Record<string, unknown> {
    try {
      if (!fs.existsSync(this.filePath)) return {};
      const raw = fs.readFileSync(this.filePath, 'utf8');
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : {};
    } catch {
      return {};
    }
  }

  get<T>(key: string, fallback: T): T {
    const all = this.readAll();
    const flutterKey = key.startsWith('flutter.') ? key : `flutter.${key}`;
    if (flutterKey in all) return all[flutterKey] as T;
    if (key in all) return all[key] as T;
    return fallback;
  }

  set(key: string, value: unknown): void {
    const all = this.readAll();
    const flutterKey = key.startsWith('flutter.') ? key : `flutter.${key}`;
    if (value === null || value === undefined) {
      delete all[flutterKey];
    } else {
      all[flutterKey] = value;
    }
    atomicWriteFile(this.filePath, JSON.stringify(all));
  }

  loadSettings(): SettingsState {
    const rawTheme = String(this.get('mario.theme', 'system'));
    const themeMode: MarioThemeMode =
      rawTheme === 'dark'
        ? 'night'
        : rawTheme === 'book'
          ? 'white'
          : (['system', 'light', 'white', 'night', 'black'].includes(rawTheme)
              ? (rawTheme as MarioThemeMode)
              : 'system');

    const rawWidth = String(this.get('mario.canvasWidth', 'medium'));
    const canvasWidth: CanvasWidth = ['narrow', 'medium', 'full'].includes(rawWidth)
      ? (rawWidth as CanvasWidth)
      : 'medium';

    const rawScale = Number(this.get('mario.fontScale', 1.0));
    const fontScale = Number.isFinite(rawScale)
      ? Math.min(2.0, Math.max(0.5, rawScale))
      : 1.0;

    return {
      themeMode,
      fontScale,
      canvasWidth,
      autoCorrectMath: Boolean(this.get('mario.autoCorrectMath', true)),
      spellCheck: Boolean(this.get('mario.spellCheck', true)),
      holdToRecord: Boolean(this.get('mario.holdToRecord', false)),
      voiceLocale: String(this.get('mario.voiceLocale', 'en_US')),
      offlineMode: Boolean(this.get('mario.offlineMode', false)),
      askOnHighlight: Boolean(this.get('mario.askOnHighlight', true)),
      recentSelection: this.loadRecentSelection(),
    };
  }

  saveSettings(next: SettingsState): SettingsState {
    this.set('mario.theme', next.themeMode);
    this.set('mario.fontScale', next.fontScale);
    this.set('mario.canvasWidth', next.canvasWidth);
    this.set('mario.autoCorrectMath', next.autoCorrectMath);
    this.set('mario.spellCheck', next.spellCheck);
    this.set('mario.holdToRecord', next.holdToRecord);
    this.set('mario.voiceLocale', next.voiceLocale);
    this.set('mario.offlineMode', next.offlineMode);
    this.set('mario.askOnHighlight', next.askOnHighlight);
    if (next.recentSelection !== undefined) {
      this.saveRecentSelection(next.recentSelection);
    }
    return this.loadSettings();
  }

  loadRecentSelection(): RecentSelectionState {
    const raw = this.get<unknown>('mario.recentSelection', null);
    return normalizeRecentSelection(raw);
  }

  saveRecentSelection(recent: RecentSelectionState): RecentSelectionState {
    const normalized = normalizeRecentSelection(recent);
    this.set('mario.recentSelection', JSON.stringify(normalized));
    return normalized;
  }

  loadAiProviders(): { providers: LlmProviderConfig[]; activeId: string | null } {
    const raw = this.get<string>('mario.ai.providers', '[]');
    let providers: LlmProviderConfig[] = [];
    try {
      const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (Array.isArray(parsed)) {
        providers = parsed as LlmProviderConfig[];
      }
    } catch {
      providers = [];
    }
    const activeId = this.get<string | null>('mario.ai.activeProvider', null);
    return { providers, activeId };
  }

  saveAiProviders(providers: LlmProviderConfig[], activeId: string | null): void {
    this.set('mario.ai.providers', JSON.stringify(providers));
    this.set('mario.ai.activeProvider', activeId);
  }
}

// ── KeyringStore (compatible with flutter_secure_storage_linux libsecret) ───

export class KeyringStore {
  private readonly account = `${APP_ID}.secureStorage`;
  private readonly label = `${APP_ID}/FlutterSecureStorage`;
  private cache: Record<string, string> | null = null;

  private get fallbackPath(): string {
    return path.join(getSupportDir(), '.secure_storage_fallback.json');
  }

  readAll(): Record<string, string> {
    if (this.cache) return { ...this.cache };
    try {
      const out = execFileSync(
        'secret-tool',
        ['lookup', 'account', this.account],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 3000 },
      );
      if (out && out.trim()) {
        const parsed = JSON.parse(out.trim());
        if (parsed && typeof parsed === 'object') {
          this.cache = parsed as Record<string, string>;
          return { ...this.cache };
        }
      }
    } catch {
      // Fallback if secret-tool is unavailable or entry doesn't exist
    }
    try {
      if (fs.existsSync(this.fallbackPath)) {
        const parsed = JSON.parse(fs.readFileSync(this.fallbackPath, 'utf8'));
        this.cache = parsed;
        return { ...parsed };
      }
    } catch {
      // ignore
    }
    this.cache = {};
    return {};
  }

  get(key: string): string | null {
    const all = this.readAll();
    return all[key] ?? null;
  }

  set(key: string, value: string | null): void {
    const all = this.readAll();
    if (value === null || value === '') {
      delete all[key];
    } else {
      all[key] = value;
    }
    this.cache = all;
    const payload = JSON.stringify(all);
    try {
      execFileSync(
        'secret-tool',
        ['store', `--label=${this.label}`, 'account', this.account],
        { input: payload, encoding: 'utf8', stdio: ['pipe', 'ignore', 'ignore'], timeout: 3000 },
      );
    } catch {
      atomicWriteFile(this.fallbackPath, payload);
    }
  }
}

// ── Desktop OAuth Secrets Loader (.env + Environment Variables) ─────────────

declare const __BUNDLED_CLIENT_ID__: string | undefined;
declare const __BUNDLED_CLIENT_SECRET__: string | undefined;

export interface OAuthSecrets {
  desktopClientId: string;
  desktopClientSecret: string;
}

export function loadOAuthSecrets(): OAuthSecrets {
  let id =
    process.env.MARIO_DESKTOP_CLIENT_ID ||
    process.env.GOOGLE_CLIENT_ID ||
    process.env.DESKTOPCLIENTID ||
    (typeof __BUNDLED_CLIENT_ID__ !== 'undefined' ? __BUNDLED_CLIENT_ID__ : '') ||
    '';
  let secret =
    process.env.MARIO_DESKTOP_CLIENT_SECRET ||
    process.env.GOOGLE_CLIENT_SECRET ||
    process.env.DESKTOPCLIENTSECRET ||
    (typeof __BUNDLED_CLIENT_SECRET__ !== 'undefined' ? __BUNDLED_CLIENT_SECRET__ : '') ||
    '';

  if (id && secret) return { desktopClientId: id, desktopClientSecret: secret };

  const candidates = [
    path.resolve(process.cwd(), '.env'),
    path.resolve(process.cwd(), '..', '.env'),
    path.resolve(__dirname, '..', '.env'),
    path.resolve(__dirname, '..', '..', '.env'),
    '/opt/mario/.env',
  ];

  for (const envPath of candidates) {
    if (!fs.existsSync(envPath)) continue;
    try {
      const content = fs.readFileSync(envPath, 'utf8');
      for (const rawLine of content.split(/\r?\n/)) {
        const line = rawLine.trim();
        if (!line || line.startsWith('#')) continue;
        const eq = line.indexOf('=');
        if (eq < 0) continue;
        const k = line.slice(0, eq).trim().toLowerCase();
        let v = line.slice(eq + 1).trim();
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
          v = v.slice(1, -1);
        }
        if (v.startsWith('{')) {
          const lastBrace = v.lastIndexOf('}');
          if (lastBrace > 0) {
            try {
              const json = JSON.parse(v.slice(0, lastBrace + 1));
              const inner = json.installed ?? json.web ?? json;
              if (!id && inner.client_id) id = String(inner.client_id);
              if (!secret && inner.client_secret) secret = String(inner.client_secret);
            } catch {
              // ignore malformed JSON
            }
          }
        }
        if (!id && (k === 'desktopclientid' || k === 'desktop_client_id' || k === 'mario_desktop_client_id')) {
          id = v;
        }
        if (
          !secret &&
          (k === 'desktopclientsecret' ||
            k === 'desktop_client_secret' ||
            k === 'mario_desktop_client_secret')
        ) {
          secret = v;
        }
      }
      if (id && secret) break;
    } catch {
      // ignore
    }
  }

  return { desktopClientId: id, desktopClientSecret: secret };
}

// ── PageContentCache (~/.local/share/com.marionote.app.mario/page_content_cache) ─

export class PageContentCache {
  private get dir(): string {
    const d = path.join(getSupportDir(), 'page_content_cache');
    fs.mkdirSync(d, { recursive: true });
    return d;
  }

  private jsonPath(id: string): string {
    return path.join(this.dir, `${safeFilename(id)}.json`);
  }

  private tagPath(id: string): string {
    return path.join(this.dir, `${safeFilename(id)}.tag`);
  }

  private dirtyPath(id: string): string {
    return path.join(this.dir, `${safeFilename(id)}.dirty`);
  }

  readContent(id: string): PageContent | null {
    try {
      const p = this.jsonPath(id);
      if (!fs.existsSync(p)) return null;
      const raw = JSON.parse(fs.readFileSync(p, 'utf8'));
      if (!raw || typeof raw !== 'object') return null;
      if ('document' in raw) return raw as PageContent;
      if (raw.type === 'page') {
        return { document: raw, title: 'Untitled page' };
      }
      return null;
    } catch {
      return null;
    }
  }

  writeContent(id: string, content: PageContent): void {
    atomicWriteFile(this.jsonPath(id), JSON.stringify(content));
  }

  readTag(id: string): string | null {
    try {
      const p = this.tagPath(id);
      if (!fs.existsSync(p)) return null;
      return fs.readFileSync(p, 'utf8').trim() || null;
    } catch {
      return null;
    }
  }

  writeTag(id: string, tag: string): void {
    atomicWriteFile(this.tagPath(id), tag);
  }

  deleteTag(id: string): void {
    try {
      const p = this.tagPath(id);
      if (fs.existsSync(p)) fs.unlinkSync(p);
    } catch {
      // ignore
    }
  }

  markDirty(id: string): void {
    this.deleteTag(id);
    atomicWriteFile(this.dirtyPath(id), id);
  }

  clearDirty(id: string): void {
    try {
      const p = this.dirtyPath(id);
      if (fs.existsSync(p)) fs.unlinkSync(p);
    } catch {
      // ignore
    }
  }

  listDirtyIds(): string[] {
    try {
      const entries = fs.readdirSync(this.dir);
      const ids: string[] = [];
      for (const name of entries) {
        if (name.endsWith('.dirty')) {
          const full = path.join(this.dir, name);
          const id = fs.readFileSync(full, 'utf8').trim();
          if (id) ids.push(id);
        }
      }
      return ids;
    } catch {
      return [];
    }
  }

  evict(id: string): void {
    for (const p of [this.jsonPath(id), this.tagPath(id), this.dirtyPath(id)]) {
      try {
        if (fs.existsSync(p)) fs.unlinkSync(p);
      } catch {
        // ignore
      }
    }
  }

  empty(title = 'Untitled page'): PageContent {
    return emptyPageContent(title);
  }
}

// ── AssetCache (~/Documents/mario_images) ───────────────────────────────────

interface AssetIndexJson {
  assets: Record<string, string>;
  hashes: Record<string, string>;
}

export class AssetCache {
  get dir(): string {
    const d = path.join(getDocumentsDir(), 'mario_images');
    fs.mkdirSync(d, { recursive: true });
    return d;
  }

  private get indexPath(): string {
    return path.join(this.dir, 'index.json');
  }

  readIndex(): AssetIndexJson {
    try {
      if (!fs.existsSync(this.indexPath)) return { assets: {}, hashes: {} };
      const parsed = JSON.parse(fs.readFileSync(this.indexPath, 'utf8'));
      return {
        assets: parsed?.assets ?? {},
        hashes: parsed?.hashes ?? {},
      };
    } catch {
      return { assets: {}, hashes: {} };
    }
  }

  writeIndex(idx: AssetIndexJson): void {
    atomicWriteFile(this.indexPath, JSON.stringify(idx, null, 2));
  }

  pathFor(driveId: string): string | null {
    const idx = this.readIndex();
    const rel = idx.assets[driveId];
    if (!rel) return null;
    const full = path.isAbsolute(rel) ? rel : path.join(this.dir, rel);
    return fs.existsSync(full) ? full : null;
  }

  sha256File(filePath: string): string {
    const bytes = fs.readFileSync(filePath);
    return crypto.createHash('sha256').update(bytes).digest('hex');
  }

  copyIntoImagesDir(sourcePath: string): { localPath: string; sha256: string } {
    const bytes = fs.readFileSync(sourcePath);
    const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
    const ext = path.extname(sourcePath) || '.png';
    const filename = `img_${sha256.slice(0, 16)}${ext}`;
    const dest = path.join(this.dir, filename);
    if (!fs.existsSync(dest)) {
      atomicWriteFile(dest, bytes);
    }
    return { localPath: dest, sha256 };
  }

  storeDownloaded(driveId: string, bytes: Buffer, ext = '.png'): string {
    const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
    const cleanExt = ext.startsWith('.') ? ext : `.${ext}`;
    const filename = `asset_${safeFilename(driveId)}${cleanExt}`;
    const full = path.join(this.dir, filename);
    atomicWriteFile(full, bytes);
    const idx = this.readIndex();
    idx.assets[driveId] = filename;
    idx.hashes[sha256] = driveId;
    this.writeIndex(idx);
    return full;
  }
}

// ── AiArtifactStore & User Skills Loader ────────────────────────────────────

export class AiArtifactStore {
  private get dir(): string {
    const d = path.join(getSupportDir(), 'ai_artifacts');
    fs.mkdirSync(d, { recursive: true });
    return d;
  }

  private filePath(notebookId: string): string {
    return path.join(this.dir, `${safeFilename(notebookId)}.json`);
  }

  read(notebookId: string): AiArtifactData {
    try {
      const p = this.filePath(notebookId);
      if (!fs.existsSync(p)) {
        return { askHistory: [], doHistory: [], quizzes: [] };
      }
      const parsed = JSON.parse(fs.readFileSync(p, 'utf8'));
      return {
        askHistory: Array.isArray(parsed?.askHistory) ? parsed.askHistory : [],
        doHistory: Array.isArray(parsed?.doHistory) ? parsed.doHistory : [],
        quizzes: Array.isArray(parsed?.quizzes) ? parsed.quizzes : [],
      };
    } catch {
      return { askHistory: [], doHistory: [], quizzes: [] };
    }
  }

  write(notebookId: string, data: AiArtifactData): void {
    atomicWriteFile(this.filePath(notebookId), JSON.stringify(data, null, 2));
  }

  forgetPage(notebookId: string, pageId: string): void {
    const cur = this.read(notebookId);
    this.write(notebookId, {
      askHistory: cur.askHistory.filter((x) => x.pageId !== pageId),
      doHistory: cur.doHistory.filter((x) => x.pageId !== pageId),
      quizzes: cur.quizzes.filter((x) => x.pageId !== pageId),
    });
  }

  forgetNotebook(notebookId: string): void {
    try {
      const p = this.filePath(notebookId);
      if (fs.existsSync(p)) fs.unlinkSync(p);
    } catch {
      // ignore
    }
  }
}

export function loadUserSkills(): string[] {
  try {
    const skillsDir = path.join(getSupportDir(), 'skills');
    if (!fs.existsSync(skillsDir)) return [];
    const files = fs
      .readdirSync(skillsDir)
      .filter((f) => f.endsWith('.md'))
      .sort();
    return files.map((f) => {
      const content = fs.readFileSync(path.join(skillsDir, f), 'utf8');
      return content.slice(0, 6000);
    });
  } catch {
    return [];
  }
}
