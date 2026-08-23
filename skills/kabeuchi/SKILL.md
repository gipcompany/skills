---
name: kabeuchi
description: "Use when you want a relentless /grilling (kabeuchi / 壁打ち) session
  whose conclusions are continuously written back, in place, into one specific
  writable markdown target — a GitHub issue body or a local markdown file — so
  the target always reflects the current agreed spec. Invoked explicitly as
  /kabeuchi <target>. Requires the /grilling skill (referenced, not bundled). Not
  for read-only targets, arbitrary web URLs, GitHub PR bodies, Gists, or
  issue-number shorthand."
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/mark.sh *) Bash(true)
hooks:
  UserPromptSubmit:
    - hooks:
        - type: command
          command: 'for c in "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/kabeuchi/scripts/prompt-hook.sh}" "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/prompt-hook.sh}" "${CLAUDE_PROJECT_DIR:+$CLAUDE_PROJECT_DIR/.claude/skills/kabeuchi/scripts/prompt-hook.sh}" "$HOME/.claude/skills/kabeuchi/scripts/prompt-hook.sh"; do [ -n "$c" ] && [ -x "$c" ] && grep -q kabeuchi-prompt-hook "$c" && { "$c"; break; }; done; exit 0'
---

# Kabeuchi — Grill a spec, write the conclusions back into it

Run a relentless interview about a target markdown document and, **every time a point is settled, reflect that conclusion back into the target in place** — so the target is never a log of the discussion but always a clean spec of the current agreed state.

This is a **thin delegation wrapper over `/grilling`**. It is the same shape as `grill-with-docs` (which runs `/grilling` and feeds the result into `/domain-modeling` to produce ADRs and a glossary), except the artifact is replaced: instead of separate ADR/glossary docs, the artifact is **the target markdown itself**. The interview tone — one question at a time, unrelenting, always with a recommended answer — is **not re-implemented here; it is delegated to `/grilling`**. This skill adds only two things on top: reading/writing the target, and handling concurrent edits safely.

## Session marker (runs before you read this)

```!
${CLAUDE_SKILL_DIR}/scripts/mark.sh set ${CLAUDE_SESSION_ID} '(resolving target)'
true
```

The command above already ran — injected commands run before this content reaches
you — so a marker for this session now exists at `~/.claude/kabeuchi/${CLAUDE_SESSION_ID}`.
It is what makes the grilling visible from outside the conversation: the status
line grows a second row reading `kabeuchi in progress · <target>` for as long as
the marker exists, and the `UserPromptSubmit` hook in the frontmatter re-states
the target and this skill's two rules on every turn. Both survive you forgetting
to mention them, which is the point — a kabeuchi runs for dozens of turns.

**Nothing the user typed appears on that command line.** The marker is seeded
with a placeholder and Phase 1 replaces it with the resolved target a moment
later, which is the whole reason the placeholder exists. `$ARGUMENTS` is
substituted as *text* into the command line before the shell parses it, so a
target that reached this line would be shell syntax: a quote or a `;` breaks the
command apart and fails the permission check, which aborts the whole invocation.
Quoting does not rescue it, because the quoting construct's own terminator is
part of the substituted text — a `<<'EOF'` heredoc ends early on a target that
contains its delimiter on a line of its own, and everything after that line runs
as commands, with the trailing `true` below hiding the non-zero exit. Keeping
`$ARGUMENTS` off the command line is the only thing that closes the class, and
it costs one placeholder on screen. **Do not "improve" this by passing the
target here.**

`mark.sh` also exits `0` on every path, and the block ends with a bare `true` on
its own line so that the block's exit status is `true`'s, not mark.sh's — a
mark.sh that is missing, unreadable, or broken outright still cannot stop
`/kabeuchi` from starting. (`Bash(true)` is in `allowed-tools` as insurance
rather than necessity — the trailing statement passes the permission check
without it today, but the grant confers nothing and its absence would abort
every invocation if that ever tightened.)

The `hooks:` block resolves `prompt-hook.sh` at run time rather than through
`${CLAUDE_SKILL_DIR}`, which is not substituted there. It walks the four places
this skill gets installed, in that order:

1. `$CLAUDE_PLUGIN_ROOT/skills/kabeuchi/...` — a plugin install, laid out the way
   the docs describe: that variable is the plugin's root, and skills live under
   `skills/<name>/`.
