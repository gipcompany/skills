issue: https://github.com/gipcompany/skills/issues/66
branch: worktree-jikkyo-66-20261119-010616
updated: 2026-11-19T01:19:00+09:00
next: delete this log, push, and open the PR with Closes #66

## Todos

- [x] AC1: SKILL.md Phase 2 task-list rule with marker order (10700a6)
- [x] AC2: SKILL.md recognise done-criteria heading by meaning (9f66af7)
- [x] AC3: SKILL.md convert plain bullets on touch, keep bullet char (cf00e83)
- [x] AC4: ready-for-goal.md Done criteria row accepts * [ ] and - [ ] (f8c4c58)
- [x] AC5: wording tests in run.sh and README listing (da5234b)
- [x] AC6: bash skills/kabeuchi/tests/run.sh passes (da5234b)
- [ ] Delete progress log and open PR

## Verified task-list items

- SKILL.md Phase 2 task-list rule with marker order: paragraph added after the write-back paragraph, read back
- Done-criteria section recognised by heading meaning in any language: sentence added to the same paragraph, read back
- Plain bullets converted on touch, keeping each bullet character: sentence added to the same paragraph, read back
- Done criteria row accepts both markers and calls plain bullets a gap: row edited, grep shows no other single-marker mention left in the kabeuchi docs
- Wording tests for both sides, listed in tests/README.md: new section passes, and its built-in negative cases show the checks fail on a row naming one marker, a rule outside Phase 2, and a rule with another fallback; shellcheck clean
- bash skills/kabeuchi/tests/run.sh passes: run on the final tree at da5234b, exit 0 with no failures

## Dead ends and decisions

- The rule is a separate bold-led paragraph right after "Each time a point is settled", so the wording tests can find it.
- The wording test scopes the SKILL.md check to the Phase 2 section and to the bold-led rule paragraph, so moving the rule out of Phase 2 also fails.
- Git commands must be run one per call; compound commands are refused in this worktree session.
