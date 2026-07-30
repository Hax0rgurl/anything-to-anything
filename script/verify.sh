#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-full}"
VERIFY_DIR="$(mktemp -d)"
VERIFY_BINARY="$VERIFY_DIR/anything-to-anything-verify"
FFMPEG_PATH="${FFMPEG_PATH:-$ROOT_DIR/vendor/ffmpeg}"
FFPROBE_PATH="${FFPROBE_PATH:-$ROOT_DIR/vendor/ffprobe}"
trap 'rm -rf "$VERIFY_DIR"' EXIT

xcrun swiftc \
  -swift-version 5 \
  "$ROOT_DIR/Sources/CodexMediaConverter/Models/MediaKind.swift" \
  "$ROOT_DIR/Sources/CodexMediaConverter/Models/OutputFormat.swift" \
  "$ROOT_DIR/Sources/CodexMediaConverter/Services/FFmpegCommandBuilder.swift" \
  "$ROOT_DIR/Sources/CodexMediaConverter/Services/FFmpegLocator.swift" \
  "$ROOT_DIR/Sources/CodexMediaConverter/Services/ConversionService.swift" \
  "$ROOT_DIR/Sources/CodexMediaConverter/Services/DocumentConversionService.swift" \
  "$ROOT_DIR/script/verify.swift" \
  -o "$VERIFY_BINARY"

case "$MODE" in
  full)
    PATH="$ROOT_DIR/vendor:$PATH" "$VERIFY_BINARY" "$FFMPEG_PATH" "$FFPROBE_PATH"
    ;;
  --media-only|media-only)
    PATH="$ROOT_DIR/vendor:$PATH" "$VERIFY_BINARY" "$FFMPEG_PATH" "$FFPROBE_PATH" --media-only
    ;;
  *)
    echo "usage: $0 [full|--media-only]" >&2
    exit 2
    ;;
esac
