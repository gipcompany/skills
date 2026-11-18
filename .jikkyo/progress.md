issue: https://github.com/gipcompany/skills/issues/68
branch: worktree-jikkyo-68-20261119-013552
updated: 2026-11-19T01:41:00+09:00
next: Update the instruction description in skills/jikkyo/SKILL.md

## Todos

- [x] Start the progress log (6a904c9)
- [x] Reword TICK_INSTRUCTION in launch.sh (e2eba33)
- [ ] Update SKILL.md description of the instruction
- [ ] Update run.sh assertion to the new wording
- [ ] Update tests/README.md summary
- [ ] Run bash skills/jikkyo/tests/run.sh
- [ ] Delete the progress log and open the PR

## Verified task-list items

- TICK_INSTRUCTION lets the child tick -, * or + items: bash -n passes and the expanded constant was read back; the sentence matches the issue wording and the rest is unchanged

## Dead ends and decisions

- The branch had no upstream, so the first push sets it with -u; later pushes are plain git push.
- Used the issue's exact sentence, with "those lines'" as a plural possessive (a first try produced "lines's" and was fixed before commit).
