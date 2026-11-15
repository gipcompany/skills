issue: https://github.com/gipcompany/skills/issues/54
branch: worktree-jikkyo-54-20261115-211754
updated: 2026-11-15T21:20:31+09:00
next: AC3, add the fourth tail

## Todos

- [x] Start the progress log (f15de66)
- [x] AC1: rename the target's line to "grilled line" (662f59e)
- [x] AC2: README says "reaches Phase 3" (234a1bb)
- [ ] AC3: add the fourth tail "not yet ready for /goal."
- [ ] AC4: say the line is not a trust signal
- [ ] AC5: add scripts/grilled-line.sh with tests
- [ ] AC6: skip no-op writes; write Known gaps and the line together
- [ ] AC7: looser wording-test pattern
- [ ] AC8: rewrap SKILL.md:420
- [ ] AC9: skip README test outside the repo
- [ ] AC10: live /kabeuchi run on both target kinds
- [ ] Delete the log and open the PR

## Verified task-list items

- AC1 (grilled line naming): grep leaves status line only for Claude Code's status line in SKILL.md, ready-for-goal.md, README.md and tests; tests/run.sh passes
- AC2 (README condition): README now says sessions that reach Phase 3 write the line, matching SKILL.md and ready-for-goal.md; tests pass

## Dead ends and decisions

- Kept one short pointer to Claude Code's status line in SKILL.md and README; with distinct names it only helps the reader.
