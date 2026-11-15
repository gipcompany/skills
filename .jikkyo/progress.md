issue: https://github.com/gipcompany/skills/issues/52
branch: worktree-jikkyo-52-20261115-233631
updated: 2026-11-16T00:15:00+09:00
next: trim the README's "How it stays visible" to the marker explanation and a pointer

## Todos

- [x] Add kabeuchi statusline.sh (marker read, plain line) (905268c)
- [x] Wrap GitHub issue targets in a hardened OSC 8 link (5cee77a)
- [x] Show path targets with $HOME folded to ~ (cc80592)
- [x] README: add kabeuchi 'In your status line' subsection (d88d270)
- [ ] README: trim 'How it stays visible' and point to new subsection
- [ ] jikkyo: name its own 'In your status line' section in SKILL.md and test
- [ ] Add statusline.sh tests to kabeuchi tests/run.sh
- [ ] Update kabeuchi tests/README.md for statusline.sh
- [ ] Run the four CI checks locally
- [ ] Delete progress log and open the pull request

## Verified task-list items

- Add skills/kabeuchi/scripts/statusline.sh: ran it against a temp marker dir (marker present prints the one line, placeholder printed plain, pid line ignored; empty, "..", "a/b" and unknown session ids print nothing and exit 0); shellcheck clean
- GitHub issue target shown as OWNER/REPO#N in a hardened OSC 8 link: ran it on valid, fragment, trailing-path, leading-zero, missing-repo, dot owner/repo, extra-segment, zero, hyphen-led owner and embedded-OSC 8 markers; links rebuilt from captures with BEL terminators, the rest plain text with control bytes gone; shellcheck clean
- Path target shown as plain text with $HOME folded to ~: ran it with HOME set to a test value; a path under it, HOME itself, a sibling sharing the prefix (left alone), and a path with backslash sequences (printed literally) all came out as expected; shellcheck clean
- Root README "### In your status line" under "## kabeuchi": section added after "How it stays visible" with both setups, the jikkyo-and-kabeuchi example, the no-refreshInterval note and the FORCE_HYPERLINK note; hyperlink claims checked against the status line docs page; the combined example run with stub scripts, with and without a marker, prints one row per non-empty script and exits 0

## Dead ends and decisions

- shellcheck is not installed locally; it is run through npx (same version line as the CI runner's default severity).
- Shell commands mixing git with other commands are refused in this worktree session, so git commands run on their own and scratch checks live in a script outside the repo.
- Control bytes stripped are C0 and DEL (byte-wise with LC_ALL=C tr), so UTF-8 paths stay intact; an issue number of 0 (all zeros) or over 18 digits falls back to plain text.
- The README's combined example first used `[ -n "$row" ] && printf ...`; with the last script silent that left exit status 1, so it uses `if ...; then ...; fi`.
