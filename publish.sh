#!/usr/bin/env bash
# Publish exactly one reviewed AI-infrastructure HTML artifact.
#
# This helper is intentionally fail-closed. It never scans the vault, discovers
# reports, rewrites an index, archives unrelated files, or publishes without a
# current-task confirmation token supplied both as an argument and private env.
#
# Usage:
#   CURRENT_TASK_CONFIRMATION_ID=<one-time-id> ./publish.sh \
#     --artifact /absolute/path/report.html \
#     --sha256 <expected-sha256> \
#     --slug leading-indicators.html \
#     --confirmation-id <one-time-id>

set -euo pipefail

SITE_DIR="$(cd "$(dirname "$0")" && pwd)"
ARTIFACT=""
EXPECTED_SHA=""
SLUG=""
CONFIRMATION_ID=""

usage() {
  echo "usage: $0 --artifact ABS_HTML --sha256 SHA256 --slug ALLOWED_SLUG --confirmation-id ID" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact) [[ $# -ge 2 ]] || usage; ARTIFACT="$2"; shift 2 ;;
    --sha256) [[ $# -ge 2 ]] || usage; EXPECTED_SHA="$2"; shift 2 ;;
    --slug) [[ $# -ge 2 ]] || usage; SLUG="$2"; shift 2 ;;
    --confirmation-id) [[ $# -ge 2 ]] || usage; CONFIRMATION_ID="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$ARTIFACT" = /* ]] || { echo "BLOCKED: --artifact must be absolute" >&2; exit 2; }
[[ -f "$ARTIFACT" && ! -L "$ARTIFACT" ]] || { echo "BLOCKED: artifact must be a regular non-symlink file" >&2; exit 2; }
[[ "$ARTIFACT" == *.html ]] || { echo "BLOCKED: only HTML artifacts are publishable" >&2; exit 2; }
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "BLOCKED: invalid SHA-256" >&2; exit 2; }
[[ -n "$CONFIRMATION_ID" ]] || { echo "BLOCKED: one-time confirmation id required" >&2; exit 2; }
[[ -n "${CURRENT_TASK_CONFIRMATION_ID:-}" && "$CURRENT_TASK_CONFIRMATION_ID" == "$CONFIRMATION_ID" ]] || {
  echo "BLOCKED: private current-task confirmation does not match" >&2
  exit 2
}

case "$SLUG" in
  optics.html|optics-epitaxy.html|optics-packaging.html|compute-fabric.html|compute-fabric-hybrid.html|\
  power.html|cooling.html|networking.html|substrates.html|macro.html|alpha-map.html|\
  alpha-map-blueprint.html|leading-data-map.html|bom-alpha-scan.html|alpha-funnel.html|\
  leading-indicators.html|aixtron.html|xfab.html|tech-alpha-map.html) ;;
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
