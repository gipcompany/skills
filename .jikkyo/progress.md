issue: https://github.com/gipcompany/skills/issues/62
branch: worktree-jikkyo-62-20261117-174248
updated: 2026-11-17T18:24:10+09:00
next: test that the summary is the bare label in en and ja

## Todos

- [x] Parse todo subjects from TaskCreate and renames from TaskUpdate (7497d5d)
- [x] Make the scheduler change key cover the whole todo list (4c03440)
- [x] Render todos in creation order with numeric ids (8f52b14)
- [x] Cap the list at 50 todos with a hidden-count line (2072ea7)
- [x] Cut subjects at 100 rendered characters (03132fd)
- [x] Neutralize subjects inside one code span (d885063)
- [x] Leave the todo section out when there are no todos (c39c6f7)
- [ ] Use the bare label as the summary in en and ja
- [ ] Show the stopped glyph for in-progress todos on failed and interrupted
- [ ] Split the body at the first details line in precheck.sh --payload
- [ ] Describe the todo section in SKILL.md, tests/README.md, and README.md
- [ ] Run the full test suite and shellcheck
- [ ] Delete the progress log and open the PR with the human-check item

## Verified task-list items

- The todo line shows the subject from TaskCreate, and the new subject after a successful TaskUpdate rename; a failed TaskUpdate changes nothing: "report.sh: the todo list" assertions in tests/run.sh pass, full suite green.
- A change of status alone and a rename alone each trigger a write at the next 30-second slot, counts unchanged: fake-clock assertions in "report.sh: when it writes" pass, full suite green.
- Todos are listed in creation order with ids compared numerically: "todos are listed by id, compared as numbers" in tests/run.sh passes, full suite green.
- With more than 50 todos completed ones are hidden oldest first with the en/ja hidden-count line, and with more than 50 open todos in-progress ones stay and the newest pending are hidden: the "cap" assertions in tests/run.sh pass, full suite green.
- A subject longer than 100 rendered characters is cut and ends in an ellipsis: the four length assertions in "report.sh: the todo list" pass (ASCII, exactly 100, Japanese, after whitespace collapse).
- Subjects are neutralized (backticks to quote, newlines and control characters to one space, empty subject placeholder in en and ja, @user, #1, details tags and comment openers inside one code span): the neutralization assertions in "report.sh: the todo list" pass, full suite green.
- With no todos the comment has no todo section (also when every todo is deleted, and in the start write): the four "no todos" assertions pass; the only failures in that run were fake-clock timing tests under a load average near 40.

## Dead ends and decisions

- The parser keeps .tasks[id] as {status, subject} instead of a bare status string; done/total and the state file are unchanged.
- The whole rendering (TODOS jq program) landed in the first commit; later todos add the tests for each rule and any fixes.
- Subjects are also trimmed at both ends after whitespace is collapsed, so a whitespace-only subject gets the placeholder and no code span starts or ends with a space.
- Unicode line and paragraph separators are treated like newlines.
- One full-suite run failed two state-file timing assertions (0.6 s waits); the rerun passed all, and a traced repro showed a write takes about 0.25 s. Treated as a timing flake, not caused by this change.
- The branch had no upstream, so the first push sets it with -u; later pushes are plain.
- The scheduler key is `.tasks // {}` so the placeholder state before the first parser line equals an empty list and does not cause a spurious write.
- One run failed the statusline "50 state files take under a second" timing test at 1.07 s; statusline.sh is untouched and the rerun passed at 0.18 s, so it was machine load.
- The state-file assertion "a todo write updates it" is a pre-existing timing flake: a standalone repro of that scenario with the 0.6 s wait succeeded 11/15 times with main's report.sh and 9/15 with this branch. Not fixed here (out of scope); the full suite is rerun until green.
- The U+2028 test input is written as UTF-8 byte escapes, since bash 3.2 has no \u in $'...' strings.
- Under heavy machine load (load average 30-40 from other work) the fake-clock tests with 0.6 s waits fail in bulk; each todo is accepted on its own assertions passing, and the full green run is left to the full-suite todo, retried when the load drops.
