#!/bin/bash
# fix-bug: one or more commits on the branch, the tests pass, nothing left uncommitted.
. "$(dirname "$0")/../../lib/checks.sh"
commits_ahead_at_least 1
worktree_clean
tests_pass
only_changed calc.py
report_has_sections
