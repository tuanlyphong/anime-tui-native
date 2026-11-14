#!/usr/bin/env bash
# Build the sideloadable Android release APK.
#
# The APK contains the Flutter UI and the built-in mobile engine. It does not
# bundle Node.js, Java, mpv, or Playwright and requires no engine path setup.
# Release builds use the debug keystore until a Play Store keystore is added.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
DIST="$ROOT/dist"
NAME="anime-tui-native-$VERSION-android"
APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"

echo "Building Android release APK..."
flutter build apk --release

if [[ ! -f "$APK" ]]; then
  echo "Android build did not produce $APK" >&2
  exit 1
fi

mkdir -p "$DIST"
rm -f "$DIST/$NAME.apk" "$DIST/$NAME.apk.sha256"
cp "$APK" "$DIST/$NAME.apk"
(
  cd "$DIST"
  sha256sum "$NAME.apk" > "$NAME.apk.sha256"
)

echo
echo "Packaged: $DIST/$NAME.apk"
echo "SHA-256:  $DIST/$NAME.apk.sha256"
echo
echo "Install on a connected device with:"
echo "  adb install -r $DIST/$NAME.apk"
echo
echo "This build is debug-signed for sideloading. Configure a release"
echo "keystore before publishing to the Play Store."
