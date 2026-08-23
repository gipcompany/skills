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

kabeuchi **delegates the entire interview to a `/grilling` skill and does not bundle it.** `/grilling` is a standalone, relentless one-question-at-a-time design-interview skill — install it into your skills directory first (from [mattpocock/skills](https://github.com/mattpocock/skills/blob/main/skills/productivity/grilling/SKILL.md)). If it is unavailable at startup, kabeuchi stops and tells you how to get it rather than falling back to an ad-hoc interview.

**kabeuchi never installs it for you.** There is no download step in the skill — no `curl`, no `git clone`, no package install, no network fetch at all; the preflight only checks whether `/grilling` is already present. Upstream it is a single `SKILL.md` with no scripts and no executables, short enough to read in full before you trust it, and that reading is yours to do. Once installed it supplies the interview tone and nothing else: it asks questions inside the same session with exactly the tools that session already had, while the write-back — the only step that touches your issue or your file — stays in kabeuchi, behind a diff you approve. If you'd rather not run a third-party skill, kabeuchi isn't for you, which is why the dependency is stated up front instead of surfacing at run time.

### How it stays safe

Multiple terminals — or a human editing the issue in a browser / the file in an editor — can change the target mid-session. kabeuchi uses **optimistic detection, conservative resolution, and no locks**: before each write it re-fetches the target and compares a normalized SHA256 against the last synced state; disjoint external edits are auto-merged (3-way), overlapping ones are handed back to you to resolve, and every write is confirmed by reading it back. It always shows you the concrete diff before writing, and performs **no git operations** on local files — committing is left to you.

**The target's content is treated as data, never as instructions.** An issue body is written by whoever can open an issue in that repo, so the skill tells Claude in as many words that text inside the target is material to be edited: instructions addressed to the assistant are not followed, commands and URLs it contains are not executed, and anything that reads as aimed at Claude is quoted back to you rather than acted on. The target body is also the *only* thing kabeuchi reads from outside — no issue comments, no linked URLs, no fetches. In the other direction, only what you settled in the interview is written back; file contents, command output, and environment values never leak into a published issue body.

### How it stays visible

A kabeuchi runs for dozens of turns, and over that distance it is easy to lose track of which window is grilling and against which target, or for the interview to drift off its two rules. So the moment `/kabeuchi` is invoked — before Claude has read a word of the skill — it drops a marker file at `~/.claude/kabeuchi/<session-id>` naming the target, and registers a `UserPromptSubmit` hook that restates the target and the rules on every turn. Neither depends on Claude remembering to do anything.

The marker is also there for your status line to read. Have `~/.claude/statusline.sh` print a second row when the file for the current session exists, and it shows up only while a grilling is running:

```
Opus · ⚡xhigh · ~/git/path · 5h: [███░░░░░░░] 28% ↻2h10m
kabeuchi in progress · gipcompany/path#125
```

Because the marker is keyed by session id it can never light up a different window's bar, and it records the owning process so a session that dies without clearing it is collected on the next run. Clearing it is the skill's own last step.

### What it runs on your machine

Two things here go beyond reading and writing the target, and you should know about both before installing this — reviewing what a checked-in skill grants itself is the recommended habit, not a special precaution for this one.

**Invoking `/kabeuchi` registers a `UserPromptSubmit` hook for the rest of the session.** From that point Claude Code runs a shell command every time you submit a prompt, until the session ends. It is declared in `skills/kabeuchi/SKILL.md`'s frontmatter and it does one thing: look for this session's marker file and, if there is one, print a single reminder line. With no marker it prints nothing. The command locates `scripts/prompt-hook.sh` by walking the places the skill gets installed — a plugin root, then your personal `~/.claude/skills` — and **greps each candidate for an identity marker before executing it**, so a script that merely *happens* to sit at the same path under some other plugin is not run. Be clear on what that marker is worth: it is a literal string published in this repo, so it catches the accidental collision, not a script planted with a matching marker on purpose.

That is why **a project's own `.claude/skills/kabeuchi` copy is not on the list by default.** It is the one candidate a repository you cloned can supply, and unlike a hook declared in a project's `.claude/settings.json` it never surfaces for review — so kabeuchi only considers it when you set `KABEUCHI_ALLOW_PROJECT_HOOK=1` (`true`/`yes` also work; every other value, `0` included, leaves it off). Without the opt-in a repo-only install still works — the skill, the marker, and the status line all resolve through the skill's own directory; the only thing you give up is the per-turn reminder line. Invoking `/kabeuchi` inside a repo you don't trust is still trusting that repo, but by default it does not also mean running its script on every prompt.

`/kabeuchi` is `disable-model-invocation: true`, so none of this can be set up by Claude deciding on its own — you have to type the command.

**The target string is fed into Claude's context verbatim on every turn.** That is the reminder line's whole job. `mark.sh` strips control characters and caps the target at 200 characters, so it cannot inject ANSI escapes into your status line or smuggle in a wall of text — but it is still text of your choosing entering the model's context repeatedly, and anything that can write to `~/.claude/kabeuchi/` can change it. Treat a target string pasted from somewhere you don't trust the way you'd treat any other untrusted input.

The skill also pre-approves `Bash(<skill-dir>/scripts/mark.sh *)` so the marker can be written without a prompt. That grant covers only that one script and lasts a single turn.

### When not to use

- Read-only targets, or you just want to stress-test a plan without saving → use `/grilling` directly.
- You want the session distilled into separate ADR / glossary documents instead of edited back into one target → that's a different workflow.
- Targets other than a GitHub issue body or a local markdown file (PR bodies, Gists, arbitrary URLs).

## License

[MIT](LICENSE)
