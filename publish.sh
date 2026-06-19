#!/usr/bin/env bash
# Sync the latest v5 AI-Infra reports + weekly Macro-Flow Monitor from the Obsidian
# vault into this site folder and publish to GitHub Pages.
#
# Safe to run unattended (from the scheduled tasks) on a machine where git/gh is
# authenticated: it rebases onto origin before pushing, so a diverged remote
# (e.g. a report pushed from another environment) self-heals instead of failing.
#
#   ./publish.sh
#
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

VAULT="$HOME/Documents/My Obsidian/04 Reports"

# copy the newest vault file matching a FILENAME glob -> a slug (no-op if no match).
# $1 is a filename pattern only (no directory); $VAULT is prepended quoted so the
# space in the vault path is preserved while the wildcard still expands.
sync_slug() {
  local pat="$1" slug="$2"
  local latest
  latest=$(ls -t "$VAULT"/$pat 2>/dev/null | head -1 || true)
  if [ -n "${latest:-}" ]; then
    cp "$latest" "$slug"
    echo "synced $(basename "$latest") -> $slug"
  fi
}

# --- sync the AI-infra chokepoint layers (latest v5 per page) ---
# Optics & Compute fabric each keep TWO curated pages: a base report + a deeper-run report.
sync_slug 'AI-Infra_Optics_CPO*_v5_*.html'                   optics.html
sync_slug 'AI-Infra_Optics_*Epitaxy*_v5_*.html'              optics-epitaxy.html
sync_slug 'AI-Infra_ComputeFabric_CoWoS*_v5_*.html'          compute-fabric.html
sync_slug 'AI-Infra_ComputeFabric_*HybridBonding*_v5_*.html' compute-fabric-hybrid.html
sync_slug 'AI-Infra_PowerDelivery_*_v5_*.html'               power.html
sync_slug 'AI-Infra_Cooling_*_v5_*.html'                     cooling.html
sync_slug 'AI-Infra_NetworkingSilicon_*_v5_*.html'           networking.html
sync_slug 'AI-Infra_Substrates_*_v5_*.html'                  substrates.html

# --- sync the latest weekly Macro-Flow Monitor ---
sync_slug 'Macro-Flow-Monitor_*.html' macro.html

# --- sync the Expectations-Layer Alpha Map (Engine C, weekly) ---
sync_slug 'AI-Infra_AlphaMap_ConsensusGap_*.html'    alpha-map.html
sync_slug 'AI-Infra_AlphaMap_FrameworkBlueprint_*.html' alpha-map-blueprint.html

# --- sync the Leading-Data Map (Engine-C data-acquisition layer) ---
sync_slug 'AI-Infra_LeadingDataMap_*.html' leading-data-map.html

# --- sync single-name reverse-model teardowns (on-demand) ---
sync_slug 'AIXTRON_ReverseModel_*.html' aixtron.html

# --- commit ---
git add -A
if git diff --cached --quiet; then
  echo "No content changes to publish."
else
  git commit -m "Update AI-Infra + Macro reports ($(date +%F))"
fi

# --- reconcile with origin, then push (so a diverged remote doesn't block us) ---
git fetch -q origin
if ! git rebase origin/main; then
  echo "ERROR: rebase hit a conflict — aborting, leaving the repo untouched for manual review." >&2
  git rebase --abort || true
  exit 1
fi

if git diff --quiet origin/main..HEAD; then
  echo "Already up to date with origin; nothing to push."
else
  git push origin main && echo "Published -> https://ronshih0130.github.io/ai-infra-deepdive/"
fi
