const ALPHABET = 'abcdefghijklmnopqrstuvwxyz0123456789';

export function newClientId(prefix: string): string {
  const ts = Date.now().toString(36);
  let rand = '';
  for (let i = 0; i < 10; i++) {
    rand += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
  }
  return `${prefix}_${ts}${rand}`;
}

export function nanoid6(): string {
  let out = '';
  for (let i = 0; i < 6; i++) {
    out += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
  }
  return out;
}

export function safeFilename(id: string): string {
  return id.replace(/[^A-Za-z0-9_-]/g, '_');
}
