issue: https://github.com/gipcompany/skills/issues/46
branch: worktree-jikkyo-46-20261115-213256
updated: 2026-11-15T21:35:46+09:00
next: fix the stale mktemp/mv comment in report.sh publish()

## Todos

- [x] place(): JIKKYO_NO_PERL switch, per-path docs, tests for both paths (a597c04)
- [ ] Fix stale mktemp/mv comment in report.sh
- [ ] Rewrap report.sh comment near line 72 and SKILL.md settings paragraph
- [ ] SKILL.md step 4/5 wording and CLAUDE_SESSION_ID pin in run.sh
- [ ] README: estimate does not count down + assert_has
- [ ] Check: run.sh passes (0 failed)
- [ ] Check: shellcheck passes
- [ ] Delete progress log and open the PR

## Verified task-list items

- place() without perl is untested, and the docs overstate it: run.sh passes with the new [perl] and [noperl] cases; ignoring JIKKYO_NO_PERL makes the [noperl] symlink assertion fail

## Dead ends and decisions

- The directory and symlink-to-directory cases run in a loop over both paths, labeled [perl] and [noperl], instead of duplicating the block.
- shellcheck is not installed locally; it is run through npx for the shellcheck check.
- Worktree-isolated sessions refuse compound git commands; git add, commit, and push run as separate calls.
