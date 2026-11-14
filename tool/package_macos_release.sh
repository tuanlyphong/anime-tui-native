#!/usr/bin/env bash
# Build the macOS release bundle and package it as a zip archive.
#
# App Sandbox is intentionally disabled for this distribution: the app launches
# trusted desktop tools (Node.js, mpv, and Java) as child processes. The engine
# is copied into Contents/Resources/engine, then the whole app is signed again
# so the added resources are covered by its signature.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
HOST_ARCH="$(uname -m)"
DIST="$ROOT/dist"
APP="$ROOT/build/macos/Build/Products/Release/anime_tui_native.app"
NAME="anime-tui-native-$VERSION-macos-$HOST_ARCH"
IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ ! -d "$ROOT/node_modules" ]]; then
  echo "Installing engine dependencies..."
  (cd "$ROOT" && npm install --omit=dev)
fi

echo "Building macOS release..."
flutter pub get
flutter build macos --release

if [[ ! -d "$APP" ]]; then
  echo "Release bundle is incomplete: missing $APP" >&2
  exit 1
fi

ENGINE="$APP/Contents/Resources/engine"
rm -rf "$ENGINE"
mkdir -p "$ENGINE/lib"

# Keep the same engine layout as the Linux and Windows releases.
cp "$ROOT/anime.js" "$ROOT/package.json" "$ROOT/abyss-dl.jar" "$ENGINE/"
find "$ROOT/lib" -maxdepth 1 -type f -name '*.js' -exec cp {} "$ENGINE/lib/" \;
cp -R "$ROOT/node_modules" "$ENGINE/node_modules"
cp "$ROOT/README.md" "$APP/Contents/Resources/README.md"

for required in \
  "$ENGINE/anime.js" \
  "$ENGINE/abyss-dl.jar" \
  "$ENGINE/lib/playback.js" \
  "$ENGINE/node_modules"; do
  if [[ ! -e "$required" ]]; then
    echo "Release bundle is incomplete: missing $required" >&2
    exit 1
  fi
done

# Copying resources after Flutter's build invalidates the original signature.
# Re-sign with a Developer ID when provided, otherwise ad-hoc sign so the app
# remains runnable after extraction.
echo "Signing app with identity: $IDENTITY"
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

rm -rf "$DIST/$NAME" "$DIST/$NAME.zip"
mkdir -p "$DIST/$NAME"
ditto "$APP" "$DIST/$NAME/anime_tui_native.app"
ditto -c -k --sequesterRsrc --keepParent \
  "$DIST/$NAME/anime_tui_native.app" "$DIST/$NAME.zip"

echo
echo "Packaged: $DIST/$NAME.zip"
echo "Extract it and open anime_tui_native.app."
