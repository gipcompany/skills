issue: https://github.com/gipcompany/skills/issues/86
branch: worktree-jikkyo-86-20261125-010413
updated: 2026-11-25T01:20:00Z
next: Limit drafted options to three in SKILL.md and voting.md

## Todos
- [x] Start progress log and read kabeuchi files
- [ ] Limit drafted options to three (SKILL.md, voting.md)
- [ ] Reword question when alternatives push past three
- [ ] One line naming each dropped option and why
- [ ] Tests cover the new limit; run.sh passes
- [ ] Delete progress log and open PR

## Verified task-list items

## Dead ends and decisions
- Every voter backs at most one option, so dropping options with no valid vote always leaves at most three; folding is a rewording for clarity that keeps option IDs, so no vote changes which option it supports.
- Browser not needed for this issue: all work is in repository files.
- Compound shell commands are refused in this worktree session; run git steps one per call.
