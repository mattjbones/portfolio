#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIGINALS="$ROOT/site/public/photos/originals"
THUMBS="$ROOT/site/public/photos/thumbs"

if command -v magick &>/dev/null; then
  CONVERT="magick"
elif command -v convert &>/dev/null; then
  CONVERT="convert"
else
  echo "ImageMagick not found, skipping thumbnail generation"
  exit 0
fi

while IFS= read -r img; do
  # Preserve subdirectory structure under thumbs/
  rel="${img#"$ORIGINALS/"}"
  thumb="$THUMBS/$rel"

  mkdir -p "$(dirname "$thumb")"

  if [ -f "$thumb" ]; then
    echo "  skip (exists): $rel"
    continue
  fi

  echo "  generating: $rel"
  "$CONVERT" "$img" -resize 800x800^ -gravity center -extent 800x800 -quality 85 "$thumb"
done < <(find "$ORIGINALS" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.tiff" \) | sort)
