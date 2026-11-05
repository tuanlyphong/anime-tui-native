# Anime TUI (native)

A native desktop anime browser for Windows, macOS, and Linux. The Flutter app
owns the UI; the existing [`anime-tui-cross`](../anime-tui-cross) Node.js engine
does search, episode discovery, stream resolution, and playback.

> **Desktop only.** The engine is Node.js and launches `mpv` (or another
> player). Android/iOS builds compile, but the app reports that the engine is
> unavailable because a sandboxed mobile process cannot spawn Node.js.

## Architecture

```
lib/
├─ main.dart                 bootstrap, global error handlers, log file
├─ app/                      MaterialApp, theme, settings, AppScope
├─ core/
│  ├─ errors/                EngineException + user-facing mapping
│  ├─ logging/               structured logger (ring buffer + rolling file)
│  └─ utils/                 paths, concurrency limiter
├─ engine/
│  ├─ engine_command.dart    typed argv commands (no shell interpolation)
│  ├─ engine_transport.dart  transport abstraction
│  ├─ cli_engine_transport.dart  one-shot process runner
│  ├─ engine_client.dart     typed API, timeouts, playback session
│  ├─ models.dart            domain models
│  └─ parsers.dart           TSV / status / outcome parsers
├─ state/
│  ├─ app_controller.dart    composition root
│  ├─ browser_controller.dart
│  ├─ playback_controller.dart
│  └─ history_controller.dart
└─ ui/                       shell, pages, reusable widgets
```

The engine is a **one-shot CLI**, not a stdin daemon:

```
node anime.js <command> <args...>   → stdout (TSV/URL/outcome) + stderr, exit code
```

Earlier versions spawned the CLI once and wrote commands to stdin; `anime.js`
exits immediately after reading `process.argv`, so no command ever ran. Every
request now starts one process, with typed arguments, a deadline, captured
stderr, and a structured error.

### Command protocol

| Command | Arguments | Output |
|---|---|---|
| `search` | `<query>` | TSV: `title, url, poster` |
| `episodes-progress` | `<anime-url> [preferred-episode-url]` | TSV: `display, url, original, preferred(0/1)` |
| `episodes` | `<anime-url>` | TSV: `title, url, poster` |
| `streams` | `<episode-url>` | one stream URL |
| `play-episode` | `<stream> <anime> <episode> <label> [--player x] [--jar p] [--quality h] [--progressive 1]` | `finished`, `stopped`, or `failed` |
| `history` | `[completed]` | TSV: `title [episode], url, poster` |
| `history-add` | `<title> <url> <poster> <latest-episode>` | — |
| `history-complete` / `history-uncomplete` | `<url>` | — |

The app passes arguments as a real argv array (`Process.start` with
`runInShell: false`), so titles containing spaces, quotes, or shell
metacharacters are safe. Root-relative URLs from older history files are
accepted.

## Prerequisites

- Flutter SDK `>= 3.3`
- Node.js 18+ on `PATH` (or configure an absolute path)
- `mpv` for playback
- Optional: Chromium/Playwright for episode and stream scraping
- Optional: `java` + `abyss-dl.jar` for the Abyss downloader

## Configure the engine

Open **Settings** in the app (or press `Ctrl+,`) and set the path to
`anime.js`. The app persists settings to:

| Platform | Settings | Logs |
|---|---|---|
| Linux | `~/.config/anime-tui-native/settings.json` | `~/.local/state/anime-tui-native/app.log` |
| macOS | `~/Library/Application Support/anime-tui-native/` | `~/Library/Logs/anime-tui-native/` |
| Windows | `%APPDATA%\anime-tui-native\` | `%LOCALAPPDATA%\anime-tui-native\` |

Environment overrides are still supported:

```bash
export ANIME_TUI_ENGINE_PATH=/home/you/playground/anime-tui-cross/anime.js
export ANIME_TUI_NODE=node
export PLAYER=mpv
export ABYSS_DL_JAR=/path/to/abyss-dl.jar
export ANIME_TUI_PROXY=http://user:pass@host:port
```

`ANIME_TUI_ENGINE_PATH` wins over the saved setting on startup.

## Using the app

- **Search**: type a title and press Enter. Results are cached by the engine.
- **Episodes**: select a result. The preferred (resume) episode is decorated by
  the engine; press **Resume** or play any row.
- **Playback**: streams resolve first, then `mpv` opens. The bottom bar shows
  live engine status, progress, and a **Stop** control.
- **Continue / Completed**: history tabs; entries can be reopened or marked
  complete/incomplete.
- **Logs**: every command, duration, error, and playback event is visible and
  written to the rolling log file.

Keyboard shortcuts:

| Shortcut | Action |
|---|---|
| `Ctrl+F` / `Ctrl+K` | Focus search |
| `Ctrl+R` | Refresh the current page |
| `Ctrl+1…4` | Search / Continue / Completed / Logs |
| `Ctrl+,` | Settings |

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux      # or macos / windows
```

Builds:

```bash
flutter build linux
flutter build macos
flutter build windows
```

## Robustness notes

- All engine commands have deadlines (default 120 s, configurable in Settings).
  Playback has no deadline; it is stopped explicitly.
- At most two non-playback engine processes run at once. Playback is never
  queued behind searches.
- Stale search responses are discarded when a newer search starts.
- Overlapping history refreshes are generation-guarded, and results from a
  replaced engine are discarded.
- Settings are written atomically through a temporary file; a read-only or
  corrupt settings file falls back to defaults instead of blocking startup.
- A killed playback resolves as `stopped`, not as a protocol error.
- `EngineException` carries a category, engine stderr, exit code, and user hint;
  the UI renders it inline with a retry action.
- Global Flutter/platform/zone errors are logged and a last-resort error screen
  replaces the red release crash screen.

## Troubleshooting

- **"Engine not configured"** — set `anime.js` in Settings or
  `ANIME_TUI_ENGINE_PATH`.
- **"Node.js could not be found"** — install Node.js 18+ or set
  `ANIME_TUI_NODE` / the Node executable in Settings.
- **Search/episode timeouts** — the site may be behind Cloudflare or a proxy.
  Check the Logs tab, then adjust the network timeout or `ANIME_TUI_PROXY`.
- **Playback fails immediately** — confirm `mpv` is installed and in `PATH`;
  the Logs tab contains the engine's stderr.
- **No video window** — playback is handled by the external player, not inside
  Flutter. Verify the player executable in Settings.
