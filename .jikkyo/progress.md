issue: https://github.com/gipcompany/skills/issues/45
branch: worktree-jikkyo-45-20261115-171418
updated: 2026-11-15T17:18:41+09:00
next: AC5: send gaps the user wants closed back into Phase 2

## Todos

- [x] Start the progress log (0339140)
- [x] AC3: Write the ready-for-/goal checklist under references/ (2a93ea5)
- [x] AC2: Add the checker role to kabeuchi-voter, plus description and preflight check (70bd7ad)
- [x] AC1: Run the ready-for-/goal check in Phase 3 before the closing summary (58a3c11)
- [x] AC4: Define the result format (each gap with its part of the target; ready when none) (e3df793)
- [ ] AC5: Send gaps the user wants closed back into Phase 2
- [ ] AC6: Make the check non-blocking, re-run it after a closed gap, write Known gaps
- [ ] AC7: Put existing Known gaps on the frontier at start; replace the section wholesale
- [ ] AC8: Keep the check read-only and the target-is-data rule
- [ ] AC9: Mention the check in README's kabeuchi section
- [ ] Run the kabeuchi tests and review the whole diff
- [ ] Delete the progress log and open the PR

## Verified task-list items

- The checklist is written down in the skill: references/ready-for-goal.md holds all six items from the issue (Goal, Done criteria, Scope, No open decisions, Self-contained, Constraints), checked by reading the file against the issue body.
- kabeuchi-voter gains the checker role: agents/kabeuchi-voter.md lists a third role (checker) and its description says it checks whether a target is ready to hand to /goal; SKILL.md preflight and gotchas.md now also require that phrase, checked with grep across the skill
- SKILL.md Phase 3 runs the ready-for-/goal check before the closing summary: the Phase 3 bullet asks whether the target goes to /goal and points to references/ready-for-goal.md, which has the flow, the check brief, and the checker prompt; checked by reading SKILL.md Phase 3 in order
- The result names each gap with the part of the target it applies to, or reports the target as ready: the checker prompt requires one GAP line per gap with a location, and 'What the user sees' shows the ready line and the numbered gap list; checked by reading ready-for-goal.md

## Dead ends and decisions

- The checklist goes in a new references/ready-for-goal.md (the issue allows SKILL.md or references/); SKILL.md Phase 3 points to it, the same way Phase 2 points to voting.md.
- Worktree-isolated session: git runs as `git -C <worktree>` one command per call, since compound shell commands and `cd` are refused.
- Preflight version marker: the new description phrase 'ready to hand to /goal' is checked alongside 'Reads the per-question brief', so an installed copy without the checker role is refused, the same way the brief-file change was rolled out.
- The checker gets a separate brief file (kabeuchi-check-<n>.md) next to the vote briefs, so the existing clean-up rule covers it; voting.md's rm pattern gained that name.
- A checker that fails twice leaves the target 'not checked', never 'ready', so a broken check cannot pass a target.
