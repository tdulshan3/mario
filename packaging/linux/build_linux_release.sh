#!/usr/bin/env bash
# Build Mario's Linux downloads for distros other than Arch, each with its own Electron:
#
#   out/Mario-<ver>-x86_64.AppImage      any distro: chmod +x and run
#   out/mario_<ver>-<rel>_amd64.deb      Debian, Ubuntu, Mint, Pop!_OS…
#   out/mario-<ver>-linux-x64.tar.gz     portable: unpack anywhere and run ./mario
#
# It packs the app bundle packaging/arch/build_release.sh made, so every download
# carries the same build (and the same OAuth credentials). Run that first.
#
# Electron and appimagetool are downloaded once into ~/.cache/mario-release and
# checked against their published SHA-256 sums.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARCH_DIR="$REPO_ROOT/packaging/arch"
OUT="$SCRIPT_DIR/out"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/mario-release"

PKGVER="$(awk -F= '/^pkgver=/ { print $2 }' "$ARCH_DIR/PKGBUILD")"
PKGREL="$(awk -F= '/^pkgrel=/ { print $2 }' "$ARCH_DIR/PKGBUILD")"
# The Electron the Arch package runs on (its electron44 dependency).
ELECTRON_VERSION="${ELECTRON_VERSION:-44.9.1}"
APPIMAGETOOL_VERSION="1.9.1"
APPIMAGETOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"

color() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
log()   { color '1;34' "==> $*"; }
die()   { color '1;31' "xx  $*"; exit 1; }

BUNDLE_TGZ="$ARCH_DIR/mario-${PKGVER}-x86_64.tar.gz"
[ -f "$BUNDLE_TGZ" ] || die "No $BUNDLE_TGZ. Run packaging/arch/build_release.sh first."

