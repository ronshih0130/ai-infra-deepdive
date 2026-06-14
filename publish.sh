#!/usr/bin/env bash
# Sync the latest v5 AI-Infra reports from the Obsidian vault into this site folder
# and publish to GitHub Pages. Run from an environment authenticated to GitHub
# (e.g. your terminal where `gh`/`git` is logged in).
#
#   ./publish.sh
#
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

VAULT="$HOME/Documents/My Obsidian/04 Reports"

# layer-file prefix -> clean site slug
map_layer() {
  case "$1" in
    Optics)            echo optics.html ;;
    ComputeFabric)     echo compute-fabric.html ;;
    PowerDelivery)     echo power.html ;;
    Cooling)           echo cooling.html ;;
    NetworkingSilicon) echo networking.html ;;
    Substrates)        echo substrates.html ;;
  esac
}

for key in Optics ComputeFabric PowerDelivery Cooling NetworkingSilicon Substrates; do
  latest=$(ls -t "$VAULT"/AI-Infra_${key}_*_v5_*.html 2>/dev/null | head -1 || true)
  slug=$(map_layer "$key")
  if [ -n "${latest:-}" ] && [ -n "$slug" ]; then
    cp "$latest" "$slug"
    echo "synced $(basename "$latest") -> $slug"
  fi
done

git add -A
if git diff --cached --quiet; then
  echo "No changes to publish."
else
  git commit -m "Update AI-Infra reports ($(date +%F))"
  git push && echo "Published -> https://ronshih0130.github.io/ai-infra-deepdive/"
fi
