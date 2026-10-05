#!/bin/bash
# Start one worker agent in the conductor's tab and point it at its brief.
#
#   spawn.sh --name NAME (--role ROLE | --kind KIND) --dir DIR --label LABEL --brief FILE
#            [--pane PANE] [--anchor PANE] [--trust] [-- AGENT_ARGS...]
#
# --role takes the agent kind, model and effort from the merged configuration (config.py agent
# ROLE --dir DIR); AGENT_ARGS after -- are appended, e.g. -- --resume <session>. --kind with
# AGENT_ARGS starts an agent without the configuration.
# Without --pane it takes the first pane labelled "free" in the anchor's tab, else
# splits the next grid slot: ① right of the anchor (anchor keeps 40%), ② under ①,
# ③ right of ①, ④ right of ②, and prefixes LABEL with the slot. A fifth worker is
# refused, and so is a tab holding panes that are neither workers nor free slots: pass --pane.
# --trust answers Claude's folder-trust dialog, only for a git worktree whose .claude/ and
# .mcp.json carry no uncommitted changes (what it trusts is the branch's committed config).
# Prints {"name","pane","tab","session"} as JSON on success; record the session id: a worker that
# exits early is brought back with -- --resume <session> (claude) instead of a fresh brief.
# On failure before the agent starts, a pane it split is closed and a reused one is labelled free again.
set -euo pipefail

name= kind= role= dir= label= brief= pane= anchor="${HERDR_PANE_ID:-}" trust=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name=$2; shift 2 ;;
    --kind) kind=$2; shift 2 ;;
    --role) role=$2; shift 2 ;;
    --dir) dir=$2; shift 2 ;;
    --label) label=$2; shift 2 ;;
    --brief) brief=$2; shift 2 ;;
    --pane) pane=$2; shift 2 ;;
    --anchor) anchor=$2; shift 2 ;;
    --trust) trust=1; shift ;;
    --) shift; break ;;
    *) echo "spawn.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
if [ -n "$role" ]; then
  [ -z "$kind" ] || { echo "spawn.sh: pass --role or --kind, not both" >&2; exit 2; }
  [ -d "$dir" ] || { echo "spawn.sh: no directory $dir" >&2; exit 2; }
  resolved=$(python3 "$(cd "$(dirname "$0")" && pwd)/config.py" agent "$role" --dir "$dir") || exit 2
  kind=$(printf '%s\n' "$resolved" | head -1)
  role_args=()
  while IFS= read -r a; do role_args+=("$a"); done < <(printf '%s\n' "$resolved" | tail -n +2 | sed '/^$/d')
  set -- ${role_args[@]+"${role_args[@]}"} "$@"
fi
for v in name kind dir label brief anchor; do
  [ -n "${!v}" ] || { echo "spawn.sh: --$v is required" >&2; exit 2; }
done
[ -d "$dir" ] || { echo "spawn.sh: no directory $dir" >&2; exit 2; }
[ -s "$brief" ] || { echo "spawn.sh: empty or missing brief $brief" >&2; exit 2; }
brief=$(cd "$(dirname "$brief")" && pwd)/$(basename "$brief")
dir=$(cd "$dir" && pwd)
if herdr agent get "$name" >/dev/null 2>&1; then
  echo "spawn.sh: an agent named $name already runs in this Herdr; pick another name (<topic>-<card>)" >&2; exit 2
fi
marks=${XDG_STATE_HOME:-$HOME/.local/state}/herdr-conductor
mkdir -p "$marks"
here=$(cd "$(dirname "$0")" && pwd)

