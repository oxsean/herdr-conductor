# shellcheck shell=bash
# Checks a scenario's check.sh calls. run.sh exports WORKTREE, MAIN, BASE, BRANCH, KIND, REPORT
# (the worker's last reply), SCREEN (its terminal) and EVENTS (watch.sh events, one per line).
# Each check prints a line; any failure makes the script exit 1 at the end.
failures=0
pass() { printf '  ok    %s\n' "$1"; }
failc() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '  note  %s\n' "$1"; }
trap 'exit $((failures > 0))' EXIT

ahead() { git -C "$WORKTREE" rev-list --count "$BASE..HEAD"; }
commits_ahead_at_least() {
  local n; n=$(ahead)
  [ "$n" -ge "$1" ] && pass "$n commit(s) on $BRANCH" || failc "$n commit(s) on $BRANCH, expected at least $1"
  [ "$(git -C "$MAIN" rev-parse HEAD)" = "$BASE" ] && [ -z "$(git -C "$MAIN" status --porcelain)" ] \
    && pass "main checkout untouched" || failc "main checkout moved or is dirty"
}
no_commits_yet() { [ "$(ahead)" = 0 ] && pass "no commits before the answer" || failc "committed before asking"; }
worktree_clean() {
  local dirty; dirty=$(git -C "$WORKTREE" status --porcelain --untracked-files=no)
  [ -z "$dirty" ] && pass "worktree clean" || failc "uncommitted changes: $dirty"
}
tests_pass() {
  (cd "$WORKTREE" && python3 -m unittest >/dev/null 2>&1) && pass "tests pass" || failc "tests fail on $BRANCH"
}
only_changed() {
  local changed extra
  changed=$(git -C "$WORKTREE" diff --name-only "$BASE..HEAD")
  extra=$(printf '%s\n' "$changed" | grep -vxF -f <(printf '%s\n' "$@") || true)
  [ -z "$extra" ] && pass "changed only: $*" || failc "changed outside the card: $extra"
}
report_has_sections() {
  local missing=
  for s in "What I did" "How I verified" "Status"; do grep -qi "$s" "$REPORT" || missing="$missing, $s"; done
  [ -z "$missing" ] && pass "report has its sections" || failc "report lacks: ${missing#, }"
}
wrote_checkin() { # the check-in file beside the brief, written before the first commit
  local first
  if [ ! -s "$CHECKIN_FILE" ]; then failc "no check-in file"; return; fi
  first=$(git -C "$WORKTREE" log --reverse --format=%ct "$BASE..HEAD" | head -1)
  if [ -n "$first" ] && [ "$(python3 -c 'import os,sys; print(int(os.path.getmtime(sys.argv[1])))' "$CHECKIN_FILE")" -gt "$first" ]; then
    failc "check-in file written after the first commit"
  else pass "wrote its check-in before committing"; fi
}
saw_event() { grep -q "^$1 " "$EVENTS" && pass "watch.sh raised $1" || failc "watch.sh never raised $1"; }
asked_in_text() {
  tail -c 1500 "$REPORT" | grep -q '[?？]' && pass "asked a question in text" || failc "no question in the last reply"
}
