issue: https://github.com/gipcompany/skills/issues/54
branch: worktree-jikkyo-54-20261115-211754
updated: 2026-11-15T21:26:39+09:00
next: AC8, rewrap the over-long SKILL.md line

## Todos

- [x] Start the progress log (f15de66)
- [x] AC1: rename the target's line to "grilled line" (662f59e)
- [x] AC2: README says "reaches Phase 3" (234a1bb)
- [x] AC3: add the fourth tail "not yet ready for /goal." (f5d8ab8)
- [x] AC4: say the line is not a trust signal (273dd4a)
- [x] AC5: add scripts/grilled-line.sh with tests (c90e17e)
- [x] AC6: skip no-op writes; write Known gaps and the line together (99162a3)
- [x] AC7: looser wording-test pattern (780356b)
- [ ] AC8: rewrap SKILL.md:420
- [ ] AC9: skip README test outside the repo
- [ ] AC10: live /kabeuchi run on both target kinds
- [ ] Delete the log and open the PR

## Verified task-list items

- AC1 (grilled line naming): grep leaves status line only for Claude Code's status line in SKILL.md, ready-for-goal.md, README.md and tests; tests/run.sh passes
- AC2 (README condition): README now says sessions that reach Phase 3 write the line, matching SKILL.md and ready-for-goal.md; tests pass
- AC3 (never points at a missing Known gaps): fourth tail added to the tail table, examples, exact pattern, SKILL.md, README and tests; the rejected-diff case now uses it; tests pass
- AC4 (not a trust signal): sentence added to README and to the grilled line section of ready-for-goal.md; tests pass
- AC5 (replacement script): scripts/grilled-line.sh added; tests/run.sh covers no line, line at end, moved up, inside backtick and tilde fences, unclosed fence, Known gaps present, running twice, bad keys and timestamps; 164 tests pass, shellcheck clean; a wording drift in a copy of the script fails the docs agreement test
- AC6 (no-op skip, one write-back): conflict-resolution.md loop and flowchart skip an unchanged body and report it; ready-for-goal.md and SKILL.md require one write-back for Known gaps and the line, with the line alone as a second diff after a rejection; reread for consistency, tests pass
- AC7 (malformed lines): collector now uses a loose pattern; new tests show it reports lines with no space, two spaces, or indentation before Grilled; 167 tests pass, shellcheck clean

## Dead ends and decisions

- Kept one short pointer to Claude Code's status line in SKILL.md and README; with distinct names it only helps the reader.
- The case where the re-check fails twice after gaps were left open is left to #53, as the issue says.
- Fence openers are recognised even when indented (conservative: more text counts as content). Wrapped status-line mention missed by AC1 fixed in b9316a3.
