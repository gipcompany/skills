issue: https://github.com/gipcompany/skills/issues/52
branch: worktree-jikkyo-52-20261115-233631
updated: 2026-11-15T23:50:00+09:00
next: wrap GitHub issue targets in a hardened OSC 8 link in statusline.sh

## Todos

- [x] Add kabeuchi statusline.sh (marker read, plain line) (905268c)
- [ ] Wrap GitHub issue targets in a hardened OSC 8 link
- [ ] Show path targets with $HOME folded to ~
- [ ] README: add kabeuchi 'In your status line' subsection
- [ ] README: trim 'How it stays visible' and point to new subsection
- [ ] jikkyo: name its own 'In your status line' section in SKILL.md and test
- [ ] Add statusline.sh tests to kabeuchi tests/run.sh
- [ ] Update kabeuchi tests/README.md for statusline.sh
- [ ] Run the four CI checks locally
- [ ] Delete progress log and open the pull request

## Verified task-list items

- Add skills/kabeuchi/scripts/statusline.sh: ran it against a temp marker dir (marker present prints the one line, placeholder printed plain, pid line ignored; empty, "..", "a/b" and unknown session ids print nothing and exit 0); shellcheck clean

## Dead ends and decisions

- shellcheck is not installed locally; it is run through npx (same version line as the CI runner's default severity).
- Shell commands mixing git with other commands are refused in this worktree session, so git commands run on their own and scratch checks live in a script outside the repo.
