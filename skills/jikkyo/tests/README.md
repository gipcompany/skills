# jikkyo tests

Regression tests for the four scripts that make up everything deterministic in
`jikkyo`: `report.sh`, `launch.sh`, `precheck.sh`, and `cleanup.sh`. The parent
session's part (carrying out what the scripts print, and writing the closing
summary) is prompt-driven, so there is nothing to unit-test there.

Dependencies: `bash`, `git`, and `jq`. `gh` and `claude` are replaced by stubs
on `PATH`, so the suite never touches GitHub and never starts a model.

## Run

```
bash skills/jikkyo/tests/run.sh
```

Exit status is non-zero if any assertion fails; the last line reports
`total: <n> passed, <m> failed`. It takes about 15 seconds, most of it the
timing and signal tests waiting on a real scheduler.

## What is covered

- **`report.sh`, progress** — completed / non-deleted todos, with a deleted
  task and a task added mid-run, shown as a percentage only (`66%`, no
  `<completed>/<total>`) in the heading and the `Progress` row; the % going
  down when tasks are added (75% before the add, 50% after); a
  failed `TaskCreate` and an update to an unknown task id changing nothing; the
  task id read from the result text (`Task #N created`) or from
  `tool_use_result.task.id`; a stream with no todo events showing the turn
  count (subagent messages are not turns) and no % anywhere; lines that are
  not JSON objects, and events of an unexpected shape (string `content`, a
  tool use without an id, a string `tool_use_result`), being skipped instead
  of ending the report — a jq error would kill the child with SIGPIPE.
- **`report.sh`, end states** — `finished` on a success `result`; `failed` on
  `error_max_turns`, `error_during_execution`, or `is_error: true`;
  `interrupted` when the stream has no `result` line, including an empty
  stream. Start and end times are local time with an explicit UTC offset.
- **`report.sh`, the final message** — the `result` text on success, the
  `errors` on an `error_*` subtype, and a no-final-message line when there is
  no `result` line.
- **`report.sh`, where it writes** — the first write is a POST of a new comment
  on the issue, every later write a PATCH of that comment by id; `--edit-last`
  and the issue body are never used; the hidden marker is the first line; a
  create that fails is retried as a create.
- **`report.sh`, when it writes** — against a fake clock (`JIKKYO_CLOCK_FILE`)
  with the stream held open on a FIFO: the start is written before any event;
  a todo change inside the 30-second window is held until the window ends;
  back-to-back changes are coalesced into one write; a heartbeat comes after
  5 minutes without a change, and not before; a change still held when the
  stream ends is in the end write, which happens at once.
- **`report.sh`, estimated time remaining** — against the fake clock, the exact
  `Remaining` row and heading for no todos (empty, no suffix), todos
  with none completed (empty, no suffix), partial progress (1 of 4 after
  150 s gives `~7m 30s (estimate)`, `25%`, and ` · ~7m 30s left`),
  and a finished run (empty, no suffix).
- **`report.sh`, signals** — SIGTERM, SIGHUP, and SIGINT each write
  `interrupted` with an end time before `report.sh` exits (143, 129, 130),
  also when the signal comes after the `result` line.
- **`launch.sh`** — anything that is not exactly a GitHub issue URL is rejected
  with exit 2 before the child or `gh` runs, as is an issue whose repository is
  not a remote of the checkout (a host like `notgithub.com` does not count),
  or a run outside a git repository. The child
  gets `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, `-p '/goal <URL> <todo instruction> <tick instruction>'`
  (one argument: the URL, then the fixed instruction to make `TaskCreate`
  todos up front, one per task-list item when there is one, and complete them
  with `TaskUpdate`, then the fixed instruction to tick each box as soon as
  it is verified, not all at the end, tick only verified boxes, change only `- [ ]` to `- [x]`,
  and fetch the body before each edit),
  `--worktree jikkyo-<N>-<timestamp>`, `--output-format stream-json`,
  `--verbose`, `--permission-mode auto`, and `--disallowedTools` with every
  rule for force pushes, remote-branch deletion, comment edits and deletes,
  and closing or deleting issues — and no rule that blocks a plain
  `git push`. The worktree name, path, and branch are printed before the child
  starts, and the path is under the repository root even from a subdirectory.
- **`precheck.sh`** — `start` with no live run; `refuse <URL>` for a `running`
  comment updated under 15 minutes ago; `rewrite <ids>` for one 15 minutes old
  or more; `--force` rewriting even a live one; `finished`, `failed`, and
  `interrupted` never blocking; comments without the marker or by another
  author not counting; several `--paginate` pages read as one list;
  fractional-second timestamps; empty input or an API error object (a
  failed `gh` listing) giving exit 2 rather than `start`; `--payload` rewriting marker, heading, and
  State row, dropping the heading's ` · ~… left` suffix and emptying the
  `Remaining` row (Elapsed untouched), also for a comment posted in the old
  format (`3/8 (37%)` and a `Remaining (est.)` row, whose label is kept),
  and refusing a comment that is
  not `running`.
- **`cleanup.sh`** — `remove` only for a worktree with no uncommitted changes
  (untracked, modified, and staged files all count) whose HEAD is on a
  remote-tracking branch: pushed, or no new commits. `keep` for an unpushed
  commit, a dirty pushed worktree, a pushed branch with a newer unpushed
  commit, a missing path, a directory that is not a
  worktree, or a path inside one.
- **`SKILL.md`** — `allowed-tools` pins exactly `launch.sh`, `precheck.sh`, and
  `cleanup.sh` under `${CLAUDE_SKILL_DIR}`, with no rule for `claude`, `gh`, or
  `git`, and the skill has no injected commands.
