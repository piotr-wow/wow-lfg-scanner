#!/usr/bin/env bash
# Zbiera pliki LFGScannerLogger.lua ze wszystkich kont w WTF/Account/* do data/samples/<ACCOUNT>/.
# Domyslnie skanuje wszystkie konta. Mozesz tez podac konkretne nazwy.
# Uzycie:
#   ./scripts/collect-logs.sh                     # wszystkie konta
#   ./scripts/collect-logs.sh ACCOUNT_A ACCOUNT_B     # tylko te
#   WOW_DIR=/inna/sciezka ./scripts/collect-logs.sh

set -euo pipefail

WOW_DIR="${WOW_DIR:-/home/piotr/Gry/wow}"
ACCOUNTS_DIR="${WOW_DIR}/WTF/Account"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST_ROOT="${REPO_ROOT}/data/samples"

if [[ ! -d "$ACCOUNTS_DIR" ]]; then
  echo "ERROR: Account folder not found: $ACCOUNTS_DIR" >&2
  exit 1
fi

mkdir -p "$DST_ROOT"

if [[ $# -gt 0 ]]; then
  accounts=("$@")
else
  accounts=()
  for d in "$ACCOUNTS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    accounts+=("$(basename "$d")")
  done
fi

found_any=0
for acc in "${accounts[@]}"; do
  src="${ACCOUNTS_DIR}/${acc}/SavedVariables/LFGScannerLogger.lua"
  if [[ ! -f "$src" ]]; then
    echo "skip: $acc (no LFGScannerLogger.lua)"
    continue
  fi
  dst_dir="${DST_ROOT}/${acc}"
  mkdir -p "$dst_dir"
  cp "$src" "$dst_dir/LFGScannerLogger.lua"
  size_kb=$(( $(stat -c%s "$src") / 1024 ))
  entries=$(grep -c '^[[:space:]]*{[[:space:]]*t[[:space:]]*=' "$src" || true)
  echo "collected: $acc -> ${dst_dir}/LFGScannerLogger.lua  (${size_kb}KB, ~${entries} entries)"
  found_any=1
done

if [[ $found_any -eq 0 ]]; then
  echo "No LFGScannerLogger.lua files found. Did you /reload or logout in-game?"
  exit 2
fi
