#!/usr/bin/env bash
#
# run.sh — regression tests for the kabeuchi helper scripts.
#
# Zero dependencies beyond git + bash: each test writes small text blobs to a
# temp dir, runs one script, and asserts on its stdout and exit code. Run from
# anywhere:  bash tests/run.sh
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${HERE}/../scripts"
NORMALIZE="${SCRIPTS}/normalize.sh"
MERGE3="${SCRIPTS}/merge3.sh"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}

echo "normalize.sh"
{
  # CRLF -> LF, and the trailing newline is stripped.
  out="$(printf 'a\r\nb\r\n' | bash "$NORMALIZE")"
  assert_eq "CRLF becomes LF, trailing newline stripped" "$(printf 'a\nb')" "$out"

  # Trailing blank lines collapse away entirely.
  out="$(printf 'hello\n\n\n' | bash "$NORMALIZE")"
  assert_eq "trailing newlines stripped" "hello" "$out"

  # Trailing spaces/tabs at the very end of the body are stripped.
  out="$(printf 'hello \t ' | bash "$NORMALIZE")"
  assert_eq "trailing spaces/tabs stripped" "hello" "$out"

  # Interior blank lines are preserved — only the END of the body is trimmed.
  out="$(printf 'a\n\nb\n' | bash "$NORMALIZE")"
  assert_eq "interior blank line preserved" "$(printf 'a\n\nb')" "$out"

  # The core GitHub scenario: our own write has no trailing newline, GitHub's
  # read-back appends one. Both must normalize to the SAME text (else every
  # check after our own write would look like an external "conflict").
  ours="$(printf 'spec body' | bash "$NORMALIZE")"
  github="$(printf 'spec body\n' | bash "$NORMALIZE")"
  assert_eq "GitHub's appended newline is not seen as a change" "$ours" "$github"

  # Normalization is idempotent.
  once="$(printf 'x\r\n\r\n' | bash "$NORMALIZE")"
  twice="$(printf '%s' "$once" | bash "$NORMALIZE")"
  assert_eq "normalization is idempotent" "$once" "$twice"

  # A missing file argument is a usage error.
  rc=0; bash "$NORMALIZE" /no/such/file >/dev/null 2>&1 || rc=$?
  assert_eq "missing file exits 2" "2" "$rc"
}

echo "merge3.sh"
{
  d="$(mktemp -d)"
  printf 'Line A\nLine B\nLine C\n'        > "$d/base"
  printf 'Line A EDITED\nLine B\nLine C\n' > "$d/theirs"
  printf 'Line A\nLine B\nLine C EDITED\n' > "$d/mine"

  out="$(bash "$MERGE3" "$d/base" "$d/mine" "$d/theirs")" && rc=0 || rc=$?
  assert_eq "disjoint edits merge cleanly -> exit 0" "0" "$rc"
  case "$out" in
    *"Line A EDITED"*) ok "clean merge keeps their edit" ;;
    *) bad "clean merge dropped their edit (got: $out)" ;;
  esac
  case "$out" in
    *"Line C EDITED"*) ok "clean merge keeps my edit" ;;
    *) bad "clean merge dropped my edit (got: $out)" ;;
  esac
  case "$out" in
    *"<<<<<<<"*) bad "clean merge must not contain conflict markers" ;;
    *) ok "clean merge has no conflict markers" ;;
  esac

  # Overlapping edits to the same line must NOT auto-resolve.
  printf 'shared line\n'   > "$d/base2"
  printf 'their version\n' > "$d/theirs2"
  printf 'my version\n'    > "$d/mine2"
  out="$(bash "$MERGE3" "$d/base2" "$d/mine2" "$d/theirs2")" && rc=0 || rc=$?
  assert_eq "overlapping edits conflict -> exit 1" "1" "$rc"
  case "$out" in
    *"<<<<<<<"*">>>>>>>"*) ok "conflict output carries markers" ;;
    *) bad "conflict output missing markers (got: $out)" ;;
  esac

  # Usage errors.
  rc=0; bash "$MERGE3" "$d/base" "$d/mine" >/dev/null 2>&1 || rc=$?
  assert_eq "wrong arg count exits 2" "2" "$rc"
  rc=0; bash "$MERGE3" "$d/base" "$d/mine" /no/such/file >/dev/null 2>&1 || rc=$?
  assert_eq "missing input file exits 2" "2" "$rc"

  rm -rf "$d"
}

echo "merge3.sh (leaves no temp litter in the working directory)"
{
  # The bug this guards against: the old inline flow wrote mine/base/theirs/
  # merged files into the caller's working tree and never cleaned them up.
  work="$(mktemp -d)"
  printf 'a\n' > "$work/base"; printf 'a\n' > "$work/mine"; printf 'a\n' > "$work/theirs"
  before="$(ls -A "$work" | sort | tr '\n' ' ')"
  ( cd "$work" && bash "$MERGE3" base mine theirs >/dev/null 2>&1 )
  after="$(ls -A "$work" | sort | tr '\n' ' ')"
  assert_eq "merge leaves no extra files in CWD" "$before" "$after"
  rm -rf "$work"
}

echo
printf 'total: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
