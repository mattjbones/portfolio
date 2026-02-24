#!/usr/bin/env bash
set -euo pipefail

ORIGINALS="site/public/photos/originals"
THUMBS="site/public/photos/thumbs"

mkdir -p "$THUMBS"

shopt -s nullglob
for img in "$ORIGINALS"/*.{jpg,jpeg,png,tiff}; do
  filename="$(basename "$img")"
  thumb="$THUMBS/$filename"

  if [ -f "$thumb" ]; then
    echo "Skip (exists): $filename"
    continue
  fi

  echo "Generating thumb: $filename"
  convert "$img" -resize 600x600^ -gravity center -extent 600x600 -quality 85 "$thumb"
done
