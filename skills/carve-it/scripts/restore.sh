#!/usr/bin/env bash
#
# restore.sh — roll a branch back to its most recent carve-it backup.
#
# Usage:
#   restore.sh [branch]          # dry-run: print the latest backup + the command
#   restore.sh --run [branch]    # actually `git reset --hard` the branch to it
#
# With no branch argument the current branch is used. Backups are the refs that
# backup.sh creates (backup/<branch>/<timestamp>); the timestamp sorts
# lexically, so the newest name is the newest backup.
#
# Because `git reset --hard` is destructive, the default is a DRY RUN. The
# real reset only happens with --run, and only when the branch to restore is
# the one currently checked out (so the working tree being discarded is the
# expected one).
#
set -euo pipefail
trap 'echo "restore.sh: FAILED at line ${LINENO}" >&2' ERR

run=0
if [ "${1:-}" = "--run" ]; then
  run=1
  shift
fi

branch="${1:-$(git symbolic-ref --short HEAD)}"

latest="$(git for-each-ref --sort=-refname \
  --format='%(refname:short)' "refs/heads/backup/${branch}/" | head -n1)"

if [ -z "${latest}" ]; then
  echo "restore.sh: no backup found under backup/${branch}/" >&2
  exit 1
fi

echo "latest backup: ${latest}"

if [ "${run}" -ne 1 ]; then
  echo "dry-run (nothing changed)."
  echo "to restore:    git switch ${branch} && git reset --hard ${latest}"
  echo "or re-run as:  restore.sh --run ${branch}"
  exit 0
fi

current="$(git symbolic-ref --short HEAD)"
if [ "${current}" != "${branch}" ]; then
  echo "restore.sh: current branch is '${current}', not '${branch}'." >&2
  echo "            run 'git switch ${branch}' first, then retry." >&2
  exit 1
fi

git reset --hard "${latest}"
echo "restored ${branch} -> ${latest}"
