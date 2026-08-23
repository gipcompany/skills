# kabeuchi tests

Regression tests for the deterministic helper scripts — `normalize.sh`,
`merge3.sh`, `mark.sh` and `prompt-hook.sh`. Zero dependencies beyond `git` and
`bash`: each test writes small text blobs to a temp dir, runs one script, and
asserts on its stdout and exit code. The interview itself is delegated to
`/grilling` and is prompt-driven, so there is nothing to unit-test there; these
tests cover the only real logic the skill owns.

## Run

```
bash skills/kabeuchi/tests/run.sh
```

Exit status is non-zero if any assertion fails; the last line reports
`total: <n> passed, <m> failed`.

## What is covered

- **`normalize.sh`** — CRLF/CR become LF; trailing whitespace and newlines are
  stripped from the end of the body; interior blank lines survive; the GitHub
  trailing-newline case does not read as a change; normalization is idempotent;
  a missing file exits 2.
- **`merge3.sh`** — disjoint edits merge cleanly (exit 0, both edits present, no
  markers); overlapping edits conflict (exit 1, markers present); bad arg count
  and a missing input file exit 2.
- **`mark.sh`** — the target is read from stdin or an argument and stored as one
  sanitized line (first line only, control characters stripped, trimmed, capped
  at 200 characters); an empty target still marks the session with a
  placeholder; `clear` removes only the named session's marker; a traversing
  session id cannot write outside the marker directory; the session id falls
  back to `$CLAUDE_CODE_SESSION_ID` and then to the `session_id` in hook JSON on
  stdin; the owning process id is recorded on a second line and a marker whose
  owner has exited is swept on the next `set`, with an age sweep after a week as
  the backstop for markers carrying no pid. The sweep deletes files and
  `KABEUCHI_DIR` is caller-settable, so it is scoped to session-id shaped names:
  **a non-marker file sharing the directory is never collected**, whatever its
  age and whatever it has on its second line. Above all,
  **every call exits 0** — bad arguments, no arguments, an unwritable marker
  directory — because the script runs from an injected `` !`...` `` command in
  `SKILL.md`, where a non-zero exit aborts the entire `/kabeuchi` invocation.
- **`SKILL.md`'s injected command** — the block still calls `mark.sh set`, and it
  **does not interpolate `$ARGUMENTS`**. That substitution is textual and happens
  before the shell parses the line, so a target reaching it arrives as shell
  syntax that no quoting construct contains — a `<<'EOF'` heredoc ends early on a
  target carrying its delimiter, and the rest of the argument runs as commands.
  The marker is seeded with a placeholder and Phase 1 refreshes it instead. That
  refresh call **single-quotes the target**, since inside double quotes a
  `$(...)` in the target would be command substitution on a command line the
  `allowed-tools` rule can pre-approve.
- **`SKILL.md`'s `UserPromptSubmit` hook command** — it searches the places the
  skill gets installed (plugin root, `$HOME/.claude/skills`, and — only on an
  explicit opt-in — `$CLAUDE_PROJECT_DIR/.claude/skills`), guards both variables
  with `:+` (with `:-`, an unset variable resolves its candidate to a path at the
  filesystem root), and **greps each candidate for the `kabeuchi-prompt-hook`
  marker before executing it**. The project candidate is the only one a cloned
  repository can supply, so tests assert it is assembled **only** when
  `KABEUCHI_ALLOW_PROJECT_HOOK` is an affirmative `1`/`true`/`yes` — `0`, `no`,
  and an unset variable all leave it out, which rules out the `:+` spelling where
  `0` would switch it on. The command is then run for real, with every candidate
  under the test's control: a decoy planted at the right relative path under a
  foreign plugin *and* project root must not run (and the command must still exit
  0); a project-local copy must be silent by default and found once opted in; and
  precedence must hold — plugin first, then the personal install, with the project
  checkout last. That last pair is deliberately the reverse of Claude Code's skill
  precedence, and the marker is a published string that a planted copy can carry,
  so a test asserts a marker-carrying project copy still loses to the personal
  install even with the opt-in on. `prompt-hook.sh` is checked for the marker too,
  since losing it turns the hook into a silent no-op.
- **`prompt-hook.sh`** — silent when the session has no marker; otherwise prints
  the one reminder line naming the target verbatim; another session's marker
  never leaks in; and it exits 0 on every payload, since a `UserPromptSubmit`
  hook that exits non-zero swallows the user's prompt.
- **no temp litter** — running `merge3.sh` from a working directory leaves no
  extra files behind (it does all work under `mktemp -d` and cleans up on exit).

## CI

`.github/workflows/kabeuchi-tests.yml` runs both steps on every push and pull
request that touches `skills/kabeuchi/**` or the workflow itself. `shellcheck`
ships preinstalled on the `ubuntu-latest` runner, and all four scripts plus this
test file are clean at its default severity.

```yaml
name: kabeuchi tests
on:
  push:
    paths: ['skills/kabeuchi/**', '.github/workflows/kabeuchi-tests.yml']
  pull_request:
    paths: ['skills/kabeuchi/**', '.github/workflows/kabeuchi-tests.yml']

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          persist-credentials: false
      - name: helper-script tests
        run: bash skills/kabeuchi/tests/run.sh
      - name: shellcheck
        run: shellcheck skills/kabeuchi/scripts/*.sh skills/kabeuchi/tests/*.sh
```

The trigger is `pull_request`, never `pull_request_target`: a fork's PR runs the
fork's code, so it must run with a read-only token and no access to secrets.
`permissions: contents: read` narrows that token further, `persist-credentials:
false` keeps it out of `.git/config` where the test steps could read it, and
`timeout-minutes` caps how long a fork's code can hold a runner. The action is
pinned to a commit rather than a tag, since a tag can be moved to point at
different code.
