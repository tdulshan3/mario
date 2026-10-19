import * as esbuild from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
fs.mkdirSync(path.join(root, 'dist-electron'), { recursive: true });

const define = {
  __BUNDLED_CLIENT_ID__: JSON.stringify(process.env.MARIO_DESKTOP_CLIENT_ID || ''),
  __BUNDLED_CLIENT_SECRET__: JSON.stringify(process.env.MARIO_DESKTOP_CLIENT_SECRET || ''),
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

