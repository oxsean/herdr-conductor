#!/bin/bash
# checkin: the worker wrote a CHECK-IN: design first, and watch.sh raised CHECKIN for it, unless
# the whole turn ended within one poll, when DONE wins and the design is read in the report.
. "$(dirname "$0")/../../lib/checks.sh"
wrote_checkin
if grep -q '^CHECKIN ' "$EVENTS"; then pass "watch.sh raised CHECKIN"
elif [ "$(head -1 "$EVENTS" | awk '{print $1}')" = DONE ] && [ -s "$CHECKIN_FILE" ]; then
  note "finished within one poll: no CHECKIN event, the check-in file is there"
else failc "watch.sh never raised CHECKIN"; fi
commits_ahead_at_least 1
worktree_clean
tests_pass
report_has_sections
