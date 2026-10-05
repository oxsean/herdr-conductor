#!/bin/bash
# ask-and-stop, after the answer: the rename landed under the given name.
. "$(dirname "$0")/../../lib/checks.sh"
commits_ahead_at_least 1
worktree_clean
tests_pass
grep -q 'def grand_total' "$WORKTREE/calc.py" && pass "calc.py defines grand_total" || failc "calc.py has no grand_total"
if grep -nE '(^|[^a-z_])total\(' "$WORKTREE"/*.py; then failc "the old name total( is still called"; else pass "no caller of the old name"; fi
report_has_sections
