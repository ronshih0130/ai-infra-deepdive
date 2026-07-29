#!/usr/bin/env bash
# Publish reviewed AI-infrastructure HTML to the public site.
#
# Two modes, both fail-closed and both requiring a current-task confirmation
# token supplied BOTH as an argument and as private env:
#
#   slug mode    — copy exactly one reviewed artifact onto one allowlisted slug.
#                  Never scans the vault, never rewrites an index.
#   index mode   — the ONLY path that may touch archive/ and the two index
#                  pages. It archives dated vault reports (minus .publishignore)
#                  and regenerates archive/index.html plus the auto-generated
#                  ROTATION-ROWS block of index.html. It may not write a slug.
#
# The two modes are mutually exclusive and each commits its own scope, so a
# content publish and an index rebuild never mix in one commit.
#
# Usage:
#   CURRENT_TASK_CONFIRMATION_ID=<one-time-id> ./publish.sh \
#     --artifact /absolute/path/report.html \
#     --sha256 <expected-sha256> \
#     --slug leading-indicators.html \
#     --confirmation-id <one-time-id>
#
#   CURRENT_TASK_CONFIRMATION_ID=<one-time-id> ./publish.sh \
#     --index-refresh --confirmation-id <one-time-id>

set -euo pipefail

SITE_DIR="$(cd "$(dirname "$0")" && pwd)"
ARTIFACT=""
EXPECTED_SHA=""
SLUG=""
CONFIRMATION_ID=""
INDEX_REFRESH=0

usage() {
  echo "usage: $0 --artifact ABS_HTML --sha256 SHA256 --slug ALLOWED_SLUG --confirmation-id ID" >&2
  echo "       $0 --index-refresh --confirmation-id ID" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact) [[ $# -ge 2 ]] || usage; ARTIFACT="$2"; shift 2 ;;
    --sha256) [[ $# -ge 2 ]] || usage; EXPECTED_SHA="$2"; shift 2 ;;
    --slug) [[ $# -ge 2 ]] || usage; SLUG="$2"; shift 2 ;;
    --confirmation-id) [[ $# -ge 2 ]] || usage; CONFIRMATION_ID="$2"; shift 2 ;;
    --index-refresh) INDEX_REFRESH=1; shift ;;
    *) usage ;;
  esac
done

[[ -n "$CONFIRMATION_ID" ]] || { echo "BLOCKED: one-time confirmation id required" >&2; exit 2; }
[[ -n "${CURRENT_TASK_CONFIRMATION_ID:-}" && "$CURRENT_TASK_CONFIRMATION_ID" == "$CONFIRMATION_ID" ]] || {
  echo "BLOCKED: private current-task confirmation does not match" >&2
  exit 2
}

if [[ "$INDEX_REFRESH" -eq 1 ]]; then
  [[ -z "$ARTIFACT$EXPECTED_SHA$SLUG" ]] || {
    echo "BLOCKED: --index-refresh may not be combined with a slug publish" >&2
    exit 2
  }
  cd "$SITE_DIR"
  [[ -z "$(git status --porcelain)" ]] || {
    echo "BLOCKED: site worktree has pre-existing changes; refusing to mix scopes" >&2
    exit 2
  }
  python3 "$SITE_DIR/tools/build_index.py" || {
    echo "BLOCKED: index build failed; nothing staged" >&2
    exit 2
  }
  git add -- archive index.html index-rows.tsv
  STAGED="$(git diff --cached --name-only)"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      archive/*|index.html|index-rows.tsv) ;;
      *) echo "BLOCKED: index mode staged out-of-scope path: $f" >&2; exit 2 ;;
    esac
  done <<< "$STAGED"
  if git diff --cached --quiet; then
    echo "Index and archive already current."
    exit 0
  fi
  git commit -m "Refresh archive and index (${CONFIRMATION_ID:0:12})"
  git fetch -q origin
  if ! git rebase origin/main; then
    git rebase --abort || true
    echo "BLOCKED: rebase conflict; no push performed" >&2
    exit 3
  fi
  git push origin main
  echo "Index and archive refreshed."
  exit 0
fi

[[ "$ARTIFACT" = /* ]] || { echo "BLOCKED: --artifact must be absolute" >&2; exit 2; }
[[ -f "$ARTIFACT" && ! -L "$ARTIFACT" ]] || { echo "BLOCKED: artifact must be a regular non-symlink file" >&2; exit 2; }
[[ "$ARTIFACT" == *.html ]] || { echo "BLOCKED: only HTML artifacts are publishable" >&2; exit 2; }
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "BLOCKED: invalid SHA-256" >&2; exit 2; }

case "$SLUG" in
  optics.html|optics-epitaxy.html|optics-packaging.html|compute-fabric.html|compute-fabric-hybrid.html|\
  power.html|cooling.html|networking.html|substrates.html|macro.html|alpha-map.html|\
  alpha-map-blueprint.html|leading-data-map.html|bom-alpha-scan.html|alpha-funnel.html|\
  leading-indicators.html|aixtron.html|xfab.html|tech-alpha-map.html|crossfeed-dashboard.html|\
  crowding-gauge.html|quant-desk.html|rotation-framework.html|coiled-spring.html) ;;
  *) echo "BLOCKED: slug is not allowlisted: $SLUG" >&2; exit 2 ;;
esac

EXPECTED_SHA_LC="$(printf '%s' "$EXPECTED_SHA" | tr 'A-F' 'a-f')"
ACTUAL_SHA="$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "$EXPECTED_SHA_LC" ]] || {
  echo "BLOCKED: artifact hash mismatch" >&2
  exit 2
}

cd "$SITE_DIR"
[[ -z "$(git status --porcelain)" ]] || {
  echo "BLOCKED: site worktree has pre-existing changes; refusing to mix scopes" >&2
  exit 2
}

TMP_DEST="${SLUG}.publish-tmp.$$"
trap 'rm -f "$SITE_DIR/$TMP_DEST"' EXIT
cp "$ARTIFACT" "$TMP_DEST"
COPIED_SHA="$(shasum -a 256 "$TMP_DEST" | awk '{print $1}')"
[[ "$COPIED_SHA" == "$EXPECTED_SHA_LC" ]] || { echo "BLOCKED: staged-copy hash mismatch" >&2; exit 2; }
mv "$TMP_DEST" "$SLUG"

git add -- "$SLUG"
STAGED="$(git diff --cached --name-only)"
[[ "$STAGED" == "$SLUG" ]] || {
  echo "BLOCKED: staged scope is not exactly the confirmed slug" >&2
  exit 2
}

if git diff --cached --quiet; then
  echo "No content change for confirmed slug."
  exit 0
fi

git commit -m "Update ${SLUG} from confirmed artifact ${EXPECTED_SHA:0:12}"
git fetch -q origin
if ! git rebase origin/main; then
  git rebase --abort || true
  echo "BLOCKED: rebase conflict; no push performed" >&2
  exit 3
fi
git push origin main
echo "Published confirmed artifact -> $SLUG"
