#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Anything to Anything"
PRODUCT_NAME="CodexMediaConverter"
BUNDLE_ID="com.muse.anything-to-anything"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="${ANYTHING_TO_ANYTHING_BUILD_CONFIGURATION:-release}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGING_DIR="$(mktemp -d)"
STAGED_APP="$STAGING_DIR/$APP_NAME.app"
APP_CONTENTS="$STAGED_APP/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
STAGED_BINARY="$APP_MACOS/$APP_NAME"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
trap 'rm -rf "$STAGING_DIR"' EXIT

if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "Codex Media Converter" >/dev/null 2>&1 || true
fi

cd "$ROOT_DIR"
if [[ ! -x "$ROOT_DIR/vendor/ffmpeg" || ! -x "$ROOT_DIR/vendor/ffprobe" ]]; then
  "$ROOT_DIR/script/install_ffmpeg.sh"
fi
swift build -c "$BUILD_CONFIGURATION"
BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$PRODUCT_NAME"

mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$STAGED_BINARY"
chmod +x "$STAGED_BINARY"
cp "$ROOT_DIR/vendor/ffmpeg" "$APP_RESOURCES/ffmpeg"
cp "$ROOT_DIR/vendor/ffprobe" "$APP_RESOURCES/ffprobe"
cp "$ROOT_DIR/Assets/AnythingToAnythingIcon.icns" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_RESOURCES/ffmpeg" "$APP_RESOURCES/ffprobe"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.4</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array><dict><key>CFBundleTypeName</key><string>Convertible File</string><key>CFBundleTypeRole</key><string>Editor</string><key>LSItemContentTypes</key><array><string>public.content</string></array></dict></array>
</dict>
</plist>
PLIST

/usr/bin/xattr -cr "$STAGED_APP"
/usr/bin/codesign --force --deep --sign - "$STAGED_APP" >/dev/null
/usr/bin/xattr -cr "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE"
COPYFILE_DISABLE=1 /usr/bin/ditto \
  --norsrc \
  --noextattr \
  --noqtn \
  --noacl \
  "$STAGED_APP" \
  "$APP_BUNDLE"
/usr/bin/xattr -cr "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }

case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == '$APP_NAME'" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == '$BUNDLE_ID'" ;;
  --verify|verify) open_app; sleep 2; pgrep -x "$APP_NAME" >/dev/null ;;
  --build-only|build-only) ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--build-only]" >&2; exit 2 ;;
esac
