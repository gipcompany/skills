issue: https://github.com/gipcompany/skills/issues/48
branch: worktree-jikkyo-48-20261115-173739
updated: 2026-11-15T17:45:00+09:00
next: Clarify when the "Known gaps" section is replaced (SKILL.md and ready-for-goal.md)

## Todos

- [x] Say mktemp -d dir holds vote and check briefs (9315cc8)
- [ ] Clarify when Known gaps is replaced
- [ ] Rewrap SKILL.md paragraphs at 226 and 425
- [ ] Test voter description has preflight phrases
- [ ] Add gotchas row: check not yet tried in a real session
- [ ] State the check's cost in README
- [ ] Run tests/run.sh and confirm pass
- [ ] Delete progress log and open PR

## Verified task-list items

- SKILL.md's allowed-commands list says the mktemp -d directory holds the vote briefs and the check briefs: read the edited bullet in SKILL.md

## Dead ends and decisions

- Worktree session: run git and gh from the worktree root only, never cd to the shared checkout.
