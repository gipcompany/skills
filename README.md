# skills

[![Skills](https://www.skills.sh/b/gipcompany/skills)](https://www.skills.sh/gipcompany/skills)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A collection of agent skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and other agents that support the [SKILL.md format](https://skills.sh).

**Featured:** [`carve-it`](#carve-it) — **split a large commit into smaller, review-sized commits.** Break up one big commit into a sequence of small, atomic, Conventional-Commits-pure commits that each pass CI on their own, without changing your branch's final state.

## Skills

| Skill | Description |
|-------|-------------|
| [carve-it](skills/carve-it/SKILL.md) | Replace a single large commit, in place, with a sequence of small review-sized commits — each passing CI on its own, each 100% pure in its Conventional Commits type. |

## Installation

```
npx skills add https://github.com/gipcompany/skills --skill carve-it
```

Or browse and pick interactively:

```
npx skills add https://github.com/gipcompany/skills
```

## carve-it

**Split one large commit into multiple smaller commits.** You wrote (or generated) one big commit — maybe an AI agent produced a sprawling diff — and reviewers hate it. `carve-it` rewrites it into a sequence of small, semantically pure commits (atomic commits, one logical change each) without changing the final state of your branch. Useful whenever you want to break up a commit, make a huge diff reviewable, keep history bisectable, or enforce clean Conventional Commits boundaries.

### Usage

```
/carve-it <commit-hash>
```

It analyzes the commit, proposes a split plan for your approval, then rebuilds the history in place.

### Example

Before — one 23-file commit:

```
$ git log --oneline
a1b2c3d (HEAD -> feature/notifications) feat: add notification settings   (+812 / -245, 23 files)
9e8d7c6 (main) chore: release v2.3.0
```

After — `/carve-it a1b2c3d`:

```
$ git log --oneline
f6e5d4c (HEAD -> feature/notifications) docs: document notification settings API
b5a4938 feat: add notification settings screen
8c7b6a5 feat: add notification settings API endpoint
7d6c5b4 test: add characterization tests for NotificationSender
3f2e1d0 refactor: extract NotificationPolicy from NotificationSender
9e8d7c6 (main) chore: release v2.3.0
```

Each commit:

- passes lint and tests **on its own** (safe for `git bisect` and per-commit review)
- contains **only** changes matching its Conventional Commits type — `refactor` commits change zero behavior
- preserves the original commit's author and dates
- the final tree is **byte-for-byte identical** to the original commit (verified by a tree-equivalence gate)

Descendant commits on top of the target are restacked automatically.

### Safety: backup and restore

Before rewriting, a timestamped backup branch is created automatically:

```
backup/feature/notifications/20260607-153012
```

To restore the original history:

```
git reset --hard backup/feature/notifications/20260607-153012
```

To delete the backup once you no longer need it:

```
git branch -D backup/feature/notifications/20260607-153012
```

The skill never deletes the backup branch and never pushes to a remote — both are left to you.

### When not to use

- Reordering or squashing multiple existing commits → `git rebase -i`
- Splitting uncommitted changes → `git add -p`
- Managing stacked PRs → [spr](https://github.com/ejoffe/spr)

## License

[MIT](LICENSE)
