#!/bin/bash
# Watch one worker until something needs the conductor, print one event line, exit 0.
# Run it with Bash run_in_background; re-arm it after handling the event.
#
#   watch.sh NAME [--stall MIN] [--idle MIN] [--context TOKENS] [--every SEC]
#
# Events:
#   DONE NAME SEQ        it finished a turn (or was interrupted) since the last DONE: read it with last.sh
#   CHECKIN NAME FILE    the worker wrote its check-in file (FILE, beside its brief), or a Claude or
#                        Codex reply starting "CHECK-IN:" (FILE is -): read it and keep going
#   IDLE NAME MIN        idle for MIN minutes without finishing a new turn (waiting on its own job, or nothing to do)
#   BLOCKED NAME         a question or approval stays on its screen
#   STALLED NAME MIN     working, but its transcript (Claude, Codex) or screen has not changed for MIN minutes
#   GONE NAME PANE       Herdr no longer knows the agent (exited, crashed, pane closed)
#   HERDR_DOWN NAME      Herdr itself did not answer three times running; the worker may still be fine
#   UNKNOWN NAME MIN     Herdr could not classify it for MIN minutes
#   CONTEXT NAME N       a Claude or Codex worker's context passed N tokens (once per session)
#   COMPACTED NAME       a Claude or Codex worker's context was compacted
#
# DONE compares Herdr's completion_seq with the last one reported for NAME (kept under
# $XDG_STATE_HOME/herdr-conductor, reset by spawn.sh), so a turn that ends between two polls,
# or before the watch starts, is still reported. One watch per worker: a new one ends the old.
set -uo pipefail
name=${1:?usage: watch.sh NAME [--stall MIN] [--idle MIN] [--context TOKENS] [--every SEC]}
shift
stall=20 idle=30 context=250000 every=30
while [ $# -gt 0 ]; do
  case "$1" in
    --stall) stall=$2; shift 2 ;;
    --idle) idle=$2; shift 2 ;;
    --context) context=$2; shift 2 ;;
    --every) every=$2; shift 2 ;;
    *) echo "watch.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
marks=${XDG_STATE_HOME:-$HOME/.local/state}/herdr-conductor
mkdir -p "$marks"

old=$(cat "$marks/$name.watch" 2>/dev/null || true)
if [ -n "$old" ] && ps -p "$old" -o command= 2>/dev/null | grep -q 'watch\.sh'; then kill "$old" 2>/dev/null || true; fi
echo $$ >"$marks/$name.watch"
trap '[ "$(cat "$marks/$name.watch" 2>/dev/null)" = $$ ] && rm -f "$marks/$name.watch"' EXIT

# probe -> "ok status pane kind session completion_seq" | "notfound" | "error"
probe() {
  local out
  out=$(herdr agent get "$name" 2>&1)
  printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    print("error"); sys.exit()
if "result" in d:
    a = d["result"]["agent"]
    seq = a.get("completion_seq")
    print("ok", a.get("agent_status", "unknown"), a.get("pane_id", "-"), a.get("agent", "?"),
          (a.get("agent_session") or {}).get("value", "-"), -1 if seq is None else seq)
elif (d.get("error") or {}).get("code") == "agent_not_found":
    print("notfound")
else:
    print("error")'
}

here=$(cd "$(dirname "$0")" && pwd)
transcript() { # kind session -> path or ""
  local sid=$2
  # Herdr reports a Codex session only after its first turn; spawn.sh notes the one it found.
  if [ "$sid" = - ] && [ -s "$marks/$name.session" ]; then sid=$(cat "$marks/$name.session"); fi
  python3 "$here/transcript.py" find "$1" "$sid"
}

fingerprint() { # kind session -> something that changes while the worker makes progress
  local f
  if f=$(transcript "$1" "$2") && [ -n "$f" ]; then
    wc -c <"$f"
  else
    # ⚠️ The bottom lines carry spinners and timers that change while nothing happens.
    herdr agent read "$name" --source recent-unwrapped --lines 60 2>/dev/null | sed '$d' | sed '$d' | sed '$d' | sed '$d' | cksum
  fi
}

reported=$(cat "$marks/$name.seq" 2>/dev/null || echo -1)
missing=0 errors=0 last_pane=- quiet_since=$(date +%s) idle_since= unknown_since= last_fp=
while :; do
  read -r state status pane kind session seq <<<"$(probe)"
  now=$(date +%s)
  case "$state" in
    notfound) missing=$((missing + 1))
      if [ "$missing" -ge 2 ]; then echo "GONE $name $last_pane"; exit 0; fi
      sleep 3; continue ;;
    ok) missing=0 errors=0 ;;
    *) errors=$((errors + 1))
      if [ "$errors" -ge 3 ]; then echo "HERDR_DOWN $name"; exit 0; fi
      sleep "$every"; continue ;;
  esac
  last_pane=$pane

  case "$status" in
    idle|done) unknown_since=
      if [ "$seq" -gt "$reported" ]; then
        if f=$(transcript "$kind" "$session") && [ -n "$f" ]; then python3 "$here/transcript.py" news "$kind" "$f" "$marks/$name.offset" >/dev/null; fi
        echo "$seq" >"$marks/$name.seq"; echo "DONE $name $seq"; exit 0
      fi
      idle_since=${idle_since:-$now}
      if [ $((now - idle_since)) -ge $((idle * 60)) ]; then echo "IDLE $name $(((now - idle_since) / 60))"; exit 0; fi ;;
    working) unknown_since= idle_since= ;;
    blocked) sleep 3
      read -r state status _ <<<"$(probe)"
      if [ "$state" = ok ] && [ "$status" = blocked ]; then echo "BLOCKED $name"; exit 0; fi
      continue ;;
    *) idle_since= unknown_since=${unknown_since:-$now}
      if [ $((now - unknown_since)) -ge 300 ]; then echo "UNKNOWN $name $(((now - unknown_since) / 60))"; exit 0; fi ;;
  esac

  fp=$(fingerprint "$kind" "$session")
  if [ "$fp" != "$last_fp" ]; then
    last_fp=$fp quiet_since=$now
  elif [ "$status" = working ] && [ $((now - quiet_since)) -ge $((stall * 60)) ]; then
    echo "STALLED $name $(((now - quiet_since) / 60))"; exit 0
  fi

  if [ -s "$marks/$name.checkin" ]; then
    read -r seen checkin <"$marks/$name.checkin"
    m=$(python3 -c 'import os, sys; p = sys.argv[1]; print(int(os.path.getmtime(p)) if os.path.exists(p) else 0)' "$checkin")
    if [ -s "$checkin" ] && [ "$m" -gt "$seen" ]; then
      printf '%s %s\n' "$m" "$checkin" >"$marks/$name.checkin"
      echo "CHECKIN $name $checkin"; exit 0
    fi
  fi
  if f=$(transcript "$kind" "$session") && [ -n "$f" ]; then
    event=$(python3 "$here/transcript.py" news "$kind" "$f" "$marks/$name.offset")
    if [ "$event" = CHECKIN ]; then echo "CHECKIN $name -"; exit 0; fi
    if [ -n "$event" ]; then echo "$event $name"; exit 0; fi
    key=$(basename "$f" .jsonl)
    if [ ! -e "$marks/$key.context" ] && n=$(python3 "$here/transcript.py" context "$kind" "$f") && [ "${n:-0}" -ge "$context" ]; then
      touch "$marks/$key.context"
      echo "CONTEXT $name $n"; exit 0
    fi
  fi
  sleep "$every"
done
