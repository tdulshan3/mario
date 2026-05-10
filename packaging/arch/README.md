# Mario — Arch Linux packaging

Produces an installable `.pkg.tar.zst` for Arch Linux (and any pacman-based
distro: Manjaro, EndeavourOS, CachyOS, …).

## What lands on disk

| Path                                              | Owner    |
| ------------------------------------------------- | -------- |
| `/opt/mario/`                                     | Flutter bundle (binary + libs + assets) |
| `/usr/bin/mario`                                  | Shell wrapper that execs the bundle |
| `/usr/share/applications/mario.desktop`           | Desktop entry |
| `/usr/share/icons/hicolor/256x256/apps/mario.png` | App icon |
| `/usr/share/licenses/mario/LICENSE`               | License placeholder |

`mario.install` refreshes the icon + desktop databases after install/upgrade/remove.

## Build a release locally

```bash
cd packaging/arch
./build_release.sh
```

`build_release.sh` will:

1. Run `flutter pub get` and `flutter build linux --release` with the OAuth
   client id/secret baked in via `--dart-define` (the same mechanism
   `scripts/install.sh` uses).
2. Pack `build/linux/x64/release/bundle/` into `mario-<version>-x86_64.tar.gz`
   next to the PKGBUILD.
3. Generate a placeholder icon `mario.png` if ImageMagick (`magick`) is
   installed.
4. Run `makepkg -f` to produce `mario-<version>-1-x86_64.pkg.tar.zst`.

Already built once? Skip step 1 with:

```bash
SKIP_BUILD=1 ./build_release.sh
```

## OAuth credentials

The Linux build needs `MARIO_DESKTOP_CLIENT_ID` and
`MARIO_DESKTOP_CLIENT_SECRET`. Provide them via environment variables or a
`.env` at the repo root (same format as `scripts/install.sh` consumes).

## Install / uninstall

```bash
sudo pacman -U mario-1.0.0-1-x86_64.pkg.tar.zst
sudo pacman -R mario
```

After install, launch from your application menu (Office / Notes category)
or run `mario` in a terminal.

## Bumping the version

Edit `pkgver` (and `pkgrel` if rebuilding the same source) in `PKGBUILD`, then
`./build_release.sh`. `pubspec.yaml` should usually be bumped to match.

## Publishing to AUR

For an AUR upload, the PKGBUILD should reference a public tarball URL instead
of the local file. Replace the `source=()` block with:

```bash
source=("${pkgname}-${pkgver}.tar.gz::https://github.com/tdulshan3/mario/releases/download/v${pkgver}/mario-${pkgver}-x86_64.tar.gz"
        "mario.desktop"
        "mario.sh"
        "mario.png")
```

and fill in `sha256sums=('<real-hash>' 'SKIP' 'SKIP' 'SKIP')`. Then:

```bash
makepkg --printsrcinfo > .SRCINFO
git init
git remote add aur ssh://aur@aur.archlinux.org/mario.git
git add PKGBUILD .SRCINFO mario.desktop mario.sh mario.install mario.png
git commit -m "v$pkgver"
git push aur master
```

## Troubleshooting

- **`No OAuth creds`** — set the env vars or put a `.env` at the repo root.
  See `lib/platform/linux/secrets_loader.dart` for the format the app expects.
- **`flutter: command not found`** — install Flutter from
  `https://docs.flutter.dev/get-started/install/linux`.
- **`GTK3 dev headers missing`** — `sudo pacman -S gtk3 base-devel cmake ninja
  clang pkgconf`.
- **First `flutter build linux` is slow** — `webview_cef` downloads ~150 MB of
  CEF binaries; subsequent builds reuse the cache.
