import * as esbuild from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
fs.mkdirSync(path.join(root, 'dist-electron'), { recursive: true });

function loadEnvOAuthCredentials() {
  let id =
    process.env.MARIO_DESKTOP_CLIENT_ID ||
    process.env.GOOGLE_CLIENT_ID ||
    process.env.DESKTOPCLIENTID ||
    '';
  let secret =
    process.env.MARIO_DESKTOP_CLIENT_SECRET ||
    process.env.GOOGLE_CLIENT_SECRET ||
    process.env.DESKTOPCLIENTSECRET ||
    '';
  if (id && secret) return { id, secret };

  const candidates = [
    path.resolve(root, '.env'),
    path.resolve(root, '..', '.env'),
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
  return { id, secret };
}

const creds = loadEnvOAuthCredentials();
const define = {
  __BUNDLED_CLIENT_ID__: JSON.stringify(creds.id),
  __BUNDLED_CLIENT_SECRET__: JSON.stringify(creds.secret),
};

await esbuild.build({
  entryPoints: ['electron/main.ts'],
  bundle: true,
  platform: 'node',
  target: 'node20',
  format: 'cjs',
  external: ['electron'],
  outfile: 'dist-electron/main.cjs',
  sourcemap: true,
  define,
});

await esbuild.build({
  entryPoints: ['electron/preload.ts'],
  bundle: true,
  platform: 'node',
  target: 'node20',
  format: 'cjs',
  external: ['electron'],
  outfile: 'dist-electron/preload.cjs',
  sourcemap: true,
});

console.log('Built dist-electron/main.cjs and dist-electron/preload.cjs');
