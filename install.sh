#!/bin/bash
# Set up herdr-conductor after Herdr itself is installed:
#   1. Herdr's agent integrations (session ids for --resume and transcript reads)
#   2. the official herdr skill (how to drive Herdr's CLI)
#   3. this plugin, through the Claude Code plugin marketplace
#   4. doctor.sh, which checks the result
#
#   ./install.sh [--codex] [--yes] [--source GITHUB_REPO_OR_PATH]
#
# --codex also installs Herdr's Codex integration (for Codex workers). Each step that changes the
# machine is shown and confirmed first unless --yes. Steps already done are skipped.
set -euo pipefail
source=oxsean/herdr-conductor codex=0 yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --codex) codex=1; shift ;;
    --yes|-y) yes=1; shift ;;
    --source) source=$2; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
run() { # run CMD... after confirmation
  printf '  $ %s\n' "$*"
  if [ "$yes" = 0 ]; then
    read -r -p "  run it? [Y/n] " answer </dev/tty
    case "$answer" in n*|N*) echo "  skipped"; return 0 ;; esac
  fi
  "$@"
}

step "0. Herdr"
if ! command -v herdr >/dev/null; then
  echo "  Herdr is not installed. Install it first, then run this again:"
  echo "    curl -fsSL https://herdr.dev/install.sh | sh     # or: brew install herdr"
  exit 1
fi
echo "  $(herdr --version)"
command -v claude >/dev/null || { echo "  Claude Code (claude) is not installed: https://code.claude.com"; exit 1; }

step "1. Herdr agent integrations"
status=$(herdr integration status 2>/dev/null || true)
targets=(claude)
[ "$codex" = 1 ] && targets+=(codex)
for t in "${targets[@]}"; do
  if printf '%s\n' "$status" | grep -qE "^$t: current"; then echo "  $t: current"
  else run herdr integration install "$t"; fi
done

step "2. Official herdr skill"
skill=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/herdr/SKILL.md
if [ -e "$skill" ] && herdr --skill | cmp -s - "$skill"; then
  echo "  installed, matches $(herdr --version)"
elif command -v npx >/dev/null; then
  run npx -y skills add herdrdev/herdr --skill herdr -g -a claude-code -y
else
  echo "  npx not found: writing the skill this Herdr binary ships"
  run sh -c "mkdir -p '$(dirname "$skill")' && herdr --skill > '$skill'"
fi

step "3. herdr-conductor plugin"
if claude plugin list 2>/dev/null | grep -q 'herdr-conductor@'; then
  echo "  installed (update with: claude plugin update herdr-conductor@herdr-conductor)"
else
  run claude plugin marketplace add "$source"
  run claude plugin install herdr-conductor@herdr-conductor
fi

step "4. Check"
doctor=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/herdr-conductor/herdr-conductor/*/skills/herdr-conductor/scripts/doctor.sh 2>/dev/null | tail -1 || true)
[ -n "$doctor" ] || doctor=$(cd "$(dirname "$0")" && pwd)/skills/herdr-conductor/scripts/doctor.sh
if [ -x "$doctor" ]; then "$doctor" || true
else echo "  run /herdr-conductor:herdr-conductor doctor in Claude Code"; fi

cat <<'EOF'

Next: open herdr, start claude in a pane inside your repository, and say
  "conduct this: <the job>"      (or invoke /herdr-conductor:herdr-conductor)
For a long run, paste the /goal line the conductor offers.
EOF
