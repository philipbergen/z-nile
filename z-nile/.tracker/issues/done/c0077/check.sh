#!/usr/bin/env bash
# Acceptance checks for c0077. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0077 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0077"

# Each spec's cases share one setup, so each spec runs once (here, outside `check`: list mode refuses it);
# a check then requires its named cases to exist in the spec and not fail, and the spec to have loaded.
replace_out=$(lune run tests/run -- "$A/replace-file.spec.luau" 2>&1)
paths_out=$(lune run tests/run -- "$A/cache-paths.spec.luau" 2>&1)
cases_in() { # $1: spec file, $2: its output, $3...: case-name prefixes that must exist and not fail
  local spec=$1 out=$2 c; shift 2
  [[ -f $spec ]] || { echo "missing $spec"; return 1; }
  if grep -q "could not load spec" <<<"$out"; then echo "$out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$out" || { echo "$out" | tail -20; return 1; }
  for c in "$@"; do
    tr -d "\n\t" < "$spec" | grep -qF "it(\"$c" || { echo "$spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$out" | grep -qF ":: $c"; then grep -F -A3 ":: $c" <<<"$out"; return 1; fi
  done
}
replace() { cases_in "$A/replace-file.spec.luau" "$replace_out" "$@"; }
paths() { cases_in "$A/cache-paths.spec.luau" "$paths_out" "$@"; }

check "AC1: replace-file replaces a link to a directory or a file with a regular 0644 file, refuses a real directory, and leaves no temporary file" replace \
  "over a link to a directory, the path becomes a regular file" "over a link to a file, the path becomes a regular file" \
  "a real directory at the path is refused" "content comes from stdin, or from a source file" \
  "a missing folder fails and leaves no temporary file" "a source that can't be read fails after the temporary file is made"
check "AC2: sh.writeReplacing writes through replace-file" replace \
  "sh.writeReplacing over a link to a directory leaves the directory unchanged"
check "AC3: check.sh stops on a failed definitions download, unlinks links at the top of .cache before writing, and lands its build by rename" replace \
  "the gate stops with a message when the definitions download fails" \
  "the gate removes links at the top of .cache before it writes there" \
  "the build lands as a regular file over a link to a directory, and leaves no build folder behind"
check "AC4: the launcher unlinks links at the top of its cache after the command ends, signal death included, and nothing else" replace \
  "after the command ends the launcher unlinks links at the top of the cache it was given" \
  "the launcher unlinks them even when the command was killed by a signal"
check "AC5: every .cache line in scripts/ is on the reviewed list; the scan flags new mentions and stale entries" paths \
  "a new .cache mention in a Luau or a shell file is flagged" "a commented mention is not flagged" \
  "a listed line that is gone is reported" "every .cache line in scripts/ and z-nile/ is on the reviewed list"
check "AC6: no mv -f is left in check.sh, fence.sh or sh.luau" bash -c '
  if grep -nE "\bmv\b.*-f|\"mv\"" ./check.sh lib/fence.sh lib/sh.luau; then
    echo "a move is still used to put a file in place (use lib/replace-file.pl)"; exit 1; fi'

finish
