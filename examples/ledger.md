# price-strings: conductor ledger

<!-- An example of a filled ledger, for a small job on the tests' calc fixture. -->

Conductor: 7c1e0b52-… · started 2026-10-05 · conductor tab `w1:t3` · briefs `2026-10-05-price-strings-ledger-briefs/`

Only the conductor edits this ledger; workers report status, cuts and handoffs, and the conductor copies them in.

## Goal

- Deliver: order summaries accept prices typed as text ("12,50", "$12.50"), and the total() bug is gone.
- Done when: `python3 -m unittest` passes on main with the three cards merged; `summary(["$1", "2,50"])` gives "2 items, 3.50".
- Check in with the user: if parse_price should accept more currencies than "$".
- Authorization: merge to main locally; no push.
- Notify: herdr notification
- Goal line: `/goal Every card in ~/notes/2026-10/2026-10-05-price-strings-ledger.md is done or deferred with a reason and wrap-up is finished, or a question for me is pending in your last message`

## Integration rules

- Validation: `python3 -m unittest >/tmp/calc-test.log 2>&1; echo $?`
- Conductor re-runs after merging: not on a fast-forward to the tree the worker validated
- Test tiers: unittest only
- Merge: conductor, into main, fast-forward
- Install / deploy: none
- Push: not allowed
- Never touch: nothing beyond the repository
- Setup for each new clone / worktree: none

## Roles

| Role | Kind | Model / effort | Used for |
|---|---|---|---|
| coding | claude | opus / high | C1, C2 |
| mechanical | claude | sonnet / medium | C3 |
| review | codex | default / high | C2 (check-in card) |

Acceptance: conductor · Coding workers at once: 2 · Merge: ff, revalidate changed-tree

## Cards

| Card | Content | Depends on | Scope | Done when | Acceptance | Check-in | Role | Review | Worker | Base | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **C1** | total() adds every price | — | `calc.py` | test_total passes | CLI: unittest | no | coding | no | `ps-c1` | `c60876e` | done · `6c37c01`, merged |
| **C2** | parse_price + summary takes strings | C1 | `calc.py`, `report.py`, `test_calc.py` | new tests pass | CLI: unittest + the summary example | yes | coding | yes | `ps-c2` | `6c37c01` | done · `9a491bd`, merged |
| **C3** | README documents string prices | C2 | `README.md` | example in README runs | CLI: run the example | no | mechanical | no | `ps-c3` | `9a491bd` | running |

## Roster

| Name | Role | Model / effort | Slot · pane | Session id | Dir · branch | Brief | State | Rework count |
|---|---|---|---|---|---|---|---|---|
| `ps-c1` | coding | opus / high | ① `w1:p4` | `b548e34d-…` | `~/dev/calc-c1` · `main-c1` | `ps-c1.md` | released | 0 |
| `ps-c2` | coding | opus / high | ② `w1:p5` | `0c83f1a2-…` | `~/dev/calc-c2` · `main-c2` | `ps-c2.md` | released | 1 |
| `ps-c2-review` | review | codex / high | ③ `w1:p6` | `01a10c68-…` | `~/dev/calc-c2` (read-only) | `ps-c2-review.md` | released | 0 |
| `ps-c3` | mechanical | sonnet / medium | ① `w1:p4` | `4f75cd84-…` | `~/dev/calc-c3` · `main-c3` | `ps-c3.md` | running | 0 |

## Cut and deferred

| Feature | Handling | Reason | Decided by | State |
|---|---|---|---|---|
| currencies other than "$" | deferred | no requirement yet; C2's check-in asked | user | open |

## Notes

- 14:05 C1 merged (ff), unittest 0.
- 14:12 C2 CHECKIN: design matched the card; no correction sent.
- 14:20 C2 review (codex): one should-fix, "12," accepted as 12.0; sent back to ps-c2, rework 1; fixed in `9a491bd`.
- 14:24 C2 accepted and merged; ps-c2 and its reviewer released; C3 started in slot ①.
