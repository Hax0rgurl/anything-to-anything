#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  "$ROOT_DIR/Sources/CodexMediaConverter/Services/DocumentConversionService.swift" \
  "$ROOT_DIR/script/verify.swift" \
  -o "$VERIFY_BINARY"

"$VERIFY_BINARY" "$FFMPEG_PATH" "$FFPROBE_PATH"
