#!/usr/bin/env bash
# new-photos.sh — upload photos to R2 and create werf post stubs
#
# Usage:
#   ./scripts/new-photos.sh <date> [options]
#
# Arguments:
#   <date>              Shoot date, YYYY-MM-DD (also used as subdirectory name under originals/thumbs)
#
# Options:
#   --originals-dir DIR  Local originals dir (default: site/public/photos/originals/<date>)
#   --thumbs-dir DIR     Local thumbs dir    (default: site/public/photos/thumbs/<date>)
#   --dry-run            Print what would happen without uploading or writing files
#
# Prerequisites:
#   - wrangler installed and authenticated (`wrangler login`)
#   - Photos already on disk at the expected paths
#
# R2 bucket  : photosbymatt-assets
# Public URL : https://pub-d1e192acd3c5456eb06f306d0bd48e3d.r2.dev

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTS_DIR="$REPO_ROOT/site/_posts"
R2_BUCKET="photosbymatt-assets"
R2_PUBLIC_URL="https://pub-d1e192acd3c5456eb06f306d0bd48e3d.r2.dev"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
DATE=""
ORIGINALS_DIR=""
THUMBS_DIR=""
DRY_RUN=false

usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --originals-dir) ORIGINALS_DIR="$2"; shift 2 ;;
    --thumbs-dir)    THUMBS_DIR="$2";    shift 2 ;;
    --dry-run)       DRY_RUN=true;       shift   ;;
    -h|--help)       usage ;;
    -*)              echo "Unknown option: $1"; usage ;;
    *)
      if [[ -z "$DATE" ]]; then DATE="$1"; shift
      else echo "Unexpected argument: $1"; usage
      fi ;;
  esac
done

if [[ -z "$DATE" ]]; then
  echo "Error: <date> is required."
  usage
fi

if ! [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: date must be YYYY-MM-DD, got: $DATE"
  exit 1
fi

ORIGINALS_DIR="${ORIGINALS_DIR:-$REPO_ROOT/site/public/photos/originals/$DATE}"
THUMBS_DIR="${THUMBS_DIR:-$REPO_ROOT/site/public/photos/thumbs/$DATE}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "  $*"; }
info() { echo "→ $*"; }
dry()  { echo "  [dry-run] $*"; }

# ---------------------------------------------------------------------------
# Upload a directory of files to R2 via wrangler
# ---------------------------------------------------------------------------
upload_dir() {
  local local_dir="$1"
  local r2_prefix="$2"   # e.g. photos/originals/2026-02-24

  if [[ "$DRY_RUN" == true ]]; then
    dry "would upload $local_dir  →  r2:$R2_BUCKET/$r2_prefix/"
    return
  fi

  local count=0
  for file in "$local_dir"/*; do
    [[ -f "$file" ]] || continue
    local filename
    filename="$(basename "$file")"
    local key="$r2_prefix/$filename"
    log "uploading $filename..."
    wrangler r2 object put "$R2_BUCKET/$key" --file "$file" --content-type "image/jpeg"
    (( count++ )) || true
  done
  log "$count file(s) uploaded"
}

# ---------------------------------------------------------------------------
# Create a post stub for one photo
# ---------------------------------------------------------------------------
create_post() {
  local slug="$1"         # e.g. 0001_37
  local date="$2"         # e.g. 2026-02-24
  local orig_url="$3"     # full R2 URL for original
  local thumb_url="$4"    # full R2 URL for thumb

  # post filename: YYYY-MM-DD-<slug with _ replaced by ->
  local file_slug="${slug//_/-}"
  local post_file="$POSTS_DIR/${date}-${file_slug}.md"

  if [[ -f "$post_file" ]]; then
    log "skip (exists): $post_file"
    return
  fi

  if [[ "$DRY_RUN" == true ]]; then
    dry "would create: $post_file"
    return
  fi

  cat > "$post_file" <<EOF
---
layout: photo
title: "${date} / ${slug}"
date: ${date}
# Fill these in
film:
film_format:
developed_by:
exposure_compensation: box
camera:
lens:
location:
tags:
image: ${orig_url}
thumb: ${thumb_url}
description:
---
EOF
  log "created: $post_file"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
info "Date: $DATE"
info "Originals: $ORIGINALS_DIR"
info "Thumbs:    $THUMBS_DIR"

if [[ ! -d "$ORIGINALS_DIR" ]]; then
  echo "Error: originals directory not found: $ORIGINALS_DIR"
  exit 1
fi

if [[ "$DRY_RUN" == false ]] && ! command -v wrangler &>/dev/null; then
  echo "Error: wrangler not found. Run: npm install -g wrangler"
  exit 1
fi

# Upload originals
info "Uploading originals..."
upload_dir "$ORIGINALS_DIR" "photos/originals/$DATE"

# Upload thumbs (only if dir exists)
if [[ -d "$THUMBS_DIR" ]]; then
  info "Uploading thumbs..."
  upload_dir "$THUMBS_DIR" "photos/thumbs/$DATE"
else
  log "No thumbs directory found at $THUMBS_DIR — skipping"
fi

# Create post stubs
info "Creating post stubs in $POSTS_DIR..."
mkdir -p "$POSTS_DIR"

for orig in "$ORIGINALS_DIR"/*.jpg "$ORIGINALS_DIR"/*.jpeg "$ORIGINALS_DIR"/*.JPG; do
  [[ -f "$orig" ]] || continue
  filename="$(basename "$orig")"
  # strip extension
  slug="${filename%.*}"

  orig_url="$R2_PUBLIC_URL/photos/originals/$DATE/$filename"
  # derive thumb filename (same name, always .jpg)
  thumb_url="$R2_PUBLIC_URL/photos/thumbs/$DATE/${slug}.jpg"

  create_post "$slug" "$DATE" "$orig_url" "$thumb_url"
done

echo ""
echo "Done. Review the new posts in $POSTS_DIR and fill in the metadata."
