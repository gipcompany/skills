# The "ready for `/goal`" check

Read this before you end a session. It expands the step in `SKILL.md` Phase 3
that checks, before the closing summary, whether the target can be handed to
`/goal` — directly, or through `/jikkyo` — and run to completion without a
human.

## Why a check at the end

A shared understanding is not the same as a self-contained spec. The user and
the session can agree on something that lives only in the conversation: a
decision referred to as "the option we picked", a term defined out loud but
never in the body, an assumption both sides took for granted. The write-back
is per point, so the target can be right point by point and still miss what a
reader with no access to the conversation needs.

That reader is usually next. A kabeuchi on an issue is often followed by
`/jikkyo <issue URL>`, which runs `/goal` in a headless child that cannot ask
anyone anything. Every gap left in the body becomes either a guess by the child
or a stalled run, and either is found only after the run.

## The checklist

The checker applies exactly these six items, each to the target as a whole.
They cover what a `/goal` condition that holds up across many turns needs: a
measurable end state, a stated check, and the constraints that matter.

| Item | The target passes when |
|---|---|
| **Goal** | What is to be achieved is stated in the body, in one place. |
| **Done criteria** | Acceptance criteria are written as checkable items — a task list (`- [ ]`) that `/jikkyo`'s child can tick — each verifiable by a command, a test, or an observable result. |
| **Scope** | What is out of scope is stated, so the run does not wander. |
| **No open decisions** | No TODO, TBD, "to be decided", or question is left unresolved, and every option the interview chose between is recorded as chosen. |
| **Self-contained** | Nothing refers to the conversation ("as discussed", "the option above"), and the terms, files, and commands the run needs are named in the body. |
| **Constraints** | Required conventions — language, commit style, tests to run, things not to touch — are stated or pointed to. |

Two notes on what is and is not on the list:

- **Constraints stay on it** because a run resumed with `/jikkyo --resume` does
  not load the project's `CLAUDE.md`. A convention that lives only there is
  invisible to that run unless the target states it or points to it.
- **Permissions and tool access are not on it.** `/jikkyo`'s launcher fixes
  them, and nothing written in the target can change them, so a gap there is
  not one the target can close.

A "Known gaps" section in the target does not make an item pass. It records
what is still missing; the item it names is still a gap.
