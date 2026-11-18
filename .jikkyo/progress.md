issue: https://github.com/gipcompany/skills/issues/66
branch: worktree-jikkyo-66-20261119-010616
updated: 2026-11-19T01:13:00+09:00
next: AC5 - add wording tests to run.sh and list them in tests/README.md

## Todos

- [x] AC1: SKILL.md Phase 2 task-list rule with marker order (10700a6)
- [x] AC2: SKILL.md recognise done-criteria heading by meaning (9f66af7)
- [x] AC3: SKILL.md convert plain bullets on touch, keep bullet char (cf00e83)
- [x] AC4: ready-for-goal.md Done criteria row accepts * [ ] and - [ ] (f8c4c58)
- [ ] AC5: wording tests in run.sh and README listing
- [ ] AC6: bash skills/kabeuchi/tests/run.sh passes
- [ ] Delete progress log and open PR

## Verified task-list items

- SKILL.md Phase 2 task-list rule with marker order: paragraph added after the write-back paragraph, read back
- Done-criteria section recognised by heading meaning in any language: sentence added to the same paragraph, read back
- Plain bullets converted on touch, keeping each bullet character: sentence added to the same paragraph, read back
- Done criteria row accepts both markers and calls plain bullets a gap: row edited, grep shows no other single-marker mention left in the kabeuchi docs

## Dead ends and decisions

- The rule is a separate bold-led paragraph right after "Each time a point is settled", so the wording tests can find it.
- Git commands must be run one per call; compound commands are refused in this worktree session.
