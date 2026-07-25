# Mario

**Your notes, your world.**

Mario is a block-based notes app built with Flutter. It pairs a rich, Notion-style
editor with first-class support for math, code, drawing, spreadsheets and voice —
then syncs your work to the cloud and exports it to PDF or Markdown. It runs as a
native Linux desktop app and in the browser.

---

## Features

### Rich block editor
Built on [`appflowy_editor`](https://pub.dev/packages/appflowy_editor) with a set of
custom blocks:

- **Code** — IDE-style block with syntax highlighting (`re_highlight`, the same
  highlight.js port AppFlowy uses), copy/paste/cut support and multi-language themes.
- **Math** — inline and block LaTeX rendering via `flutter_math_fork` (KaTeX), plus
  live expression evaluation (`math_expressions`).
- **Drawing** — freehand ink canvas (`perfect_freehand`) with a drawing toolbar,
  usable both as a standalone block and as an overlay layer on any page.
- **Spreadsheet** — a grid with a formula evaluator and `.xlsx` import (`excel`).
- **Image** — drag-and-drop / paste images, embedded directly into exports.
- **Table** and **Audio** blocks.

### Capture & organize
- **Notebooks → sections → pages** navigation tree with a sidebar rail.
- **Voice dictation** — speech-to-text (`speech_to_text`) plus audio recording and
  playback (`record`, `just_audio`).
- **OCR** — extract text from images.
- **Search** across your notes.
- **AI assist** — bring your own [Anthropic](https://www.anthropic.com/) API key
  (stored in the OS secure storage) for in-app assistance.

### Sync & storage
- **Cloud sync** via Firebase/Firestore on web, and via `firedart` on Linux (where
  the official FlutterFire SDK has no native support).
- **Google Drive** integration for page content.
- **Local persistence** with `drift` (SQLite), `shared_preferences` and
  `flutter_secure_storage`.
- **Google OAuth** sign-in — a desktop OAuth client on Linux, Firebase Auth on web.

### Export
- **PDF** — paginated, with embedded images and bundled Noto fonts for broad Unicode
  coverage (non-Latin scripts and math symbols render correctly).
- **Markdown**.

### Desktop experience
- Native window management and a system tray (`window_manager`, `tray_manager`).
- Embedded HTML preview via Chromium/CEF (`webview_cef`).
- Light, dark, book and system theme modes.

---

## Platforms

| Platform | Status |
|----------|--------|
| Linux (desktop) | Primary target — native build via `firedart` + CEF |
| Web | Supported — Firebase path |
| macOS / Windows | Scaffolded (fall back to FlutterFire) |
| iOS / Android | Project scaffolding present |

---

## Getting started

### Prerequisites
- [Flutter](https://docs.flutter.dev/get-started/install) SDK (Dart `>=3.3.0 <4.0.0`)
- For Linux desktop builds: `clang`, `cmake`, `ninja`, `pkg-config` and the GTK3
  dev headers.

> **Note:** the first Linux build downloads ~150 MB of CEF (Chromium) binaries for
> the embedded HTML preview.

### Configuration
Mario needs a Google OAuth **desktop client id + secret** for Google sign-in / Drive.
Supply them either as environment variables:

```bash
export MARIO_DESKTOP_CLIENT_ID=...
export MARIO_DESKTOP_CLIENT_SECRET=...
```

…or via a `.env` in the repo root (the dev workflow — see
[`lib/platform/linux/secrets_loader.dart`](lib/platform/linux/secrets_loader.dart)
for the expected format). The Anthropic API key for AI features is entered in-app
under **Settings** and kept in secure storage.

### Run in development

```bash
flutter pub get
flutter run -d linux    # or: flutter run -d chrome
```

When running on Linux, pass the OAuth credentials through:

```bash
flutter run -d linux \
  --dart-define=MARIO_DESKTOP_CLIENT_ID="$MARIO_DESKTOP_CLIENT_ID" \
  --dart-define=MARIO_DESKTOP_CLIENT_SECRET="$MARIO_DESKTOP_CLIENT_SECRET"
```

---

## Install on Linux

A one-shot installer builds a release bundle (with the OAuth secrets baked in via
`--dart-define`) and installs it into `/opt/mario`:

```bash
# from a clone:
bash scripts/install.sh

# or one-liner:
curl -fsSL https://raw.githubusercontent.com/tdulshan3/mario/master/scripts/install.sh | bash
```

Then launch **Mario** from your application menu or run `mario` in a terminal.

**Uninstall:**
```bash
sudo rm -rf /opt/mario /usr/local/bin/mario \
  /usr/share/applications/mario.desktop \
  /usr/share/icons/hicolor/256x256/apps/mario.png
```

### Arch Linux
Packaging scripts and a `PKGBUILD` live under [`packaging/arch/`](packaging/arch/).

---

## Project layout

```
lib/
├── main.dart              # entrypoint — platform-aware init (Firebase / firedart)
├── app.dart               # root MaterialApp.router, theming, auth-aware routing
├── core/
│   ├── models/            # Notebook, Section, NotePage, Collaborator
│   └── services/          # auth, drive, firestore, sync, OCR, voice, caching
├── features/
│   ├── editor/            # editor screen + custom blocks (code, math, drawing, …)
│   ├── drawing/           # freehand canvas + strokes
│   ├── math/              # tokenizer / evaluator / shortcuts
│   ├── spreadsheet/       # sheet data, formula evaluator, xlsx parser
│   ├── export/            # PDF + Markdown exporters
│   ├── voice/             # dictation
│   ├── shell/             # nav tree, notebook rail, toolbar, shortcuts
│   ├── auth/ · search/ · settings/ · sharing/
└── platform/
    ├── linux/             # firedart client, secrets loader, window config
    └── web/               # Firebase/Firestore + web auth/OCR
```

**Stack:** Flutter · Riverpod + GetIt + go_router · Firebase / Firestore / firedart ·
Google APIs · AppFlowy Editor · drift.

---

## Building a release

```bash
flutter build linux --release \
  --dart-define=MARIO_DESKTOP_CLIENT_ID="$MARIO_DESKTOP_CLIENT_ID" \
  --dart-define=MARIO_DESKTOP_CLIENT_SECRET="$MARIO_DESKTOP_CLIENT_SECRET"
```

The bundle is written to `build/linux/x64/release/bundle`.
