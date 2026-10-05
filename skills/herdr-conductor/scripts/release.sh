#!/bin/bash
# End a worker and free its slot.
#
#   release.sh NAME [--close]
#   release.sh --pane PANE [--close]
#
# Exits the agent if it still runs, ends its watch, moves the pane's shell to $HOME (its
# worktree can then be removed) and labels the pane "free" for the next worker; --close closes
# the pane instead. --pane frees or closes a pane whose agent is already gone.
set -euo pipefail
name= pane= close=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pane) pane=$2; shift 2 ;;
    --close) close=1; shift ;;
    -*) echo "release.sh: unknown argument $1" >&2; exit 2 ;;
    *) name=$1; shift ;;
  esac
done
[ -n "$name$pane" ] || { echo "usage: release.sh NAME|--pane PANE [--close]" >&2; exit 2; }
marks=${XDG_STATE_HOME:-$HOME/.local/state}/herdr-conductor

field() { python3 -c 'import json,sys; a=json.load(sys.stdin)["result"][sys.argv[1]]; print(a.get(sys.argv[2]) or "")' "$@"; }

if [ -n "$name" ]; then
  if info=$(herdr agent get "$name" 2>/dev/null); then
    kind=$(printf '%s' "$info" | field agent agent)
    pane=$(printf '%s' "$info" | field agent pane_id)
    status=$(printf '%s' "$info" | field agent agent_status)
    # ⚠️ A busy agent queues /exit behind its turn, and a blocked one refuses prompts: clear both first.
    case "$status" in
      working) herdr agent send-keys "$name" esc >/dev/null 2>&1 || true
        herdr agent wait "$name" --timeout 20000 >/dev/null 2>&1 || true ;;
      idle|done) ;;
      *) herdr agent send-keys "$name" esc >/dev/null 2>&1 || true; sleep 0.5
        herdr agent send-keys "$name" esc >/dev/null 2>&1 || true; sleep 1 ;;
    esac
    case "$kind" in
      claude) herdr agent prompt "$name" "/exit" >/dev/null 2>&1 || true ;;
      codex) herdr agent prompt "$name" "/quit" >/dev/null 2>&1 || true ;;
    esac
    for i in $(seq 30); do
      herdr agent get "$name" >/dev/null 2>&1 || break
      if [ "$i" = 10 ] || [ "$i" = 20 ]; then
        herdr agent send-keys "$name" ctrl+c >/dev/null 2>&1 || true; sleep 0.3
        herdr agent send-keys "$name" ctrl+c >/dev/null 2>&1 || true
      fi
      sleep 1
    done
    if herdr agent get "$name" >/dev/null 2>&1; then
      echo "release.sh: $name is still running in $pane; look at it with: herdr agent read $name --source visible" >&2
      exit 1
    fi
  elif [ -z "$pane" ]; then
    echo "release.sh: Herdr has no agent $name; free its pane with: release.sh --pane <pane from the roster> [--close]" >&2
    exit 1
  fi
  old=$(cat "$marks/$name.watch" 2>/dev/null || true)
  if [ -n "$old" ] && ps -p "$old" -o command= 2>/dev/null | grep -q 'watch\.sh'; then kill "$old" 2>/dev/null || true; fi
  rm -f "$marks/$name".*
fi

occupant=$(herdr pane get "$pane" | field pane agent)
if [ -n "$occupant" ]; then
  echo "release.sh: $pane now runs $occupant; left alone" >&2
  exit 1
fi
if [ "$close" = 1 ]; then
  herdr pane close "$pane" >/dev/null
  echo "closed $pane"
else
  herdr pane run "$pane" "cd ~" >/dev/null
  herdr pane rename "$pane" "free" >/dev/null
  echo "freed $pane"
fi
