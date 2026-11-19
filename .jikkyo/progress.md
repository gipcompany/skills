issue: https://github.com/gipcompany/skills/issues/73
branch: worktree-jikkyo-73-20261120-010725
updated: 2026-11-19T16:25:22Z
next: tick the README item (todo 21)

## Todos

- [x] Fenced blocks: opener/closer rules, unclosed runs to end (06161ad)
- [x] Code spans: matching run length, may span lines, unmatched is literal (06161ad)
- [x] Indented blocks, HTML code, fences in quotes/lists are not dropped (06161ad)
- [x] Title and body cleaned separately (06161ad)
- [x] LANG_FILTER drops code before testing for Japanese (06161ad)
- [x] Check still runs entirely inside jq (06161ad)
- [x] Test: Japanese only in code spans gives en (6075189)
- [x] Test: Japanese only in a fenced block gives en (6075189)
- [x] Test: Japanese prose gives ja (6075189)
- [x] Test: Japanese prose with code gives ja (6075189)
- [x] Test: Japanese only in a ~~~ fence gives en (6075189)
- [x] Test: unclosed fence holding Japanese gives en (6075189)
- [x] Test: double-backtick span with a backtick and Japanese gives en (6075189)
- [x] Test: unmatched backtick then Japanese prose gives ja (6075189)
- [x] Test: title Japanese only in a code span gives en (6075189)
- [x] Test: title starting with ``` does not hide Japanese body (6075189)
- [x] Test: indented block, blockquote fence, HTML code give ja (6075189)
- [x] run.sh covers each rule (parent item) (6075189)
- [x] Code-only Japanese gives en, prose gives ja (end to end) (6075189)
- [x] SKILL.md "Which language" describes new rule and limit (ad6316f)
- [ ] README.md jikkyo language paragraph updated
- [ ] tests/README.md language entry lists new cases
- [ ] Delete progress log and push
- [ ] Open PR with Closes #73

## Verified task-list items

- Fenced block rules (indent up to 3, 3+ backticks or tildes, closer same char and at least as long, unclosed runs to end): LANG_FILTER extracted from report.sh and run by jq on ad hoc issues (longer/shorter closer, other char, 4-space opener and closer, closer with info, CRLF, unclosed)
- Code span rules (closed by the next run of the same length, across lines; unmatched run is literal): same ad hoc jq runs (double span holding a single backtick, multi-line span, unmatched run, run-length mismatch, unmatched run followed by a later span) and the run.sh cases
- Not dropped (indented blocks, HTML pre/code, fences in blockquotes or list items): ad hoc jq runs on each (indented block with and without backtick lines, blockquote fence, list-item fence, HTML code) all gave ja, and the run.sh limit cases pass
- Title and body cleaned separately (spans only from the title, fences then spans from the body, ja if either keeps Japanese): run.sh cases "title Japanese only in a code span" (en), "title that starts with a fence over a Japanese body" (ja), and "Japanese in the title alone" (ja) pass
- LANG_FILTER drops fenced blocks and code spans before the Japanese test: all four sub-items above verified; full run.sh passed (0 failed) and shellcheck is clean; the report.sh diff against main is two hunks, the header Language paragraph and the LANG_FILTER block with its comment
- Check still runs entirely inside jq: detect_lang is unchanged (gh api piped to jq, case on ja/en); the run.sh tests that no issue text reaches a gh argument, the comment, or the output, and that a $(...) in the issue is never run, pass
- run.sh case, Japanese only in code spans gives en: passes in the full run.sh run
- run.sh case, Japanese only in a fenced block gives en: passes in the full run.sh run
- run.sh case, Japanese prose gives ja: passes in the full run.sh run
- run.sh case, Japanese prose that also contains code gives ja: passes in the full run.sh run
- run.sh case, Japanese only in a ~~~ fence gives en: passes in the full run.sh run
- run.sh case, English prose followed by an unclosed fence holding Japanese gives en: passes in the full run.sh run
- run.sh case, a double-backtick span holding a single backtick and Japanese gives en: passes in the full run.sh run
- run.sh case, an unmatched backtick followed by Japanese prose gives ja: passes in the full run.sh run
- run.sh case, a title whose Japanese is only in a code span, with an English body, gives en: passes in the full run.sh run
- run.sh case, a title that starts with a backtick fence over a Japanese body gives ja: passes in the full run.sh run
- run.sh cases, Japanese only in an indented block, a blockquote fence, or HTML code gives ja: all three pass in the full run.sh run
- run.sh covers each rule, one case each: all 11 sub-items verified; the full run passed with 0 failed and shellcheck on scripts and tests is clean
- Code-only Japanese gives en and Japanese prose gives ja: end to end through report.sh with the gh stub answering the issue read (run.sh), the printed language line checked
- SKILL.md Which language: re-read after the edit; it gives the fence and span rules, title and body cleaned apart, and the updated limit (Japanese outside code, and the constructs not dropped count as prose); run.sh, which reads SKILL.md, passed with 0 failed

## Dead ends and decisions

- Code is dropped by a line-based reduce (fences) and a token scan of backtick runs (spans), with no string offsets, so it does not depend on how a jq version counts match offsets.
- A backtick fence whose info string holds a backtick is not a fence (CommonMark rule), so it falls through to the code-span scan.
- First draft let a fence inside a blockquote pair its backtick runs as a code span, which hid the Japanese inside and gave en; the issue says such fences count as prose (ja). Fixed with unfence: a line that is only a backtick fence after indent, `>`, or list markers loses that run before the span scan.
- First draft read the closer's run length from the line instead of the state (jq `.` inside `$l | test(...)`), so every fence ran to the end; caught by the "ja after a closed fence" case.
- The test suite takes over 2 minutes; run it in the background, and do not edit run.sh while it runs (bash reads the script as it goes).
- Code, tests, and docs are already committed (06161ad, 6075189, 5bbb556); the suite passed in full and shellcheck is clean on that tree. The remaining todos are one log push and one tick each.
- The branch had no upstream, so the first push sets it with -u; later pushes are plain.
