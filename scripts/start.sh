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

# Download werf if missing or older than 24h
STALE=false
if [ -f "$WERF" ]; then
  AGE=$(( $(date +%s) - $(stat -f %m "$WERF" 2>/dev/null || stat -c %Y "$WERF" 2>/dev/null) ))
  if [ "$AGE" -gt 86400 ]; then
    STALE=true
  fi
fi

if [ ! -f "$WERF" ] || [ "$STALE" = true ]; then
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
else
  echo "Using cached werf binary"
fi

# Start werf in watch mode
cd "$ROOT"
# Prevent stale in-source build artifacts from shadowing dynamic pages (e.g. [tags].html).
rm -rf "$ROOT/site/dist"
echo "Starting werf watch..."
exec "$WERF" watch site