mtime() { python3 -c 'import os, sys; p = sys.argv[1]; print(int(os.path.getmtime(p)) if os.path.exists(p) else 0)' "$1"; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

split() { # split PANE DIRECTION RATIO -> new pane id
  herdr pane split "$1" --direction "$2" --ratio "$3" --cwd "$dir" --env HERDR_CONDUCTOR_ROLE=worker --no-focus \
    | json 'd["result"]["pane"]["pane_id"]'
}

fresh=0 reused=0 started=0
cleanup() {
  [ "$started" = 1 ] && return
  if [ "$fresh" = 1 ]; then herdr pane close "$pane" >/dev/null 2>&1 || true
  elif [ "$reused" = 1 ]; then herdr pane rename "$pane" "free" >/dev/null 2>&1 || true
  fi
}
trap 'rc=$?; [ $rc = 0 ] || cleanup; exit $rc' EXIT

if [ -z "$pane" ]; then
  layout=$(herdr pane layout --pane "$anchor")
  panes=$(herdr pane list --workspace "${anchor%%:*}")
  tab=$(printf '%s' "$layout" | json 'd["result"]["layout"]["tab_id"]')
  pick=$(LAYOUT=$layout PANES=$panes python3 - "$anchor" "$tab" <<'EOF'
import json, os, sys
anchor, tab = sys.argv[1], sys.argv[2]
slots = "①②③④"
FREE = ("free", "空位")  # 空位: the label earlier versions used
layout = json.loads(os.environ["LAYOUT"])["result"]["layout"]
listed = {p["pane_id"]: p for p in json.loads(os.environ["PANES"])["result"]["panes"] if p["tab_id"] == tab}
label = lambda p: listed.get(p["pane_id"], {}).get("label") or ""
others = [p for p in layout["panes"] if p["pane_id"] != anchor]
workers = [p for p in others if label(p)[:1] in slots or label(p).startswith(FREE)]
strays = [p["pane_id"] for p in others if p not in workers]
if strays:
    print("stray", ",".join(strays)); sys.exit()
xs = sorted({p["rect"]["x"] for p in workers})
top = min((p["rect"]["y"] for p in workers), default=0)
slot = lambda p: slots[xs.index(p["rect"]["x"]) * 2 + (p["rect"]["y"] != top)]
free = [p for p in workers if label(p).startswith(FREE) and not listed[p["pane_id"]].get("agent")]
if free:
    print("reuse", slot(free[0]), free[0]["pane_id"]); sys.exit()
key = lambda p: (p["rect"]["y"], p["rect"]["x"])
n = len(workers)
if n == 0:
    print("split", slots[0], anchor, "right", 0.4)
elif n == 1:
    print("split", slots[1], workers[0]["pane_id"], "down", 0.5)
elif n == 2:
    print("split", slots[2], min(workers, key=key)["pane_id"], "right", 0.5)
elif n == 3:
    bottom = max(p["rect"]["y"] for p in workers)
    print("split", slots[3], min((p for p in workers if p["rect"]["y"] == bottom), key=key)["pane_id"], "right", 0.5)
else:
    print("full")
EOF
)
  set -- $pick "$@"
  case "$1" in
    reuse) label="$2 $label"; pane=$3; reused=1; shift 3 ;;
    split) label="$2 $label"; pane=$(split "$3" "$4" "$5"); fresh=1; shift 5 ;;
    full) echo "spawn.sh: tab $tab already holds four workers; open another tab or free a slot" >&2; exit 3 ;;
    stray) echo "spawn.sh: tab $tab holds panes that are not workers ($2); pass --pane" >&2; exit 3 ;;
  esac
fi

if [ "$fresh" = 0 ]; then
  herdr pane run "$pane" "cd '${dir//\'/\'\\\'\'}' && export HERDR_CONDUCTOR_ROLE=worker" >/dev/null
fi
herdr pane rename "$pane" "$label" >/dev/null
rm -f "$marks/$name".*

t0=$(date +%s)
# ⚠️ A pane whose shell is still starting (or still running the cd above) is "not an available shell".
for _ in $(seq 15); do
  start_out=$(herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 90000 -- "$@" 2>&1) || true
  printf '%s' "$start_out" | grep -q '"agent_pane_busy"' || break
  sleep 1
done
if printf '%s' "$start_out" | grep -q '"agent_not_ready"'; then
  started=1
  screen=$(herdr agent read "$name" --source visible --lines 40)
  if printf '%s' "$screen" | grep -q 'trust this folder'; then
    if [ "$trust" = 0 ]; then
      echo "spawn.sh: $name waits on the folder-trust dialog; pass --trust for a worktree you created, or ask the user" >&2; exit 4
    fi
    if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      || [ -n "$(git -C "$dir" status --porcelain -- .claude .mcp.json)" ]; then
      echo "spawn.sh: $dir is not a git worktree or has uncommitted .claude/ or .mcp.json changes; show them to the user before trusting" >&2; exit 4
    fi
    # ⚠️ Claude lists "No, exit" first with the cursor on it: move, then confirm only on the "Yes" line.
    herdr agent send-keys "$name" down >/dev/null
    sleep 0.5
    if herdr agent read "$name" --source visible --lines 40 | grep -q '❯ *Yes, I trust'; then
      herdr agent send-keys "$name" enter >/dev/null
    else
      herdr agent send-keys "$name" up >/dev/null
      herdr agent read "$name" --source visible --lines 40 >&2
      echo "spawn.sh: the trust dialog changed; answer it by hand (screen above)" >&2; exit 4
    fi
  else
    printf '%s\n' "$screen" >&2
    echo "spawn.sh: $name is blocked at startup (screen above); answer it, then: herdr agent prompt $name \"Read your brief $brief and carry it out.\"" >&2
    exit 4
  fi
