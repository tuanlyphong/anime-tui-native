# Anime TUI Native

A **native, cross-platform** Flutter app (Windows/macOS/Linux/Android/iOS) that wraps a Node.js anime engine as a subprocess and communicates over stdio. Rich Material Design 3 UI with search, watch history, playback control, logs, and settings.

> Engine stays untouched as a subprocess — you only ship the UI.

## Features

| Feature | Details |
|---|---|
| **Search** | Search anime titles; results cached by the engine |
| **Watch history** | Continue-watching & completed tabs; mark complete/incomplete |
| **Playback** | Streams resolve first, then `mpv` opens; live status bar |
| **Logs** | Every command, duration, error, and playback event |
| **Settings** | Engine path, Node executable, player, proxy, timeouts |
| **Keyboard shortcuts** | `Ctrl+F` search, `Ctrl+1…4` tabs, `Ctrl+R` refresh |

## Quick Start

```bash
# 1. Install dependencies (Flutter >= 3.3)
flutter pub get

# 2. Set your engine path (Node.js engine, e.g. anime.js)
export ANIME_TUI_ENGINE_PATH=/path/to/anime.js

# 3. Run
flutter run -d linux
```

## Build for Desktop

```bash
# Linux
flutter build linux --release

# macOS
flutter build macos --release

# Windows
flutter build windows --release
```

## Build for Mobile

```bash
# Android
flutter build apk --release
flutter build appbundle --release

# iOS
flutter build ipa --release
```

## Engine Protocol

```
node anime.js <command> <args...>   → stdout (TSV/URL/outcome) + stderr, exit
```

| Command | Args | Output |
|---|---|---|
| `search` | `<query>` | `title, url, poster` |
| `episodes` | `<anime-url>` | `title, url, poster` |
| `streams` | `<episode-url>` | stream URL |
| `play-episode` | `<stream> <anime> <episode> <label>` | `finished`, `stopped`, or `failed` |
| `history` | `[completed]` | `title [episode], url, poster` |

## Troubleshooting

| Problem | Fix |
|---|---|
| "Engine not configured" | Set `anime.js` in Settings or `ANIME_TUI_ENGINE_PATH` |
| "Node.js could not be found" | Install Node.js 18+ or set `ANIME_TUI_NODE` |
| Playback fails immediately | Confirm `mpv` is in `PATH` |
| Search/episode timeouts | Check Logs, adjust network timeout or `ANIME_TUI_PROXY` |

## Project Structure

```
lib/
├─ app/          App bootstrap, theme, settings, scope
├─ core/         Errors, logger, utils
├─ engine/       Engine transport, client, commands, models, parsers
├─ state/        App, browser, history, playback controllers
└─ ui/           Material 3 shell, pages, widgets
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.
