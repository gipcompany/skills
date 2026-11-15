issue: https://github.com/gipcompany/skills/issues/48
branch: worktree-jikkyo-48-20261115-173739
updated: 2026-11-15T17:55:00+09:00
next: Add a test in tests/run.sh for the voter description's preflight phrases

## Todos

- [x] Say mktemp -d dir holds vote and check briefs (9315cc8)
- [x] Clarify when Known gaps is replaced (662fd72)
- [x] Rewrap SKILL.md paragraphs at 226 and 425 (c905d4d)
- [ ] Test voter description has preflight phrases
- [ ] Add gotchas row: check not yet tried in a real session
- [ ] State the check's cost in README
- [ ] Run tests/run.sh and confirm pass
- [ ] Delete progress log and open PR

## Verified task-list items

- SKILL.md's allowed-commands list says the mktemp -d directory holds the vote briefs and the check briefs: read the edited bullet in SKILL.md
- SKILL.md says Known gaps is replaced only when the check ran; ready-for-goal.md says an incomplete check leaves it and the summary says so: read both edited passages
- Paragraphs around SKILL.md:226 and SKILL.md:425 rewrapped: measured line lengths, all within the surrounding 82-column width

## Dead ends and decisions

- Worktree session: run git and gh from the worktree root only, never cd to the shared checkout.
- The second over-long line moved from 425 to 429 after the earlier edits; it is the same paragraph the issue names. Single-line paragraphs (e.g. the "only the current agreed state" bullet) are left unwrapped as the issue says.
