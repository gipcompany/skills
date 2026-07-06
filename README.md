# skills

[![Skills](https://www.skills.sh/b/gipcompany/skills)](https://www.skills.sh/gipcompany/skills)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A collection of agent skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and other agents that support the [SKILL.md format](https://skills.sh).

**Featured:** [`carve-it`](#carve-it) — **split a large commit into smaller, review-sized commits.** Break up one big commit into a sequence of small, atomic, Conventional-Commits-pure commits that each pass CI on their own, without changing your branch's final state.

## Skills

| Skill | Description |
|-------|-------------|
| [carve-it](skills/carve-it/SKILL.md) | Replace a single large commit, in place, with a sequence of small review-sized commits — each passing CI on its own, each 100% pure in its Conventional Commits type. |
| [kabeuchi](skills/kabeuchi/SKILL.md) | Run a relentless `/grilling` (壁打ち) session that writes each settled conclusion back, in place, into a writable markdown target — a GitHub issue body or a local markdown file — so it always reflects the current agreed spec. Requires the `/grilling` skill. |

## Installation

```
npx skills add https://github.com/gipcompany/skills --skill carve-it
npx skills add https://github.com/gipcompany/skills --skill kabeuchi
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

## kabeuchi

**Grill a spec, and write the conclusions back into it.** `kabeuchi` (壁打ち — "hitting a ball against a wall") runs a relentless, one-question-at-a-time interview about a target markdown document, and every time a point is settled it rewrites that conclusion **back into the target, in place**. The target is never a transcript of the discussion — it is always a clean spec of the current agreed state. It is a thin delegation wrapper over `/grilling`: the interview is `/grilling`'s job, and the only artifact kabeuchi produces is the updated target markdown itself.

### Usage

```
/kabeuchi <target>
```

`<target>` is **writable markdown**, one of exactly two kinds (v1):

- a **GitHub issue URL** (`https://github.com/<owner>/<repo>/issues/<N>`) — the issue **body only**, via `gh`; comments are never read or posted.
- a **local markdown file path**, relative to the current directory.

Arbitrary web URLs, GitHub PR bodies, Gists, and bare issue-number shorthand are out of scope.

### Requires `/grilling`

kabeuchi **delegates the entire interview to a `/grilling` skill and does not bundle it.** `/grilling` is a standalone, relentless one-question-at-a-time design-interview skill — install it into your skills directory first. If it is unavailable at startup, kabeuchi stops and tells you how to get it rather than falling back to an ad-hoc interview.

### How it stays safe

Multiple terminals — or a human editing the issue in a browser / the file in an editor — can change the target mid-session. kabeuchi uses **optimistic detection, conservative resolution, and no locks**: before each write it re-fetches the target and compares a normalized SHA256 against the last synced state; disjoint external edits are auto-merged (3-way), overlapping ones are handed back to you to resolve, and every write is confirmed by reading it back. It always shows you the concrete diff before writing, and performs **no git operations** on local files — committing is left to you.

### When not to use

- Read-only targets, or you just want to stress-test a plan without saving → use `/grilling` directly.
- You want the session distilled into separate ADR / glossary documents instead of edited back into one target → that's a different workflow.
- Targets other than a GitHub issue body or a local markdown file (PR bodies, Gists, arbitrary URLs).

## License

[MIT](LICENSE)
