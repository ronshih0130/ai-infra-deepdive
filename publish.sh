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

# --- sync the BOM Alpha Scan (live free-data BOM x leading-data scan, weekly) ---
sync_slug 'AI-Infra_BOM_AlphaScan_*.html' bom-alpha-scan.html

# --- sync the Leading-Indicators Command Center (flagship MECE dashboard, weekly) ---
sync_slug 'AI-Infra_LeadingIndicators_*.html' leading-indicators.html

# --- sync single-name reverse-model teardowns (on-demand) ---
sync_slug 'AIXTRON_ReverseModel_*.html' aixtron.html
sync_slug 'XFAB_DeepDive_*.html'        xfab.html

# --- catch-all archive: EVERY dated report lands in git, even un-slugged one-offs ---
# Guarantees no report is ever silently dropped: any dated *.html in the vault is
# version-controlled under archive/ (the curated slugs above stay the polished
# homepage). To keep a report OUT of the repo entirely, add a filename glob (one
# per line) to .publishignore next to this script.
mkdir -p archive
shopt -s nullglob
for f in "$VAULT"/*20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*.html; do
  base=$(basename "$f")
  skip=
  if [ -f .publishignore ]; then
    while IFS= read -r pat; do
      case "$pat" in ''|'#'*) continue;; esac
      case "$base" in $pat) skip=1; break;; esac
    done < .publishignore
  fi
  if [ -n "$skip" ]; then echo "archive skip (.publishignore): $base"; continue; fi
  if [ ! -f "archive/$base" ] || ! cmp -s "$f" "archive/$base"; then
    cp "$f" "archive/$base"
    echo "archived $base"
  fi
done
shopt -u nullglob

# --- regenerate the rotation table in index.html from index-rows.tsv ---
# The landing-page table used to be hand-edited and silently drifted out of sync
# with the slugs on every run. Now each row's DATE is auto-stamped from the live
# report filename (so it can never go stale), and the curated columns (layer label,
# chokepoint, tightness) live one-per-line in index-rows.tsv — edit the TSV, not the HTML.
if [ -f index-rows.tsv ] && grep -q 'ROTATION-ROWS:START' index.html; then
  rows_tmp=$(mktemp)
  while IFS=$'\t' read -r num layer slug glob choke tight; do
    case "$num" in ''|'#'*) continue;; esac
    f=$(ls -t "$VAULT"/$glob 2>/dev/null | head -1 || true)
    base=$(basename "${f:-}")
    d=$(printf '%s' "$base" | grep -oE '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | head -1 || true)
    [ -z "$d" ] && d="pending"
    badge=""
    case "$base" in *_v5_*) badge=' <span class="mono" style="font-size:10px;color:var(--faint)">v5</span>';; esac
    {
      printf '      <tr>\n'
      printf '        <td class="mono">%s</td><td>%s</td>\n' "$num" "$layer"
      printf '        <td><span class="pill done">Done · %s</span></td>\n' "$d"
      printf '        <td>%s</td>\n' "$choke"
      printf '        <td class="sev">%s/20</td>\n' "$tight"
      printf '        <td><a href="%s">Open ↗</a>%s</td>\n' "$slug" "$badge"
      printf '      </tr>\n'
    } >> "$rows_tmp"
  done < index-rows.tsv

  idx_tmp=$(mktemp)
  awk -v rows="$rows_tmp" '
    /ROTATION-ROWS:START/ {print; while ((getline line < rows) > 0) print line; close(rows); skip=1; next}
    /ROTATION-ROWS:END/   {skip=0}
    !skip {print}
  ' index.html > "$idx_tmp" && mv "$idx_tmp" index.html
  rm -f "$rows_tmp"
  echo "regenerated rotation table from index-rows.tsv"
fi

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
