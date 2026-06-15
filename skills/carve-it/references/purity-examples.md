# Type purity: worked examples and the entanglement decision flow

Consult this when Phase 2 (split plan) or the Phase 3 purity audit hits a commit
whose type and behavior are hard to call. The rules live in `SKILL.md`; this file
shows what they look like on real diffs.

The single test for a `refactor` (and every other behavior-preserving type —
`style` / `test` / `docs` / `chore` / `build` / `ci`): **could the change alter
what an external observer sees?** If yes, it is not behavior-preserving.

## Violations hiding inside a "refactor"

Each of these is commonly mislabeled `refactor`. None is.

### 1. A new guard / changed condition

```diff
-  return user.plan.price
+  if (!user.plan) return 0
+  return user.plan.price
```

The added guard changes the result for `user.plan == null` (was a throw, now
`0`). That is observable behavior → `fix` (or `feat`), plus the test that pins it.

### 2. A changed constant or literal

```diff
-  const TIMEOUT_MS = 3000
+  const TIMEOUT_MS = 5000
```

Renaming the constant is `refactor`; changing its value is not. Different timeout
= different behavior under load → `fix`/`perf`/`feat` per intent.

### 3. New external call / I/O / logging

```diff
   function charge(amount) {
+    logger.info("charging", { amount })
     return gateway.capture(amount)
   }
```

A new log line, metric, network call, file write, or env read is observable
output → not `refactor`. (A logging-only change is typically `chore` or `feat`
depending on intent, but it is *not* `refactor`.)

### 4. Changed error-handling policy

```diff
-  } catch (e) { throw e }
+  } catch (e) { return null }
```

Swallowing instead of rethrowing changes the contract callers see → `fix`/`feat`.

### 5. Changed meaning of a public API

Reordering parameters, widening/narrowing a return type, renaming a JSON field
in a response — even if "it still basically works" — changes the meaning of the
public surface → `feat` (or `fix` if the old shape was a bug).

## What IS still a pure refactor

- Rename a symbol and update **every** call site / import / test reference in the
  same commit. The follow-up edits to call sites and tests are mechanical
  consequences of the rename, so they belong in that same `refactor` commit.
- Move code between files/modules with no signature change.
- Extract a function and replace the inline body with a call to it.
- Reformat / reorder imports with no semantic effect (often `style`, not
  `refactor`).
- Update a comment or docstring **attached to the code being changed** — it
  rides along with that change's commit.

## The reverse violation

Do not smuggle a pure structural change into a `feat`/`fix` either. A `feat`
commit that also renames three unrelated helpers is impure in the other
direction. Pull the rename out into its own `refactor` and stack the `feat` on
top (refactor-first, below).

## Decision flow for an entangled change

When one diff mixes a structural change and a behavior change:

```
Are the structural part and the behavior part separable
into two diffs that each leave lint/test green?
│
├─ YES → reorder REFACTOR-FIRST:
│        001 refactor: the pure structural change (green on its own)
│        002 feat/fix:  the behavior change stacked on top
│                       (+ the test that verifies it, same commit)
│
└─ NO  → they are genuinely inseparable, which means it was never a pure
         refactor of the old code. Combine into ONE commit, adopt the
         behavior-changing type (feat/fix), and record the reason for
         inseparability in the plan.
```

Two corollaries from the green constraint (Phase 2, principle 1):

- A behavior change and the existing/new tests that verify it go in the **same**
  commit — never strand a behavior change on a commit that no test covers.
- A pure addition (new code + its new tests) **may** split the tests into a
  second commit, but only if **both** resulting commits stay green on their own.

## Standalone docs are different

Editing a separate documentation file (`README`, `docs/*.md`) is `docs`, split
out from the code change. This is distinct from a docstring/comment that is
physically attached to the code being modified, which stays with that code's
commit.
