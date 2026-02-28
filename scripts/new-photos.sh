#!/usr/bin/env bash
# new-photos.sh — process uploads, upload to R2, create werf post stubs
#
# Usage:
#   ./scripts/new-photos.sh <YYYY-MM-DD> [--dry-run] [--rewrite-urls]
#
# Arguments:
#   <YYYY-MM-DD>   Shoot date; must match an uploads/<date>/ directory
#
# Options:
#   --dry-run       Run in local mode (no remote uploads); create posts with local URLs
#   --rewrite-urls  Update image/thumb URLs in existing posts for this date
#
# Prerequisites:
#   - ImageMagick installed (magick or convert)
#   - wrangler installed and authenticated (wrangler login)
#   - uploads/<date>/ exists and contains JPEG files
#   - XMP sidecars named <file>.jpg.xmp alongside each JPEG (optional)
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
LOCAL_PUBLIC_URL="/public/photos"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
DATE=""
DRY_RUN=false
REWRITE_URLS=false

usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --rewrite-urls) REWRITE_URLS=true; shift ;;
    -h|--help) usage ;;
    -*)        echo "Unknown option: $1"; usage ;;
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

UPLOADS_DIR="$REPO_ROOT/uploads/$DATE"
PROCESSED_DIR="$REPO_ROOT/processed/$DATE"
MAINS_DIR="$PROCESSED_DIR/mains"
THUMBS_DIR="$PROCESSED_DIR/thumbs"
LOCAL_ORIGINALS_DIR="$REPO_ROOT/site/public/photos/originals/$DATE"
LOCAL_THUMBS_DIR="$REPO_ROOT/site/public/photos/thumbs/$DATE"

MODE="remote"
if [[ "$DRY_RUN" == true ]]; then
  MODE="local"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "  $*"; }
info() { echo "→ $*"; }
dry()  { echo "  [dry-run] $*"; }
yaml_quote() {
  local value="${1-}"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}