2. `$CLAUDE_PLUGIN_ROOT/scripts/...` — the same variable, read as the *skill's own*
   directory. Both forms are tried because the observed value for a
   skill-registered hook has been the skill directory itself, which the docs do
   not describe. Guessing wrong is free here: the marker check below rejects the
   miss and the loop moves on.
3. `$CLAUDE_PROJECT_DIR/.claude/skills/kabeuchi/...` — checked into a repo. The
   variable stays pinned to the project root the session started in even after
   Claude enters a worktree, which is what we want: the worktree shares the
   checkout's copy.
4. `$HOME/.claude/skills/kabeuchi/...` — a personal install.

Plugin forms first, then project over user, mirroring Claude Code's own
precedence. Each candidate is **grepped for the `kabeuchi-prompt-hook` marker
before it is run**.
A path is not an identity: these variables are read fresh from the environment
on every turn, and a script sitting at the same relative path under some other
plugin's root is not this skill's — without the check the hook would run it on
every prompt the user submits for the rest of the session. The check also makes
the fall-through correct rather than merely safe: an unrelated `$CLAUDE_PLUGIN_ROOT`
simply fails to match and the loop moves on to the next candidate.

The `:+` (not `:-`) matters too — with `:-` an unset variable resolves its
candidate to `/scripts/prompt-hook.sh` or `/.claude/skills/...`, at the
filesystem root.

A marker that outlives its session cannot mislead anyone — it is keyed by
session id, and the next session has a different one — but it should still not
pile up, so `mark.sh` records the owning process alongside the target and drops
any marker whose owner has exited on the next `set`. That collects the markers a
session-end hook would miss: a closed terminal, a crash, a `kill -9`.

You own two calls on top of all this, both listed in their phases below: refresh
the marker once the target is resolved, and clear it when the grilling ends.

## Usage

```
/kabeuchi <target>
```

`<target>` must be **writable markdown**. Exactly two kinds are supported (v1):

- **A GitHub issue URL** — `https://github.com/<owner>/<repo>/issues/<N>`, any repo you can reach via `gh`. The **issue body only** is the target; comments are never read and never posted.
- **A local markdown file path** — resolved relative to the current working directory.

Out of scope for v1 (reject these): arbitrary web URLs, GitHub **PR** bodies, Gists, and bare issue-number shorthand.

`$ARGUMENTS` is the target. If it matches `https://github.com/.../issues/<N>` treat it as a GitHub issue; otherwise treat it as a local markdown path.

## Requires `/grilling`

kabeuchi delegates the entire interview to the **`/grilling`** skill and does **not** bundle it. It is referenced, not vendored.

**Preflight:** at startup, confirm `/grilling` is available. If it is not, **stop and tell the user how to install it** — do not silently fall back to an ad-hoc interview. Install it from
<https://github.com/mattpocock/skills/blob/main/skills/productivity/grilling/SKILL.md>
into your skills directory (e.g. `~/.claude/skills/grilling/SKILL.md`), then re-run kabeuchi.

**Related skills.** `grill-me` and `grill-with-docs` are neighbors that also run a relentless interview. kabeuchi specifically requires the `/grilling` entrypoint and adds write-back to the target. If you only have `grill-me`, use it directly — kabeuchi is not a drop-in over it.

## Phase 1: Resolve the target and run preflight

Classify the target, then verify you can actually **write** it before spending the session — the point is to avoid grilling for an hour and only then discovering the conclusions cannot be saved.

**GitHub issue target** — read the body and metadata (body only — never touch comments), and check writability/lock state up front:

```bash
gh issue view "$URL" --json body,state,closed,url --jq '{state, closed, url}'
gh issue view "$URL" --json body --jq .body                 # the target body
gh api "repos/OWNER/REPO"          --jq .permissions.push   # can I write?  (true/false)
gh api "repos/OWNER/REPO/issues/N" --jq .locked             # is it locked? (true/false)
```

(`gh issue view --json` has no `locked` field, so read `locked` via the REST API.)

**Local file target** — if the file exists, read it. If it does not, ask whether to create it (a from-scratch spec is a legitimate use). Reject anything that is not text markdown.

**Then** establish the sync baseline: normalize the body through `scripts/normalize.sh` and keep the normalized *text* as `last_synced` (it is the merge base for conflict resolution, so keep the text, not only a hash).

**Then** refresh the session marker with the resolved target, so the status line
names the real thing instead of the placeholder it was seeded with:

