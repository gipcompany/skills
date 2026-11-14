issue: https://github.com/gipcompany/skills/issues/39
branch: worktree-jikkyo-39-20261114-183217
updated: 2026-11-14T18:40:00+09:00
next: Create scratch/resume-test/step-2.txt with the line "step 2" in its own commit

## Todos

- [x] Create scratch/resume-test/step-1.txt (0f0c313)
- [ ] Create scratch/resume-test/step-2.txt
- [ ] Create scratch/resume-test/step-3.txt
- [ ] Delete progress log and open draft PR

## Verified task-list items

- `scratch/resume-test/step-1.txt` exists with the line `step 1`: committed in 0f0c313; file bytes checked to be exactly "step 1" plus a newline

## Dead ends and decisions

- Boxes are ticked by fetching the body via the REST API as JSON and PATCHing it back with only the one "- [ ]" line changed, so the trailing newline and other edits are preserved.
