issue: https://github.com/gipcompany/skills/issues/70
branch: worktree-jikkyo-70-20261119-030304
updated: 2026-11-19T03:40:00+09:00
next: Delete progress log and open PR

## Todos

- [x] kabeuchi: nested lists and marker choice wording (4636692)
- [x] kabeuchi: per-paragraph match in wording test (efb90af)
- [x] kabeuchi: add two positive fixtures (a871040)
- [x] jikkyo: rewrap "Who writes the issue body" bullet (ff0fd11)
- [x] jikkyo: wording test for SKILL.md tick rule (4d03636)
- [x] Update both tests READMEs (d965cc0)
- [x] Run both test suites (d965cc0)
- [ ] Delete progress log and open PR

## Verified task-list items

- Nested lists and marker choice: SKILL.md Phase 2 rule now says the order applies to each list on its own and "into any one list"; kabeuchi tests pass
- The wording test breaks if the rule is wrapped: phase2_rule joins RS="" paragraphs; kabeuchi tests pass, and the old per-line matcher was shown to fail on a wrapped fixture
- No positive fixture: two fixtures assert rc 0 for row_ok and a wrapped rule_ok; kabeuchi tests pass (235 passed)
- Uneven line wrapping: bullet refilled greedily, every line at most 79 characters with the two-space indent; whitespace-collapsed file is identical to before; jikkyo tests pass
- No wording test for the SKILL.md description: four new assertions on the joined bullet pass (845 passed), and the pre-#69 bullet was shown to trip both the assert_has and the assert_lacks
- Each tests README describes the test it changed or gained: kabeuchi entry names the per-paragraph match and positive fixtures (b007dea), jikkyo SKILL.md entry lists the tick wording check (d965cc0); read back in the diff
- Both run.sh pass: kabeuchi 235 passed 0 failed, jikkyo 845 passed 0 failed, on d965cc0

## Dead ends and decisions

- The branch had no upstream, so the first push sets it with -u; later pushes are plain.
- The rewrap keeps each code span on one line (a span is one word for filling), so no line ends inside a span such as the marker examples.
