#!/usr/bin/env bash
#
# prompt-hook.sh — UserPromptSubmit hook: restate the kabeuchi contract each turn.
#
# kabeuchi-prompt-hook
#
# ^ DO NOT REMOVE OR RENAME that marker. The `hooks:` block in ../SKILL.md greps
# for it before executing this file. That block searches the three places this
# skill gets installed — a plugin root, a project's .claude/skills, a personal
# ~/.claude/skills — and a path is not an identity: `$CLAUDE_PLUGIN_ROOT` and
# `$CLAUDE_PROJECT_DIR` are read fresh from the environment on every turn, and a
# script sitting at the same relative path under some other plugin or project is
# not this one. The hook would otherwise execute it on every prompt the user
# submits, for the rest of the session. The marker is also what lets the search
# fall through correctly rather than merely safely: an unrelated plugin root
# fails to match and the next candidate gets its turn. tests/run.sh asserts the
# marker is still here, and exercises each candidate against a decoy.
#
# Registered by the `hooks:` block in ../SKILL.md, which means it is installed
# only when /kabeuchi is actually invoked and stays for the rest of that session.
# A session that never ran kabeuchi never registers it.
#
# It prints one line to stdout, which Claude Code passes to the model as extra
# context for the turn, whenever the current session has a marker file — that
# is, whenever a grilling is in progress. With no marker it prints nothing, so
# the hook costs nothing once the session moves on to other work.
#
# The line exists because a kabeuchi session runs for dozens of turns, and over
# that distance the two rules that make it kabeuchi rather than a chat — ask one
# question at a time, write each settled point back into the target — are the
# first things to slip out of the model's attention.
#
# The message is deliberately English, matching SKILL.md and the status line.
#
# Exit codes:
#   0  always — a UserPromptSubmit hook that exits 2 blocks the user's prompt,
#      and no reminder is worth swallowing someone's message.
#
set -u

session="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$session" ] && [ ! -t 0 ]; then
  session="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null | head -n 1)"
fi

case "$session" in
  "" | . | .. | *[!A-Za-z0-9._-]* ) exit 0 ;;
esac

marker="${KABEUCHI_DIR:-$HOME/.claude/kabeuchi}/$session"
[ -s "$marker" ] || exit 0

target="$(head -n 1 "$marker" 2>/dev/null)"
[ -n "$target" ] || exit 0

printf 'kabeuchi in progress. Target: %s. Ask one question at a time. Write each settled point back into the target in place.\n' "$target"
exit 0
