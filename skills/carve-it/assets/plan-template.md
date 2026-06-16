# Plan presentation template

Fill in the `{{...}}` placeholders and present the approval block below verbatim
at the end of Phase 2. Do not proceed to Phase 3 until the user approves. The
per-commit design fields and the type-vs-behavior consistency rule that the table
must satisfy live in `SKILL.md` (Phase 2); this file is only the output skeleton
plus the response handling.

## Commit-message conventions (each row's subject)

- Format: `<type>: <short summary>`, where `<type>` is exactly one of the standard
  Conventional Commits types — feat / fix / refactor / style / test / docs / chore
  / build / ci / perf.
- Keep the subject imperative and roughly under 72 characters.
- Add a body below the subject when the "why" needs more than the subject line —
  in particular, record the reason whenever a commit had to break a split
  principle (e.g. an inseparable structural+behavior change combined into one
  feat/fix, or a diff over the ~200-line target).

## Approval block (render verbatim, placeholders filled)

```
Proposed commit split plan ({{commit}} on branch {{branch}} / {{total}} commits total):

| # | Commit message (subject) | Behavior | +lines | -lines | Review load |
|---|--------------------------|----------|--------|--------|-------------|
| 001 | refactor: {{summary}}    | preserved | {{add}} | {{del}} | low    |
| 002 | feat: {{summary}}        | changed   | {{add}} | {{del}} | medium |
| ... | ...                      | ...       | ...     | ...     | ...    |

Total: {{total-files}} files, +{{total-add}} lines, -{{total-del}} lines
Verification commands: {{lint}} / {{test}}
Descendant commits to restack: {{n}} (or "none (target is HEAD)")

Proceed with this plan?
```

The `Behavior` column must read `preserved` for refactor/style/test/docs/chore/
build/ci rows and `changed` for feat/fix/perf rows — this is the type-vs-behavior
consistency check from SKILL.md. If even one row is inconsistent, do not present
the plan; redesign it first.

## Handling the response

- yes / ok → proceed to execution (Phase 3)
- no / abort → abort, leaving the branch untouched
- adjust → ask for the requested changes and regenerate the plan
