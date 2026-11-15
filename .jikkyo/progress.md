issue: https://github.com/gipcompany/skills/issues/49
branch: worktree-jikkyo-49-20261115-174159
updated: 2026-11-15T17:43:12+0900
next: document the three tail cases of the status line

## Todos

- [x] Phase 3 writes the status line after the /goal check, diff first (e955157)
- [ ] Document the three tail cases
- [ ] Replace an existing line; keep it last, after Known gaps
- [ ] Write the line for both target kinds
- [ ] Name the status line in the current-state rule
- [ ] Phase 1/2 treat an existing status line as data
- [ ] Mention the status line in README's kabeuchi section
- [ ] Remove the progress log and open the PR

## Verified task-list items

- SKILL.md Phase 3 writes the status line after the check and before the closing summary, with a diff shown before the write: read the new Phase 3 bullet, references/ready-for-goal.md "When it is written", and flow step 7

## Dead ends and decisions

- The detailed spec lives in references/ready-for-goal.md under "The status line", because the tail depends on the check result; SKILL.md Phase 3 has a short bullet that points to it.
- "Status line" collides with Claude Code's status line (the session marker); SKILL.md says the two are unrelated.
- A declined check still leads to the status line (flow step 1 now jumps to step 7).
- Worktree-isolated session refuses compound shell commands: run git commands one at a time and write the log with the Write tool.
