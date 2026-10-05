# <topic>: conductor ledger

Conductor: <Claude session id> · started <YYYY-MM-DD> · conductor tab `<tab id>` · briefs `<ledger name>-briefs/`

Only the conductor edits this ledger; workers report status, cuts and handoffs, and the conductor copies them in.

## Goal

- Deliver: <one sentence>
- Done when: <a checkable result>
- Check in with the user: <decision points, places that need an account or authorization>
- Authorization: <what the user explicitly allowed: push or not, until when, which machines; anything not written here is asked first>
- Notify: <the session's push tool / herdr notification / none>
- Goal line: <the /goal the user pasted, or none>

## Integration rules

Copied from the project's own instructions (AGENTS.md / CLAUDE.md / README); every brief points here.

- Validation: <gate command; output redirected to a file, exit status read from it>
- Conductor re-runs after merging: <what the project requires; or "not on a fast-forward to the tree the worker validated">
- Test tiers: <what runs normally, what on high risk, what only when the user asks>
- Merge: <who merges, into which branch, fast-forward or cherry-pick>
- Install / deploy: <commands; conductor only>
- Push: <allowed or not; what to check first (names that must not go public, secrets)>
- Never touch: <directories, services, containers, real data, credential files>
- Setup for each new clone / worktree: <e.g. hooks path>

## Roles

From `config.py show`; the values this job uses.

| Role | Kind | Model / effort | Used for |
|---|---|---|---|
| coding | claude | opus / high | cards with a clear contract |
| review | claude | fable / high | `pipeline.review = checkin`: cards marked check-in |

Acceptance: <conductor / role> · Coding workers at once: <n> · Merge: <strategy>, revalidate <always / changed-tree>

## Cards

| Card | Content | Depends on | Scope | Done when | Acceptance | Check-in | Role | Review | Worker | Base | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **C1** | | — | `<dirs or files>` | | UI walk / CLI / API / migration | yes / no | coding | yes / no | | `<base commit>` | todo |

Status is "todo / running / to accept / done · <commits> / deferred"; when done, add the commits and where it is installed. Cards whose Scopes overlap run one after another.

## Roster

| Name | Role | Model / effort | Slot · pane | Session id | Dir · branch | Brief | State | Rework count |
|---|---|---|---|---|---|---|---|---|
| `x-c1` | coding | opus / high | ① `w1:p2` | `<session from spawn.sh>` | `~/dev/x-c1` · `feat/x-c1` | `x-c1.md` | running | 0 |

Session id and pane stay useful after a worker exits: Herdr forgets the name, and `last.sh --session`, `release.sh --pane` and `--resume` rely on them. Rework count = acceptance failed, sent back, or replaced for quality; at wrap-up it shows whether roles were chosen well.

## Cut and deferred

| Feature | Handling | Reason | Decided by | State |
|---|---|---|---|---|

Anything planned and not done this time (cut, deferred, done another way) gets a row here and is reported separately as "what was cut". A feature brought back changes its State; rows are never deleted.

## Notes

Appended by time: what merged, where it is installed, problems and how they were handled, items waiting on the user.
