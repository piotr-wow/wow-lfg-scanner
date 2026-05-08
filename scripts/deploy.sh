#!/usr/bin/env bash
# Copies all addons from ./addons/ into the WoW client's Interface/AddOns folder.
# Usage:
#   ./scripts/deploy.sh                  # copy to the default path
#   WOW_DIR=/other/path ./scripts/deploy.sh
#   ./scripts/deploy.sh LFGScannerLogger    # only the named addon

set -euo pipefail

WOW_DIR="${WOW_DIR:-$HOME/Games/wow}"
ADDONS_DST="${WOW_DIR}/Interface/AddOns"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDONS_SRC="${REPO_ROOT}/addons"

if [[ ! -d "$ADDONS_DST" ]]; then
  echo "ERROR: AddOns folder not found: $ADDONS_DST" >&2
  echo "Set WOW_DIR env var to your WoW client root." >&2
  exit 1
fi

if [[ ! -d "$ADDONS_SRC" ]]; then
  echo "ERROR: source addons folder not found: $ADDONS_SRC" >&2
  exit 1
fi

deploy_one() {
  local name="$1"
  local src="${ADDONS_SRC}/${name}"
  local dst="${ADDONS_DST}/${name}"
  if [[ ! -d "$src" ]]; then
    echo "skip: $name (not found in $ADDONS_SRC)"
    return
  fi
  rm -rf "$dst"
  cp -r "$src" "$dst"
  echo "deployed: $name -> $dst"
}

if [[ $# -gt 0 ]]; then
  for name in "$@"; do
    deploy_one "$name"
  done
else
  for dir in "$ADDONS_SRC"/*/; do
    [[ -d "$dir" ]] || continue
    deploy_one "$(basename "$dir")"
  done
fi
