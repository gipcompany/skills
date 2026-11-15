issue: https://github.com/gipcompany/skills/issues/54
branch: worktree-jikkyo-54-20261115-211754
updated: 2026-11-15T21:21:32+09:00
next: AC4, say the line is not a trust signal

## Todos

- [x] Start the progress log (f15de66)
- [x] AC1: rename the target's line to "grilled line" (662f59e)
- [x] AC2: README says "reaches Phase 3" (234a1bb)
- [x] AC3: add the fourth tail "not yet ready for /goal." (f5d8ab8)
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
- AC3 (never points at a missing Known gaps): fourth tail added to the tail table, examples, exact pattern, SKILL.md, README and tests; the rejected-diff case now uses it; tests pass

## Dead ends and decisions

- Kept one short pointer to Claude Code's status line in SKILL.md and README; with distinct names it only helps the reader.
- The case where the re-check fails twice after gaps were left open is left to #53, as the issue says.
