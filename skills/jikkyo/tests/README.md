# jikkyo tests

Regression tests for the five scripts that make up everything deterministic in
`jikkyo`: `report.sh`, `launch.sh`, `precheck.sh`, `cleanup.sh`, and
`statusline.sh`. The parent
session's part (carrying out what the scripts print, and writing the closing
summary) is prompt-driven, so there is nothing to unit-test there.

Dependencies: `bash`, `git`, and `jq`. `gh` and `claude` are replaced by stubs
on `PATH`, so the suite never touches GitHub and never starts a model. It
runs from a scratch git repository, so the state files `report.sh` writes into
the git common dir never land in the checkout you run it from.

## Run

```
bash skills/jikkyo/tests/run.sh
```

Exit status is non-zero if any assertion fails; the last line reports
`total: <n> passed, <m> failed`. It takes about 40 seconds, most of it the
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
- **`report.sh`, the branch** — with a second argument
  `worktree-jikkyo-12-<8 digits>-<6 digits>`, every write's marker carries
  `branch=<name>` after `state=`, and a `Branch` row (`ブランチ` in Japanese)
  right after State shows it; with no second argument the marker has no
  `branch=` and the row is empty. A branch for another issue number, wrong
  digit counts, another prefix, a newline, ` -->`, `$(…)`, an empty string,
  or a third argument that is not a comment id is exit 2 with no `gh` write.
- **`report.sh`, a resumed run** — with a third argument, the numeric id of
  the earlier run's status comment, a new comment is posted (the earlier one
  is never written), its marker carries the same branch, and a
  `Resumed from` row right after `Branch` links
  `https://github.com/o/r/issues/12#issuecomment-<id>` (`再開元` /
  `前回の実行` in Japanese); a fresh run has no such row; `--payload` on a
  resumed Japanese comment keeps the row. An empty id, `0`, a leading zero,
  letters, a space, `$(…)`, a newline, a URL, or a fourth argument is exit 2
  with no `gh` write.
- **`report.sh`, the language of the issue** — the `gh` stub answers the
  issue read (`gh api repos/o/r/issues/12`, logged apart from the writes) with
  `$GH_ISSUE`. An English issue gives today's English text; Japanese in the
  body, in the title alone, or as halfwidth katakana gives a Japanese heading,
  table header, field names, and state words (running, finished, failed,
  interrupted, and the turn count), with the marker still `v=1` and the
  English state; other non-ASCII text (accented Latin, Korean), a failed
  read, an answer that is not JSON, and an issue with no title or body give
  English. The issue's text never appears in a `gh` argument, the comment,
  or the output, and a `$(…)` in it is never run. The hand-over lines stay
  English apart from `jikkyo: language <ja|en>`.
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
  and a finished run (empty, no suffix); the same in Japanese, where the
  durations keep their format and only the words change.
- **`report.sh`, signals** — SIGTERM, SIGHUP, and SIGINT each write
  `interrupted` with an end time before `report.sh` exits (143, 129, 130),
  also when the signal comes after the `result` line.
