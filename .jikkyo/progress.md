issue: https://github.com/gipcompany/skills/issues/72
branch: worktree-jikkyo-72-20261120-043310
updated: 2026-11-20T05:50:00+09:00
next: AC2, precheck.sh --body mode that refuses an issue with no task-list item, run by SKILL.md before the comments check

## Todos
- [x] AC1: incomplete state when todos not all completed (299df03)
- [ ] AC2: precheck.sh --body refuses issue with no task-list item
- [x] AC3: ordered marker example in tick instruction (84eef02)
- [x] AC4: unconditional todo instruction, resume todos per item (4fa3173)
- [x] AC5: no todos ends incomplete (6defc94)
- [x] AC6: incomplete is resumable (5e49d9b)
- [x] AC7: docs and stopped glyph cover incomplete (b1a6126)
- [x] AC8: jikkyo: todos line and closing-summary sentence (d10eb30)
- [x] AC9: statusline.sh shows incomplete (299df03)
- [ ] AC10: tests/run.sh coverage for new cases
- [ ] Run CI checks, delete log, open PR

## Verified task-list items
- A run whose stream ends with a non-error result line but whose non-deleted todos are not all completed ends incomplete: new end-state tests in tests/run.sh (some pending, in progress, deleted ignored, Japanese 未完了); full suite 883/0 and shellcheck clean
- statusline.sh shows an incomplete run like the other ended states: state-file loops for incomplete in en and ja (5-minute window), end-to-end runs through report.sh showing incomplete and 未完了; full suite 883/0
- A run that still ends with no todos ends incomplete: new tests for no todos and for every todo deleted, plus the no-todo turn-count tests in en and ja; full suite 886/0 and shellcheck clean
- incomplete is resumable like interrupted and failed: precheck --resume tests (own, trusted, untrusted, latest wins, later finished takes it out, never blocks a start, --payload refuses it); SKILL.md Phase 3 resumable rule and README updated; full suite 893/0 and shellcheck clean
- The status comment, state line, SKILL.md, and stopped-glyph rule cover incomplete: glyph in report.sh and its TODOS comment, SKILL.md sentence, README sentence, tests/README, and the glyph tests (incomplete shows the stopped glyph, finished keeps an all-completed snapshot, SKILL.md and README sentences checked word for word); full suite 896/0 and shellcheck clean
- report.sh prints jikkyo: todos completed/total next to jikkyo: state, and the incomplete closing summary says which case: tests check the line right after the state line (deleted todos left out, 0/0 with none, failed too) and the SKILL.md sentences in en and ja; full suite 906/0 and shellcheck clean
- The tick instruction's marker examples in launch.sh and SKILL.md include an ordered one: the prompt test checks the launch.sh sentence word for word and the SKILL.md "Who writes the issue body" test checks the ordered example; full suite 907/0 and shellcheck clean
- The todo instruction is unconditional and the resume instruction makes one todo per task-list item, ticked ones included, completed once re-verified: launch.sh prompt tests check both new sentences word for word and that the old conditional and "for what is left" wording are gone; SKILL.md, README, tests/README updated; full suite 910/0 and shellcheck clean

## Dead ends and decisions
- AC1 and AC9 are one commit: the status-line end-to-end tests run report.sh, so they flip together.
- Existing tests with open todos and a success result now expect incomplete when they test progress, language, or the estimate; tests about a clean run complete their todo so they still test finished.
- The --payload tests build a running body from an ended one with a generic as_running helper (any ended state, and the stopped glyph back to the in-progress one).
- AC1 alone kept a run with zero todos finished; AC5 added that guard as its own step. Every todo deleted counts as no todos.
- An ended run can no longer show the in-progress glyph (finished has no in-progress todo), so the todo-list and cap tests that ended with a clean exit now expect the stopped glyph; the live in-progress glyph stays covered by the mid-run write test.
