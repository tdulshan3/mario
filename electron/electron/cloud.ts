import { PageContent } from '../src/shared/types';
import { AuthServiceMain, FIREBASE_PROJECT_ID } from './auth';

// ── Firestore REST v1 Value Encoding / Decoding ─────────────────────────────

interface FirestoreValue {
  nullValue?: null;
  booleanValue?: boolean;
  integerValue?: string;
  doubleValue?: number;
  stringValue?: string;
  timestampValue?: string;
  arrayValue?: { values?: FirestoreValue[] };
  mapValue?: { fields?: Record<string, FirestoreValue> };
}

function encodeValue(val: unknown): FirestoreValue {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (typeof val === 'number') {
    if (Number.isInteger(val)) return { integerValue: String(val) };
    return { doubleValue: val };
  }
  if (typeof val === 'string') return { stringValue: val };
  if (Array.isArray(val)) {
    return { arrayValue: { values: val.map(encodeValue) } };
  }
  if (typeof val === 'object') {
    const fields: Record<string, FirestoreValue> = {};
    for (const [k, v] of Object.entries(val as Record<string, unknown>)) {
      if (v !== undefined) {
        fields[k] = encodeValue(v);
      }
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

function decodeValue(v: FirestoreValue | undefined): unknown {
  if (!v) return null;
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return Boolean(v.booleanValue);
  if ('integerValue' in v) return parseInt(String(v.integerValue ?? '0'), 10);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('stringValue' in v) return String(v.stringValue ?? '');
  if ('timestampValue' in v) return String(v.timestampValue ?? '');
  if ('arrayValue' in v) {
    return (v.arrayValue?.values ?? []).map(decodeValue);
  }
  if ('mapValue' in v) {
    const out: Record<string, unknown> = {};
    for (const [k, fv] of Object.entries(v.mapValue?.fields ?? {})) {
      out[k] = decodeValue(fv);
    }
    return out;
  }
  return null;
}

export interface FirestoreDocResult {
  id: string;
  path: string;
  data: Record<string, unknown>;
}

export interface FirestoreFilter {
  field: string;
  isEqualTo?: unknown;
  arrayContains?: unknown;
}

export class FirestoreRestClient {
  private readonly auth: AuthServiceMain;
  private readonly baseUrl = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents`;

  constructor(auth: AuthServiceMain) {
    this.auth = auth;
  }

  private async headers(): Promise<Record<string, string>> {
    const token = await this.auth.getFirebaseIdToken();
    return {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    };
  }

  private unwrapDoc(doc: {
    name: string;
    fields?: Record<string, FirestoreValue>;
  }): FirestoreDocResult {
    const parts = doc.name.split('/documents/');
    const relPath = parts[1] ?? doc.name;
    const segs = relPath.split('/');
    const id = segs[segs.length - 1];
    const data: Record<string, unknown> = {};
    for (const [k, fv] of Object.entries(doc.fields ?? {})) {
      data[k] = decodeValue(fv);
    }
    return { id, path: relPath, data };
  }

  async fetchCollection(
    collectionPath: string,
    opts?: {
      where?: FirestoreFilter;
      orderBy?: string;
      descending?: boolean;
    },
  ): Promise<FirestoreDocResult[]> {
    const segs = collectionPath.split('/').filter(Boolean);
    const collectionId = segs[segs.length - 1];
    const parentRel = segs.slice(0, -1).join('/');
    const parentUrl = parentRel ? `${this.baseUrl}/${parentRel}` : this.baseUrl;

    const structuredQuery: Record<string, unknown> = {
      from: [{ collectionId }],
    };

    if (opts?.where) {
      const op =
        opts.where.arrayContains !== undefined ? 'ARRAY_CONTAINS' : 'EQUAL';
      const val =
        opts.where.arrayContains !== undefined
          ? opts.where.arrayContains
          : opts.where.isEqualTo;
      structuredQuery.where = {
        fieldFilter: {
          field: { fieldPath: opts.where.field },
          op,
          value: encodeValue(val),
        },
      };
    }

    if (opts?.orderBy) {
      structuredQuery.orderBy = [
        {
          field: { fieldPath: opts.orderBy },
          direction: opts.descending ? 'DESCENDING' : 'ASCENDING',
        },
      ];
    }

    const resp = await fetch(`${parentUrl}:runQuery`, {
      method: 'POST',
      headers: await this.headers(),
      body: JSON.stringify({ structuredQuery }),
    });

    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Firestore runQuery(${collectionPath}) failed (${resp.status}): ${text}`);
    }

    const rows = (await resp.json()) as Array<{
      document?: { name: string; fields?: Record<string, FirestoreValue> };
    }>;

    const out: FirestoreDocResult[] = [];
    for (const row of rows) {
      if (row.document) {
        out.push(this.unwrapDoc(row.document));
      }
    }
    return out;
  }

  async getDoc(docPath: string): Promise<FirestoreDocResult | null> {
    const resp = await fetch(`${this.baseUrl}/${docPath}`, {
      headers: await this.headers(),
    });
    if (resp.status === 404) return null;
    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Firestore getDoc(${docPath}) failed (${resp.status}): ${text}`);
    }
    const doc = (await resp.json()) as {
      name: string;
      fields?: Record<string, FirestoreValue>;
    };
    return this.unwrapDoc(doc);
  }

  async setDoc(docPath: string, data: Record<string, unknown>): Promise<void> {
    const fields: Record<string, FirestoreValue> = {};
    for (const [k, v] of Object.entries(data)) {
      if (v !== undefined) fields[k] = encodeValue(v);
    }
    const resp = await fetch(`${this.baseUrl}/${docPath}`, {
      method: 'PATCH',
      headers: await this.headers(),
      body: JSON.stringify({ fields }),
    });
    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Firestore setDoc(${docPath}) failed (${resp.status}): ${text}`);
    }
  }

  async updateDoc(docPath: string, data: Record<string, unknown>): Promise<void> {
    const keys = Object.keys(data).filter((k) => data[k] !== undefined);
    if (keys.length === 0) return;
    const params = new URLSearchParams();
    for (const k of keys) {
      params.append('updateMask.fieldPaths', k);
    }
    const fields: Record<string, FirestoreValue> = {};
    for (const k of keys) {
      fields[k] = encodeValue(data[k]);
    }
    const resp = await fetch(`${this.baseUrl}/${docPath}?${params.toString()}`, {
      method: 'PATCH',
      headers: await this.headers(),
      body: JSON.stringify({ fields }),
    });
    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Firestore updateDoc(${docPath}) failed (${resp.status}): ${text}`);
    }
  }

  async deleteDoc(docPath: string): Promise<void> {
    const resp = await fetch(`${this.baseUrl}/${docPath}`, {
      method: 'DELETE',
      headers: await this.headers(),
    });
    if (!resp.ok && resp.status !== 404) {
      const text = await resp.text();
      throw new Error(`Firestore deleteDoc(${docPath}) failed (${resp.status}): ${text}`);
    }
  }

  async arrayUnion(docPath: string, field: string, items: unknown[]): Promise<void> {
    const existing = await this.getDoc(docPath);
    const cur = Array.isArray(existing?.data?.[field])
      ? (existing!.data[field] as unknown[])
      : [];
    const seen = new Set(cur.map((x) => JSON.stringify(x)));
    const next = [...cur];
    for (const it of items) {
      const s = JSON.stringify(it);
      if (!seen.has(s)) {
        seen.add(s);
        next.push(it);
      }
    }
    await this.updateDoc(docPath, { [field]: next });
  }
}

// ── Google Drive appDataFolder REST v3 Client ───────────────────────────────

export class DriveRestClient {
  private readonly auth: AuthServiceMain;

  constructor(auth: AuthServiceMain) {
    this.auth = auth;
  }

  async createPageFile(
    name: string,
    content: PageContent,
  ): Promise<{ id: string; modifiedTime: string }> {
    const token = await this.auth.getDriveAccessToken();
    const boundary = `mario_boundary_${Date.now().toString(36)}`;
    const metadata = JSON.stringify({
      name: name.endsWith('.json') ? name : `${name}.json`,
      parents: ['appDataFolder'],
      mimeType: 'application/json',
    });
    const media = JSON.stringify(content);
    const multipartBody = [
      `--${boundary}`,
      'Content-Type: application/json; charset=UTF-8',
      '',
      metadata,
      `--${boundary}`,
      'Content-Type: application/json; charset=UTF-8',
      '',
      media,
      `--${boundary}--`,
    ].join('\r\n');

    const resp = await fetch(
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,modifiedTime',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': `multipart/related; boundary=${boundary}`,
        },
        body: multipartBody,
      },
    );

    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Drive createPageFile failed (${resp.status}): ${text}`);
    }

    const res = (await resp.json()) as { id: string; modifiedTime?: string };
    return {
      id: res.id,
      modifiedTime: res.modifiedTime || new Date().toISOString(),
    };
  }

  async updatePageFile(fileId: string, content: PageContent): Promise<string> {
    const token = await this.auth.getDriveAccessToken();
    const resp = await fetch(
      `https://www.googleapis.com/upload/drive/v3/files/${encodeURIComponent(fileId)}?uploadType=media&fields=modifiedTime`,
      {
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify(content),
      },
    );

    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Drive updatePageFile(${fileId}) failed (${resp.status}): ${text}`);
    }

    const res = (await resp.json()) as { modifiedTime?: string };
    return res.modifiedTime || new Date().toISOString();
  }

  async readPageFile(fileId: string): Promise<PageContent> {
    const token = await this.auth.getDriveAccessToken();
    const resp = await fetch(
      `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?alt=media`,
      {
        headers: { Authorization: `Bearer ${token}` },
      },
    );

    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Drive readPageFile(${fileId}) failed (${resp.status}): ${text}`);
    }

    const raw = await resp.json();
    if (raw && typeof raw === 'object' && 'document' in raw) {
      return raw as PageContent;
    }
    return {
      document: raw?.type === 'page' ? raw : { type: 'page', children: [] },
      title: 'Untitled page',
    };
  }

  async remoteModifiedTime(fileId: string): Promise<string | null> {
    const token = await this.auth.getDriveAccessToken();
    const resp = await fetch(
      `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?fields=modifiedTime`,
      {
        headers: { Authorization: `Bearer ${token}` },
      },
    );
    if (!resp.ok) return null;
    const data = (await resp.json()) as { modifiedTime?: string };
    return data.modifiedTime ?? null;
  }

  async deleteFile(fileId: string): Promise<void> {
    const token = await this.auth.getDriveAccessToken();
    const resp = await fetch(
      `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}`,
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      },
    );
    if (!resp.ok && resp.status !== 404) {
      const text = await resp.text();
      throw new Error(`Drive deleteFile(${fileId}) failed (${resp.status}): ${text}`);
    }
  }

  async uploadBinaryAsset(
    name: string,
    mimeType: string,
    bytes: Buffer,
  ): Promise<string> {
    const token = await this.auth.getDriveAccessToken();
    const boundary = `mario_asset_${Date.now().toString(36)}`;
    const meta = JSON.stringify({
      name,
      parents: ['appDataFolder'],
      mimeType,
    });
    const prefix = Buffer.from(
      `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${meta}\r\n--${boundary}\r\nContent-Type: ${mimeType}\r\n\r\n`,
      'utf8',
    );
    const suffix = Buffer.from(`\r\n--${boundary}--`, 'utf8');
    const body = Buffer.concat([prefix, bytes, suffix]);

    const resp = await fetch(
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': `multipart/related; boundary=${boundary}`,
        },
        body,
      },
    );

    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Drive uploadBinaryAsset failed (${resp.status}): ${text}`);
    }
    const res = (await resp.json()) as { id: string };
    return res.id;
  }

  async downloadBinaryAsset(fileId: string): Promise<Buffer> {
    const token = await this.auth.getDriveAccessToken();
    const resp = await fetch(
      `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?alt=media`,
      {
        headers: { Authorization: `Bearer ${token}` },
      },
    );
    if (!resp.ok) {
      throw new Error(`Drive downloadBinaryAsset(${fileId}) failed (${resp.status})`);
    }
    const ab = await resp.arrayBuffer();
    return Buffer.from(ab);
  }
}
