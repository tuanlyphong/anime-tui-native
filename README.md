# Anime TUI Native

A native Flutter app for Linux, Windows, macOS, and Android. Desktop wraps the
Node.js anime engine as a subprocess; Android uses a built-in Dart/WebView
engine and requires none of the desktop tooling.

> Desktop releases bundle the engine next to the executable, so no
> `ANIME_TUI_ENGINE_PATH` or other path configuration is required. Node.js,
> Java 21+, `mpv`, and a Chromium-based browser still need to be installed on
> the machine.
>
> The Android APK is self-contained: it does **not** need Node.js, Java, `mpv`,
> or Playwright. Search merges the site's suggestions with up to 10 pages of
> full search results over HTTP, and episode scraping plus playback run in an
> in-app WebView.

## Features

| Feature | Details |
|---|---|
| **Search** | Search anime titles; results cached by the engine |
| **Watch history** | Continue-watching & completed tabs; mark complete/incomplete |
| **Playback** | Desktop: streams resolve, then `mpv` opens. Android: full-screen in-app WebView player with a browser fallback |
| **Logs** | Every command, duration, error, and playback event |
| **Settings** | Desktop: engine path, Node executable, player, proxy, timeouts. Android: built-in engine info and storage paths |
| **Keyboard shortcuts** | Desktop only: `Ctrl+F` search, `Ctrl+1…4` tabs, `Ctrl+R` refresh |
| **Mobile UI** | Bottom navigation, Android back handling, compact history cards |

## Quick Start

### Run a packaged release

**Linux**

```bash
tar -xzf anime-tui-native-2.0.0-linux-x86_64.tar.gz
./anime-tui-native-2.0.0-linux-x86_64/anime_tui_native
```

**Windows**

Extract the release zip and start `anime_tui_native.exe`. Keep the `engine/`
directory next to the executable.

**macOS**

Extract the zip and open `anime_tui_native.app`. The app is not sandboxed
because it launches Node.js, `mpv`, and Java as child processes. If macOS
blocks the ad-hoc-signed build, right-click the app and choose **Open**.

**Android**

The release is a universal APK (arm64-v8a, armeabi-v7a, x86_64):

```bash
adb install -r anime-tui-native-2.0.0-android.apk
```

Or copy the APK to the device and open it, allowing installs from the file
manager/browser when prompted. The APK is debug-signed for sideloading; Android
may show a Play Protect warning for builds distributed outside the Play Store.

### Run from source

```bash
# Install engine dependencies once (desktop engine)
npm install --omit=dev

# Install Flutter dependencies (Flutter 3.47+ recommended)
flutter pub get

# Desktop
flutter run -d linux
flutter run -d windows
flutter run -d macos

# Android (device or emulator)
flutter run -d android
```

When running from the repository root, the desktop engine and `abyss-dl.jar`
are discovered automatically. Android selects the built-in mobile engine.

### Prerequisites

| Requirement | Needed for |
|---|---|
| Node.js 18+ on `PATH` | Desktop engine process |
| `mpv` on `PATH` | Desktop playback |
| Java 21+ (auto-discovered) | Desktop Abyss streams |
| Chromium/Chrome, or Playwright's Chromium | Desktop episode and stream scraping |
| Android 7.0+ (API 24) | Android APK |
| Android SDK 36 + NDK 28.2.13676358, JDK 17 | Building the Android APK |

`ANIME_TUI_NODE`, `ANIME_TUI_JAVA`, `JAVA_HOME`, and `PLAYER` can override
desktop auto-detection when needed, but are not required.

On Windows, make sure the executables are available as `node.exe`,
`mpv.exe`, `java.exe`, and `chrome.exe` (or Edge/Chromium) on `PATH` or in the
usual installation directories.

## Build Releases

```bash
# Linux: full bundle + dist/*.tar.gz
tool/package_linux_release.sh

# macOS: app bundle + dist/*.zip (ad-hoc signed by default)
tool/package_macos_release.sh

# Windows (PowerShell): release directory + dist/*.zip
powershell -ExecutionPolicy Bypass -File tool/package_windows_release.ps1

# Android: universal release APK + .sha256
tool/package_android_release.sh
```

