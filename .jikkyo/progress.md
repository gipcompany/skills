issue: https://github.com/gipcompany/skills/issues/86
branch: worktree-jikkyo-86-20261125-010413
updated: 2026-11-25T01:45:00Z
next: Verify the dropped: line rule, then add the three-option check to tests/run.sh

## Todos
- [x] Start progress log and read kabeuchi files (62d43ee)
- [x] Limit drafted options to three (SKILL.md, voting.md) (b812191)
- [x] Reword question when alternatives push past three (97aacf8)
- [ ] One line naming each dropped option and why
- [ ] Tests cover the new limit; run.sh passes
- [ ] Delete progress log and open PR

## Verified task-list items
- The main session drafts at most three options per question: SKILL.md Phase 2 and voting.md flow step 1 both say "at most three options" (read back with grep)
- Voter alternatives past three trigger a rewording: voting.md flow step 9, "At most three options shown" under Grouping and tallying, and "Never more than three choices" under What the user sees; options keep IDs and are never merged; example vote line checked against tally.sh output; run.sh 260 passed

## Dead ends and decisions
- Every voter backs at most one option, so dropping options with no valid vote always leaves at most three; folding is a rewording for clarity that keeps option IDs, so no vote changes which option it supports.
- Browser not needed for this issue: all work is in repository files.
- Compound shell commands are refused in this worktree session; run git steps one per call.
