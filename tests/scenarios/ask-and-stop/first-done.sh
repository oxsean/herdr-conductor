#!/bin/bash
# ask-and-stop, first turn: a question in text, no commits yet, no dialog left open.
. "$(dirname "$0")/../../lib/checks.sh"
commits_ahead_at_least 0
no_commits_yet
asked_in_text
