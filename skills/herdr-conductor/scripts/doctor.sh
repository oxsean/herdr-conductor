#!/bin/bash
# Check that this machine can conduct: Herdr, its agent integrations and skill, Python, git,
# the agents the configured roles use, and the ledger directory.
#
#   doctor.sh [--dir REPO]
#
# Prints one line per check (ok / warn / FAIL, with the command that fixes it) and exits 1
# when any check fails.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=.
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) repo=$2; shift 2 ;;
    *) echo "doctor.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
tested_herdr=0.9.3
min_claude=2.1.236   # /goal with idle check-ins
claude_home=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
failed=0

ok() { printf 'ok    %s\n' "$1"; }
warn() { printf 'warn  %s\n' "$1"; [ -n "${2:-}" ] && printf '      fix: %s\n' "$2"; return 0; }
fail() { printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      fix: %s\n' "$2"; failed=1; }
older() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }

if [ "${HERDR_CONDUCTOR_ROLE:-}" = worker ]; then
  fail "this session is a worker (HERDR_CONDUCTOR_ROLE=worker); workers never conduct"
fi

if ! command -v herdr >/dev/null; then
  fail "herdr is not installed" "curl -fsSL https://herdr.dev/install.sh | sh   (or: brew install herdr)"
else
  v=$(herdr --version 2>/dev/null | awk '{print $2}')
  if older "$v" "$tested_herdr"; then
    fail "herdr $v is older than $tested_herdr, the version these scripts were checked with" "herdr update"
  else
    ok "herdr $v"
  fi
  if [ "${HERDR_ENV:-}" = 1 ]; then ok "running inside a Herdr pane (${HERDR_PANE_ID:-?})"
  else warn "not inside a Herdr pane: setup checks only; start Claude Code from a pane in herdr to conduct"; fi
fi

if command -v python3 >/dev/null && python3 -c 'import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli' 2>/dev/null; then
  ok "python3 $(python3 -c 'import platform; print(platform.python_version())')"
else
  fail "python3 3.11+ (or python3 with tomli) is required" "brew install python   (or: pip install tomli)"
fi

if command -v git >/dev/null; then ok "git $(git --version | awk '{print $3}')"
else fail "git is not installed"; fi

roles=$(python3 "$here/config.py" show --dir "$repo" 2>"${TMPDIR:-/tmp}/hc-doctor.$$") || roles=
if [ -s "${TMPDIR:-/tmp}/hc-doctor.$$" ]; then
  while IFS= read -r line; do warn "${line#config.py: warning: }"; done <"${TMPDIR:-/tmp}/hc-doctor.$$"
fi
rm -f "${TMPDIR:-/tmp}/hc-doctor.$$"
kinds=$( { echo claude; printf '%s\n' "$roles" | sed -n "s/^roles\.[^.]*\.kind = '\(.*\)'.*/\1/p"; } | sort -u)
if [ -n "$roles" ]; then ok "configuration: $(python3 "$here/config.py" paths --dir "$repo" | cut -d: -f1 | paste -sd'+' -)"
else fail "the configuration does not load" "python3 $here/config.py show --dir $repo"; fi

integrations=$(herdr integration status 2>/dev/null || true)
for k in $kinds; do
  if ! command -v "$k" >/dev/null; then
    fail "$k is used by a configured role but is not installed"
    continue
  fi
  case "$k" in
    claude)
      v=$(claude --version 2>/dev/null | awk '{print $1}')
      if older "$v" "$min_claude"; then warn "claude $v: /goal needs $min_claude or later" "claude update"
      else ok "claude $v"; fi ;;
    codex) ok "codex $(codex --version 2>/dev/null | awk '{print $2}') (experimental as a worker; see docs/agents.md)" ;;
    *) warn "$k workers are untested; watch.sh sees only their screen" ;;
  esac
  line=$(printf '%s\n' "$integrations" | grep -E "^$k( \(experimental\))?:" || true)
  case "$line" in
    *": current"*) ok "herdr integration for $k" ;;
    *outdated*) fail "herdr integration for $k: ${line#*: }" "herdr integration install $k" ;;
    *"not installed"*) fail "herdr integration for $k is not installed: without it Herdr cannot report the worker's session id" "herdr integration install $k" ;;
    "") warn "herdr has no integration for $k: no session id, so no --resume and no transcript reads" ;;
    *) warn "herdr integration for $k: ${line#*: }" ;;
  esac
done

skill=$claude_home/skills/herdr/SKILL.md
if [ ! -e "$skill" ]; then
  fail "the official herdr skill is not installed" "npx skills add herdrdev/herdr --skill herdr -g -a claude-code"
elif command -v herdr >/dev/null && ! herdr --skill 2>/dev/null | cmp -s - "$skill"; then
  warn "the herdr skill differs from the one this herdr binary ships (herdr --skill)" "npx skills update herdr -g   (or: herdr --skill > $skill)"
else
  ok "herdr skill"
fi

if [ -d "$claude_home/projects" ]; then ok "Claude transcripts in $claude_home/projects"
else warn "no $claude_home/projects: last.sh and watch.sh fall back to reading the screen"; fi

dir=$(python3 "$here/config.py" get ledger.dir --dir "$repo" 2>/dev/null || true)
if [ -n "$dir" ] && mkdir -p "$dir" 2>/dev/null && [ -w "$dir" ]; then ok "ledger directory $dir"
else fail "cannot create or write the ledger directory ${dir:-?}" "set [ledger] dir in ~/.config/herdr-conductor/config.toml"; fi

exit $failed