normalize_output_filename() {
  local filename="${1-}"
  local stem="${filename%.*}"
  local ext="${filename##*.}"
  local cleaned="$stem"

  # Drop trailing placeholder markers like _### from output names.
  cleaned="$(sed -E 's/_#+$//' <<<"$cleaned")"
  # Keep only URL-friendly filename characters.
  cleaned="$(python3 - "$cleaned" <<'PY'
import re
import sys
import unicodedata

value = sys.argv[1]
value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
value = re.sub(r"[^A-Za-z0-9._-]+", "-", value)
value = re.sub(r"-{2,}", "-", value).strip("-._")
print(value or "photo")
PY
)"

  printf '%s.%s\n' "$cleaned" "$ext"
}
url_encode_segment() {
  local value="${1-}"
  python3 - "$value" <<'PY'
import sys
import urllib.parse

print(urllib.parse.quote(sys.argv[1], safe="-._~"))
PY
}
rewrite_post_urls() {
  local post_file="$1"
  local orig_url="$2"
  local thumb_url="$3"

  python3 - "$post_file" "$orig_url" "$thumb_url" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
orig = sys.argv[2]
thumb = sys.argv[3]

def yq(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"

text = path.read_text()
text = re.sub(r'(?m)^image:.*$', f'image: {yq(orig)}', text)
text = re.sub(r'(?m)^thumb:.*$', f'thumb: {yq(thumb)}', text)
path.write_text(text)
PY
}

# ---------------------------------------------------------------------------
# Detect ImageMagick
# ---------------------------------------------------------------------------
if command -v magick &>/dev/null; then
  CONVERT="magick"
elif command -v convert &>/dev/null; then
  CONVERT="convert"
else
  echo "Error: ImageMagick not found. Install via: brew install imagemagick"
  exit 1
fi

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
if [[ "$MODE" == "remote" ]] && ! command -v wrangler &>/dev/null; then
  echo "Error: wrangler not found. Run: npm install -g wrangler"
  exit 1
fi

if [[ ! -d "$UPLOADS_DIR" ]]; then
  echo "Error: uploads directory not found: $UPLOADS_DIR"
  exit 1
fi

# Collect JPEGs
shopt -s nullglob
JPEGS=("$UPLOADS_DIR"/*.jpg "$UPLOADS_DIR"/*.jpeg "$UPLOADS_DIR"/*.JPG "$UPLOADS_DIR"/*.JPEG)
shopt -u nullglob

if [[ ${#JPEGS[@]} -eq 0 ]]; then
  echo "Error: no JPEG files found in $UPLOADS_DIR"
  exit 1
fi

info "Date:     $DATE"
info "Uploads:  $UPLOADS_DIR (${#JPEGS[@]} JPEG(s))"
info "Mains:    $MAINS_DIR"
info "Thumbs:   $THUMBS_DIR"
info "Mode:     $MODE"
echo ""

# Ensure sanitized output filenames are unique before processing.
normalized_manifest="$(mktemp)"
trap 'rm -f "$normalized_manifest"' EXIT
for src_jpg in "${JPEGS[@]}"; do
  src_filename="$(basename "$src_jpg")"
  normalize_output_filename "$src_filename" >> "$normalized_manifest"
done
collision="$(sort "$normalized_manifest" | uniq -d | head -n 1 || true)"
if [[ -n "$collision" ]]; then
  echo "Error: normalized filename collision after stripping suffixes: $collision"
  echo "Please rename source files in $UPLOADS_DIR so normalized names are unique."
  exit 1
fi

# ---------------------------------------------------------------------------
# XMP parsing
# Sets caller-scope vars: xmp_film_name, xmp_film_format, xmp_film_speed,
# xmp_film_type, xmp_developed_by, xmp_camera, xmp_lens, xmp_location
# ---------------------------------------------------------------------------
parse_xmp() {
  local xmp_file="$1"

  xmp_film_name=""
  xmp_film_format=""
  xmp_film_speed=""
  xmp_film_type=""
  xmp_developed_by=""
  xmp_camera=""
  xmp_lens=""
  xmp_location=""

  [[ -f "$xmp_file" ]] || return 0

  local entries
  entries="$(awk '/<lr:hierarchicalSubject>/,/<\/lr:hierarchicalSubject>/' "$xmp_file" \
    | sed -n 's|.*<rdf:li>\(.*\)</rdf:li>.*|\1|p')"

  _xmp_extract() {
    local key="$1"
    awk -F'|' -v key="$key" '$1 == key {sub(/^[^|]*\|/, ""); print; exit}' <<<"$entries"
  }

  xmp_film_name="$(_xmp_extract 'Film')"
  xmp_film_format="$(_xmp_extract 'Film Format')"
  xmp_film_speed="$(_xmp_extract 'Film Speed')"
  xmp_film_type="$(_xmp_extract 'Film Type')"
  xmp_developed_by="$(_xmp_extract 'Developed By')"
  xmp_camera="$(_xmp_extract 'Camera')"
  xmp_lens="$(_xmp_extract 'Lens')"
  xmp_location="$(_xmp_extract 'Location')"
}

# ---------------------------------------------------------------------------
# Create a post stub for one photo
# ---------------------------------------------------------------------------
create_post() {
  local filename="$1"
  local date="$2"
  local orig_url="$3"
  local thumb_url="$4"

  local slug="${filename%.*}"
  local file_slug="${slug//_/-}"
  local post_file="$POSTS_DIR/${date}-${file_slug}.md"

  if [[ -f "$post_file" ]]; then
    if [[ "$REWRITE_URLS" == true ]]; then
      rewrite_post_urls "$post_file" "$orig_url" "$thumb_url"
      log "rewrote URLs: $(basename "$post_file")"
    else
      log "skip (exists): $(basename "$post_file")"
    fi
    return
  fi

  cat > "$post_file" <<EOF
---
layout: photo
title: $(yaml_quote "${date} / ${slug}")
date: ${date}
film_name: $(yaml_quote "$xmp_film_name")
film_format: $(yaml_quote "$xmp_film_format")
film_speed: $(yaml_quote "$xmp_film_speed")
film_type: $(yaml_quote "$xmp_film_type")
developed_by: $(yaml_quote "$xmp_developed_by")
exposure_compensation: box
camera: $(yaml_quote "$xmp_camera")
lens: $(yaml_quote "$xmp_lens")
location: $(yaml_quote "$xmp_location")
tags:
image: $(yaml_quote "$orig_url")
thumb: $(yaml_quote "$thumb_url")
description:
---
EOF
  log "created: $(basename "$post_file")"
}

# ---------------------------------------------------------------------------
# Process images
# ---------------------------------------------------------------------------
info "Processing images..."
mkdir -p "$MAINS_DIR" "$THUMBS_DIR"

for src_jpg in "${JPEGS[@]}"; do
  src_filename="$(basename "$src_jpg")"
  filename="$(normalize_output_filename "$src_filename")"
  if [[ -f "$MAINS_DIR/$filename" && -f "$THUMBS_DIR/$filename" ]]; then
    log "skip (exists): $filename"
  else
    log "processing: $src_filename -> $filename"
    "$CONVERT" "$src_jpg" \
      -auto-orient -colorspace sRGB \
      -filter LanczosSharp -define filter:blur=0.95 \
      -resize '2000x2000>' \
      -unsharp 0x0.6+0.7+0.02 \
      -sampling-factor 4:2:0 -interlace Plane -quality 82 \
      -strip "$MAINS_DIR/$filename"
    "$CONVERT" "$src_jpg" \
      -auto-orient -colorspace sRGB \
      -filter LanczosSharp -define filter:blur=0.95 \
      -resize '800x800>' \
      -unsharp 0x0.5+0.6+0.02 \
      -sampling-factor 4:2:0 -interlace Plane -quality 60 \
      -strip "$THUMBS_DIR/$filename"
  fi
done
echo ""

# ---------------------------------------------------------------------------
# Upload to R2 (remote) or publish to site/public (local)
# ---------------------------------------------------------------------------
publish_dir() {
  local local_dir="$1"
  local r2_prefix="$2"
  local local_prefix="$3"

  if [[ "$MODE" == "local" ]]; then
    local target_dir="$local_prefix"
    mkdir -p "$target_dir"
    for file in "$local_dir"/*; do
      [[ -f "$file" ]] || continue
      local filename
      filename="$(basename "$file")"
      log "publishing $filename..."
      cp -f "$file" "$target_dir/$filename"
    done
    return 0
  fi

  local -a files=()
  local file
  for file in "$local_dir"/*; do
    [[ -f "$file" ]] || continue
    files+=("$file")
  done

  [[ ${#files[@]} -eq 0 ]] && return 0

  local upload_jobs="${UPLOAD_JOBS:-4}"
  if ! [[ "$upload_jobs" =~ ^[1-9][0-9]*$ ]]; then
    upload_jobs=4
  fi
  info "Upload concurrency: $upload_jobs"

  if ! (
    export R2_PREFIX="$r2_prefix" R2_BUCKET_ENV="$R2_BUCKET"
    printf '%s\0' "${files[@]}" | xargs -0 -n1 -P "$upload_jobs" bash -c '
      file="$1"
      filename="$(basename "$file")"
      key="$R2_PREFIX/$filename"
      echo "  uploading $filename..."
      if ! wrangler r2 object put "$R2_BUCKET_ENV/$key" --remote --file "$file" --content-type "image/jpeg"; then
        echo "  ERROR: failed to upload $filename" >&2
        exit 1
      fi
    ' _
  ); then
    return 1
  fi

  return 0
}

if [[ "$MODE" == "local" ]]; then
  info "Publishing mains to site/public..."
else
  info "Uploading mains to R2 (remote)..."
fi
mains_ok=true
publish_dir "$MAINS_DIR" "photos/originals/$DATE" "$LOCAL_ORIGINALS_DIR" || mains_ok=false

if [[ "$MODE" == "local" ]]; then
  info "Publishing thumbs to site/public..."
else
  info "Uploading thumbs to R2 (remote)..."
fi
thumbs_ok=true
publish_dir "$THUMBS_DIR" "photos/thumbs/$DATE" "$LOCAL_THUMBS_DIR" || thumbs_ok=false

echo ""

# ---------------------------------------------------------------------------
# Ensure remote uploads complete before writing post URLs
# ---------------------------------------------------------------------------
if [[ "$MODE" == "remote" && ( "$mains_ok" != true || "$thumbs_ok" != true ) ]]; then
  echo "WARNING: Upload errors occurred — post stubs were NOT created."
  echo "processed/ retained for retry:"
  echo "  $PROCESSED_DIR"
  exit 1
fi

# ---------------------------------------------------------------------------
# Create post stubs
# ---------------------------------------------------------------------------
info "Creating post stubs in $POSTS_DIR..."
mkdir -p "$POSTS_DIR"

for src_jpg in "${JPEGS[@]}"; do
  src_filename="$(basename "$src_jpg")"
  filename="$(normalize_output_filename "$src_filename")"
  xmp_file="${src_jpg}.xmp"
  encoded_filename="$(url_encode_segment "$filename")"

  parse_xmp "$xmp_file"

  orig_url="$R2_PUBLIC_URL/photos/originals/$DATE/$encoded_filename"
  thumb_url="$R2_PUBLIC_URL/photos/thumbs/$DATE/$encoded_filename"
  if [[ "$MODE" == "local" ]]; then
    orig_url="$LOCAL_PUBLIC_URL/originals/$DATE/$encoded_filename"
    thumb_url="$LOCAL_PUBLIC_URL/thumbs/$DATE/$encoded_filename"
  fi

  create_post "$filename" "$DATE" "$orig_url" "$thumb_url"
done
echo ""

# ---------------------------------------------------------------------------
# Cleanup — remove processed/ only if uploads succeeded; uploads/ is kept
# ---------------------------------------------------------------------------
if [[ "$MODE" == "local" ]]; then
  echo "Local mode: processed/ retained for inspection."
elif [[ "$mains_ok" == true && "$thumbs_ok" == true ]]; then
  info "Cleaning up..."
  rm -rf "$PROCESSED_DIR"
  log "removed $PROCESSED_DIR"
else
  echo "WARNING: processed/ retained because uploads were not successful."
  exit 1
fi

echo ""
echo "Done. Review new posts in $POSTS_DIR and fill in any missing metadata."
