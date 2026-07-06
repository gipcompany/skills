#!/usr/bin/env bash
#
# run.sh — regression tests for the carve-it helper scripts.
#
# Zero dependencies beyond git + bash: every test builds a throwaway git repo in
# a temp dir, exercises one script, and asserts on its exit code and output.
# Run from anywhere:  bash tests/run.sh
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${HERE}/../scripts"

# shellcheck source=fixtures/scenario.sh
. "${HERE}/fixtures/scenario.sh"

pass=0
fail=0

ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

# Build an isolated repo with one commit on branch 'work'. Echoes its path.
new_repo() {
  local d
  d="$(mktemp -d)"
  git -C "$d" init -q -b work
  git -C "$d" config user.email carve@test
  git -C "$d" config user.name carve-test
  printf 'one\n' > "$d/a.txt"
  git -C "$d" add a.txt
  git -C "$d" commit -q -m 'feat: first'
  echo "$d"
}

echo "backup.sh"
{
  d="$(new_repo)"
  ref="$(cd "$d" && bash "$SCRIPTS/backup.sh")"
  assert_eq "prints a backup/work/<ts> ref" "backup/work/" "${ref%%[0-9]*}"
  have="$(git -C "$d" rev-parse --verify --quiet "refs/heads/$ref" || true)"
  work="$(git -C "$d" rev-parse work)"
  assert_eq "backup ref points at work's tip" "$work" "$have"

  rc=0; (cd "$d" && bash "$SCRIPTS/backup.sh" nope) >/dev/null 2>&1 || rc=$?
  assert_eq "invalid branch exits 1" "1" "$rc"
  rm -rf "$d"
}

echo "verify-tree.sh"
{
  d="$(new_repo)"
  a="$(git -C "$d" rev-parse HEAD)"
  # An empty commit on top has a DIFFERENT commit hash but the SAME tree as a.
  git -C "$d" commit -q --allow-empty -m 'chore: empty'
  same="$(git -C "$d" rev-parse HEAD)"
  # A real change produces a different tree.
  printf 'two\n' > "$d/a.txt"
  git -C "$d" commit -q -am 'feat: change'
  diff_tree="$(git -C "$d" rev-parse HEAD)"

  rc=0; (cd "$d" && bash "$SCRIPTS/verify-tree.sh" "$a" "$same") >/dev/null 2>&1 || rc=$?
  assert_eq "identical trees, different commits -> exit 0" "0" "$rc"

  rc=0; (cd "$d" && bash "$SCRIPTS/verify-tree.sh" "$a" "$diff_tree") >/dev/null 2>&1 || rc=$?
  assert_eq "differing trees -> exit 1" "1" "$rc"

  rc=0; (cd "$d" && bash "$SCRIPTS/verify-tree.sh" "$a") >/dev/null 2>&1 || rc=$?
  assert_eq "wrong arg count -> exit 2" "2" "$rc"
  rm -rf "$d"
}

echo "restore.sh"
{
  d="$(new_repo)"
  c1="$(git -C "$d" rev-parse HEAD)"
  # Two backups with controlled, distinct timestamps; the later one must win.
  git -C "$d" branch backup/work/20200101-000000 "$c1"
  git -C "$d" branch backup/work/20200102-000000 "$c1"
  # Advance work past the backups.
  printf 'two\n' > "$d/a.txt"
  git -C "$d" commit -q -am 'feat: advance'
  c2="$(git -C "$d" rev-parse HEAD)"

  out="$(cd "$d" && bash "$SCRIPTS/restore.sh")"
  latest="$(printf '%s\n' "$out" | sed -n 's/^latest backup: //p')"
  assert_eq "dry-run reports the newest backup" "backup/work/20200102-000000" "$latest"
  assert_eq "dry-run does not move work" "$c2" "$(git -C "$d" rev-parse work)"

  # The --run branch guard must be exercised via a branch that HAS a backup but
  # is NOT checked out. (Targeting a backup-less branch would exit 1 through the
  # earlier 'no backup found' path instead, leaving the destructive-reset guard
  # untested.) 'work' stays checked out; we target 'other', which owns a backup.
  git -C "$d" branch other "$c2"
  git -C "$d" branch backup/other/20200101-000000 "$c1"
  err="$(cd "$d" && bash "$SCRIPTS/restore.sh" --run other 2>&1 1>/dev/null)" && rc=0 || rc=$?
  assert_eq "--run on a branch that isn't checked out refuses (exit 1)" "1" "$rc"
  case "$err" in
    *"current branch is 'work'"*) ok "refusal hits the current-branch guard, not 'no backup'" ;;
    *) bad "refusal should hit the current-branch guard (got: ${err})" ;;
  esac
  assert_eq "guarded --run leaves the target branch untouched" "$c2" "$(git -C "$d" rev-parse other)"

  # The distinct 'no backup found' refusal path (also exit 1).
  rc=0; (cd "$d" && bash "$SCRIPTS/restore.sh" --run nope) >/dev/null 2>&1 || rc=$?
  assert_eq "--run on a branch with no backup exits 1" "1" "$rc"

  (cd "$d" && bash "$SCRIPTS/restore.sh" --run work) >/dev/null 2>&1
  assert_eq "--run resets work to the newest backup" "$c1" "$(git -C "$d" rev-parse work)"
  rm -rf "$d"
}

