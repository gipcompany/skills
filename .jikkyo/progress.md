issue: https://github.com/gipcompany/skills/issues/76
branch: worktree-jikkyo-76-20261120-190608
updated: 2026-11-20T19:36:13+09:00
next: item 9: own-tabs instruction

## Todos

- [x] Item 1: Phase 1 trust check of body author, comment authors, body editors; launch.sh --chrome only when all trusted (d274d6d)
- [x] Item 2: same check on --resume; resumed child with --chrome --setting-sources user loads Claude in Chrome (live) (d274d6d)
- [x] Item 3: live check headless claude -p --chrome child connects, opens tab, navigates, reads (log-only commit)
- [ ] Item 4: live check interactive session and jikkyo child keep to own tabs
- [x] Item 5: --no-chrome flag, usage line and argument validation in SKILL.md (6c3e678)
- [x] Item 6: start message says Chrome on/off and why, warns about logged-in browser (6c3e678)
- [x] Item 7: first-step tab-listing instruction and fixed not-reachable message passed to the summary (d274d6d)
- [x] Item 8: comments instruction and report.sh watcher that SIGTERMs the child on an untrusted comment or edit (d274d6d)
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
- The same applies to --resume, and a resumed child with --chrome --setting-sources user loads Claude in Chrome: SKILL.md step 4c runs for a resume too; tests/run.sh checks the resumed command line (--setting-sources user then --chrome, browser instructions before the resume one, --watch to report.sh, resume environment unchanged); live: a child started with --setting-sources user --chrome and the resume environment variables (Claude Code 2.1.329) listed claude-in-chrome as connected in its init event and called tabs_context_mcp without an error
- --no-chrome for one run, usage line, and argument validation: tests/run.sh checks SKILL.md's usage line, the rule that flags go before the URL in any order with at most one of --force or --resume and at most one --no-chrome, the usage-and-stop for a repeated or unknown flag, that it is recorded nowhere, and precheck.sh --chrome --no-chrome printing chrome off no-chrome; launch.sh rejects --no-chrome
- The start message says Chrome on or off and why: tests/run.sh checks SKILL.md step 6's three lines (on, with the logged-in browser warning; off naming the untrusted accounts from the decision line; off for --no-chrome)
- First step is the tab listing, and an unavailable browser ends at once with the fixed message the summary shows: tests/run.sh checks BROWSER_INSTRUCTION (tab listing first, without createIfEmpty; missing tool or any error ends at once) ending in report.sh's NOT_REACHABLE text, report.sh printing jikkyo: browser not reachable for it and not for other messages, and SKILL.md Phase 3 reading that line into the summary
- Comments instruction and the watcher: tests/run.sh checks COMMENTS_INSTRUCTION in the Chrome-on prompt only, report.sh --watch stopping a stand-in child with SIGTERM on an untrusted comment and an untrusted body edit (and read permission, a permission error, a deleted account), ending interrupted with the Stopped row and the jikkyo: stopped by hand-over, and the real launch.sh --chrome with report.sh stopping a silent child by its PID within seconds; SKILL.md Phase 3 puts the account and reason in the closing summary

## Dead ends and decisions

- The first tabs_context_mcp call without createIfEmpty, in a fresh session, answers (not as an error) that the session has no tab group of its own; that means the browser is reachable. tabs_create_mcp fails until tabs_context_mcp with createIfEmpty: true has made the session's group, so the instruction tells the child to make its group that way when it needs a tab.
- The trust check lives in precheck.sh as a filter (--people lists accounts to check, --chrome decides from --trusted), so the parent and report.sh's watcher share one parser; the permission calls stay with the caller, as in --resume.
