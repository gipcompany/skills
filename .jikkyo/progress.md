issue: https://github.com/gipcompany/skills/issues/86
branch: worktree-jikkyo-86-20261125-010413
updated: 2026-11-25T02:10:00Z
next: Delete this log and open the PR closing #86

## Todos
- [x] Start progress log and read kabeuchi files (62d43ee)
- [x] Limit drafted options to three (SKILL.md, voting.md) (b812191)
- [x] Reword question when alternatives push past three (97aacf8)
- [x] One line naming each dropped option and why (40f4c0a)
- [x] Tests cover the new limit; run.sh passes (d729bfe, 899c3b9)
- [ ] Delete progress log and open PR

## Verified task-list items
- The main session drafts at most three options per question: SKILL.md Phase 2 and voting.md flow step 1 both say "at most three options" (read back with grep)
- Voter alternatives past three trigger a rewording: voting.md flow step 9, "At most three options shown" under Grouping and tallying, and "Never more than three choices" under What the user sees; options keep IDs and are never merged; example vote line checked against tally.sh output; run.sh 260 passed
- A dropped option gets one line naming it and why: voting.md defines "dropped: <option-id> — no valid vote (<reason>)" with an example, flow step 10 and SKILL.md require one per dropped option (grep)
- run.sh passes and its SKILL.md/voting.md tie covers the new limit: new "three-option limit" block (limit in both files, dropped: format in both, subsection present, no example over three options, drift fixtures); bash skills/kabeuchi/tests/run.sh 273 passed, 0 failed; shellcheck clean

## Dead ends and decisions
- Every voter backs at most one option, so dropping options with no valid vote always leaves at most three; folding is a rewording for clarity that keeps option IDs, so no vote changes which option it supports.
- Browser not needed for this issue: all work is in repository files.
- Compound shell commands are refused in this worktree session; run git steps one per call.
