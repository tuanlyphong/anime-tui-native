#!/usr/bin/env bash
# Build the Linux release bundle and package it as a relocatable tarball.
#
# The bundle contains the Flutter runtime, the Node.js engine, its npm
# dependencies, and abyss-dl.jar, so running the extracted app requires no
# engine-path configuration. Node.js, Java 21+ (Abyss), mpv, and a Chromium
# browser still need to be installed on the machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64) FLUTTER_ARCH="x64" ;;
  aarch64 | arm64) FLUTTER_ARCH="arm64" ;;
  *) FLUTTER_ARCH="$HOST_ARCH" ;;
esac
DIST="$ROOT/dist"
BUNDLE="$ROOT/build/linux/$FLUTTER_ARCH/release/bundle"
NAME="anime-tui-native-$VERSION-linux-$HOST_ARCH"

if [[ ! -d "$ROOT/node_modules" ]]; then
  echo "Installing engine dependencies..."
  (cd "$ROOT" && npm install --omit=dev)
fi

echo "Building Linux release..."
flutter build linux --release

for required in \
  "$BUNDLE/anime_tui_native" \
  "$BUNDLE/engine/anime.js" \
  "$BUNDLE/engine/abyss-dl.jar" \
  "$BUNDLE/engine/node_modules" \
  "$BUNDLE/lib/libflutter_linux_gtk.so"; do
  if [[ ! -e "$required" ]]; then
    echo "Release bundle is incomplete: missing $required" >&2
    exit 1
  fi
done

rm -rf "$DIST/$NAME" "$DIST/$NAME.tar.gz"
mkdir -p "$DIST/$NAME"
cp -a "$BUNDLE/." "$DIST/$NAME/"
cp "$ROOT/README.md" "$DIST/$NAME/README.md"

tar -C "$DIST" -czf "$DIST/$NAME.tar.gz" "$NAME"

echo
echo "Packaged: $DIST/$NAME.tar.gz"
echo "Run it with:"
echo "  tar -xzf $DIST/$NAME.tar.gz -C /tmp"
echo "  /tmp/$NAME/anime_tui_native"
