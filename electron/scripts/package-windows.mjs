import { execFileSync, spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const repoRoot = path.resolve(root, '..');
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const version = pkg.version;
const electronVersion = process.env.ELECTRON_VERSION || '44.9.2';

const iconScript = path.join(repoRoot, 'scripts', 'build-windows-icon.ps1');
const icoPath = path.join(root, 'public', 'assets', 'logo', 'mario.ico');
const artifactsDir = path.join(root, 'artifacts');
const installerDir = path.join(artifactsDir, 'installer');
const bundleDir = path.join(artifactsDir, 'Mario-win32-x64');

function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  const data = fs.readFileSync(filePath);
  hash.update(data);
  return hash.digest('hex').toLowerCase();
}

function writeSha256Sidecar(filePath) {
  const digest = sha256File(filePath);
  const line = `${digest}  ${path.basename(filePath)}\n`;
  fs.writeFileSync(`${filePath}.sha256`, line, 'ascii');
  return digest;
}

function findCachedPackagerModule() {
  const localAppData = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
  const npxRoot = path.join(localAppData, 'npm-cache', '_npx');
  if (!fs.existsSync(npxRoot)) return null;
  for (const entry of fs.readdirSync(npxRoot)) {
    const candidate = path.join(npxRoot, entry, 'node_modules', '@electron', 'packager', 'dist', 'index.js');
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

function findIscc() {
  const localAppData = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
  const candidates = [
    process.env.ISCC_PATH,
    path.join(localAppData, 'Programs', 'Inno Setup 6', 'ISCC.exe'),
    'C:\\Program Files (x86)\\Inno Setup 6\\ISCC.exe',
    'C:\\Program Files\\Inno Setup 6\\ISCC.exe',
  ].filter(Boolean);
  for (const c of candidates) {
    if (c && fs.existsSync(c)) return c;
  }
  return 'iscc';
}

console.log(`==> Generating Windows .ico from mario_mark.png`);
execFileSync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', iconScript], {
  stdio: 'inherit',
});
if (!fs.existsSync(icoPath)) {
  throw new Error(`Expected icon file at ${icoPath}`);
}

console.log(`==> Building Mario Electron main & renderer (v${version})`);
const npmCmd = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const buildRes = spawnSync(npmCmd, ['run', 'build'], {
  cwd: root,
  stdio: 'inherit',
  shell: true,
});
if (buildRes.status !== 0) {
  throw new Error('npm run build failed');
}

fs.mkdirSync(artifactsDir, { recursive: true });
fs.mkdirSync(installerDir, { recursive: true });

console.log(`==> Packaging Mario-win32-x64 with embedded Mario icon`);
const cachedPackager = findCachedPackagerModule();
if (cachedPackager) {
  const { packager } = await import(pathToFileURL(cachedPackager).href);
  await packager({
    dir: root,
    name: 'Mario',
    platform: 'win32',
    arch: 'x64',
    electronVersion,
    out: artifactsDir,
    overwrite: true,
    asar: true,
    icon: icoPath,
    appVersion: version,
    buildVersion: version,
    appCopyright: 'Copyright (C) 2026 Mario',
    win32metadata: {
      CompanyName: 'Mario',
      FileDescription: 'Mario',
      ProductName: 'Mario',
      InternalName: 'Mario',
      OriginalFilename: 'Mario.exe',
    },
    ignore: [
      /^\/artifacts($|\/)/,
      /^\/packaging($|\/)/,
      /^\/src($|\/)/,
      /^\/electron($|\/)/,
      /^\/scripts($|\/)/,
    ],
  });
} else {
  const npxRes = spawnSync(
    'npx',
    [
      '--yes',
      '@electron/packager',
      '.',
      'Mario',
      '--platform=win32',
      '--arch=x64',
      `--electron-version=${electronVersion}`,
      `--out=${artifactsDir}`,
      '--overwrite',
      '--asar',
      `--icon=${icoPath}`,
      `--app-version=${version}`,
      `--build-version=${version}`,
      '--ignore=^/artifacts($|/)',
      '--ignore=^/packaging($|/)',
      '--ignore=^/src($|/)',
      '--ignore=^/electron($|/)',
      '--ignore=^/scripts($|/)',
    ],
    { cwd: root, stdio: 'inherit', shell: true },
  );
  if (npxRes.status !== 0) {
    throw new Error('@electron/packager failed');
  }
}

// Also copy mario.ico directly into the bundle root and resources folder so shortcuts,
// uninstaller, and runtime window icon resolution always have direct file access.
fs.copyFileSync(icoPath, path.join(bundleDir, 'mario.ico'));
fs.copyFileSync(icoPath, path.join(bundleDir, 'resources', 'mario.ico'));

const zipPath = path.join(artifactsDir, `Mario-${version}-windows-x64.zip`);
if (fs.existsSync(zipPath)) fs.unlinkSync(zipPath);
console.log(`==> Creating portable archive ${zipPath}`);
execFileSync('tar.exe', ['-a', '-c', '-f', zipPath, '-C', artifactsDir, 'Mario-win32-x64'], {
  stdio: 'inherit',
});
const zipSha = writeSha256Sidecar(zipPath);
console.log(`    SHA-256: ${zipSha}`);

const iscc = findIscc();
const issPath = path.join(root, 'packaging', 'mario.iss');
console.log(`==> Compiling Windows installer with Inno Setup (${iscc})`);
execFileSync(iscc, [`/DAppVersion=${version}`, issPath], {
  cwd: path.dirname(issPath),
  stdio: 'inherit',
});

const installerPath = path.join(installerDir, `Mario-${version}-windows-x64-setup.exe`);
if (!fs.existsSync(installerPath)) {
  throw new Error(`Expected installer at ${installerPath}`);
}
const installerSha = writeSha256Sidecar(installerPath);
console.log(`    Installer: ${installerPath}`);
console.log(`    SHA-256:   ${installerSha}`);

