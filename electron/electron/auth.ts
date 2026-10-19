import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { URL } from 'node:url';
import { AuthUser } from '../src/shared/types';
import { DEMO_USER } from '../src/shared/demo-data';
import { getSupportDir, KeyringStore, loadOAuthSecrets } from './storage';

export const FIREBASE_WEB_API_KEY = 'AIzaSyC-jbbCfBFLaJlXXnOxNf6TzwXgKz_cXzY';
export const FIREBASE_PROJECT_ID = 'mario-aa9aa';

const OAUTH_SCOPES = [
  'email',
  'profile',
  'openid',
  'https://www.googleapis.com/auth/drive.appdata',
  'https://www.googleapis.com/auth/drive.file',
];

const REFRESH_TOKEN_KEY = 'mario_google_refresh_token';
const CACHED_USER_FILE = 'cached_auth_user.json';

interface TokenState {
  googleAccessToken: string;
  googleIdToken: string;
  googleRefreshToken: string;
  googleExpiresAt: number;
  firebaseIdToken: string;
  firebaseRefreshToken: string;
  firebaseExpiresAt: number;
}

export class AuthServiceMain {
  private user: AuthUser | null = null;
  private tokens: TokenState | null = null;
  private readonly keyring: KeyringStore;
  private readonly demoMode: boolean;

  constructor(keyring: KeyringStore, demoMode = false) {
    this.keyring = keyring;
    this.demoMode = demoMode;
    if (this.demoMode) {
      this.user = DEMO_USER;
    }
  }

  isDemo(): boolean {
    return this.demoMode;
  }

  getCurrentUser(): AuthUser | null {
    return this.user;
  }

  private get cachedUserPath(): string {
    return path.join(getSupportDir(), CACHED_USER_FILE);
  }

  private saveCachedUser(user: AuthUser): void {
    try {
      fs.writeFileSync(this.cachedUserPath, JSON.stringify(user), 'utf8');
    } catch {
      // ignore
    }
  }

  private loadOfflineFallbackUser(): AuthUser | null {
    try {
      if (fs.existsSync(this.cachedUserPath)) {
        const u = JSON.parse(fs.readFileSync(this.cachedUserPath, 'utf8'));
        if (u?.uid) return u as AuthUser;
      }
    } catch {
      // ignore
    }
    // Check sync/index.json for an existing `notebooks:<uid>` entry from Flutter
    try {
      const idxPath = path.join(getSupportDir(), 'sync', 'index.json');
      if (fs.existsSync(idxPath)) {
        const idx = JSON.parse(fs.readFileSync(idxPath, 'utf8'));
        const keys = Object.keys(idx?.keys ?? {});
        const nbKey = keys.find((k) => k.startsWith('notebooks:'));
        if (nbKey) {
          const uid = nbKey.slice('notebooks:'.length);
          if (uid) {
            return {
              uid,
              email: 'Offline Session',
              displayName: 'Mario User',
            };
          }
        }
      }
    } catch {
      // ignore
    }
    return null;
  }

  signInOffline(): AuthUser {
    let fallback = this.loadOfflineFallbackUser();
    if (!fallback) {
      fallback = {
        uid: 'offline-local-user',
        email: 'offline@local.dev',
        displayName: 'Offline User',
      };
    }
    this.user = fallback;
    this.saveCachedUser(fallback);
    return fallback;
  }

  async restoreSession(): Promise<AuthUser | null> {
    if (this.demoMode) {
      this.user = DEMO_USER;
      return this.user;
    }

    const refreshToken = this.keyring.get(REFRESH_TOKEN_KEY);
    if (!refreshToken) {
      return null;
    }

    try {
      await this.refreshWithToken(refreshToken);
      return this.user;
    } catch (err) {
      // If offline or secrets missing, check if we have a local cached session
      const fallback = this.loadOfflineFallbackUser();
      if (fallback) {
        this.user = fallback;
        return this.user;
      }
      console.warn('Silent session restore failed:', err);
      return null;
    }
  }

