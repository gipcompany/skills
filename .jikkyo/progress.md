issue: https://github.com/gipcompany/skills/issues/54
branch: worktree-jikkyo-54-20261116-010238
updated: 2026-11-16T01:06:00+09:00
next: live /kabeuchi run on throwaway issue #60 with the check answered yes

## Todos

- [x] Set up plugin wrapper and two targets with fenced examples (setup has no code commit; logged in this commit)
- [ ] Live /kabeuchi run on throwaway issue (check: yes)
- [ ] Live /kabeuchi run on local file (check: no)
- [ ] Close throwaway issue, delete log, open PR closing #54, tick box

## Verified task-list items

- Items 1-9: ticked by the earlier run (PR #56, merged); not re-verified here.

## Dead ends and decisions

- The installed ~/.claude/skills/kabeuchi is older than main (no grilled-line.sh), so the live runs load this worktree's skills/kabeuchi through a temp plugin dir (--plugin-dir) instead; the personal install is left alone.
- Throwaway target: issue #60. Local target: a markdown file under /tmp, outside the repo. Both carry one backtick-fenced and one tilde-fenced example of the line.
- The live runs are driven in tmux, with this session answering as the user.
- Worktree sessions refuse compound git commands, so each git step runs as its own command.