elif printf '%s' "$start_out" | grep -q '"result"'; then
  started=1
else
  printf '%s\n' "$start_out" >&2
  exit 5
fi

# ⚠️ Herdr may report "blocked" for a moment after the trust dialog closes; settle on the screen, not one reading.
for _ in 1 2 3 4 5 6; do
  status=$(herdr agent wait "$name" --timeout 30000 | json 'd["result"]["agent"]["agent_status"]') || status=unknown
  [ "$status" = idle ] || [ "$status" = done ] && break
  sleep 2
  status=$(herdr agent get "$name" | json 'd["result"]["agent"]["agent_status"]')
  [ "$status" = idle ] || [ "$status" = done ] && break
done
if [ "$status" != idle ] && [ "$status" != done ]; then
  herdr agent read "$name" --source visible --lines 40 >&2
  echo "spawn.sh: $name is $status, not ready; answer it, then: herdr agent prompt $name \"Read your brief $brief and carry it out.\"" >&2
  exit 4
fi

seq_now() { herdr agent get "$name" | json 'd["result"]["agent"].get("completion_seq", -1)'; }
session_now() { herdr agent get "$name" | json '(d["result"]["agent"].get("agent_session") or {}).get("value", "")'; }
find_transcript() { python3 "$here/transcript.py" find "$kind" "${session:--}" --cwd "$dir" --since "$t0"; }
prompts_in() { if [ -n "$1" ]; then python3 "$here/transcript.py" prompts "$kind" "$1"; else echo 0; fi; }
# ⚠️ Some agents (Codex) carry a completion_seq from startup: only completions after the brief count.
seq_now >"$marks/$name.seq"
session=$(session_now)
f=$(find_transcript)
asked=$(prompts_in "$f")
# CHECK-IN and compaction are looked for only in what the worker writes after its brief.
if [ -n "$f" ]; then wc -c <"$f" | tr -d ' ' >"$marks/$name.offset"; else echo 0 >"$marks/$name.offset"; fi
# A check-in is a file beside the brief; watch.sh reports it when it is written after this point.
checkin=${brief%.*}.checkin.md
printf '%s %s\n' "$(mtime "$checkin")" "$checkin" >"$marks/$name.checkin"
# ⚠️ Claude Code wraps long pasted text in <pasted_content>, marked as possibly not the user's own
# words. The prompt is one short line of the user's own, pointing at the brief file.
lead="You are a worker started by a conductor session. Your brief is the file $brief: read all of it now and carry it out as your instructions for this session."
submit() { herdr agent prompt "$name" "$lead" --wait --until working --until blocked --timeout 30000 >/dev/null 2>&1 || true; }
delivered() { # the transcript holds a new prompt; agents without one: Herdr saw a turn start
  case "$kind" in
    claude|codex)
      for _ in 1 2 3 4 5 6 7 8; do
        session=${session:-$(session_now)}
        f=$(find_transcript)
        [ "$(prompts_in "$f")" -gt "$asked" ] && return 0
        sleep 2
      done
      return 1 ;;
    *) status=$(herdr agent get "$name" | json 'd["result"]["agent"]["agent_status"]')
      [ "$status" = working ] || [ "$status" = blocked ] ;;
  esac
}
# ⚠️ Codex reports idle while its start-up screen still swallows input, and its spinning title
# reads as working: only the transcript proves the brief arrived. Sent again once, only when it did not.
submit
if ! delivered; then
  submit
  if ! delivered; then
    herdr agent read "$name" --source visible --lines 40 >&2
    echo "spawn.sh: $name did not take its brief; look at the screen above, then: herdr agent prompt $name \"Read your brief $brief and carry it out.\"" >&2
    exit 4
  fi
fi
tab=$(herdr pane get "$pane" | json 'd["result"]["pane"]["tab_id"]')
if [ -z "$session" ] && [ -n "$f" ] && [ "$kind" = codex ]; then
  session=$(python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).readline())["payload"]["id"])' "$f")
fi
[ -n "$session" ] && printf '%s\n' "$session" >"$marks/$name.session"
printf '{"name":"%s","pane":"%s","tab":"%s","session":"%s"}\n' "$name" "$pane" "$tab" "$session"
