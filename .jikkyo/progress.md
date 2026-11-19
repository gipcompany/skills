issue: https://github.com/gipcompany/skills/issues/72
branch: worktree-jikkyo-72-20261120-043310
updated: 2026-11-20T04:49:23+09:00
next: AC5, a run that ends with no todos ends incomplete (report.sh final_state)

## Todos
- [x] AC1: incomplete state when todos not all completed (299df03)
- [ ] AC2: precheck.sh --body refuses issue with no task-list item
- [ ] AC3: ordered marker example in tick instruction
- [ ] AC4: unconditional todo instruction, resume todos per item
- [ ] AC5: no todos ends incomplete
- [ ] AC6: incomplete is resumable
- [ ] AC7: docs and stopped glyph cover incomplete
- [ ] AC8: jikkyo: todos line and closing-summary sentence
- [x] AC9: statusline.sh shows incomplete (299df03)
- [ ] AC10: tests/run.sh coverage for new cases
- [ ] Run CI checks, delete log, open PR

## Verified task-list items
- A run whose stream ends with a non-error result line but whose non-deleted todos are not all completed ends incomplete: new end-state tests in tests/run.sh (some pending, in progress, deleted ignored, Japanese 未完了); full suite 883/0 and shellcheck clean
- statusline.sh shows an incomplete run like the other ended states: state-file loops for incomplete in en and ja (5-minute window), end-to-end runs through report.sh showing incomplete and 未完了; full suite 883/0

## Dead ends and decisions
- AC1 and AC9 are one commit: the status-line end-to-end tests run report.sh, so they flip together.
- Existing tests with open todos and a success result now expect incomplete when they test progress, language, or the estimate; tests about a clean run complete their todo so they still test finished.
- The --payload tests build a running body from an ended one with a generic as_running helper (any ended state, and the stopped glyph back to the in-progress one).
- AC1 alone keeps a run with zero todos finished; AC5 adds that guard as its own step.
