issue: https://github.com/gipcompany/skills/issues/46
branch: worktree-jikkyo-46-20261115-213256
updated: 2026-11-15T21:41:21+09:00
next: README: say the estimate does not count down, pinned in run.sh

## Todos

- [x] place(): JIKKYO_NO_PERL switch, per-path docs, tests for both paths (a597c04)
- [x] Fix stale mktemp/mv comment in report.sh (1f44c76)
- [x] Rewrap report.sh comment near line 72 and SKILL.md settings paragraph (d21b581)
- [x] SKILL.md step 4/5 wording and CLAUDE_SESSION_ID pin in run.sh (2f70a53)
- [ ] README: estimate does not count down + assert_has
- [ ] Check: run.sh passes (0 failed)
- [ ] Check: shellcheck passes
- [ ] Delete progress log and open the PR

## Verified task-list items

- place() without perl is untested, and the docs overstate it: run.sh passes with the new [perl] and [noperl] cases; ignoring JIKKYO_NO_PERL makes the [noperl] symlink assertion fail
- A stale comment: report.sh publish() comment now says mktemp and place(); grep finds no other stale mention
- Wrapping: the report.sh state-file comment block and the SKILL.md settings paragraph are greedily refilled to 80 columns (line lengths checked); run.sh 749 passed, 0 failed
- SKILL.md step 4/5 wording after substitution: exact wording in steps 4 and 5, run.sh asserts both and pins the CLAUDE_SESSION_ID lines; 750 passed, 0 failed; an extra mention of the variable makes the pin fail

## Dead ends and decisions

- The directory and symlink-to-directory cases run in a loop over both paths, labeled [perl] and [noperl], instead of duplicating the block.
- shellcheck is not installed locally; it is run through npx for the shellcheck check.
- Worktree-isolated sessions refuse compound git commands; git add, commit, and push run as separate calls.
- The SKILL.md refreshInterval pin in run.sh relied on the old line break; it is split into two phrases that each sit on one line after the refill.
- The pin compares the grep output of CLAUDE_SESSION_ID in SKILL.md with the exact three lines, which also catches the bare $CLAUDE_SESSION_ID spelling.
