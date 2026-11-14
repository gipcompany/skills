issue: https://github.com/gipcompany/skills/issues/33
branch: worktree-jikkyo-33-20261115-082953
updated: 2026-11-15T08:36:02+0900
next: make report.sh write the state file under <git common dir>/jikkyo/<N>.json (AC1)

## Todos

- [x] Pass the session id to launch.sh and report.sh (AC2) (c39cd37)
- [ ] report.sh writes the state file atomically (AC1)
- [ ] statusline.sh prints running/ended/none segments (AC3)
- [ ] statusline.sh shows stale running files (AC4)
- [ ] statusline.sh: no network, fast, silent on errors (AC5)
- [ ] Segment wording follows ja/en (AC6)
- [ ] Document both status line setups in README (AC7)
- [ ] Full test suite and shellcheck pass (AC8)
- [ ] Delete the progress log and open the PR

## Verified task-list items

- The skill passes ${CLAUDE_SESSION_ID} to launch.sh in both forms; launch.sh rejects a malformed id and hands it to report.sh: tests/run.sh section "launch.sh and report.sh: the session id" (a stub report.sh records the hand-off for fresh and resumed launches; nine malformed ids refused by both scripts) and the SKILL.md assertions pass; shellcheck clean.

## Dead ends and decisions

- Session id is a positional argument right before the URL in both launch.sh forms; report.sh takes it as a leading --session option so its existing optional positionals stay as they were.
- Session id shape: a UUID (hex 8-4-4-4-12, either case), the shape Claude Code uses.
- The resume hand-off test needs its own pushed branch: the shared fixture branch has local commits by then, which launch.sh rightly refuses.
- Worktree-isolated sessions refuse compound shell commands; run git steps one per call.
