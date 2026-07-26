#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY_BINARY="$(mktemp -d)/anything-to-anything-verify"

xcrun swiftc \
  -swift-version 5 \
  "$ROOT_DIR/Sources/CodexMediaConverter/Models/MediaKind.swift" \
  "$ROOT_DIR/Sources/CodexMediaConverter/Models/OutputFormat.swift" \
  "$ROOT_DIR/Sources/CodexMediaConverter/Services/FFmpegCommandBuilder.swift" \
  "$ROOT_DIR/Sources/CodexMediaConverter/Services/DocumentConversionService.swift" \
  "$ROOT_DIR/script/verify.swift" \
  -o "$VERIFY_BINARY"

"$VERIFY_BINARY" "$ROOT_DIR/vendor/ffmpeg" "$ROOT_DIR/vendor/ffprobe"
