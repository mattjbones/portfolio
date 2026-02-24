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

# Always download fresh in CI, use cache locally
echo "Downloading werf-${PLATFORM}..."
curl -fSL "https://github.com/mattjbones/werf/releases/latest/download/werf-${PLATFORM}" -o "$WERF"
chmod +x "$WERF"

# Generate thumbnails (if ImageMagick is available)
if command -v magick &> /dev/null || command -v convert &> /dev/null; then
  bash "$ROOT/scripts/generate-thumbs.sh"
else
  echo "ImageMagick not found, skipping thumbnail generation"
fi

# Build site
cd "$ROOT/site"
exec "$WERF"
