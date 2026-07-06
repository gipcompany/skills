# kabeuchi tests

Regression tests for the two deterministic helper scripts — `normalize.sh` and
`merge3.sh`. Zero dependencies beyond `git` and `bash`: each test writes small
text blobs to a temp dir, runs one script, and asserts on its stdout and exit
code. The interview itself is delegated to `/grilling` and is prompt-driven, so
there is nothing to unit-test there; these tests cover the only real logic the
skill owns.

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
- **no temp litter** — running `merge3.sh` from a working directory leaves no
  extra files behind (it does all work under `mktemp -d` and cleans up on exit).

## CI

There is no active workflow in this repo; wire the tests into CI with a snippet
like the following (GitHub Actions). `shellcheck` ships preinstalled on the
`ubuntu-latest` runner.

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