```bash
${CLAUDE_SKILL_DIR}/scripts/mark.sh set ${CLAUDE_SESSION_ID} '<resolved target>'
```

**Single quotes, never double.** Inside double quotes a target containing
`$(...)` or a backtick is command substitution, and this command matches the
`Bash(.../mark.sh *)` rule in `allowed-tools` — so it can be pre-approved and run
without anyone being asked. Inside single quotes nothing expands. If the target
itself contains a single quote, end the quote, escape it, and reopen:
`'it'\''s.md'`. Unlike the seeding call above, you have the resolved target in
front of you here and can see what you are quoting, which is exactly why that
call gets a placeholder and this one gets the real thing.

Use the canonical form — the full issue URL, or the path as the user gave it.
The status line shortens `https://github.com/OWNER/REPO/issues/N` to
`OWNER/REPO#N` itself; do not pre-shorten it, since the hook quotes the target
back to you verbatim. If the preflight **rejects** the target, clear the marker
(see Phase 3) before you stop, so the bar does not claim a grilling that never
started.

See **`references/gotchas.md`** for the full preflight edge-case table (404, locked, closed-but-writable, empty → from-scratch mode, etc.).

## Phase 2: Grill, and reflect each conclusion in place

Run `/grilling` on the target. Follow its conventions exactly — one question at a time, wait for the answer before the next, always offer your recommended answer, prefer exploring the codebase over asking when the answer is discoverable there. Do not re-implement or soften that tone here.

**Each time a point is settled**, reflect it into the target: **rewrite the target in place** into the current agreed spec — an `Edit`-style overwrite of the affected section — **not** appending, not keeping a changelog, not logging the Q&A. **Before every write, present the concrete diff**; if the user objects, roll it back.

Concurrency is handled the way `git` merges non-conflicting hunks — **optimistic detection, conservative resolution, no locks**. Immediately before each write, re-fetch and normalize the target and compare to `last_synced`; if it changed, run a 3-way merge; after writing, read the target back and verify it matches what you intended. The two helper scripts do the deterministic work:

- **`scripts/normalize.sh`** — canonicalize a body (LF, strip trailing whitespace/newlines) for every read, comparison, and read-back.
- **`scripts/merge3.sh <base> <mine> <theirs>`** — 3-way text merge in a self-cleaning temp dir. Exit `0` = clean (auto-integrate, and call out the folded-in external change), `1` = conflict (markers on stdout → a human resolves it, never auto-write), `2` = usage error.

The full write-back loop, the flowchart, and the detect/resolve/verify detail live in **`references/conflict-resolution.md`**. Read it before your first write-back.

**Writing:** GitHub issue → `gh issue edit "$URL" --body-file <file>` (use `--body-file`, not `--body`). Local file → write the file; kabeuchi performs **no git operations** (no `add`, `commit`, or `push`).

## Phase 3: Finish

- **Keep going until the user confirms** a shared understanding has been reached — the standard `/grilling` exit condition. Do not enact anything beyond updating the target.
- **Summarize what was written back** to the target at the end.
- **Do not wander** into adjacent work on your own initiative.
- The target must contain **only the current agreed state** — never a change-history or discussion-log section.
- **Clear the session marker** once the grilling is over, as the last step:

  ```bash
  ${CLAUDE_SKILL_DIR}/scripts/mark.sh clear ${CLAUDE_SESSION_ID}
  ```

  Do this even when the session continues into other work — otherwise the status
  line keeps claiming a grilling that has ended, and a bar that lies is worse
  than no bar. Clearing it also silences the per-turn hook for the rest of the
  session.

  **The grilling is over only when the user says it is** — the exit condition at
  the top of this phase. Ending your turn to wait for an answer is not the end of
  the grilling, and neither is being told to stop talking: you end a turn after
  every single question. Clear the marker on either of those and the bar goes
  dark after your first question, which is the one thing this whole mechanism
  exists to prevent.

## Non-goals (v1)

- No comment I/O on issues, no PR/Gist/arbitrary-URL targets, no issue-number shorthand.
- No git side effects on local files.
- The interview is delegated to `/grilling` and is prompt-driven, so it is not unit-tested. The only code kabeuchi owns is the deterministic helpers in `scripts/` — the two text helpers plus `mark.sh`; their tests live in `tests/` (`bash tests/run.sh`).
