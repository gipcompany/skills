issue: https://github.com/gipcompany/skills/issues/41
branch: worktree-jikkyo-41-20261114-192024
updated: 2026-11-14T10:21:52Z
next: update SKILL.md prose to the order complete, push, tick

## Todos

- [x] launch.sh tick and todo instructions: tick only after push (3c17cfa)
- [x] Resume instruction: ticked box with no work behind it (3c17cfa)
- [ ] SKILL.md describes order complete, push, tick
- [ ] tests/run.sh assertions for new wording, suite passes
- [ ] Delete progress log and open PR

## Verified task-list items

- launch.sh's tick and todo instructions say to tick a box only after that todo's commits are pushed: new assertions in tests/run.sh pass
- The resume instruction says what to do with a ticked box that has no work behind it on the branch: new resume assertions in tests/run.sh pass

## Dead ends and decisions

- The resume case keeps the box ticked and redoes the work, because unticking stays forbidden, as the issue says.
- Items with no commits of their own (such as an open draft PR) are ticked once verified, as before.
