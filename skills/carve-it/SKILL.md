---
name: carve-it
description: "Use when replace a single large commit on the current branch, in
  place, with a sequence of small review-sized commits, each of which passes CI
  on its own. Every commit is 100% pure in its Conventional Commits type
  (refactor means zero behavior change). Automatically creates a timestamped
  backup branch before rewriting, and fully preserves the original commit's
  author, dates, and tree. Descendant commits are restacked automatically.
  Triggers: \"split this commit\", \"break this commit into reviewable pieces\",
  \"split this commit into semantic units\", \"split this commit into meaningful
  units\", \"carve\". Do not use for: reordering/squashing multiple existing
  commits → git rebase / splitting uncommitted changes → git add -p / managing
  stacked PRs → gh-stack."
---

# Split Large Commit into Logical Sequence

Split a single commit on the current branch into multiple small commits, each sized
so it can be reasonably evaluated in a single review pass, and rewrite
the current branch's history in place to minimize reviewer cognitive load and missed defects.
The pre-rewrite state is preserved in a timestamped backup branch.

## Usage

```
/carve-it <commit-hash>
```

- `<commit-hash>`: the commit to split (required; short form, full form, or relative specs such as `HEAD~2` are accepted). Must exist on the current branch.

## Phase 1: Analysis and Precondition Checks

Verify the following and abort if any check fails:

- The target commit resolves to a full hash.
- HEAD is not detached.
- The working tree is clean (if dirty, advise the user to commit or stash, then abort; never auto-stash).
- The target commit is an ancestor of the current branch's HEAD (`git merge-base --is-ancestor <commit> HEAD`).
- The target commit is not a merge commit, and no merge commits exist in the `<commit>..HEAD` range.

**Pushed-commit check:** if the target commit is already reachable from the upstream (e.g. `origin/<branch>`),
warn that "after the rewrite, `git push --force-with-lease` will be required; if this is a shared branch, it will affect others",
and obtain explicit confirmation before continuing.

After validation passes, collect and present:

- The original commit's author name/email, commit date, subject, parent commit, and the current branch name
- The list of descendant commits in `<commit>..HEAD` (to be restacked in Phase 4; if none, state explicitly that "the target is HEAD")
- The full diff: the list of changed files (with A/M/D status), per-file added/deleted line counts, and a summary of the changes
- **Verification commands**: infer the project's lint/test commands and state them explicitly in the plan (mistakes can be corrected at approval time).

## Phase 2: Split Plan and Approval

Design a commit sequence that minimizes review cost. The number of commits varies with the size of the change
(a few for small changes; 10-20 or more for large ones).

**Split principles (in priority order):**

1. **Green constraint (absolute)**: each commit will be subject to git bisect and per-commit review, so cut boundaries such that lint/test pass on each commit alone (verified incrementally in Phase 3). A behavior-changing change and the existing/new tests that verify it go into the same commit. Pure additions (new code plus new tests) may have tests split out only if both commits stay green.
2. **Type purity (absolute)**: each commit's diff must consist solely of elements of the type declared in the subject. Types are limited to the standard set of [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) (feat/fix/refactor/style/test/docs/chore/build/ci/perf).
   - **refactor is 100% behavior-preserving.** It must not change a single line of observable behavior (conditionals, constant values, external calls and I/O, error-handling policy, the meaning of public APIs). Mechanical follow-up changes to call sites/tests caused by renames or moves are behavior-preserving, so they belong in the same refactor commit.
   - The reverse direction is also a violation: do not mix behavior-preserving refactoring into feat/fix. When they are entangled, resolve it by reordering with **refactor-first** (commit the pure structural change first, then stack the behavior change on top).
   - If truly inseparable (= then it is not a pure refactor of the old code), combine into one commit, adopt the behavior-changing side's type (feat/fix), and note the reason for inseparability in the plan.
   - Exceptions: per principle 1, a behavior change and the tests that verify it may share a commit. Comments and docstrings attached to the code being changed are part of that change. Updates to standalone documentation files are split out as docs.
3. **One commit = one reviewable intent.** It must be possible to state "what changed and why" in a single sentence. Mechanical changes (moves, renames, formatting, code generation) and judgment-bearing changes go into separate commits even when they share a type. Do not mix unrelated areas.
4. **Aim for roughly 200 lines (added + deleted) per diff** (equivalent to a 5-15 minute review). Exceeding this is fine when needed for principles 1-3 (note the reason in the plan).

Order commits from depended-upon to dependent.

