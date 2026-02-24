#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/.bin"
mkdir -p "$BIN_DIR"

# Detect platform
case "$(uname -s)" in
  Linux*)  PLATFORM="linux" ;;
  Darwin*) PLATFORM="macos" ;;
  *)       echo "Unsupported platform: $(uname -s)" && exit 1 ;;
esac

WERF="$BIN_DIR/werf"

# Download werf if missing or older than 24h
STALE=false
if [ -f "$WERF" ]; then
  AGE=$(( $(date +%s) - $(stat -f %m "$WERF" 2>/dev/null || stat -c %Y "$WERF" 2>/dev/null) ))
  if [ "$AGE" -gt 86400 ]; then
    STALE=true
  fi
fi

if [ ! -f "$WERF" ] || [ "$STALE" = true ]; then
  echo "Downloading werf-${PLATFORM}..."
  curl -fSL "https://github.com/mattjbones/werf/releases/latest/download/werf-${PLATFORM}" -o "$WERF"
  chmod +x "$WERF"
else
  echo "Using cached werf binary"
fi

# Generate thumbnails if ImageMagick is available
if command -v magick &> /dev/null; then
  bash "$ROOT/scripts/generate-thumbs.sh"
elif command -v convert &> /dev/null; then
  bash "$ROOT/scripts/generate-thumbs.sh"
else
  echo "ImageMagick not found, skipping thumbnail generation"
fi

# Start werf in watch mode
cd "$ROOT/site"
echo "Starting werf watch..."
exec "$WERF" watch
