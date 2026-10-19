#!/usr/bin/env bash
# Build a Mario .pkg.tar.zst for Arch Linux (Electron v2).
#
# Steps:
#   1. npm run build in electron/ (with OAuth credentials baked into dist-electron/main.cjs)
#   2. pack dist/, dist-electron/, public/, package.json → mario-<version>-x86_64.tar.gz
#   3. makepkg to produce mario-<version>-<pkgrel>-x86_64.pkg.tar.zst

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ELECTRON_DIR="$REPO_ROOT/electron"

PKGVER="$(awk -F= '/^pkgver=/ { print $2 }' "$SCRIPT_DIR/PKGBUILD")"
PKGREL="$(awk -F= '/^pkgrel=/ { print $2 }' "$SCRIPT_DIR/PKGBUILD")"

color() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
log()   { color '1;34' "==> $*"; }
die()   { color '1;31' "xx  $*"; exit 1; }

# ── 1. OAuth credentials ─────────────────────────────────────────────────
if [ -z "${MARIO_DESKTOP_CLIENT_ID:-}" ] || [ -z "${MARIO_DESKTOP_CLIENT_SECRET:-}" ]; then
  [ -f "$REPO_ROOT/.env" ] || die "No OAuth creds. Export MARIO_DESKTOP_CLIENT_ID/SECRET or put a .env in $REPO_ROOT."
  log "Reading OAuth credentials from .env"
  eval "$(python3 - "$REPO_ROOT/.env" << 'PY'
import json, re, shlex, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
cid = sec = None
m = re.search(r'\{[\s\S]*"installed"[\s\S]*\}', text)
if m:
    block = m.group(0)
    depth, end = 0, 0
    for i, ch in enumerate(block):
        if ch == '{': depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                end = i + 1; break
    try:
        data = json.loads(block[:end])
        inner = data.get('installed') or data.get('web') or {}
        cid = inner.get('client_id'); sec = inner.get('client_secret')
    except Exception:
        pass
def get(k):
    mm = re.search(rf'(?im)^{re.escape(k)}\s*=\s*(\S+)', text)
    return mm.group(1).strip() if mm else None
cid = cid or get('desktopclientid') or get('desktop_client_id')
sec = sec or get('desktopclientsecret') or get('desktop_client_secret')
if not cid or not sec:
    sys.exit('FAIL: could not extract client id/secret from .env')
print(f'export MARIO_DESKTOP_CLIENT_ID={shlex.quote(cid)}')
print(f'export MARIO_DESKTOP_CLIENT_SECRET={shlex.quote(sec)}')
PY
)"
fi

# ── 2. Build Electron Main & Renderer ────────────────────────────────────
log "Building Electron app in $ELECTRON_DIR (v$PKGVER)"
(
  cd "$ELECTRON_DIR"
  npm run build
)

# ── 3. Stage & Tar the bundle ────────────────────────────────────────────
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
BUNDLE_DIR="$STAGE_DIR/bundle"
mkdir -p "$BUNDLE_DIR"

cp -a "$ELECTRON_DIR/package.json" "$BUNDLE_DIR/"
cp -a "$ELECTRON_DIR/dist" "$BUNDLE_DIR/"
cp -a "$ELECTRON_DIR/dist-electron" "$BUNDLE_DIR/"
cp -a "$ELECTRON_DIR/public" "$BUNDLE_DIR/"

TARBALL="$SCRIPT_DIR/mario-${PKGVER}-x86_64.tar.gz"
log "Packing $TARBALL"
tar -C "$STAGE_DIR" -czf "$TARBALL" bundle

# ── 4. Icon ──────────────────────────────────────────────────────────────
if [ -f "$REPO_ROOT/assets/logo/mario_mark.png" ]; then
  cp -f "$REPO_ROOT/assets/logo/mario_mark.png" "$SCRIPT_DIR/mario.png"
fi

# ── 5. makepkg ───────────────────────────────────────────────────────────
log "Running makepkg in $SCRIPT_DIR"
cd "$SCRIPT_DIR"
makepkg -Cf --noconfirm

PKG="mario-${PKGVER}-${PKGREL}-x86_64.pkg.tar.zst"
if [ -f "$PKG" ]; then
  log "Done."
  echo
  echo "  Package: $SCRIPT_DIR/$PKG"
  echo "  Install: pkexec pacman -U --noconfirm $SCRIPT_DIR/$PKG"
else
  die "makepkg finished but $PKG was not produced. Check the output above."
fi