mkdir -p "$CACHE" "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── Downloads ──────────────────────────────────────────────────────────────
fetch() { # url dest
  [ -s "$2" ] || { log "Downloading $(basename "$2")"; curl -fL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"; }
}
EZIP="$CACHE/electron-v${ELECTRON_VERSION}-linux-x64.zip"
ESUMS="$CACHE/electron-v${ELECTRON_VERSION}-SHASUMS256.txt"
fetch "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip" "$EZIP"
fetch "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/SHASUMS256.txt" "$ESUMS"
want="$(awk -v f="*electron-v${ELECTRON_VERSION}-linux-x64.zip" '$2 == f || $2 == substr(f, 2) { print $1 }' "$ESUMS")"
[ -n "$want" ] && [ "$(sha256sum "$EZIP" | cut -d' ' -f1)" = "$want" ] || die "Electron zip checksum mismatch"

TOOL="$CACHE/appimagetool-${APPIMAGETOOL_VERSION}-x86_64.AppImage"
fetch "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage" "$TOOL"
[ "$(sha256sum "$TOOL" | cut -d' ' -f1)" = "$APPIMAGETOOL_SHA256" ] || die "appimagetool checksum mismatch"
chmod +x "$TOOL"

# ── The app: Electron with Mario as its resources/app ─────────────────────
# mario.bin is Electron; ./mario is a launcher that turns the OS sandbox off
# only where the kernel won't let an unprivileged app use it.
APP="$WORK/app"
mkdir -p "$APP"
log "Assembling Electron ${ELECTRON_VERSION} + Mario ${PKGVER}"
bsdtar -xf "$EZIP" -C "$APP"
mv "$APP/electron" "$APP/mario.bin"
rm -f "$APP/resources/default_app.asar"
mkdir -p "$APP/resources/app"
tar -xzf "$BUNDLE_TGZ" -C "$WORK"
cp -a "$WORK/bundle/." "$APP/resources/app/"

cat > "$APP/mario" <<'SH'
#!/bin/sh
# Mario launcher. Electron sandboxes its renderers with a setuid chrome-sandbox
# (the .deb) or, failing that, unprivileged user namespaces. Where neither is
# available (an AppImage or a tarball on Ubuntu 24.04+, or Debian with
# unprivileged_userns_clone=0) Electron would refuse to start, so run without it.
HERE="$(dirname "$(readlink -f "$0")")"
NO_SANDBOX=
if [ ! -u "$HERE/chrome-sandbox" ]; then
  if [ "$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null)" = 0 ] ||
     [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = 1 ]; then
    NO_SANDBOX=--no-sandbox
  fi
fi
exec "$HERE/mario.bin" $NO_SANDBOX "$@"
SH
chmod 0755 "$APP/mario" "$APP/mario.bin"

ICON="$WORK/mario.png"
if command -v magick >/dev/null 2>&1; then
  magick "$APP/resources/app/public/assets/logo/mario_mark.png" -resize 256x256 "$ICON"
else
  cp "$APP/resources/app/public/assets/logo/mario_mark.png" "$ICON"
fi

desktop_entry() { # exec
  cat <<EOF
[Desktop Entry]
Type=Application
Name=Mario
GenericName=Notes
Comment=Your notes, your world
Exec=$1 %U
Icon=mario
Terminal=false
Categories=Office;Utility;TextEditor;
StartupWMClass=mario
StartupNotify=true
Keywords=notes;notebook;markdown;editor;
EOF
}

# ── Portable tarball ──────────────────────────────────────────────────────
PORT="mario-${PKGVER}-linux-x64"
log "Packing $PORT.tar.gz"
mkdir -p "$WORK/$PORT"
cp -a "$APP/." "$WORK/$PORT/"
cp "$ICON" "$WORK/$PORT/mario.png"
desktop_entry mario > "$WORK/$PORT/mario.desktop"
cat > "$WORK/$PORT/README.txt" <<EOF
Mario ${PKGVER} for Linux (x86-64), with Electron ${ELECTRON_VERSION} included.

Run it:   ./mario
Needs:    GTK 3, NSS, and libsecret's secret-tool to keep you signed in
          (Debian/Ubuntu: libsecret-tools; Fedora: libsecret).

To add it to your applications menu, edit Exec= in mario.desktop to this
folder's path to ./mario, then copy mario.desktop to ~/.local/share/applications/
and mario.png to ~/.local/share/icons/hicolor/256x256/apps/.
EOF
tar -C "$WORK" --owner=0 --group=0 --numeric-owner -czf "$OUT/$PORT.tar.gz" "$PORT"

# ── AppImage ──────────────────────────────────────────────────────────────
APPIMAGE="Mario-${PKGVER}-x86_64.AppImage"
log "Building $APPIMAGE"
AD="$WORK/Mario.AppDir"
mkdir -p "$AD/usr/lib/mario"
cp -a "$APP/." "$AD/usr/lib/mario/"
cp "$ICON" "$AD/mario.png"
ln -s mario.png "$AD/.DirIcon"
desktop_entry mario > "$AD/mario.desktop"
cat > "$AD/AppRun" <<'SH'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/mario/mario" "$@"
SH
chmod 0755 "$AD/AppRun"
rm -f "$OUT/$APPIMAGE"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$AD" "$OUT/$APPIMAGE" >/dev/null

# ── .deb ──────────────────────────────────────────────────────────────────
DEB="mario_${PKGVER}-${PKGREL}_amd64.deb"
log "Building $DEB"
D="$WORK/deb"
mkdir -p "$D/data/opt/mario" "$D/data/usr/bin" "$D/data/usr/share/applications" \
         "$D/data/usr/share/icons/hicolor/256x256/apps" "$D/control"
cp -a "$APP/." "$D/data/opt/mario/"
chmod 4755 "$D/data/opt/mario/chrome-sandbox"
ln -s /opt/mario/mario "$D/data/usr/bin/mario"
desktop_entry /opt/mario/mario > "$D/data/usr/share/applications/mario.desktop"
cp "$ICON" "$D/data/usr/share/icons/hicolor/256x256/apps/mario.png"
INSTALLED_KB="$(du -sk "$D/data" | cut -f1)"
cat > "$D/control/control" <<EOF
Package: mario
Version: ${PKGVER}-${PKGREL}
Section: editors
Priority: optional
Architecture: amd64
Maintainer: Thushara Dulshan <135942637+tdulshan3@users.noreply.github.com>
Installed-Size: ${INSTALLED_KB}
Depends: libgtk-3-0 | libgtk-3-0t64, libnss3, libgbm1, libasound2 | libasound2t64, libxss1, libxtst6, libsecret-1-0, xdg-utils
Recommends: libsecret-tools
Homepage: https://github.com/tdulshan3/mario
Description: Notes with an AI assistant and Google Drive sync
 Mario is a notebook app in the style of macOS: notebooks, sections and
 pages with Markdown, math, tables and code, an AI panel that asks, quizzes,
 checks writing and edits the page, and local-first sync to Google Drive.
EOF
cat > "$D/control/postinst" <<'EOF'
#!/bin/sh
set -e
# Electron's renderer sandbox needs its helper setuid root.
chown root:root /opt/mario/chrome-sandbox
chmod 4755 /opt/mario/chrome-sandbox
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
exit 0
EOF
cat > "$D/control/postrm" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
exit 0
EOF
chmod 0755 "$D/control/postinst" "$D/control/postrm"
(cd "$D/data" && find . -type f -printf '%P\0' | sort -z | xargs -0 md5sum) > "$D/control/md5sums"
TARFLAGS=(--owner=0 --group=0 --numeric-owner --sort=name)
tar -C "$D/control" "${TARFLAGS[@]}" -cJf "$D/control.tar.xz" .
tar -C "$D/data" "${TARFLAGS[@]}" -cJf "$D/data.tar.xz" .
printf '2.0\n' > "$D/debian-binary"
# An ar archive laid out as dpkg-deb writes one (names without GNU's trailing slash).
python3 - "$OUT/$DEB" "$D/debian-binary" "$D/control.tar.xz" "$D/data.tar.xz" <<'PY'
import os, sys, time
out, *members = sys.argv[1:]
with open(out, 'wb') as f:
    f.write(b'!<arch>\n')
    for path in members:
        data = open(path, 'rb').read()
        name = os.path.basename(path).encode()
        header = b''.join([
            name.ljust(16), str(int(time.time())).encode().ljust(12), b'0'.ljust(6), b'0'.ljust(6),
            b'100644'.ljust(8), str(len(data)).encode().ljust(10), b'`\n',
        ])
        assert len(header) == 60
        f.write(header + data + (b'\n' if len(data) % 2 else b''))
PY

# ── Checksums ─────────────────────────────────────────────────────────────
cd "$OUT"
for f in "$APPIMAGE" "$DEB" "$PORT.tar.gz"; do sha256sum "$f" > "$f.sha256"; done
log "Done."
ls -lh "$OUT"