  private async refreshWithToken(refreshToken: string): Promise<void> {
    const secrets = loadOAuthSecrets();
    if (!secrets.desktopClientId || !secrets.desktopClientSecret) {
      throw new Error(
        'Missing Google OAuth Desktop credentials in .env (MARIO_DESKTOP_CLIENT_ID / MARIO_DESKTOP_CLIENT_SECRET).',
      );
    }

    const body = new URLSearchParams({
      client_id: secrets.desktopClientId,
      client_secret: secrets.desktopClientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    });

    const resp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    });

    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Google token refresh failed (${resp.status}): ${text}`);
    }

    const data = (await resp.json()) as {
      access_token: string;
      id_token: string;
      refresh_token?: string;
      expires_in?: number;
    };

    const nextRefresh = data.refresh_token || refreshToken;
    if (data.refresh_token) {
      this.keyring.set(REFRESH_TOKEN_KEY, nextRefresh);
    }

    await this.exchangeForFirebaseSession(
      data.access_token,
      data.id_token,
      nextRefresh,
      Number(data.expires_in ?? 3500),
    );
  }

  private async exchangeForFirebaseSession(
    googleAccessToken: string,
    googleIdToken: string,
    googleRefreshToken: string,
    googleExpiresInSec: number,
  ): Promise<void> {
    const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=${FIREBASE_WEB_API_KEY}`;
    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        postBody: `id_token=${encodeURIComponent(googleIdToken)}&providerId=google.com`,
        requestUri: 'http://localhost',
        returnSecureToken: true,
        returnIdpCredential: true,
      }),
    });

    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`Firebase signInWithIdp failed (${resp.status}): ${text}`);
    }

    const fb = (await resp.json()) as {
      localId: string;
      idToken: string;
      refreshToken: string;
      expiresIn?: string;
      email?: string;
      displayName?: string;
      photoUrl?: string;
    };

    const now = Date.now();
    this.tokens = {
      googleAccessToken,
      googleIdToken,
      googleRefreshToken,
      googleExpiresAt: now + Math.max(60, googleExpiresInSec - 60) * 1000,
      firebaseIdToken: fb.idToken,
      firebaseRefreshToken: fb.refreshToken,
      firebaseExpiresAt:
        now + Math.max(60, parseInt(fb.expiresIn || '3600', 10) - 60) * 1000,
    };

    this.user = {
      uid: fb.localId,
      email: fb.email || '',
      displayName: fb.displayName || fb.email || 'Mario User',
      photoUrl: fb.photoUrl,
    };
    this.saveCachedUser(this.user);
  }

  async signInInteractive(openExternal: (url: string) => Promise<void>): Promise<AuthUser> {
    if (this.demoMode) {
      this.user = DEMO_USER;
      return this.user;
    }

    const secrets = loadOAuthSecrets();
    if (!secrets.desktopClientId || !secrets.desktopClientSecret) {
      throw new Error(
        'OAuth credentials not found. Add MARIO_DESKTOP_CLIENT_ID and MARIO_DESKTOP_CLIENT_SECRET to .env.',
      );
    }

    const state = crypto.randomBytes(16).toString('base64url');

    const { code, redirectUri } = await new Promise<{
      code: string;
      redirectUri: string;
    }>((resolve, reject) => {
      const server = http.createServer((req, res) => {
        try {
          const reqUrl = new URL(req.url || '/', 'http://127.0.0.1');
          const returnedState = reqUrl.searchParams.get('state');
          const returnedCode = reqUrl.searchParams.get('code');
          const error = reqUrl.searchParams.get('error');

          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end(`<!doctype html><html><body style="font-family:system-ui;text-align:center;padding:48px">
            <h2>${error ? 'Sign-in cancelled' : 'Signed in to Mario'}</h2>
            <p>You can close this browser tab and return to Mario.</p>
            <script>window.close()</script>
          </body></html>`);

          server.close();
          if (error) {
            reject(new Error(`Google OAuth error: ${error}`));
            return;
          }
          if (returnedState !== state || !returnedCode) {
            reject(new Error('Invalid OAuth state or missing authorization code.'));
            return;
          }
          resolve({ code: returnedCode, redirectUri: currentRedirectUri });
        } catch (e) {
          server.close();
          reject(e);
        }
      });

      let currentRedirectUri = '';
      server.listen(0, '127.0.0.1', () => {
        const addr = server.address();
        if (!addr || typeof addr === 'string') {
          server.close();
          reject(new Error('Failed to bind local loopback server'));
          return;
        }
        currentRedirectUri = `http://127.0.0.1:${addr.port}/`;
        const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
        authUrl.searchParams.set('response_type', 'code');
        authUrl.searchParams.set('client_id', secrets.desktopClientId);
        authUrl.searchParams.set('redirect_uri', currentRedirectUri);
        authUrl.searchParams.set('scope', OAUTH_SCOPES.join(' '));
        authUrl.searchParams.set('state', state);
        authUrl.searchParams.set('access_type', 'offline');
        authUrl.searchParams.set('prompt', 'consent select_account');
        openExternal(authUrl.toString()).catch((err) => {
          server.close();
          reject(err);
        });
      });

      setTimeout(() => {
        server.close();
        reject(new Error('Sign-in timed out after 5 minutes.'));
      }, 5 * 60 * 1000);
    });

    const tokenResp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: secrets.desktopClientId,
        client_secret: secrets.desktopClientSecret,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code',
      }).toString(),
    });

    if (!tokenResp.ok) {
      const text = await tokenResp.text();
      throw new Error(`OAuth code exchange failed (${tokenResp.status}): ${text}`);
    }

    const tokenData = (await tokenResp.json()) as {
      access_token: string;
      id_token: string;
      refresh_token?: string;
      expires_in?: number;
    };

    const refreshToken =
      tokenData.refresh_token || this.keyring.get(REFRESH_TOKEN_KEY) || '';
    if (refreshToken) {
      this.keyring.set(REFRESH_TOKEN_KEY, refreshToken);
    }

    await this.exchangeForFirebaseSession(
      tokenData.access_token,
      tokenData.id_token,
      refreshToken,
      Number(tokenData.expires_in ?? 3500),
    );

    if (!this.user) {
      throw new Error('Failed to establish user session');
    }
    return this.user;
  }

  async signOut(): Promise<void> {
    this.user = null;
    this.tokens = null;
    this.keyring.set(REFRESH_TOKEN_KEY, null);
    try {
      if (fs.existsSync(this.cachedUserPath)) fs.unlinkSync(this.cachedUserPath);
    } catch {
      // ignore
    }
  }

  async getDriveAccessToken(): Promise<string> {
    if (this.demoMode) return 'demo-drive-token';
    if (this.tokens && Date.now() < this.tokens.googleExpiresAt) {
      return this.tokens.googleAccessToken;
    }
    const refresh =
      this.tokens?.googleRefreshToken || this.keyring.get(REFRESH_TOKEN_KEY);
    if (!refresh) {
      throw new Error('Not signed in (missing refresh token)');
    }
    await this.refreshWithToken(refresh);
    if (!this.tokens) throw new Error('Token refresh failed');
    return this.tokens.googleAccessToken;
  }

  async getFirebaseIdToken(): Promise<string> {
    if (this.demoMode) return 'demo-firebase-token';
    if (this.tokens && Date.now() < this.tokens.firebaseExpiresAt) {
      return this.tokens.firebaseIdToken;
    }
    const refresh =
      this.tokens?.googleRefreshToken || this.keyring.get(REFRESH_TOKEN_KEY);
    if (!refresh) {
      throw new Error('Not signed in (missing refresh token)');
    }
    await this.refreshWithToken(refresh);
    if (!this.tokens) throw new Error('Token refresh failed');
    return this.tokens.firebaseIdToken;
  }
}
