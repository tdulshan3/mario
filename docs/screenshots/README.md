# Regenerating the screenshots

The images in this folder are shot from a **demo build** — the real release
binary, run against fixture data — so that a public repository never carries
anyone's actual notes. The fixtures live in
[`lib/core/demo/demo_data.dart`](../../lib/core/demo/demo_data.dart); edit them
there, not here.

Two sets, five views each: `light/` and `dark/`.

## 1. Build with the demo flag

```bash
flutter build linux --release --dart-define=MARIO_DEMO=true
```

`MARIO_DEMO` swaps five providers — auth, notebooks, sections, pages and page
content — for the fixtures. Nothing else changes, so what you photograph is the
shipping UI. Sign-in is skipped, so this build needs no OAuth credentials and
never touches Drive or Firestore.

> Don't install a demo build. It cannot open a real account.

## 2. Run it on a virtual display

The app must run somewhere it can be driven programmatically. On GNOME/Wayland
that is **not** the real desktop: the compositor silently drops synthetic input
into XWayland windows, so `xdotool` can move a pointer but every click and
keystroke is discarded. Use Xvfb, where input works normally.

```bash
Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp &
XDG_DATA_HOME=/tmp/mario-demo-home \
  DISPLAY=:99 GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
  build/linux/x64/release/bundle/mario &
```

Point `XDG_DATA_HOME` at a scratch directory. That is what keeps the demo run
out of your own `shared_preferences.json` — otherwise it picks up your theme,
your font scale and your configured AI backends, and the model name in the
AI-panel shot becomes whatever you happen to be running. Seed that file to
choose the theme (`flutter.mario.theme`: `light` or `black`) and to give the
AI panel a neutral backend to name.

## 3. Drive and capture

Two traps, both of which cost an afternoon the first time:

- **The window is not at the screen origin.** With no window manager it lands
  at an offset like `160,100`. `xdotool mousemove` takes absolute coordinates,
  so add the window's own offset — from `xdotool getwindowgeometry --shell` —
  or every click misses and nothing happens.
- **Park the pointer off-window before each capture**, or whatever row it
  happens to rest on is frozen in a hover state.

```bash
W=$(xdotool search --name '^Mario$' | head -1)
import -window "$W" light/01-home.png     # 1280x800
```

## 4. Frame them

The committed files are 1328×848: the 1280×800 capture with a 14px corner
radius and a 24px pure-black pad. That reproduces the rounded window a real
compositor draws, which Xvfb has none of.

```bash
magick -size 1280x800 xc:black -fill white \
  -draw "roundrectangle 0,0,1279,799,14,14" mask.png
magick shot.png mask.png -alpha off -compose CopyOpacity -composite r.png
magick r.png -background black -gravity center -extent 1328x848 -flatten out.png
```

## The five views

| File | How to get there |
|---|---|
| `01-home.png` | Where the app opens — the Recent list |
| `02-editor.png` | Click the top recent page (Photosynthesis) |
| `03-ai-panel.png` | **Ask**, top right |
| `04-settings.png` | The gear, top right (or `Ctrl+,`) |
| `05-search.png` | `Ctrl+Shift+F`, then type a query with several hits |
