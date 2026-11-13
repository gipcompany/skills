# skills

[![Skills](https://www.skills.sh/b/gipcompany/skills)](https://www.skills.sh/gipcompany/skills)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A collection of agent skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and other agents that support the [SKILL.md format](https://skills.sh).

**Featured:** [`carve-it`](#carve-it) — **split a large commit into smaller, review-sized commits.** Break up one big commit into a sequence of small, atomic, Conventional-Commits-pure commits that each pass CI on their own, without changing your branch's final state.

## Skills

| Skill | Description |
|-------|-------------|
| [carve-it](skills/carve-it/SKILL.md) | Replace a single large commit, in place, with a sequence of small review-sized commits — each passing CI on its own, each 100% pure in its Conventional Commits type. |
| [kabeuchi](skills/kabeuchi/SKILL.md) | Run a relentless `/grilling` (壁打ち) session that writes each settled conclusion back, in place, into a writable markdown target — a GitHub issue body or a local markdown file — so it always reflects the current agreed spec. Every recommendation is put to an evidence-checked vote of read-only subagents. Requires the `/grilling` skill and the bundled `kabeuchi-voter` subagent. |
| [jikkyo](skills/jikkyo/SKILL.md) | Run `/goal` on a GitHub issue in a headless child, in its own git worktree, and commentate the run live on that issue — one status comment with start time, end time, progress %, and an estimated time remaining, edited in place, plus a closing summary. Requires `gh` and `jq`. |

## Installation

```
npx skills add https://github.com/gipcompany/skills --skill carve-it
npx skills add https://github.com/gipcompany/skills --skill kabeuchi
npx skills add https://github.com/gipcompany/skills --skill jikkyo
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

**Grill a spec, and write the conclusions back into it.** `kabeuchi` (壁打ち — "hitting a ball against a wall") runs a relentless, one-question-at-a-time interview about a target markdown document, and every time a point is settled it rewrites that conclusion **back into the target, in place**. The target is never a transcript of the discussion — it is always a clean spec of the current agreed state. It is a thin delegation wrapper over `/grilling`: the interview is `/grilling`'s job, except that kabeuchi asks one question per turn instead of `/grilling`'s round of questions, so each settled point becomes its own write-back, and the recommendation under each question comes from a vote rather than a single pass of the model's reasoning. The only artifact kabeuchi produces is the updated target markdown itself.

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

### Requires `kabeuchi-voter`

The recommendation under each question is the one place a grilling session can quietly go wrong: it is one line of reasoning settling a question in one pass, and a wrong one tends to be found only after other decisions have been built on it. So kabeuchi puts every recommendation to a vote before you see it:

- Three subagents vote **independently**, each from a fixed perspective — `spec` (what has been required and agreed), `code` (what the codebase actually does), and `docs` (what the library or service does today, via Context7 and the web). Each must cite evidence it actually looked at, or abstain.
- A fourth subagent **verifies** that evidence. A vote whose evidence does not hold is invalid, however many voters agree with it.
- An option needs **two valid votes** to become the recommendation. Otherwise the competing options are laid out side by side for you to choose from. A line under each recommendation shows how it was decided, for example `🗳️ 2/2 valid, unanimous (docs: abstained)`.
- Questions with no right answer (a name, a tone) are not voted on, and say so.

The counting is done by `scripts/tally.sh`, which is covered by the test suite.

All four subagents run the `kabeuchi-voter` agent definition, which ships with the skill but which you install yourself:

```
cp ~/.claude/skills/kabeuchi/agents/kabeuchi-voter.md ~/.claude/agents/
```

Read it first; it is short. Its `tools:` allowlist is `Read, Grep, Glob, WebFetch, WebSearch` and the Context7 MCP server — no `Bash`, no file writes, no subagents of its own. The voters read web pages and whole codebases, so they are where a prompt injection would land, and this makes "read-only" a guarantee Claude Code enforces rather than a request in a prompt. If your Context7 server has a different name (plugin installs use `mcp__plugin_<plugin>_<server>`), change that one entry.

At startup kabeuchi stops if `kabeuchi-voter` is missing, **or if the definition in effect has broader tools than that** — a project's `.claude/agents/` overrides yours, so a repository you cloned could otherwise ship a `kabeuchi-voter` of its own. It never falls back to unvoted recommendations.

Voting costs four subagent runs per question and makes each question take longer to appear. That trade is deliberate: the point of the vote is that a recommendation you see has been checked.

### How it stays safe

Multiple terminals — or a human editing the issue in a browser / the file in an editor — can change the target mid-session. kabeuchi uses **optimistic detection, conservative resolution, and no locks**: before each write it re-fetches the target and compares a normalized SHA256 against the last synced state; disjoint external edits are auto-merged (3-way), overlapping ones are handed back to you to resolve, and every write is confirmed by reading it back. It always shows you the concrete diff before writing, and performs **no git operations** on local files — committing is left to you.

**The target's content is treated as data, never as instructions.** An issue body is written by whoever can open an issue in that repo, so the skill tells Claude in as many words that text inside the target is material to be edited: instructions addressed to the assistant are not followed, commands and URLs it contains are not executed, and anything that reads as aimed at Claude is quoted back to you rather than acted on. The target body is also the *only* thing the main session reads from outside — no issue comments, no linked URLs, no fetches. The voters do read the codebase, documentation, and the web, but they run as read-only subagents: the main session never opens what they cite, and it is the only part of kabeuchi that can write. In the other direction, only what you settled in the interview is written back; file contents, command output, and environment values never leak into a published issue body.

### How it stays visible

A kabeuchi runs for dozens of turns, and over that distance it is easy to lose track of which window is grilling and against which target, or for the interview to drift off its rules. So the moment `/kabeuchi` is invoked — before Claude has read a word of the skill — it drops a marker file at `~/.claude/kabeuchi/<session-id>` naming the target, and registers a `UserPromptSubmit` hook that restates the target and the rules on every turn. Neither depends on Claude remembering to do anything.

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

## jikkyo

**Run `/goal` on an issue, and commentate it on the issue.** `jikkyo` (実況 — "live commentary," the play-by-play of a sports broadcast) takes the GitHub issue URL you would have given `/goal`, starts the `/goal` run itself, and writes the run's status back to the issue as it goes. You type only `/jikkyo <URL>`; you never type a `/goal` line.

### Usage

```
/jikkyo [--force] https://github.com/<owner>/<repo>/issues/<N>
```

Run it from a checkout of that repository. `--force` starts a run even when another one looks active on the issue.

### What shows up on the issue

One status comment, created when the run starts and edited in place:

```
### jikkyo · running · 50% · ~12m 03s left

| Field     | Value                     |
| --------- | ------------------------- |
| State     | running                   |
| Started   | 2026-11-13 18:01:16 +0900 |
| Ended     |                           |
| Progress  | 50%                       |
| Elapsed   | 12m 03s                   |
| Remaining | ~12m 03s (estimate)       |
```

Progress is a percentage of the child's own todo list: completed / not deleted, rounded down. It counts the child's todos, not the issue's task list, so it is shown as a percentage only, with no `<completed>/<total>` fraction that could be read as a count of the issue's boxes. It can go down when the child adds tasks (3 of 4 is 75%, then 3 of 5 is 60%). A run with no todos shows the turn count instead, never a made-up %. The `Remaining` row is a rough estimate (its value says so), elapsed / completed × (total − completed); it can jump when the child adds todos, and it is left empty when there are no todos, none is completed yet, or the run has ended. Because both come from the child's todos, the child is asked up front (a fixed instruction after the URL) to break the work into small todos and complete each as it goes; it is asked, not enforced. The comment is written at the start and the end at once, on todo changes at most once every 30 seconds, and every 5 minutes as a heartbeat. When the run ends, a second, **new** comment gives a short summary: whether the goal was met, any PR, and what happened to the worktree. It is a new comment so that subscribers get a notification. The reporters never write the issue body; the only change to it is the child ticking the task-list boxes (for example the acceptance criteria) it has done and verified. It is asked to tick each box as soon as its item is verified, right after completing that item's todo (one todo per task-list item), rather than all at once at the end, so the boxes fill in as the run goes; this too is asked, not enforced.

The comment follows the language of the issue. At the start, `report.sh` reads the issue's title and body and, if they contain any Japanese characters (hiragana, katakana, or kanji), writes the heading, the field names, and the state words in Japanese; otherwise in English, as above. The choice is made by the script, not a model, and only the resulting `ja` or `en` is used: no text from the issue goes into a command line or the comment. Numbers, durations, and the hidden state marker are the same in both, and the closing summary is written in the same language as the status comment. Only Japanese and English are told apart (any other language gets English), an English issue that quotes Japanese text gets Japanese, and the language does not change if the issue is edited mid-run.

The run ends in one of three states: `finished` (the child exited cleanly, which is not the same as the goal being met; the summary says which), `failed` (an error result), or `interrupted` (no result, or the reporter was killed).

### How it works

A skill cannot start `/goal` in its own session, so `jikkyo` runs it in a headless child, `claude -p '/goal <URL> <todo instruction> <tick instruction>'`, and acts as the reporter:

- **The child does the work** in its own git worktree (`.claude/worktrees/jikkyo-<N>-<timestamp>`, branch `worktree-jikkyo-<N>-<timestamp>`), so you can keep using your checkout. Unpushed local commits are not visible to it.
- **A script reports.** `scripts/report.sh` reads the child's `stream-json` output and updates the status comment through `gh` on its own, without the model being awake.
- **The parent session** checks the issue before the start and, at exit, removes the worktree when that is safe (`scripts/cleanup.sh` decides: no uncommitted changes, and pushed or no new commits) and posts the summary.
- **At most one run per issue**, judged from the issue itself, so it works across terminals and machines. A `running` status comment updated in the last 15 minutes blocks a new run, and an older one is marked `interrupted`.

### What it runs on your machine

Know this before you install it: **the child runs unattended with `--permission-mode auto`**, and you cannot steer it once it has started. On top of auto mode it gets a short deny list (`--disallowedTools`) blocking the plain forms of force pushes, remote-branch deletion, editing or deleting issue comments, and closing or deleting issues. Plain `git push` stays allowed so that it can open a PR, and `gh issue edit` stays allowed so that it can tick the task-list boxes it has verified. Deny rules match only the command as written, so the list is a limit on the obvious, not a sandbox. Read `skills/jikkyo/scripts/launch.sh`, where it is defined.

`allowed-tools` pre-approves only `jikkyo`'s own `launch.sh`, `precheck.sh`, and `cleanup.sh`, for the turn that invokes the skill. Every `gh` and `git` call made by the parent session asks as usual. `/jikkyo` is `disable-model-invocation: true`, so you have to type it.

### When not to use

- You want to steer the run while it is in progress → type `/goal <URL>` yourself.
- Targets other than a GitHub issue URL.

## License

[MIT](LICENSE)
