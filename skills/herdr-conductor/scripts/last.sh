#!/bin/bash
# Print what a worker said last.
#
#   last.sh NAME [--lines N]
#   last.sh --session ID [--kind KIND]
#
# A Claude or Codex worker: the text of its replies since the last prompt it was given, read from
# its transcript (complete even when the terminal has scrolled it away). --session reads a
# worker that has exited, by the session id in the roster (--kind defaults to claude). Any
# other kind, or no transcript: the last N lines of its terminal (default 150).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
name= sid= kind= lines=150
while [ $# -gt 0 ]; do
  case "$1" in
    --session) sid=$2; shift 2 ;;
    --kind) kind=$2; shift 2 ;;
    --lines) lines=$2; shift 2 ;;
    -*) echo "last.sh: unknown argument $1" >&2; exit 2 ;;
    *) name=$1; shift ;;
  esac
done
[ -n "$name$sid" ] || { echo "usage: last.sh NAME [--lines N] | last.sh --session ID [--kind KIND]" >&2; exit 2; }

if [ -z "$sid" ]; then
  if ! info=$(herdr agent get "$name" 2>/dev/null); then
    echo "last.sh: Herdr has no agent $name (it exited); use: last.sh --session <session id from the roster>" >&2
    exit 1
  fi
  read -r kind sid < <(printf '%s' "$info" | python3 -c '
import json, sys
a = json.load(sys.stdin)["result"]["agent"]
print(a.get("agent", "?"), (a.get("agent_session") or {}).get("value", "-"))')
fi
kind=${kind:-claude}
marks=${XDG_STATE_HOME:-$HOME/.local/state}/herdr-conductor
# Herdr reports a Codex session only after its first turn; spawn.sh notes the one it found.
if [ "$sid" = - ] && [ -n "$name" ] && [ -s "$marks/$name.session" ]; then sid=$(cat "$marks/$name.session"); fi

f=$(python3 "$here/transcript.py" find "$kind" "$sid")
if [ -n "$f" ]; then
  python3 "$here/transcript.py" reply "$kind" "$f"
  exit 0
fi
if [ -z "$name" ]; then
  echo "last.sh: no transcript for $kind session $sid" >&2; exit 1
fi
herdr agent read "$name" --source recent-unwrapped --lines "$lines"
