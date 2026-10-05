#!/bin/bash
# Run every scenario against several worker setups and print a Markdown table.
#
#   tests/matrix.sh [--parallel N] [--setup "RUN.SH ARGS"]... [SCENARIO...]
#
# Default setups: --role coding, --role mechanical, --kind codex (effort medium). Default
# scenarios: every directory under tests/scenarios. Runs go N at a time (default 3), each in its
# own Herdr tab; full output per run lands in the directory printed at the end.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
parallel=3 setups=() scenarios=()
while [ $# -gt 0 ]; do
  case "$1" in
    --parallel) parallel=$2; shift 2 ;;
    --setup) setups+=("$2"); shift 2 ;;
    -*) echo "matrix.sh: unknown argument $1" >&2; exit 2 ;;
    *) scenarios+=("$1"); shift ;;
  esac
done
[ ${#setups[@]} -gt 0 ] || setups=("--role coding" "--role mechanical" "--kind codex -- -c model_reasoning_effort=medium")
if [ ${#scenarios[@]} -eq 0 ]; then
  for d in "$here"/scenarios/*/; do scenarios+=("$(basename "$d")"); done
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/hc-matrix.XXXXXX")

jobs=$out/jobs
: >"$jobs"
for s in "${scenarios[@]}"; do
  for i in "${!setups[@]}"; do
    printf '%s\t%s\t%s\n' "$s" "$i" "${setups[$i]}" >>"$jobs"
  done
done
# shellcheck disable=SC2016
tr '\n' '\0' <"$jobs" | xargs -0 -P "$parallel" -I{} bash -c '
  IFS=$(printf "\t") read -r s i setup <<<"$1"
  # shellcheck disable=SC2086
  "$2/run.sh" "$s" $setup >"$3/$s.$i.txt" 2>&1
' _ {} "$here" "$out"

cell() { # result file -> table cell
  local f=$1 line
  line=$(head -1 "$f" 2>/dev/null)
  case "$line" in
    PASS*) printf 'PASS · %s' "$(printf '%s' "$line" | awk -F' · ' '{print $(NF-1)" · "$NF}')" ;;
    FAIL*) printf '**FAIL** · %s' "$(grep -m1 'FAIL  ' "$f" | sed 's/^ *FAIL  //')" ;;
    *) printf 'no result' ;;
  esac
}
printf '| Scenario |'
for s in "${setups[@]}"; do printf ' `%s` |' "$s"; done
printf '\n|---|'
for _ in "${setups[@]}"; do printf -- '---|'; done
printf '\n'
for s in "${scenarios[@]}"; do
  printf '| %s |' "$s"
  for i in "${!setups[@]}"; do printf ' %s |' "$(cell "$out/$s.$i.txt")"; done
  printf '\n'
done
echo
echo "runs: $out"
! grep -l '^FAIL' "$out"/*.txt >/dev/null 2>&1
