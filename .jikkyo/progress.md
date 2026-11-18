issue: https://github.com/gipcompany/skills/issues/70
branch: worktree-jikkyo-70-20261119-030304
updated: 2026-11-19T03:16:00+09:00
next: kabeuchi: add two positive fixtures

## Todos

- [x] kabeuchi: nested lists and marker choice wording (4636692)
- [x] kabeuchi: per-paragraph match in wording test (efb90af)
- [ ] kabeuchi: add two positive fixtures
- [ ] jikkyo: rewrap "Who writes the issue body" bullet
- [ ] jikkyo: wording test for SKILL.md tick rule
- [ ] Update both tests READMEs
- [ ] Run both test suites
- [ ] Delete progress log and open PR

## Verified task-list items

- Nested lists and marker choice: SKILL.md Phase 2 rule now says the order applies to each list on its own and "into any one list"; kabeuchi tests pass
- The wording test breaks if the rule is wrapped: phase2_rule joins RS="" paragraphs; kabeuchi tests pass, and the old per-line matcher was shown to fail on a wrapped fixture

## Dead ends and decisions

- The branch had no upstream, so the first push sets it with -u; later pushes are plain.
