# carve-it tests

Regression tests for the helper scripts plus an end-to-end check of the
tree-equivalence invariant. Zero dependencies beyond `git` and `bash`: every test
builds a throwaway repo in a temp dir, exercises a script, and asserts on its exit
code and output.

## Run

```
bash skills/carve-it/tests/run.sh
```

Exit status is non-zero if any assertion fails; the last line reports
`total: <n> passed, <m> failed`.

## What is covered

- **`backup.sh`** — creates a `backup/<branch>/<ts>` ref at the tip; rejects an
  invalid branch.
- **`verify-tree.sh`** — identical trees -> exit 0, differing trees -> exit 1, bad
  usage -> exit 2.
- **`restore.sh`** — dry-run reports the newest backup and moves nothing; `--run`
  refuses unless the target branch is checked out, then resets to the newest
  backup.
- **end-to-end** — `fixtures/scenario.sh` builds the sample input: one target
  commit that entangles a rename (refactor) and a `.trim()` behavior + its test
  (feat) in `src/app.js`. The test reconstructs the documented two-commit split
  using only the Phase 3 staging moves (final-state checkout + one intermediate
  edit) and asserts the gate: a correct carve is tree-equivalent (exit 0), and a
  carve that drops `app.js`'s final-state checkout is caught (exit 1).

## Fixtures

`fixtures/scenario.sh` is the sample input/output for the end-to-end test. It is
sourced by `run.sh` and exposes `mk_target_repo` (build the sample target commit)
and `write_app_intermediate` (stage the split file's intermediate state). Keep the
expected output fixed there so a regression in `verify-tree.sh` or in the staging
contract surfaces as a failed assertion.

## CI

There is no active workflow in this repo; wire the tests into CI with a snippet
like the following (GitHub Actions). `shellcheck` ships preinstalled on the
`ubuntu-latest` runner.

```yaml
name: carve-it tests
on:
  push:
    paths: ['skills/carve-it/**']
  pull_request:
    paths: ['skills/carve-it/**']
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: helper-script tests
        run: bash skills/carve-it/tests/run.sh
      - name: shellcheck
        run: shellcheck skills/carve-it/scripts/*.sh skills/carve-it/tests/*.sh skills/carve-it/tests/fixtures/*.sh
```
