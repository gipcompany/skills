issue: https://github.com/gipcompany/skills/issues/41
branch: worktree-jikkyo-41-20261114-192024
updated: 2026-11-14T10:26:00Z
next: delete this log in one commit, push, and open the PR

## Todos

- [x] launch.sh tick and todo instructions: tick only after push (3c17cfa)
- [x] Resume instruction: ticked box with no work behind it (3c17cfa)
- [x] SKILL.md describes order complete, push, tick (81b7638)
- [x] tests/run.sh assertions for new wording, suite passes (81b7638)
- [ ] Delete progress log and open PR

## Verified task-list items

- launch.sh's tick and todo instructions say to tick a box only after that todo's commits are pushed: new assertions in tests/run.sh pass
- The resume instruction says what to do with a ticked box that has no work behind it on the branch: new resume assertions in tests/run.sh pass
- SKILL.md describes the order complete, push, tick: new SKILL.md assertions in tests/run.sh pass
- bash skills/jikkyo/tests/run.sh passes, with assertions for the new wording: full suite run, 0 failures

## Dead ends and decisions

- The resume case keeps the box ticked and redoes the work, because unticking stays forbidden, as the issue says.
- Items with no commits of their own (such as an open draft PR) are ticked once verified, as before.
- The first push needed --set-upstream because the branch had no upstream yet.
