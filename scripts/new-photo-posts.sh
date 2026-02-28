#!/usr/bin/env bash
# new-photo-posts.sh
# Creates stub _posts entries for any image in public/photos/originals/
# that doesn't already have a corresponding post.
#
# Usage: bash scripts/new-photo-posts.sh [--dry-run]
#
# Image layout expected:
#   site/public/photos/originals/<YYYY-MM-DD>/<filename>.jpg
#
# Post created at:
#   site/_posts/<YYYY-MM-DD>-<slug>.md

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIGINALS="$ROOT/site/public/photos/originals"
POSTS_DIR="$ROOT/site/_posts"
DRY_RUN=false
xmp_film_name=""
xmp_film_format=""
xmp_film_type=""
xmp_film_speed=""
xmp_developed_by=""

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[dry-run] No files will be written."
fi

created=0
skipped=0
ignored=0

while IFS= read -r img_path; do
  dir_name="$(basename "$(dirname "$img_path")")"

  # Only process images sitting in a YYYY-MM-DD directory
  if ! echo "$dir_name" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "  ignore: $img_path (parent dir '$dir_name' not YYYY-MM-DD)"
    ignored=$((ignored + 1))
    continue
  fi

  date="$dir_name"
  filename="$(basename "$img_path")"
  stem="${filename%.*}"
  slug="$(echo "$stem" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
  post_file="$POSTS_DIR/${date}-${slug}.md"
  img_rel="/public/photos/originals/${date}/${filename}"
  thumb_rel="/public/photos/thumbs/${date}/${filename}"

  if [[ -f "$post_file" ]]; then
    echo "  exists: $(basename "$post_file")"
    skipped=$((skipped + 1))
    continue
  fi

  echo "  create: $(basename "$post_file")"

  if [[ "$DRY_RUN" == false ]]; then
    cat > "$post_file" <<FRONTMATTER
---
layout: photo
title: "${date} / ${stem}"
date: ${date}

# Fill these in
film_name: ${xmp_film_name}
film_format: ${xmp_film_format:-35mm}
film_type: ${xmp_film_type}
film_speed: ${xmp_film_speed}
developed_by: ${xmp_developed_by}
exposure_compensation: box
camera:
lens:
location:

tags:

image: ${img_rel}
thumb: ${thumb_rel}

description:
---
FRONTMATTER
    created=$((created + 1))
  fi

done < <(find "$ORIGINALS" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) | sort)

echo ""
echo "Done. Created: $created  Already existed: $skipped  Ignored: $ignored"