Design fields for each commit: commit number (3-digit zero-padded, starting at 001), target files
(for files split across multiple commits, also the policy for intermediate states), added/deleted line counts,
behavior (preserved/changed), estimated review load (low/medium/high),
commit message (`<type>: <short summary>` plus body).

**Type-vs-behavior consistency check (required before presenting)**: refactor/style/test/docs/chore/build/ci → preserved;
feat/fix/perf → changed. If even one row is inconsistent, do not present the plan; redesign it.

Present the plan in the following format and do not proceed to execution (Phase 3 onward) until approval is given.

```
Proposed commit split plan ({{commit}} on branch {{branch}} / {{total}} commits total):

| # | Commit message (subject) | Behavior | +lines | -lines | Review load |
|---|--------------------------|----------|--------|--------|-------------|
| 001 | refactor: ... | preserved | 2 | 0 | low |

Total: {{total-files}} files, +{{total-add}} lines, -{{total-del}} lines
Verification commands: {{lint}} / {{test}}
Descendant commits to restack: {{n}} (or "none (target is HEAD)")

Proceed with this plan?
```

- yes / ok → proceed to execution
- no / abort → abort
- adjust → ask for the requested changes and regenerate

## Phase 3: Construction (create commits on a detached HEAD with incremental verification)

First create the backup branch (no checkout round-trip):

```
git branch backup/<branch>/<YYYYMMDD-HHMMSS>
```

Check out the target commit's parent as a detached HEAD and stack each commit on top of it in plan order.
Show progress in the form `✓ [n/total] ...`.

Stage changes in only the following two ways (no patch application):

- When the file reaches its final state (= the target commit's content) in this commit: extract it with `git checkout <target> -- <file>` (use `git rm` for deletions).
- For intermediate states of files split across multiple commits: edit the file directly to match the planned intermediate content and stage it. The last touch of such a file must always be the final-state checkout (this structurally guarantees that the final tree matches the target commit's tree).

After staging, commit **always carrying over the author and dates from the original commit**.

### Purity audit (immediately after creating each "preserved" commit; fail-fast; before unit verification)

For commits declared behavior-preserving (refactor/style/test/docs/chore/build/ci), read the diff and
inspect for signs of behavior change: added/removed/changed conditionals / changed constant or literal values /
new external calls or I/O / changed error-handling policy / changed meaning of public APIs.
On detection, stop immediately and present remediation options (re-split with refactor-first, or move
the change into the behavior-changing commit), deferring the decision to the user.

### Unit verification (immediately after creating each commit; fail-fast)

Confirm that the commit alone is green with a minimal run, and stop immediately on failure (never stack further commits on a red base).
Do not run the full suite or the whole repository; fix the scope to these two rules:

- lint: run only against the files changed in that commit.
- test: run only the test files included in that commit's diff, specified individually.
- On failure: present which unit failed and why, plus the recommended remediation (usually merging with an adjacent commit to pull in the needed tests/changes), deferring the decision to the user.

## Phase 4: Verification and Switchover

1. **Tree-equivalence gate**: confirm that the tree of the constructed tip matches the tree of the target commit (compare `^{tree}` values via `git rev-parse`). If they match, the result is byte-for-byte identical, so if the original commit was green the final commit is green too (no full test/lint needed). If they differ, some diff was dropped or duplicated; present the mismatch and abort.
2. **Restack descendants**: cherry-pick the descendant commits in `<commit>..HEAD` oldest-first (`--allow-empty` to preserve empty commits; cherry-pick carries over author and dates). Because of tree equivalence, conflicts cannot occur in principle. If one does occur, it signals a dropped change, so abort.
3. **Atomic switchover**: `git branch -f <branch> <new-tip>` → `git switch <branch>`.

## Phase 5: Completion Report

Present the following:

- The list of created commits (number, subject, changed file count, added/deleted line counts) and the number of restacked descendant commits
- How to inspect the result commit by commit (`git log --oneline` / `git show`)
- The backup branch name, the restore command (`git reset --hard backup/<branch>/<ts>`), and the deletion command for when it is no longer needed (`git branch -D backup/<branch>/<ts>`)
- If the target had been pushed: note that `git push --force-with-lease` is required

## Invariants

- The current branch is never moved until the atomic switchover (Phase 4) after all verification passes (unit verification, tree-equivalence gate, descendant restack). On any mid-course failure or abort, the original branch is left untouched and unchanged.
- On failure or abort, report and keep the tip hash of the partially built commit sequence (recoverable via reflog).
- The skill never deletes the backup branch and never pushes to a remote (both are performed by the user).
