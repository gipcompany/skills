issue: https://github.com/gipcompany/skills/issues/53
branch: worktree-jikkyo-53-20261115-205012
updated: 2026-11-15T20:52:07+09:00
next: align the README's Known gaps and status-line tail descriptions

## Todos

- [x] State the re-check-failed rule in SKILL.md and ready-for-goal.md in the same words (594bedc)
- [x] Map the flow to the not-yet-ready tail in the status-line table (73064d8)
- [ ] Align README Known gaps and status-line tail descriptions
- [ ] Delete progress log and open the PR

## Verified task-list items

- SKILL.md and ready-for-goal.md state the rule in the same words: both carry the identical sentence for a last check that failed after an earlier one completed; kabeuchi tests pass
- Status-line table maps the flow to "not yet ready" and limits the "failed twice" row: read the table after the edit; the three tails and the pattern are unchanged; kabeuchi tests pass

## Dead ends and decisions

- "When the check ran" became "when the last check of the session completed", so it no longer overlaps the new case.
- Reading the reply also points to the new rule, since that is where a failed re-check is first handled.
- The new case got its own table row rather than being folded into the "left gaps open" row, so the "failed twice" row's limit reads plainly.
