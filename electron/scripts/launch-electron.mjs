import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

function findElectronBinary() {
  const candidates = [
    process.env.ELECTRON_PATH,
    '/usr/bin/electron44',
    '/usr/bin/electron42',
    '/usr/bin/electron',
    path.join(process.cwd(), 'node_modules', '.bin', 'electron'),
  ].filter(Boolean);

  for (const bin of candidates) {
    if (bin && fs.existsSync(bin)) {
      return bin;
    }
  }
  return 'electron';
}

const bin = findElectronBinary();
const args = ['.', ...process.argv.slice(2)];
const child = spawn(bin, args, {
  stdio: 'inherit',
  env: { ...process.env },
});

child.on('exit', (code) => {
  process.exit(code ?? 0);
});
