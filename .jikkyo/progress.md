issue: https://github.com/gipcompany/skills/issues/85
branch: worktree-jikkyo-85-20261124-231136
updated: 2026-11-24T23:50:00+09:00
next: tick item 13 (agreement checks and tests/README.md)

## Todos

- [x] Start the progress log (bd9f770)
- [x] Item 1: feasibility check before the question (cf67ade)
- [x] Item 2: one feasibility-only round for unconfirmed options (cf67ade)
- [x] Item 3: left-out lines under the question (cf67ade)
- [x] Item 4: ALTERNATIVE goes through the feasibility check (cf67ade)
- [x] Item 5: no-winner display lists only confirmed options (cf67ade)
- [x] Item 6: tally.sh infeasible state (c791afa)
- [x] Item 7: matter-of-taste questions get a feasibility-only round (cf67ade)
- [x] Item 8: fewer than two survivors still asked (cf67ade)
- [x] Item 9: verifier fails twice (cf67ade)
- [x] Item 10: SKILL.md, voting.md, kabeuchi-voter.md describe the rule (cf67ade)
- [x] Item 11: README kabeuchi section (7b9ed65)
- [x] Item 12: tests for tally.sh infeasible (c791afa)
- [ ] Item 13: agreement checks and tests/README.md
- [ ] Item 14: run.sh and shellcheck pass
- [ ] Delete progress log and open the PR

## Verified task-list items

- Item 1 (feasibility checked before the question): read voting.md voter and verifier prompts (FEASIBILITY block, per-verdict HOLDS | FAILS lines), flow steps 5-6, the Feasibility section, and SKILL.md's classify rule
- Item 2 (one extra feasibility-only round): read voting.md flow step 7 (kabeuchi-brief-Q<n>-r2.md, three voters then verifier, at most once) and Failures (one retry, at most one extra round)
- Item 3 (left-out lines): read voting.md What the user sees, which shows the "left out: <id> — found infeasible | not confirmed (<reason>)" format and example
- Item 4 (ALTERNATIVE checked): read voting.md Grouping and tallying (ALT mapped to X<n>, same check, no re-vote) and the voter/verifier prompts (ALT, <perspective> ALT)
- Item 5 (no-winner shows only confirmed): read voting.md What the user sees, no-winner layout ("List only confirmed options here", example with a left out: line)
- Item 6 (tally.sh infeasible): tests/run.sh tally cases pass (not judged, "chose B, not confirmed feasible", never wins); header, voting.md state table and its "run once, final state" rule updated; agreement test passes
- Item 7 (taste questions checked): read voting.md Which questions get a vote, SKILL.md taste bullet, and gotchas.md voting FAQ (no longer says exempt)
- Item 8 (fewer than two survive): read voting.md What the user sees, "Fewer than two options survive" paragraph and its no-option example
- Item 9 (verifier fails twice): read voting.md Failures (nothing confirmed, all options to the extra round, no re-vote, no-options question if it confirms nothing)
- Item 10 (three files describe the rule): read SKILL.md Phase 2 bullets, voting.md Feasibility section, kabeuchi-voter.md roles and rule 4; diff shows the voter's tools: line unchanged
- Item 11 (README): read the Requires kabeuchi-voter section (feasibility bullet with left-out example, taste questions still checked, extra round adds four runs)
- Item 12 (infeasible tests): run.sh has 5 counting/wording cases and 4 malformed-input cases for infeasible, all ok

## Dead ends and decisions

- Option IDs are kept as drafted (no relettering) so the vote line and the "left out:" lines point at the same options.
- Feasibility-only rounds get their own voter and verifier prompts in voting.md (same roles), so kabeuchi-voter.md gains no role.
- The extra round's brief takes the next free -r<n> suffix, -r2 normally, since a re-vote also uses -r2.
- Votes whose option is confirmed after a verifier failure stay unverified; tally.sh allows infeasible next to unverified.
- No new preflight description phrase: the formats are carried by the task prompts, so an older voter copy still works.
- Worktree guard refuses long python heredocs and compound git commands; use Edit and one git command per call.
