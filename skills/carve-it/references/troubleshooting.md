# Troubleshooting and recovery

Symptom-driven recovery for a carve-it run. Read this when a phase aborts, a
gate fails, or a helper refuses. The guiding fact: **the current branch is never
moved until the atomic switchover (Phase 4, step 3).** Everything before that
runs on a detached HEAD, so almost every failure here is recovered by
`git switch <branch>` — there is nothing to roll back.

## Tree-equivalence gate reports MISMATCH (Phase 4, step 1)

`verify-tree.sh` exits 1 and prints the differing paths via `git diff --stat`.
This means the carved sequence does **not** reproduce the target commit's tree
byte-for-byte: some diff was dropped or duplicated. Switchover has not happened,
so the branch is untouched.

**Diagnose** — for each path the gate listed:

```
git diff <target> <constructed-tip> -- <path>
```

**Typical causes:**

1. **A split file never got its final-state checkout.** Phase 3 requires that the
   *last* touch of any file split across commits be the final-state extraction
   (`git checkout <target> -- <file>`). If an intermediate edit was the last
   thing staged for that file, its content is frozen at the intermediate state.
   The `git diff` above shows the leftover intermediate hunk. Fix: add/repair the
   final-state checkout in the commit that should hold it, then re-run the gate.
2. **A changed file was never assigned to any commit.** It appears in
   `<target>`'s diff but in none of the carved commits, so it shows as fully
   missing. Fix: add it to the appropriate commit per the plan.
3. **A deletion was applied as an edit (or not at all).** Removing a file must use
   `git rm` (or `git checkout <target> -- <file>` when the target also deleted
   it), not an empty edit. The path shows as still-present. Fix: `git rm` it in
   the right commit.
4. **A hunk was duplicated across two commits.** The final tree is still correct
   only if the last touch is the final-state checkout; if an intermediate edit
   re-introduced content the target removed, the gate catches it. Fix: correct
   the intermediate content.

**Return to a clean state at any time:** `git switch <branch>`. The partially
built tip survives in the reflog (see below) if you want to inspect it first.

## Construction was interrupted on the detached HEAD (Phase 3)

If the terminal closed, you `git switch`ed away, or the run aborted mid-stack,
the carved commits are no longer pointed at by any branch — but they are **not
lost**. They live in the reflog until garbage collection.

**If you kept the tip hash** (the abort/completion report always reports it):

```
git switch --detach <tip-hash>     # resume stacking more commits on top
# or
git switch -c carve-wip <tip-hash> # park it on a throwaway branch to inspect
```

**If you lost the hash**, find it in the reflog — the most recent detached-HEAD
commits sit at the top:

```
git reflog --date=relative          # look for your "✓ [n/total]" commits
git log -g --oneline                # same, log form
```

Take the hash of the highest commit in your carved stack and re-anchor as above.
Nothing here touches `<branch>`, so there is no risk in exploring.

## cherry-pick conflict while restacking descendants (Phase 4, step 2)

Because the constructed tip is tree-equivalent to the target, replaying the
descendant commits **cannot conflict in principle**. A conflict therefore means
the trees were *not* actually equivalent — a change was dropped or duplicated
and slipped past (or around) the gate.

**Do not resolve the conflict and continue.** Resolving it by hand would silently
bake a divergence from the original history into the result. Instead:

```
git cherry-pick --abort
git switch <branch>     # switchover (step 3) has not run; branch is intact
```

Then re-examine: re-run `verify-tree.sh <target> <constructed-tip>`, inspect the
conflicting descendant's diff against what the carved stack produced, fix the
split (usually a missed final-state checkout, as above), and retry Phase 4 from
step 1.

## Unit verification fails on a single commit (Phase 3)

A commit is red on its own. Never stack further commits on a red base. The usual
remediation is to **merge the failing commit with an adjacent one** so the
needed test or change rides along — e.g. a behavior change stranded on a commit
no test covers, or a test-only commit whose subject-under-test lands in the next
commit. Re-check the green and type-purity constraints after merging; present the
options and defer the decision to the user.

## Failure AFTER the switchover (Phase 4, step 3) — the only case needing restore

Once `git branch -f <branch> <new-tip>` has run, the branch points at the carved
history. This is the one failure mode that needs an actual restore to the
pre-rewrite state. The backup branch makes it a single command.

```
scripts/restore.sh <branch>          # dry-run: prints the latest backup + command
scripts/restore.sh --run <branch>    # actually reset --hard to it
```

`restore.sh` auto-detects the newest `backup/<branch>/<timestamp>` and, for
safety, **refuses to run unless `<branch>` is the branch currently checked out**
(so the working tree it discards is the expected one). If it complains that the
current branch differs, `git switch <branch>` first, then retry. Manual
equivalent: `git reset --hard backup/<branch>/<ts>`.

## restore.sh: "no backup found under backup/<branch>/"

`restore.sh` looks only under `refs/heads/backup/<branch>/`. Causes:

- **The branch was renamed after carving.** The backup is filed under the old
  name. List every backup and restore the right one manually:

  ```
  git for-each-ref --format='%(refname:short)' 'refs/heads/backup/'
  git reset --hard backup/<old-branch>/<ts>
  ```

- **The backup was already deleted.** carve-it never deletes backups, so this was
  manual. If the pre-rewrite tip is recent, recover it from the reflog of
  `<branch>` instead: `git reflog <branch>`.

## backup.sh: "already exists; refusing to overwrite"

Two backups requested within the same second (the timestamp has 1-second
resolution). The existing ref already captures the current tip, so this is safe —
either reuse it, or wait a second and re-run. `backup.sh` never overwrites a ref
by design.

## A "preserved" commit failed the purity audit (Phase 3)

The audit found a behavior change inside a commit declared behavior-preserving
(refactor/style/test/docs/chore/build/ci). This is expected and handled: stop,
and choose either to re-split refactor-first or to fold the change into a
behavior-changing commit. The concrete patterns and the refactor-first vs.
combine-into-one decision flow are in `references/purity-examples.md`.
