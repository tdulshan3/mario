#!/usr/bin/env bash
# Mario one-shot installer for Linux.
#
# Usage:
#   # from inside a clone:
#   bash scripts/install.sh
#
#   # one-liner (clones into ~/.cache/mario-build, then installs):
#   curl -fsSL https://raw.githubusercontent.com/tdulshan3/mario/master/scripts/install.sh | bash
#
# OAuth desktop client id + secret can come from:
#   1. env vars MARIO_DESKTOP_CLIENT_ID and MARIO_DESKTOP_CLIENT_SECRET (preferred for CI / fresh installs)
#   2. a .env at the repo root (the dev workflow)
# Either way they're baked into the binary via --dart-define so the installed
# /opt/mario tree is self-contained.

set -euo pipefail

REPO_URL="https://github.com/tdulshan3/mario.git"
REPO_BRANCH="master"
INSTALL_DIR="/opt/mario"
LAUNCHER="/usr/local/bin/mario"
DESKTOP_FILE="/usr/share/applications/mario.desktop"
ICON_PATH="/usr/share/icons/hicolor/256x256/apps/mario.png"

color() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
log()   { color '1;34' "==> $*"; }
warn()  { color '1;33' "!!  $*"; }
die()   { color '1;31' "xx  $*"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Locate the source tree (current dir if it's a Mario checkout, else clone)
# ---------------------------------------------------------------------------
detect_repo_root() {
  local d="$PWD"
  while [ "$d" != "/" ]; do
    if [ -f "$d/pubspec.yaml" ] && grep -q "^name: mario$" "$d/pubspec.yaml" 2>/dev/null; then
      printf '%s\n' "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}

if REPO_ROOT="$(detect_repo_root)"; then
  log "Using existing checkout at $REPO_ROOT"
else
  REPO_ROOT="${MARIO_BUILD_DIR:-$HOME/.cache/mario-build}"
  log "Cloning $REPO_URL ($REPO_BRANCH) → $REPO_ROOT"
  if [ -d "$REPO_ROOT/.git" ]; then
    git -C "$REPO_ROOT" fetch --depth 1 origin "$REPO_BRANCH"
    git -C "$REPO_ROOT" reset --hard "origin/$REPO_BRANCH"
  else
    rm -rf "$REPO_ROOT"
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_ROOT"
  fi
fi
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# 2. Sanity-check tools
# ---------------------------------------------------------------------------
need() {
  local cmd="$1" hint="$2"
  command -v "$cmd" >/dev/null 2>&1 || die "Missing '$cmd'. $hint"
}

need flutter "Install Flutter from https://docs.flutter.dev/get-started/install/linux"
need git    "sudo pacman -S git"
need clang  "sudo pacman -S clang"
need cmake  "sudo pacman -S cmake"
need ninja  "sudo pacman -S ninja"
need pkg-config "sudo pacman -S pkgconf"
command -v magick >/dev/null 2>&1 || warn "ImageMagick (magick) not found — installer will skip the placeholder icon."

# Quick GTK3 probe — `flutter build linux` itself will fail with a clear error
# if it's missing, but the upfront check is friendlier.
pkg-config --exists gtk+-3.0 || die "GTK3 dev headers missing. sudo pacman -S gtk3"

# ---------------------------------------------------------------------------
# 3. OAuth credentials — env vars win, .env is the fallback
# ---------------------------------------------------------------------------
if [ -z "${MARIO_DESKTOP_CLIENT_ID:-}" ] || [ -z "${MARIO_DESKTOP_CLIENT_SECRET:-}" ]; then
  if [ -f "$REPO_ROOT/.env" ]; then
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
cid = cid or get('desktopclientid') or get('desktop_client_id') or get('desktop client id')
sec = sec or get('desktopclientsecret') or get('desktop_client_secret') or get('desktop client secret')
if not cid or not sec:
    sys.exit('FAIL: could not extract id/secret from .env')
print(f'export MARIO_DESKTOP_CLIENT_ID={shlex.quote(cid)}')
print(f'export MARIO_DESKTOP_CLIENT_SECRET={shlex.quote(sec)}')
PY
)"
  else
    die "OAuth credentials not provided.
Either export MARIO_DESKTOP_CLIENT_ID / MARIO_DESKTOP_CLIENT_SECRET, or
drop a .env in the repo root (see lib/platform/linux/secrets_loader.dart for format)."
  fi
fi

# ---------------------------------------------------------------------------
# 4. Build the release bundle with the secrets baked in
# ---------------------------------------------------------------------------
log "flutter pub get"
flutter pub get >/dev/null

log "flutter build linux --release (with --dart-define)"
flutter build linux --release \
  --dart-define=MARIO_DESKTOP_CLIENT_ID="$MARIO_DESKTOP_CLIENT_ID" \
  --dart-define=MARIO_DESKTOP_CLIENT_SECRET="$MARIO_DESKTOP_CLIENT_SECRET"

BUNDLE="$REPO_ROOT/build/linux/x64/release/bundle"
[ -d "$BUNDLE" ] || die "Release bundle missing at $BUNDLE"

# ---------------------------------------------------------------------------
# 5. Stage launcher, desktop entry, icon
# ---------------------------------------------------------------------------
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cat > "$STAGE/mario-launcher" << 'EOF'
#!/bin/sh
exec /opt/mario/mario "$@"
EOF
chmod +x "$STAGE/mario-launcher"

cat > "$STAGE/mario.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Mario
GenericName=Notes
Comment=Your notes, your world
Exec=mario
Icon=mario
Terminal=false
Categories=Office;Utility;TextEditor;
StartupWMClass=mario
StartupNotify=true
Keywords=notes;notebook;markdown;editor;
EOF

if command -v magick >/dev/null 2>&1; then
  log "Generating placeholder icon"
  magick -size 256x256 xc:none \
    -fill '#FFDE7A' -draw 'roundrectangle 0,0 255,255 48,48' \
    -gravity center -fill white \
    -font DejaVu-Sans-Bold -pointsize 200 -annotate -2-12 'M' \
    "$STAGE/mario.png"
fi

# ---------------------------------------------------------------------------
# 6. System install (sudo)
# ---------------------------------------------------------------------------
log "Installing into $INSTALL_DIR (sudo)"
sudo mkdir -p "$INSTALL_DIR"
if command -v rsync >/dev/null 2>&1; then
  sudo rsync -a --delete "$BUNDLE/" "$INSTALL_DIR/"
else
  sudo find "$INSTALL_DIR" -mindepth 1 -delete
  sudo cp -a "$BUNDLE/." "$INSTALL_DIR/"
fi
sudo install -m 0755 "$STAGE/mario-launcher" "$LAUNCHER"
sudo install -m 0644 "$STAGE/mario.desktop"  "$DESKTOP_FILE"
if [ -f "$STAGE/mario.png" ]; then
  sudo install -D -m 0644 "$STAGE/mario.png" "$ICON_PATH"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  sudo update-desktop-database /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  sudo gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
fi

log "Done."
echo
echo "  Launch from your application menu, or run 'mario' in a terminal."
echo "  Uninstall:  sudo rm -rf $INSTALL_DIR $LAUNCHER $DESKTOP_FILE $ICON_PATH"
