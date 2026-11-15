issue: https://github.com/gipcompany/skills/issues/48
branch: worktree-jikkyo-48-20261115-173739
updated: 2026-11-15T18:15:00+09:00
next: Run bash skills/kabeuchi/tests/run.sh on the final tree

## Todos

- [x] Say mktemp -d dir holds vote and check briefs (9315cc8)
- [x] Clarify when Known gaps is replaced (662fd72)
- [x] Rewrap SKILL.md paragraphs at 226 and 425 (c905d4d)
- [x] Test voter description has preflight phrases (c8030a0)
- [x] Add gotchas row: check not yet tried in a real session (436af3b)
- [x] State the check's cost in README (7bbb79a)
- [ ] Run tests/run.sh and confirm pass
- [ ] Delete progress log and open PR

## Verified task-list items

- SKILL.md's allowed-commands list says the mktemp -d directory holds the vote briefs and the check briefs: read the edited bullet in SKILL.md
- SKILL.md says Known gaps is replaced only when the check ran; ready-for-goal.md says an incomplete check leaves it and the summary says so: read both edited passages
- Paragraphs around SKILL.md:226 and SKILL.md:425 rewrapped: measured line lengths, all within the surrounding 82-column width
- tests/run.sh fails if the voter description lacks a preflight phrase and passes on the current file: ran it (all pass), then reworded the description temporarily and saw it fail with exit 1, then restored; shellcheck clean
- gotchas.md has a row saying the ready-for-/goal check is not yet tried in a real session: read the new table row; tests still pass (the row does not use "description lacks")
- README's "Ready for /goal at the end" section states the check's cost: read the new sentence; matches ready-for-goal.md (one re-check once the picked gaps are closed)

## Dead ends and decisions

- Worktree session: run git and gh from the worktree root only, never cd to the shared checkout.
- The second over-long line moved from 425 to 429 after the earlier edits; it is the same paragraph the issue names. Single-line paragraphs (e.g. the "only the current agreed state" bullet) are left unwrapped as the issue says.
- The test reads the phrases from the gotchas.md "description lacks" rows rather than hard-coding them, and also asserts SKILL.md's preflight names each, so a new phrase added to the preflight and gotchas is covered without editing the test. New gotchas rows must not use the words "description lacks" for anything else.