- **`report.sh`, the state file** — `<git common dir>/jikkyo/<N>.json` with
  exactly the documented keys (one line of JSON, no temp file left beside
  it): the final state, counts, epoch `started` and `updated`, `eta_secs`,
  `lang`, the `--session` id, and the comment URL rebuilt from a numeric id
  (null, with `session`, when unknown). Against the fake clock it is written
  at the first comment write, on a todo write (with the same estimate as the
  comment, in seconds), on a heartbeat, and as `interrupted` on SIGTERM. A
  Japanese issue records `ja`. Nothing from the issue, the result line, or
  `gh`'s answer (escape sequences included) reaches it. From a linked
  worktree it goes to the shared common dir; outside a git repository, or
  with an unwritable directory, there is no file and the run goes on. A
  `jikkyo/` swapped for a symlink is not written through, nor is a `<N>.json`
  that is a symlink to a directory (no temp file is moved into it or left
  beside it), and an old temp
  file of the issue left by a killed write is removed by the next write
  (another issue's is left).
- **`launch.sh`** — anything that is not exactly a GitHub issue URL is rejected
  with exit 2 before the child or `gh` runs, as is an issue whose repository is
  not a remote of the checkout (a host like `notgithub.com` does not count),
  or a run outside a git repository. The child
  gets `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, `-p '/goal <URL> <todo instruction> <tick instruction> <log instruction>'`
  (one argument: the URL, then the fixed instruction to make `TaskCreate`
  todos up front, one per task-list item when there is one, and complete them
  with `TaskUpdate`, then the fixed instruction to tick each box as soon as
  it is verified, not all at the end, tick only verified boxes, change only `- [ ]` to `- [x]`,
  and fetch the body before each edit, then, last, the fixed instruction to
  keep `.jikkyo/progress.md` in its fixed shape, updating, committing, and
  pushing it after every todo, keeping secrets, environment values, and
  command output out of it, and deleting it in one pushed commit right before
  the PR),
  `--worktree jikkyo-<N>-<timestamp>`, `--output-format stream-json`,
  `--verbose`, `--permission-mode auto`, and `--disallowedTools` with every
  rule for force pushes, remote-branch deletion, comment edits and deletes,
  and closing or deleting issues — and no rule that blocks a plain
  `git push`. The worktree name, path, and branch are printed before the child
  starts, and the path is under the repository root even from a subdirectory.
  That branch is passed to `report.sh`, so it ends up in the comment's
  marker and `Branch` row. A fresh run gets no resume instruction. The run's
  state file lands in the repository's common dir with the session id.
- **`launch.sh --resume`** — against a real bare remote reached through the
  issue's GitHub URL (`url.<file>.insteadOf`, with a thin `git` wrapper that
  shows the GitHub URL in `remote -v` and logs every git command line).
  - Exit 2 before any worktree, child, or `gh` write for missing or extra
    arguments, an empty branch or id (`--resume '' ''` included),
    `--resume` after the URL, a branch for another issue, `main`, ` -->`,
    `$(…)`, a bad comment id, or a URL of another issue.
  - A good resume adds a new worktree `jikkyo-<N>-<timestamp>` on the
    branch at the pushed tip, tracking `origin/<branch>`, prints the
    worktree lines (naming the resumed branch) first, and runs the child
    inside it without `--worktree`, with the same flags and deny list and
    the resume instruction last. The status comment is a new one with the
    same branch and a `Resumed from` row.
  - A `.jikkyo/progress.md` holding a sentinel, `$(…)`, and backticks never
    reaches the child's or any git command line and is never run. Leaving
    out `rev-parse`, the git command lines are exactly these five:
    `remote -v`, `worktree list` (before the fetch), the fetch of the one
    branch, `show-ref`, and `worktree add` (with `core.hooksPath` set to
    `/dev/null`).
  - The tests start with no `GIT_CONFIG_*` variables in the environment.
  - The resumed child runs with `--setting-sources user` right after the
    prompt, with `GIT_CONFIG_*` pointing `core.hooksPath` at `/dev/null`
    and `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, and is told that the project's
    configuration is not loaded and git hooks are off; a fresh run has none
    of these. A branch carrying a hook, an `.mcp.json`, a `.claude`
    symlink, a `CLAUDE.md` symlink, and git hooks is resumed with that
    flag, and launch.sh runs nothing from it, with a relative
    `core.hooksPath` in the checkout (`claude` is a stub here; that Claude
    Code honours the flag is its own behaviour). A commit in the worktree
    under the child's environment lands there and runs none of the
    branch's git hooks; a plain commit, and a plain `worktree add` of the
    branch, would run them.
  - Refused before the worktree lines: a branch checked out in another
    worktree, a local branch with a commit the remote lacks (left where it
    was), a branch not on the remote, a failed `git worktree add`, a
    failed `git worktree list` (before the fetch), and a worktree that
    cannot be entered (launch.sh then removes it, or drops its record when
    its directory is gone).
  - Resumed: with two remotes pointing at the issue's repository, from the
    first one listed; and a local branch behind the remote, brought up to
    the pushed tip.
- **`launch.sh` and `report.sh`, the session id** — a copy of `launch.sh`
  next to a stub `report.sh` shows `--session <id>` handed over, before the
  URL, for a fresh and a resumed launch. An empty id, a wrong shape, a
  trailing character or `$(…)`, underscores, a non-hex digit, or a path is
  dropped by `launch.sh`, which warns `jikkyo: status line off`, does not
  echo the value, and starts the run without `--session` (fresh and
  resumed); `report.sh` refuses the same values with exit 2 before any `gh`
  write. A launch with no session id argument at all, or `--session` with
  no value, is refused; an upper-case id is accepted.
- **`statusline.sh`** — against a fake clock, with state files written into
  a scratch checkout's common dir:
  - Nothing with no state directory or an empty one. Running:
    `jikkyo #27 · 60% · ~12m left`, `0%` with no estimate yet, estimates in
    seconds, minutes, and hours, and `12 turns` / `1 turn` with no todos; one
    line ending in a newline.
  - `finished`, `failed`, `interrupted` shown 4 m 59 s after `updated`, gone
    at 5 minutes. `stale` for a `running` file 15 minutes old (not at
    14 m 59 s), however old, also with no todos, cleared by the next write,
    and replaced when `report.sh` runs that issue again.
  - Several runs on one line by issue number, joined with ` | `, an expired
    one dropped; another session's run and a run with no session not shown,
    while the other session sees its own; found from a linked worktree's
    subdirectory with only `current_dir` or `cwd`, and from `current_dir` or
    `cwd` when `project_dir` is outside any git checkout.
  - Japanese: `残り ~12m`, `12 ターン`, `1 ターン`, `完了`, `失敗`, `中断`,
    `応答なし`, mixed languages on one line, an unknown or missing `lang`
    skipped, and each ended state's word checked against what `report.sh`'s
    `state_word` gives for that state.
  - Quiet: empty or non-JSON stdin, a missing, malformed, or numeric
    `session_id`, no, relative, missing, or non-git directory, a bad clock,
    and no `jq` all print nothing, exit 0, and write nothing to stderr.
    Malformed JSON, wrong types, a number that does not match the file name,
    a bad state, negative or fractional numbers, `done` over `total`, a file
    over 4 KiB, a misnamed file, a FIFO, a directory, and an unreadable file
    are skipped while good runs still show; files without a trailing newline
    are read whole; odd extra fields never reach the output. An ended run
    whose `updated` is far in the future (the clock was set back) is not
    shown; one a few seconds ahead is.
  - No network tool (`gh`, `curl`, `wget`, `nc`, `ssh`) is run. 50 state
    files take well under a second, and 501 under half a second (one `find`,
    one `awk`, one `jq` for all of them). Under `/bin/bash` when it is 3.2,
    as on macOS, the main cases give the same line.
  - End to end, what `report.sh` writes (English and Japanese) is what it
    shows.
- **Constants shared by the scripts** — `statusline.sh` and `precheck.sh`
  call a `running` file stale at the same age, longer than `report.sh`'s
  heartbeat; `launch.sh`, `report.sh`, and `statusline.sh` check the session
  id with the same pattern.
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
  not `running`. The same decisions for Japanese status comments (live,
  stale, and each ended state, also next to an English one), and `--payload`
  rewriting a Japanese one, including the running comment `report.sh` itself
  wrote with an estimate (suffix dropped, `Remaining` row emptied, Elapsed
  and Progress untouched). Markers with `branch=` after the state give the
  same decisions as markers without it (also side by side), a malformed
  `branch=` does not count, and `--payload` keeps the `branch=` field and
  the Branch row, for a built comment and for the comments `report.sh`
  itself wrote with a branch in English and in Japanese.

  With `--resume <N>`:
  - `none` with no comments, for a `finished` run, another author, a latest
    run without a branch, a branch of another issue (also `jikkyo-123-`
    for 12), or a malformed one.
  - `resume <branch> <id>` for the latest `interrupted` or `failed`
    comment, by id, in English or Japanese, and nothing but that shape on
    the line. A later `finished` run of another branch does not hide it.
  - `none` once a later `finished` comment names the same branch, but that
    branch again if it was then interrupted once more. A `finished` comment
    by another author does not count, nor does a comment whose id is not a
    number.
  - `refuse` for a live `running` comment (also at 14 m 59 s), and
    `rewrite` for a stale one, after which the same check resumes it.
  - Exit 2 for `--force` with `--resume`, a bad issue number (empty, `0`, a
    leading zero, `$(…)`-like text, letters), `--payload` with `--resume`,
    or a failed listing.

  Takeover by another account (`--authors`, `--trusted <login>`):
  - `--authors` prints each other account with a status comment once,
    sorted, leaves out comments without the marker and logins not of
    GitHub's shape (`'`, a leading `-`, `[bot]`, over 39 characters), exits
    2 on a failed listing, and does not combine with the decision flags.
  - An untrusted account (not passed with `--trusted`) is ignored: its
    `interrupted` comment is not resumed, its live `running` one does not
    refuse, its stale `running` one is neither resumed nor rewritten, and
    its `finished` one takes no branch out.
  - A trusted account's `interrupted` or `failed` comment is resumed, the
    latest of all counted accounts wins, several `--trusted` all count, and
    its `finished` comment takes the branch out.
  - A trusted account's live `running` comment refuses (also at 14 m 59 s,
    and next to this account's stale one).
  - A trusted account's stale `running` comment is resumed from, unless a
    later `finished` comment names its branch or a later run on it is
    newer, gives `none` without a branch, and is never on the `rewrite`
    list: only this account's stale one is, and after that rewrite the
    check resumes the latest.
  - Exit 2 for a `--trusted` that is not a login (empty, `'`, a leading `-`,
    `[bot]`, a space, 40 characters), for `--trusted` without `--resume` or
    with `--force`, and for `--payload` with `--trusted`.
  - `--payload --author` exits 1 for another account's `running` comment
    and rewrites this account's own.
