# kabeuchi gotchas, edge cases, and FAQ

## Preflight edge cases (decide before interviewing)

The whole point of the preflight is to avoid grilling for an hour and only then
discovering the conclusions cannot be saved. Classify the target, then verify
you can actually **write** it before spending the session.

| Case | Behavior |
|---|---|
| Issue 404 / not readable | Abort immediately with an explicit message. |
| Readable but not writable (`permissions.push = false`) | Detected by the startup preflight → abort. If the user only wants a read-only session, tell them to use `/grilling` directly. |
| Issue locked **and** not writable | Abort; state that editing is impossible. |
| Issue closed **but** writable | Continue, but warn that the issue is closed. |
| Local file does not exist | Ask whether to create it from scratch. If no, abort. |
| Non-markdown / binary target | Reject. |
| Target is empty (empty issue body / brand-new file) | Enter **from-scratch mode**: build the spec through grilling. |

## Known pitfalls

- **GitHub appends a trailing newline to issue bodies.** Without normalizing
  trailing whitespace/newlines, the body you just wrote reads back as an
  external "conflict" on the very next check. Always normalize through
  `scripts/normalize.sh` on every read, comparison, and read-back.
- **`gh issue view --json` has no `locked` field.** Read `locked` via the REST
  API instead:

  ```bash
  gh api "repos/OWNER/REPO/issues/N" --jq .locked   # true/false
  ```

- **The issue API has no conditional update (no If-Match / CAS).** You cannot
  make the write atomic against a concurrent edit, so an interruption between
  fetch and write cannot be prevented outright. This is why the write-back loop
  ends with a **read-back verification** rather than trusting the write — see
  `conflict-resolution.md`.
- **Never take a lock.** An issue body has nowhere to store one, and a crashed
  terminal would leave it stale. Detect optimistically and resolve
  conservatively with a 3-way merge instead.
- **`merge3.sh` cleans up after itself.** It does all work under `mktemp -d` and
  removes it on exit, so it never litters `mine`/`base`/`theirs`/`merged` files
  into your working tree. Do not re-implement the merge inline — that is the
  behavior this replaces.

## FAQ

**The issue is closed but I can still write to it — what happens?**
kabeuchi continues but warns you the issue is closed. Closing an issue does not
make its body read-only.

**Can kabeuchi read or post issue comments?**
No. The **issue body only** is the target. Comments are never read and never
posted (v1).

**Can I point kabeuchi at a PR body, a Gist, or an arbitrary web URL?**
No (v1). Only a GitHub **issue** URL or a local markdown file path. Bare
issue-number shorthand is also rejected — pass the full URL.

**I only want to be grilled, not to write anything back.**
Use `/grilling` directly. kabeuchi's whole job is the write-back; without a
writable target there is nothing for it to add.

**Will kabeuchi commit or push my local file changes?**
No. It performs no git operations on local targets — no `add`, `commit`, or
`push`. It leaves the edited working tree; committing is your call.
