issue: https://github.com/gipcompany/skills/issues/31
branch: worktree-jikkyo-31-20261114-181026
updated: 2026-11-14T09:11:46Z
next: add --authors and --trusted to precheck.sh, with tests for untrusted authors

## Todos

- [x] Bring the branch up to date with main (#30 merged) (ae00cfa)
- [ ] AC1: A comment by an account without write permission, or whose permission check fails, is ignored.
- [ ] AC2: A live run by another trusted account refuses the resume.
- [ ] AC3: A stale running comment by another trusted account can be resumed from and is never edited.
- [ ] Document the permission check in SKILL.md Phase 1 and the design notes
- [ ] AC4: `bash tests/run.sh` passes, with cases for foreign authors (trusted and untrusted, live and stale).
- [ ] Delete the progress log and open the PR

## Verified task-list items

## Dead ends and decisions

- The branch was cut before #30 merged; fast-forwarded to origin/main, since the branch had no commits of its own.
- Trusted logins reach command lines (the permission API path and --trusted), so precheck.sh --authors prints only logins matching GitHub's login shape.
- --trusted is accepted only with --resume; a fresh start keeps counting this account's comments only, as #31 scopes the change to --resume.
