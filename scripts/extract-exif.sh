#!/usr/bin/env bash
set -euo pipefail

# Reads EXIF from a scan and prints a YAML block for frontmatter.
# Usage: bash scripts/extract-exif.sh path/to/image.jpg

if [ $# -eq 0 ]; then
  echo "Usage: $0 <image-path>"
  exit 1
fi

if ! command -v exiftool &> /dev/null; then
  echo "exiftool not found — install with: brew install exiftool"
  exit 1
fi

IMAGE="$1"
echo "---"
echo "# EXIF data from: $(basename "$IMAGE")"
echo "# Scanner/scan metadata (auto-extracted)"
exiftool -s -s -s -DateTimeOriginal -XResolution -YResolution -ImageWidth -ImageHeight "$IMAGE" 2>/dev/null | while IFS= read -r line; do
  echo "# $line"
done
echo ""
echo "# Film metadata (fill in manually)"
echo "film: # TODO"
echo "film_format: # TODO"
echo "camera: # TODO"
echo "lens: # TODO"
echo "location: # TODO"
echo "---"
