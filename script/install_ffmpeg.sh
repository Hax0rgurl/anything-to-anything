#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"
RELEASE="b6.1.2-rc.1"
BASE_URL="https://github.com/descriptinc/ffmpeg-ffprobe-static/releases/download/$RELEASE"

mkdir -p "$VENDOR_DIR"

download() {
  local name="$1"
  local destination="$VENDOR_DIR/$name"
  local temporary="$destination.download"
  echo "Downloading $name for Apple Silicon…"
  curl -fL --retry 3 --progress-bar -o "$temporary" "$BASE_URL/$name-darwin-arm64"
  mv "$temporary" "$destination"
  chmod +x "$destination"
}

[[ -x "$VENDOR_DIR/ffmpeg" ]] || download ffmpeg
[[ -x "$VENDOR_DIR/ffprobe" ]] || download ffprobe

echo "FFmpeg tools are ready in $VENDOR_DIR"
