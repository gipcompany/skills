issue: https://github.com/gipcompany/skills/issues/62
branch: worktree-jikkyo-62-20261117-174248
updated: 2026-11-17T17:56:16+09:00
next: test creation order with numeric ids (2 before 10)

## Todos

- [x] Parse todo subjects from TaskCreate and renames from TaskUpdate (7497d5d)
- [x] Make the scheduler change key cover the whole todo list (4c03440)
- [ ] Render todos in creation order with numeric ids
- [ ] Cap the list at 50 todos with a hidden-count line
- [ ] Cut subjects at 100 rendered characters
- [ ] Neutralize subjects inside one code span
- [ ] Leave the todo section out when there are no todos
- [ ] Use the bare label as the summary in en and ja
- [ ] Show the stopped glyph for in-progress todos on failed and interrupted
- [ ] Split the body at the first details line in precheck.sh --payload
- [ ] Describe the todo section in SKILL.md, tests/README.md, and README.md
- [ ] Run the full test suite and shellcheck
- [ ] Delete the progress log and open the PR with the human-check item

## Verified task-list items

- The todo line shows the subject from TaskCreate, and the new subject after a successful TaskUpdate rename; a failed TaskUpdate changes nothing: "report.sh: the todo list" assertions in tests/run.sh pass, full suite green.
- A change of status alone and a rename alone each trigger a write at the next 30-second slot, counts unchanged: fake-clock assertions in "report.sh: when it writes" pass, full suite green.

## Dead ends and decisions

- The parser keeps .tasks[id] as {status, subject} instead of a bare status string; done/total and the state file are unchanged.
- The whole rendering (TODOS jq program) landed in the first commit; later todos add the tests for each rule and any fixes.
- Subjects are also trimmed at both ends after whitespace is collapsed, so a whitespace-only subject gets the placeholder and no code span starts or ends with a space.
- Unicode line and paragraph separators are treated like newlines.
- One full-suite run failed two state-file timing assertions (0.6 s waits); the rerun passed all, and a traced repro showed a write takes about 0.25 s. Treated as a timing flake, not caused by this change.
- The branch had no upstream, so the first push sets it with -u; later pushes are plain.
- The scheduler key is `.tasks // {}` so the placeholder state before the first parser line equals an empty list and does not cause a spurious write.
