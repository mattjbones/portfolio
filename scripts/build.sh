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

AUTH_TOKEN="${GITHUB_PAT:-${GITHUB_TOKEN:-}}"
if [ -z "$AUTH_TOKEN" ]; then
  echo "GITHUB_PAT (or GITHUB_TOKEN) is required to download werf from the private repo."
  exit 1
fi

# Always download fresh in CI, use cache locally
WERF_TAG=2026-02-25
TAG="${WERF_TAG:-$(date +%Y-%m-%d)}"
echo "Downloading werf-${PLATFORM} (tag: ${TAG})..."
ASSET_NAME="werf-${PLATFORM}"
API_JSON="$(curl -fsSL \
  -H "Authorization: token ${AUTH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/mattjbones/werf/releases/tags/${TAG}" \
  || true)"

if [ -z "$API_JSON" ]; then
  echo "Failed to fetch release metadata for tag ${TAG}. Check token scope (needs repo), repo access, and tag name."
  exit 1
fi

ASSET_ID="$(API_JSON="$API_JSON" python3 - "$ASSET_NAME" <<'PY'
import json, os, sys
data = json.loads(os.environ.get("API_JSON", "") or "{}")
assets = data.get("assets", [])
name = sys.argv[1]
for a in assets:
    if a.get("name") == name:
        print(a.get("id", ""))
        sys.exit(0)
sys.exit(1)
PY
)"

if [ -z "$ASSET_ID" ]; then
  ASSET_LIST="$(API_JSON="$API_JSON" python3 - <<'PY'
import json, os
data = json.loads(os.environ.get("API_JSON", "") or "{}")
assets = data.get("assets", [])
print(", ".join([a.get("name","") for a in assets]))
PY
)"
  echo "Release asset not found: $ASSET_NAME"
  echo "Available assets: ${ASSET_LIST}"
  exit 1
fi

curl -fSL \
  -H "Authorization: token ${AUTH_TOKEN}" \
  -H "Accept: application/octet-stream" \
  "https://api.github.com/repos/mattjbones/werf/releases/assets/${ASSET_ID}" \
  -o "$WERF"
chmod +x "$WERF"

# Generate thumbnails (if ImageMagick is available)
if command -v magick &> /dev/null || command -v convert &> /dev/null; then
  bash "$ROOT/scripts/generate-thumbs.sh"
else
  echo "ImageMagick not found, skipping thumbnail generation"
fi

# Enable analytics for production builds
if [ "${PRODUCTION_BUILD:-false}" = "true" ]; then
  echo "analytics: true" >> site/_config.yml
fi

# Build site
cd "$ROOT"
"$WERF" nowatch site

# Cloudflare Pages requires a plain `_headers` file at the output root.
# Werf currently emits `site/_headers` as `_headers.html`, so copy the raw file.
if [ -f "$ROOT/site/_headers" ]; then
  cp "$ROOT/site/_headers" "$ROOT/dist/_headers"
fi
