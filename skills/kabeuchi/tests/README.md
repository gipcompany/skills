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
  the backstop for markers carrying no pid. Above all,
  **every call exits 0** — bad arguments, no arguments, an unwritable marker
  directory — because the script runs from an injected `` !`...` `` command in
  `SKILL.md`, where a non-zero exit aborts the entire `/kabeuchi` invocation.
- **`prompt-hook.sh`** — silent when the session has no marker; otherwise prints
  the one reminder line naming the target verbatim; another session's marker
  never leaks in; and it exits 0 on every payload, since a `UserPromptSubmit`
  hook that exits non-zero swallows the user's prompt.
- **no temp litter** — running `merge3.sh` from a working directory leaves no
  extra files behind (it does all work under `mktemp -d` and cleans up on exit).

## CI

`.github/workflows/kabeuchi-tests.yml` runs both steps on every push and pull
request that touches `skills/kabeuchi/**`. `shellcheck` ships preinstalled on the
`ubuntu-latest` runner, and all four scripts plus this test file are clean at its
default severity.

```yaml
name: kabeuchi tests
on:
  push:
    paths: ['skills/kabeuchi/**']
  pull_request:
    paths: ['skills/kabeuchi/**']
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: helper-script tests
        run: bash skills/kabeuchi/tests/run.sh
      - name: shellcheck
        run: shellcheck skills/kabeuchi/scripts/*.sh skills/kabeuchi/tests/*.sh
```
