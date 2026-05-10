#!/usr/bin/env bash
# Build a Mario .pkg.tar.zst for Arch Linux.
#
# Steps:
#   1. flutter build linux --release (with OAuth dart-defines, like install.sh)
#   2. pack build/linux/x64/release/bundle/ → mario-<version>-x86_64.tar.gz
#   3. makepkg to produce mario-<version>-1-x86_64.pkg.tar.zst
#
# Run from anywhere — paths are resolved relative to this script.
#
# OAuth creds: same convention as scripts/install.sh
#   - env vars MARIO_DESKTOP_CLIENT_ID / MARIO_DESKTOP_CLIENT_SECRET, or
#   - a .env at the repo root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# pkgver is sourced from the PKGBUILD so the two stay in sync — bump there.
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

# ── 2. Build ─────────────────────────────────────────────────────────────
BUNDLE="$REPO_ROOT/build/linux/x64/release/bundle"
if [ ! -d "$BUNDLE" ] || [ "${SKIP_BUILD:-0}" != "1" ]; then
  log "flutter pub get"
  ( cd "$REPO_ROOT" && flutter pub get >/dev/null )
  log "flutter build linux --release (v$PKGVER)"
  ( cd "$REPO_ROOT" && flutter build linux --release \
      --dart-define=MARIO_DESKTOP_CLIENT_ID="$MARIO_DESKTOP_CLIENT_ID" \
      --dart-define=MARIO_DESKTOP_CLIENT_SECRET="$MARIO_DESKTOP_CLIENT_SECRET" )
fi
[ -d "$BUNDLE" ] || die "Release bundle missing at $BUNDLE"

# ── 3. Tar the bundle so PKGBUILD has something to point at ──────────────
TARBALL="$SCRIPT_DIR/mario-${PKGVER}-x86_64.tar.gz"
log "Packing $TARBALL"
# Use a stable inner directory name ('bundle/') so PKGBUILD doesn't care
# about the host's flutter output path.
tar -C "$(dirname "$BUNDLE")" -czf "$TARBALL" "$(basename "$BUNDLE")"

# ── 4. Generate a placeholder icon if ImageMagick is available ───────────
if command -v magick >/dev/null 2>&1; then
  log "Generating placeholder icon"
  magick -size 256x256 xc:none \
    -fill '#F2C94C' -draw 'roundrectangle 0,0 255,255 56,56' \
    -gravity center -fill white \
    -font DejaVu-Sans-Bold -pointsize 180 -annotate -2-8 'M' \
    "$SCRIPT_DIR/mario.png"
fi

# ── 5. makepkg ───────────────────────────────────────────────────────────
log "Running makepkg in $SCRIPT_DIR"
cd "$SCRIPT_DIR"
makepkg -f --noconfirm

PKG="mario-${PKGVER}-${PKGREL}-x86_64.pkg.tar.zst"
if [ -f "$PKG" ]; then
  log "Done."
  echo
  echo "  Package: $SCRIPT_DIR/$PKG"
  echo "  Install: sudo pacman -U $SCRIPT_DIR/$PKG"
else
  die "makepkg finished but $PKG was not produced. Check the output above."
fi
