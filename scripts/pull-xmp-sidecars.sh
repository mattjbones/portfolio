#!/usr/bin/env bash
# pull-xmp-sidecars.sh
# Copy XMP sidecars from a source export folder into uploads/<date>.
#
# Usage:
#   ./scripts/pull-xmp-sidecars.sh <YYYY-MM-DD> [--source-dir <path>] [--overwrite]
#
# Defaults:
#   source-dir: /Users/mbarnettjones/Documents/Pictures and Scans/Snappy Snaps/00060165 09-02-2026
#
# Notes:
#   - Matches sidecars by exact image filename: <name>.jpg -> <name>.jpg.xmp
#   - Copies sidecars into uploads/<date>/ alongside each image.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_SOURCE_DIR="/Users/mbarnettjones/Documents/Pictures and Scans/Snappy Snaps/00060165 09-02-2026"

DATE=""
SOURCE_DIR="$DEFAULT_SOURCE_DIR"
OVERWRITE=false

usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      [[ $# -ge 2 ]] || { echo "Error: --source-dir requires a value"; exit 1; }
      SOURCE_DIR="$2"
      shift 2
      ;;
    --overwrite)
      OVERWRITE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Unknown option: $1"
      usage
      ;;
    *)
      if [[ -z "$DATE" ]]; then
        DATE="$1"
        shift
      else
        echo "Unexpected argument: $1"
        usage
      fi
      ;;
  esac
done

if [[ -z "$DATE" ]]; then
  echo "Error: <YYYY-MM-DD> is required."
  usage
fi

if ! [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: date must be YYYY-MM-DD, got: $DATE"
  exit 1
fi

UPLOADS_DIR="$REPO_ROOT/uploads/$DATE"

if [[ ! -d "$UPLOADS_DIR" ]]; then
  echo "Error: uploads directory not found: $UPLOADS_DIR"
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Error: source directory not found: $SOURCE_DIR"
  exit 1
fi

shopt -s nullglob
IMAGES=("$UPLOADS_DIR"/*.jpg "$UPLOADS_DIR"/*.JPG "$UPLOADS_DIR"/*.jpeg "$UPLOADS_DIR"/*.JPEG)
shopt -u nullglob

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  echo "Error: no JPEG files found in $UPLOADS_DIR"
  exit 1
fi

copied=0
skipped_existing=0
missing=0

echo "Date:   $DATE"
echo "Uploads: $UPLOADS_DIR"
echo "Source:  $SOURCE_DIR"
echo ""

for image in "${IMAGES[@]}"; do
  filename="$(basename "$image")"
  src_xmp="$SOURCE_DIR/$filename.xmp"
  dst_xmp="$UPLOADS_DIR/$filename.xmp"

  if [[ ! -f "$src_xmp" ]]; then
    echo "missing source xmp: $filename.xmp"
    missing=$((missing + 1))
    continue
  fi

  if [[ -f "$dst_xmp" && "$OVERWRITE" != true ]]; then
    echo "exists, skipped: $filename.xmp"
    skipped_existing=$((skipped_existing + 1))
    continue
  fi

  cp "$src_xmp" "$dst_xmp"
  echo "copied: $filename.xmp"
  copied=$((copied + 1))
done

echo ""
echo "Done. Copied: $copied  Skipped existing: $skipped_existing  Missing source xmp: $missing"
