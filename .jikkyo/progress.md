issue: https://github.com/gipcompany/skills/issues/68
branch: worktree-jikkyo-68-20261119-013552
updated: 2026-11-19T01:58:00+09:00
next: Delete this log in one commit, push, and open the PR with Closes #68

## Todos

- [x] Start the progress log (6a904c9)
- [x] Reword TICK_INSTRUCTION in launch.sh (e2eba33)
- [x] Update SKILL.md description of the instruction (ce4521d)
- [x] Update run.sh assertion to the new wording (c1e7f85)
- [x] Update tests/README.md summary (024b656)
- [x] Run bash skills/jikkyo/tests/run.sh (024b656)
- [ ] Delete the progress log and open the PR

## Verified task-list items

- TICK_INSTRUCTION lets the child tick -, * or + items: bash -n passes and the expanded constant was read back; the sentence matches the issue wording and the rest is unchanged
- SKILL.md describes the instruction with the same marker rule: the "Who writes the issue body" bullet now states the box rule with the three marker examples; grep shows no other copy of the old wording there
- run.sh asserts the new wording and fails on the old: the suite passes with the fix, and with launch.sh from main both new assertions fail (2 failed)
- tests/README.md summarises the assertion with the new rule: the passage now states the box rule with the three markers, and grep finds no "change only `- [ ]` to `- [x]`"
- bash skills/jikkyo/tests/run.sh passes: run at 024b656 with exit 0 and no failures; the diff against main touches only the four named files and this log

## Dead ends and decisions

- The branch had no upstream, so the first push sets it with -u; later pushes are plain git push.
- Used the issue's exact sentence, with "those lines'" as a plural possessive (a first try produced "lines's" and was fixed before commit).
- Added an assert_lacks on the old sentence besides the assert_has, so going back to naming only "- [ ]" fails even if the new sentence were kept alongside it.
- The test-run todo has no commit of its own, so its hash is the commit that was tested.