- **`cleanup.sh`** — `remove` only for a worktree with no uncommitted changes
  (untracked, modified, and staged files all count) whose HEAD is on a
  remote-tracking branch: pushed, or no new commits. `keep` for an unpushed
  commit, a dirty pushed worktree, a pushed branch with a newer unpushed
  commit, a missing path, a directory that is not a worktree, or a path
  inside one. A `core.fsmonitor` command in git config, and a git hook the
  worktree's branch carries under a relative `core.hooksPath`, are not run
  by its `git status`, while a plain `git status` would run them. The
  `git worktree remove` that `SKILL.md` gives the parent carries the same
  two options and runs no hook from the branch.
- **`SKILL.md`** — `allowed-tools` pins exactly `launch.sh`, `precheck.sh`, and
  `cleanup.sh` under `${CLAUDE_SKILL_DIR}`, with no rule for `claude`, `gh`, or
  `git`, and the skill has no injected commands; every script is executable;
  it tells the parent to write the closing summary in the status comment's
  language, and documents the `--resume` flow: the usage line,
  `precheck.sh --resume '<N>'`, stopping when no valid branch is found, and
  `launch.sh --resume` with the branch, comment id, and
  `${CLAUDE_SESSION_ID}`; a fresh launch passes `${CLAUDE_SESSION_ID}` too.
  Before launching, the parent checks that value's shape itself and, if it
  is not a UUID, tells the user the run will not show in the status line.
  It has a Status line section saying the skill edits no settings, and no
  script mentions `settings.json`. The repository README documents both
  status line setups with `refreshInterval` and why, and its appended
  example, run as written, appends the segment (and nothing when there is
  no run).
