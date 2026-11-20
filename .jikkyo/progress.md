issue: https://github.com/gipcompany/skills/issues/76
branch: worktree-jikkyo-76-20261120-190608
updated: 2026-11-20T19:35:21+09:00
next: item 2: resume path and its live check

## Todos

- [x] Item 1: Phase 1 trust check of body author, comment authors, body editors; launch.sh --chrome only when all trusted (d274d6d)
- [ ] Item 2: same check on --resume; resumed child with --chrome --setting-sources user loads Claude in Chrome (live)
- [x] Item 3: live check headless claude -p --chrome child connects, opens tab, navigates, reads (log-only commit)
- [ ] Item 4: live check interactive session and jikkyo child keep to own tabs
- [ ] Item 5: --no-chrome flag, usage line and argument validation in SKILL.md
- [ ] Item 6: start message says Chrome on/off and why, warns about logged-in browser
- [ ] Item 7: first-step tab-listing instruction and fixed not-reachable message passed to the summary
- [ ] Item 8: comments instruction and report.sh watcher that SIGTERMs the child on an untrusted comment or edit
- [ ] Item 9: own-tabs instruction; browser-choice prompt at first step counts as not reachable
- [ ] Item 10: fixed login instruction
- [ ] Item 11: decisions on login, shared browser, comments during a run, body edits, resumed runs in SKILL.md
- [ ] Item 12: tests/run.sh covers the decision, child command line, watcher
- [ ] Item 13: README jikkyo section describes the behavior
- [ ] Item 14: tests/run.sh and shellcheck pass
- [ ] Delete progress log and open the PR (Closes #76)

## Verified task-list items

- A headless claude -p --chrome child, started in the background: started in the background with stdin /dev/null, stream-json, --permission-mode auto and --chrome (Claude Code 2.1.329); its stream shows tabs_context_mcp, tabs_context_mcp with createIfEmpty creating its own group and tab, navigate to https://example.com, read_page and get_page_text returning the page text, then tabs_close_mcp
- Phase 1 checks the author of the issue body, every comment, and the edit history; --chrome only when all trusted: tests/run.sh decision cases (all trusted, untrusted body author, comment author, editor, earlier editor, permission error) and the launch.sh command line with and without --chrome pass; precheck.sh --people and --chrome tried on the real issue 76

## Dead ends and decisions

- The first tabs_context_mcp call without createIfEmpty, in a fresh session, answers (not as an error) that the session has no tab group of its own; that means the browser is reachable. tabs_create_mcp fails until tabs_context_mcp with createIfEmpty: true has made the session's group, so the instruction tells the child to make its group that way when it needs a tab.
- The trust check lives in precheck.sh as a filter (--people lists accounts to check, --chrome decides from --trusted), so the parent and report.sh's watcher share one parser; the permission calls stay with the caller, as in --resume.
