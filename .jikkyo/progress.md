issue: https://github.com/gipcompany/skills/issues/85
branch: worktree-jikkyo-85-20261124-231136
updated: 2026-11-24T23:50:00+09:00
next: tick item 5 (no-winner display)

## Todos

- [x] Start the progress log (bd9f770)
- [x] Item 1: feasibility check before the question (cf67ade)
- [x] Item 2: one feasibility-only round for unconfirmed options (cf67ade)
- [x] Item 3: left-out lines under the question (cf67ade)
- [x] Item 4: ALTERNATIVE goes through the feasibility check (cf67ade)
- [ ] Item 5: no-winner display lists only confirmed options
- [ ] Item 6: tally.sh infeasible state
- [ ] Item 7: matter-of-taste questions get a feasibility-only round
- [ ] Item 8: fewer than two survivors still asked
- [ ] Item 9: verifier fails twice
- [ ] Item 10: SKILL.md, voting.md, kabeuchi-voter.md describe the rule
- [ ] Item 11: README kabeuchi section
- [ ] Item 12: tests for tally.sh infeasible
- [ ] Item 13: agreement checks and tests/README.md
- [ ] Item 14: run.sh and shellcheck pass
- [ ] Delete progress log and open the PR

## Verified task-list items

- Item 1 (feasibility checked before the question): read voting.md voter and verifier prompts (FEASIBILITY block, per-verdict HOLDS | FAILS lines), flow steps 5-6, the Feasibility section, and SKILL.md's classify rule
- Item 2 (one extra feasibility-only round): read voting.md flow step 7 (kabeuchi-brief-Q<n>-r2.md, three voters then verifier, at most once) and Failures (one retry, at most one extra round)
- Item 3 (left-out lines): read voting.md What the user sees, which shows the "left out: <id> — found infeasible | not confirmed (<reason>)" format and example
- Item 4 (ALTERNATIVE checked): read voting.md Grouping and tallying (ALT mapped to X<n>, same check, no re-vote) and the voter/verifier prompts (ALT, <perspective> ALT)

## Dead ends and decisions

- Option IDs are kept as drafted (no relettering) so the vote line and the "left out:" lines point at the same options.
- Feasibility-only rounds get their own voter and verifier prompts in voting.md (same roles), so kabeuchi-voter.md gains no role.
- The extra round's brief takes the next free -r<n> suffix, -r2 normally, since a re-vote also uses -r2.
- Votes whose option is confirmed after a verifier failure stay unverified; tally.sh allows infeasible next to unverified.
- No new preflight description phrase: the formats are carried by the task prompts, so an older voter copy still works.
- Worktree guard refuses long python heredocs and compound git commands; use Edit and one git command per call.