The desktop scripts run `flutter build` and copy the Node.js engine, its
`lib/` modules, `node_modules/`, and `abyss-dl.jar` into the release bundle.
The Android script runs `flutter build apk --release` and writes
`dist/anime-tui-native-<version>-android.apk` plus its SHA-256 checksum.

Desktop bundle layout:

```
Linux/Windows:  engine/ beside the executable
macOS:          anime_tui_native.app/Contents/Resources/engine/
```

A raw `flutter build` also installs the engine on Linux and Windows. On macOS,
use the packaging script so the engine is copied into `Contents/Resources` and
the app is signed again after its contents change.

The Android build uses the debug keystore so releases can be sideloaded.
Add a release keystore and signing config before publishing to the Play Store.

### Code signing

`tool/package_macos_release.sh` uses an ad-hoc signature by default. To use a
Developer ID identity:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  tool/package_macos_release.sh
```

Windows releases are unsigned; add an Authenticode signing step for public
distribution if needed.

### CI

- `.github/workflows/build-desktop.yml` builds Linux, Windows, and macOS
  release artifacts. Linux also runs `flutter analyze` and `flutter test`.
- `.github/workflows/build-android.yml` runs analysis/tests and uploads the
  Android APK artifact.

## Engine Protocol

Desktop:

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

Android implements the same `AnimeEngine` interface directly:

- `search` → `POST /ajax/suggest` merged with up to 10 pages of
  `/tim-kiem/<query>/` results over HTTP against the gateway origin.
- `episodes` → headless WebView scraping of the episode list.
- `resolveStream` → headless WebView `/ajax/player` HDX handshake.
- `history` → local JSON at the app-support `mobile-history.json`.
- `play` → the UI opens `MobilePlayerPage` via a playback-session factory.

## Troubleshooting

| Problem | Fix |
|---|---|
| Desktop: "Engine not configured" | Re-extract the full release; it must contain `engine/anime.js`. You can still set a custom path in Settings. |
| Desktop: "Node.js could not be found" | Install Node.js 18+ or set `ANIME_TUI_NODE` |
| Desktop: Abyss playback says Java 21+ is missing | Install a Java 21+ JDK; the app auto-detects Windows, macOS, and Linux locations |
| Desktop: playback fails immediately | Confirm `mpv` is in `PATH` |
| Desktop: episodes/streams fail to launch a browser | Install Chromium/Chrome, or run `npx playwright install chromium` once |
| Windows playback leaves a player running | The app uses `taskkill /T` to stop the engine's child process tree; check Logs for the termination result |
| Search/episode timeouts | Check Logs, adjust network timeout or `ANIME_TUI_PROXY` |
| Android: Cloudflare challenge or "just a moment" | Turn off VPN/proxy, wait for the WebView challenge to clear, or try another network. Cookie clearance is shared between operations. |
| Android: video does not play | Tap the external-browser fallback in the player if the embedded player is blocked; check Logs for WebView network errors. |
| Android: APK will not install | Allow installs from the source app, confirm Android 7.0+, and uninstall an older copy signed with a different key. |
| Android build: missing SDK/NDK | Install platform 36 and NDK 28.2.13676358; Gradle can also auto-install them after accepting SDK licenses. |

## Project Structure

```
lib/
├─ app/          App bootstrap, theme, settings, scope
├─ core/         Errors, logger, paths, utils
├─ engine/       Engine transport, client, commands, models, parsers
│  └─ mobile/    Android engine, gateway, WebView scraper, history
├─ state/        App, browser, history, playback controllers
└─ ui/           Material 3 shell, pages, widgets, mobile player

anime.js         Node.js engine entry point (bundled as engine/anime.js)
lib/*.js         Desktop engine modules (bundled as engine/lib/*.js)
tool/            Release packaging scripts
windows/         Standard Flutter Windows runner
macos/           Standard Flutter macOS runner
android/         Android runner (built-in mobile engine)
```

## Contributing

Issues and pull requests are welcome. Run `flutter analyze` and `flutter test`
before opening a PR, and describe which platform (Linux, Windows, macOS,
Android) you tested.