echo "restore.sh (nested-branch backup isolation)"
{
  d="$(new_repo)"
  git -C "$d" branch -m work feature
  c1="$(git -C "$d" rev-parse feature)"
  git -C "$d" branch backup/feature/20200101-000000 "$c1"
  # A leftover backup that BELONGS TO 'feature/notifications' (a different
  # branch). 'notifications' sorts lexically above any digit, so a naive prefix
  # match on backup/feature/ would surface it first and roll 'feature' back onto
  # the wrong branch's snapshot. restore.sh must ignore nested backups.
  git -C "$d" branch backup/feature/notifications/20991231-235959 "$c1"
  out="$(cd "$d" && bash "$SCRIPTS/restore.sh" feature)"
  latest="$(printf '%s\n' "$out" | sed -n 's/^latest backup: //p')"
  assert_eq "dry-run ignores a nested branch's backup" "backup/feature/20200101-000000" "$latest"
  rm -rf "$d"
}

echo "end-to-end (a carved sequence reproduces the target tree)"
{
  d="$(mk_target_repo)"
  target="$(git -C "$d" rev-parse HEAD)"
  parent="$(git -C "$d" rev-parse HEAD~1)"

  # Reference carve on a detached HEAD off the target's parent, using ONLY the
  # two documented Phase 3 staging moves: final-state checkout, and a direct
  # intermediate edit for the file split across commits (src/app.js).
  git -C "$d" checkout -q --detach "$parent"
  # 001 refactor: rename only. format.js reaches its final state; app.js is
  # written to its intermediate state (renamed, no .trim() yet).
  git -C "$d" checkout "$target" -- src/format.js
  write_app_intermediate "$d"
  git -C "$d" add -A && git -C "$d" commit -q -m 'refactor: rename fmt to format'
  # 002 feat: the behavior change + its test. app.js's LAST touch is its
  # final-state checkout, which structurally guarantees the final tree matches.
  git -C "$d" checkout "$target" -- src/app.js test/app.test.js
  git -C "$d" add -A && git -C "$d" commit -q -m 'feat: trim run() output'
  good_tip="$(git -C "$d" rev-parse HEAD)"

  rc=0; (cd "$d" && bash "$SCRIPTS/verify-tree.sh" "$target" "$good_tip") >/dev/null 2>&1 || rc=$?
  assert_eq "carved sequence is tree-equivalent to target -> exit 0" "0" "$rc"

  # Negative: a carve that FORGETS app.js's final-state checkout leaves it stuck
  # at the intermediate (no .trim()), so the gate must catch the dropped change.
  git -C "$d" checkout -q --detach "$parent"
  git -C "$d" checkout "$target" -- src/format.js
  write_app_intermediate "$d"
  git -C "$d" add -A && git -C "$d" commit -q -m 'refactor: rename fmt to format'
  git -C "$d" checkout "$target" -- test/app.test.js   # forgot src/app.js
  git -C "$d" add -A && git -C "$d" commit -q -m 'feat: trim run() output'
  bad_tip="$(git -C "$d" rev-parse HEAD)"

  rc=0; (cd "$d" && bash "$SCRIPTS/verify-tree.sh" "$target" "$bad_tip") >/dev/null 2>&1 || rc=$?
  assert_eq "carve with a dropped final-state checkout -> exit 1" "1" "$rc"
  rm -rf "$d"
}

echo
printf 'total: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
