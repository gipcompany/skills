issue: https://github.com/gipcompany/skills/issues/68
branch: worktree-jikkyo-68-20261119-013552
updated: 2026-11-19T01:50:00+09:00
next: Update the assertion summary in skills/jikkyo/tests/README.md

## Todos

- [x] Start the progress log (6a904c9)
- [x] Reword TICK_INSTRUCTION in launch.sh (e2eba33)
- [x] Update SKILL.md description of the instruction (ce4521d)
- [x] Update run.sh assertion to the new wording (c1e7f85)
- [ ] Update tests/README.md summary
- [ ] Run bash skills/jikkyo/tests/run.sh
- [ ] Delete the progress log and open the PR

## Verified task-list items

- TICK_INSTRUCTION lets the child tick -, * or + items: bash -n passes and the expanded constant was read back; the sentence matches the issue wording and the rest is unchanged
- SKILL.md describes the instruction with the same marker rule: the "Who writes the issue body" bullet now states the box rule with the three marker examples; grep shows no other copy of the old wording there
- run.sh asserts the new wording and fails on the old: the suite passes with the fix, and with launch.sh from main both new assertions fail (2 failed)

## Dead ends and decisions

- The branch had no upstream, so the first push sets it with -u; later pushes are plain git push.
- Used the issue's exact sentence, with "those lines'" as a plural possessive (a first try produced "lines's" and was fixed before commit).
- Added an assert_lacks on the old sentence besides the assert_has, so going back to naming only "- [ ]" fails even if the new sentence were kept alongside it.
