#!/usr/bin/env bash
set -euo pipefail

# Detect platform and download the correct werf binary
case "$(uname -s)" in
  Linux*)  PLATFORM="linux" ;;
  Darwin*) PLATFORM="macos" ;;
  *)       echo "Unsupported platform: $(uname -s)" && exit 1 ;;
esac

echo "Downloading werf-${PLATFORM}..."
curl -L "https://github.com/mattjbones/werf/releases/latest/download/werf-${PLATFORM}" -o werf
chmod +x werf

# Generate thumbnails (if ImageMagick is available)
if command -v convert &> /dev/null; then
  bash scripts/generate-thumbs.sh
else
  echo "ImageMagick not found, skipping thumbnail generation"
fi

# Build site
cd site && ../werf
