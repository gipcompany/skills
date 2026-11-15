issue: https://github.com/gipcompany/skills/issues/53
branch: worktree-jikkyo-53-20261115-205012
updated: 2026-11-15T20:51:19+09:00
next: map the re-check-failed flow to the not-yet-ready tail in the status-line table

## Todos

- [x] State the re-check-failed rule in SKILL.md and ready-for-goal.md in the same words (594bedc)
- [ ] Map the flow to the not-yet-ready tail in the status-line table
- [ ] Align README Known gaps and status-line tail descriptions
- [ ] Delete progress log and open the PR

## Verified task-list items

- SKILL.md and ready-for-goal.md state the rule in the same words: both carry the identical sentence for a last check that failed after an earlier one completed; kabeuchi tests pass

## Dead ends and decisions

- "When the check ran" became "when the last check of the session completed", so it no longer overlaps the new case.
- Reading the reply also points to the new rule, since that is where a failed re-check is first handled.
