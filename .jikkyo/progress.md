issue: https://github.com/gipcompany/skills/issues/33
branch: worktree-jikkyo-33-20261115-082953
updated: 2026-11-15T08:43:43+0900
next: show a running state file not updated for 15 minutes as stale (AC4)

## Todos

- [x] Pass the session id to launch.sh and report.sh (AC2) (c39cd37)
- [x] report.sh writes the state file atomically (AC1) (be81cd0)
- [x] statusline.sh prints running/ended/none segments (AC3) (3c9eaf8)
- [ ] statusline.sh shows stale running files (AC4)
- [ ] statusline.sh: no network, fast, silent on errors (AC5)
- [ ] Segment wording follows ja/en (AC6)
- [ ] Document both status line setups in README (AC7)
- [ ] Full test suite and shellcheck pass (AC8)
- [ ] Delete the progress log and open the PR

## Verified task-list items

- The skill passes ${CLAUDE_SESSION_ID} to launch.sh in both forms; launch.sh rejects a malformed id and hands it to report.sh: tests/run.sh section "launch.sh and report.sh: the session id" (a stub report.sh records the hand-off for fresh and resumed launches; nine malformed ids refused by both scripts) and the SKILL.md assertions pass; shellcheck clean.
- report.sh writes a state file atomically on every comment write and on exit, with only numbers, the enum state, the language, the session id, and pre-validated URLs: tests/run.sh section "report.sh: the state file" (exact key set, values, no temp file left, written at start/todo/heartbeat/signal under a fake clock, nothing from the issue, result, or gh answer in it, worktree goes to the common dir, unwritable dir does not stop the run) plus a launch.sh integration check; shellcheck clean.
- scripts/statusline.sh prints the running segment (percentage and estimate, or turns), an ended run for 5 minutes after updated, and nothing with no run: tests/run.sh section "statusline.sh" (fake clock; 4m59s shown, 5m gone for each ended state; several runs ordered and joined; other session and null session hidden; found from a linked worktree; end to end from report.sh); shellcheck clean.

## Dead ends and decisions

- Session id is a positional argument right before the URL in both launch.sh forms; report.sh takes it as a leading --session option so its existing optional positionals stay as they were.
- Session id shape: a UUID (hex 8-4-4-4-12, either case), the shape Claude Code uses.
- The resume hand-off test needs its own pushed branch: the shared fixture branch has local commits by then, which launch.sh rightly refuses.
- Worktree-isolated sessions refuse compound shell commands; run git steps one per call.
- The state file's comment URL is rebuilt from the validated owner, repo, number, and a numeric comment id, never taken from gh's answer.
- statusline.sh does not hand the files to jq -R directly: a file with no trailing newline would merge into the next. It feeds jq one "<file name><TAB><contents>" line per file instead, and checks the number against the file name.
- The status line's estimate format is coarse (45s, 12m, 1h 05m) and shows the stored estimate as of the last write, not a countdown.
- tests/run.sh now runs from a scratch git repository, so report.sh's state file never lands in the real checkout's .git.
