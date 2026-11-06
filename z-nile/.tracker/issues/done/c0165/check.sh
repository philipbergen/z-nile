#!/usr/bin/env bash
# Acceptance checks for c0165. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0165 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0165"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
S="$A/select.spec.luau"
P="$A/plan.spec.luau"
D="$A/store.spec.luau"
# one file per mechanism (design review 007 F5): each holds at most 4 fixture builds and 10 gate runs (about 40 s idle), and
# each runs once, in the one check that names it
GR="$A/gate-reuse.spec.luau" GI="$A/gate-inputs.spec.luau" GN="$A/gate-norecord.spec.luau" GS="$A/gate-results.spec.luau"
GW="$A/gate-whole.spec.luau" GP="$A/gate-refs.spec.luau" GF="$A/gate-full.spec.luau"
check "AC1: one predicate decides both selection and fingerprints for every seeded change kind, and the moved rules keep their outcomes" lune run tests/run -- "$S"
check "AC2: a spec's fingerprint changes for each kind of input (tracker paths through explicit entries, HEAD for a * spec, a declared ref, the tools, the gate mode) and for nothing else" lune run tests/run -- "$S"
check "AC3: reuseplan.decide gives reuse for a passed row and run for no row, a failed row and every row under --fresh" lune run tests/run -- "$P"
check "AC4: the db records a result that reads back, is idempotent with the latest result winning (12 concurrent recorders leave one row), round-trips any text, stamps resultsdb.SCHEMA, and open answers nil with a reason (a newer schema, an unwritable folder, no sqlite3)" lune run tests/run -- "$D"
check "AC5: through the orchestrator, same content reuses every spec (in a second worktree too), an edit reruns exactly its selection, two runs at once both succeed and leave one passed row, an ordinary run prunes rows older than 30 days, only an exit of 0 records passes, a missing or omitted result counts failed, an input changed mid-run records nothing, a weak jail or a no-record marker records nothing, reuse off runs everything, and * and folder specs rerun when they must" lune run tests/run -- "$P" "$GR" "$GI" "$GN" "$GS"
check "AC6: the runner writes every file's cases and results in process and concurrently, marks a dead worker's file not loaded, and its output and exit code are unchanged" lune run tests/run -- "$A/results.spec.luau"
check "AC7: --full runs every spec and reuses nothing and refuses --fresh with exit 2, an unchanged second affected gate is reused whole with its static report, scoped by projects and base, its digest holds HEAD for a * selection and every selected spec's declared refs (a ref-only spec's ref alone moves it), a gate-check that never says reused never skips, a tree that changed during the gate records no whole-gate pass, the digest ignores spend.md and ignored files, and the workspace reads write nothing to git and fail closed" lune run tests/run -- "$A/digest.spec.luau" "$GF" "$GW" "$GP"
check "AC9: inputs.tsv parses comments, blank lines, files, folders, * and ref: declarations, and refuses the whole file on a malformed line" lune run tests/run -- "$S"
check "AC10: zz-test names reuse, --fresh, declared inputs and the db writer, AGENTS.md names the db, and .gitignore ignores it" lune run tests/run -- "$A/docs.spec.luau"
# promoted specs (every project's tests/acceptance) are unchanged, except the four Overrides and c0165's own folder
# (c0185 lands first: its selector.spec is promoted when this check runs)
OVERRIDES='^z-nile/tests/acceptance/(c0165/|c0114/gate-cover\.spec\.luau$|c0120/graph-homes\.spec\.luau$|c0185/selector\.spec\.luau$|c0172/narrowed\.spec\.luau$)'
promoted_unchanged() {
  local out changed
  # git's own failure (no origin/main, a bad pathspec) is red, never filtered away
  out=$(git -C "$ZN_ROOT" diff --name-only origin/main...HEAD -- "$ZN_ROOT/pickman/tests/acceptance" "$ZN_ROOT/z-nile/tests/acceptance" 2>&1) ||
    { echo "cannot compare with origin/main: $out"; return 1; }
  changed=$(printf '%s\n' "$out" | grep -Ev "$OVERRIDES" | grep -v '^$' || true)
  [[ -z $changed ]] || { echo "promoted specs changed: $changed"; return 1; }
}
check "AC11: no promoted spec changes except the three selector Overrides, c0172's narrowed.spec (the gate-cover digest) and c0165's own folder" promoted_unchanged
# the three selector pins change only by `--graph-only` in their one `affected` helper: with that argument removed, each
# file is main's byte for byte, and the argument is there (zz-test/narrowing-pins-the-whole-file). The fourth Override,
# c0172/narrowed.spec, pins gate-cover.spec whole by SHA-256: it changes only that one digest (every other row and line is
# main's byte for byte), and running it proves the new digest is the narrowed file's (design review 009 F1)
graph_only_narrowed() {
  local f old new ZH=z-nile # repo-relative home, kept out of the literal paths (c0120/check-paths reads them from the item home)
  for f in "$ZH"/tests/acceptance/c0114/gate-cover.spec.luau "$ZH"/tests/acceptance/c0120/graph-homes.spec.luau "$ZH"/tests/acceptance/c0185/selector.spec.luau; do
    old=$(git -C "$ZN_ROOT" show "origin/main:$f" 2>&1) || { echo "cannot read origin/main:$f: $old"; return 1; }
    [[ $(grep -c -- '"--graph-only"' "$ZN_ROOT/$f") == 1 ]] || { echo "$f does not pass --graph-only exactly once"; return 1; }
    new=$(sed -E -e 's/"--", "--graph-only"/"--"/' "$ZN_ROOT/$f") || return 1
    [[ $new == "$old" ]] || { echo "$f changes more than its affected helper's --graph-only"; return 1; }
  done
  # c0172/narrowed.spec: the 64-hex value on the line after the gate-cover row's file name is the only change
  local pin=$ZH/tests/acceptance/c0172/narrowed.spec.luau oldhex newhex
  old=$(git -C "$ZN_ROOT" show "origin/main:$pin" 2>&1) || { echo "cannot read origin/main:$pin: $old"; return 1; }
  oldhex=$(printf '%s\n' "$old" | grep -A1 -F '"gate-cover.spec.luau",' | grep -oE '[0-9a-f]{64}' || true)
  newhex=$(grep -A1 -F '"gate-cover.spec.luau",' "$ZN_ROOT/$pin" | grep -oE '[0-9a-f]{64}' || true)
  [[ ${#oldhex} == 64 && ${#newhex} == 64 ]] || { echo "$pin has no single gate-cover digest row"; return 1; }
  [[ $newhex != "$oldhex" ]] || { echo "$pin keeps main's gate-cover digest, but the overridden gate-cover.spec changed"; return 1; }
  [[ $(sed -e "s/$newhex/$oldhex/" "$ZN_ROOT/$pin") == "$old" ]] || { echo "$pin changes more than the gate-cover digest"; return 1; }
  # the pin holds: c0172's own spec recomputes the digest of the narrowed file with its own normaliser
  lune run tests/run -- tests/acceptance/c0172/narrowed.spec.luau || { echo "c0172/narrowed does not pass on the narrowed gate-cover"; return 1; }
}
check "AC12: each selector Override changes only its affected helper, by \"--graph-only\" right after \"--\", and c0172/narrowed.spec changes only its gate-cover digest, which is the narrowed file's" graph_only_narrowed
# The reviewed lists are sequestered beside the specs ($A): declared-<home>.tsv (the input lines each home's tests/inputs.tsv
# must hold) and audited.tsv (every audited spec, declared or excluded, keyed to the blob that was audited). The executor
# edits none of them; step 7 writes only to the unsequestered $ADD/added-declared-<home>.tsv and $ADD/added-audited.tsv
# (design review 008 F2). A removal of a reviewed line is a sequestration violation, and shows here as a missing line.
ADD="$HERE/declared"
declared_lists() { # every declared-<home>.tsv and added-declared-<home>.tsv that exists
  local f
  for f in "$A"/declared-*.tsv "$ADD"/added-declared-*.tsv; do [[ -f $f ]] && echo "$f"; done
  return 0
}
home_of() { local b; b=$(basename "$1" .tsv); b=${b#added-}; echo "${b#declared-}"; }
# the declared inputs this issue ships (design review 002 F2): every line of every reviewed list and of every addition is
# a line of its home's file, and each home's file parses
declared_shipped() {
  local file home inputs line missing=0 homes=""
  while IFS= read -r file; do
    home=$(home_of "$file")
    inputs="$ZN_ROOT/$home/tests/inputs.tsv"
    [[ -f $inputs ]] || { echo "no $home/tests/inputs.tsv"; return 1; }
    while IFS= read -r line; do
      [[ -z $line || $line == \#* ]] && continue
      grep -qxF -- "$line" "$inputs" || { echo "$home/tests/inputs.tsv lacks: $line (from $(basename "$file"))"; missing=1; }
    done < "$file"
    case " $homes " in *" $home "*) ;; *) homes="$homes $home" ;; esac
  done < <(declared_lists)
  [[ -n $homes ]] || { echo "no declared list found: the check is broken"; return 1; }
  # the selector reads each file and refuses a malformed one (exit 2): it parses
  for home in $homes; do
    (cd "$ZN_ROOT" && lune run "$ZN_ROOT/z-nile/affected" -- --project "$home" "$home/tests/inputs.tsv" > /dev/null) || { echo "$home/tests/inputs.tsv does not parse"; missing=1; }
  done
  return $missing
}
check "AC13: every reviewed and every added declared input line is in its home's inputs.tsv, and each home's file parses" declared_shipped
# the migration of existing work (design review 007 F1, 008 F1 and 009 F2, z-design/rerun-shipped-audits-at-execution): E9's
# search over today's spec files, and every spec that has a declaration, whatever its content now. Each is an audited spec: a
# line of audited.tsv (or of the additions) keys it to the blob that was read, with the class declared (it has declaration
# lines) or covered, fixture or literal (it has none). A hit or declared spec that is new, or edited since its audit, fails
# here until it is re-read and a line for its new blob is added. The search reads only a spec's own text, so it cannot see a
# wrapper (a spec that is one `return require(...)`) or a read made by a helper: every OTHER spec file on the tree therefore
# has a `nohit` line, matched by PATH (blob field `-`), and a spec file with no line at all fails until it is read.
E9_PATTERN='fs\.(readFile|readDir|isFile|isDir)|ls-files|show-toplevel|listLuau|cat-file|lune run|"show"|"log"'
audit_lines() { # the reviewed and the added audit lines, comments and blanks dropped
  local f
  for f in "$A/audited.tsv" "$ADD/added-audited.tsv"; do [[ -f $f ]] && grep -Ev '^(#|$)' "$f"; done
  return 0
}
e9_hits_accounted() {
  local files f blob declared audit bad=0 n=0 listed own
  [[ -s $A/audited.tsv ]] || { echo "no audited.tsv"; return 1; }
  audit=$(audit_lines)
  # every line is well formed: four fields, a known class, a blob id (class nohit: `-`, it is matched by path)
  awk -F'\t' 'NF < 4 || $3 !~ /^(declared|covered|fixture|literal|nohit)$/ || $4 == "" || ($3 == "nohit" ? $2 != "-" : $2 !~ /^[0-9a-f]{40}$/) { bad = 1; print "malformed audit line: " $0 } END { exit bad }' <<<"$audit" || return 1
  declared=$(while IFS= read -r file; do
    h=$(home_of "$file")
    grep -Ev '^(#|$)' "$file" | cut -f1 | sed "s#^#$h/#"
  done < <(declared_lists) | sort -u)
  # every home's tests/ (c0184 adds homes with specs), not only pickman's and z-nile's
  files=$(git -C "$ZN_ROOT" ls-files -co --exclude-standard | grep -E '^[^/]+/tests/.*\.spec\.luau$' || true)
  listed=$(while IFS= read -r f; do
    [[ $f == *.spec.luau && -f $ZN_ROOT/$f ]] || continue
    grep -qE "$E9_PATTERN" "$ZN_ROOT/$f" && echo "$f"
  done <<<"$files"; printf '%s\n' "$declared")
  while IFS= read -r f; do
    [[ -n $f && -f $ZN_ROOT/$f ]] || continue
    n=$((n + 1))
    blob=$(git -C "$ZN_ROOT" hash-object -- "$ZN_ROOT/$f") || { echo "cannot hash $f"; return 1; }
    if grep -qxF -- "$f" <<<"$declared"; then
      awk -F'\t' -v f="$f" -v b="$blob" '$1 == f && $2 == b && $3 == "declared" { ok = 1 } END { exit !ok }' <<<"$audit" ||
        { echo "declared spec edited since its audit, or not keyed as declared: $f ($blob)"; bad=1; }
    else
      awk -F'\t' -v f="$f" -v b="$blob" '$1 == f && $2 == b && $3 ~ /^(covered|fixture|literal)$/ { ok = 1 } END { exit !ok }' <<<"$audit" ||
        { echo "E9 hit neither declared nor excluded (or edited since its exclusion): $f ($blob)"; bad=1; }
    fi
  done < <(printf '%s\n' "$listed" | sort -u)
  # every other spec file on the tree (the search misses wrappers and helper reads, so no text decides this): a nohit line by path
  while IFS= read -r f; do
    [[ $f == *.spec.luau && -f $ZN_ROOT/$f ]] || continue
    grep -qxF -- "$f" <<<"$(printf '%s\n' "$listed")" && continue
    awk -F'\t' -v f="$f" '$1 == f && $3 == "nohit" { ok = 1 } END { exit !ok }' <<<"$audit" ||
      { echo "spec file with no audit line (read it; a spec the E9 search does not hit gets a nohit line): $f"; bad=1; }
  done <<<"$files"
  # a spec audited as declared still has its declaration lines (a deleted line is not a quiet way to unselect it)
  while IFS= read -r f; do
    [[ -f $ZN_ROOT/$f ]] || continue
    grep -qxF -- "$f" <<<"$declared" || { echo "audited as declared but no declaration line: $f"; bad=1; }
  done < <(awk -F'\t' '$3 == "declared" { print $1 }' <<<"$audit" | sort -u)
  # c0165's own specs: before ./zn done they are not under tests/ yet, so their keys are checked against the sequestered files
  if [[ $A == "$HERE/acceptance" ]]; then
    while IFS= read -r f; do
      own="$A/${f##*/}"
      [[ -f $own ]] || { echo "audited c0165 spec has no sequestered file: $f"; bad=1; continue; }
      if awk -F'\t' -v f="$f" '$1 == f && $3 == "nohit" { ok = 1 } END { exit !ok }' <<<"$audit"; then
        # a nohit own spec stays one: the search still does not hit it
        ! grep -qE "$E9_PATTERN" "$own" || { echo "c0165's own nohit spec now matches the E9 search: $f"; bad=1; }
        continue
      fi
      blob=$(git -C "$ZN_ROOT" hash-object -- "$own")
      awk -F'\t' -v f="$f" -v b="$blob" '$1 == f && $2 == b { ok = 1 } END { exit !ok }' <<<"$audit" ||
        { echo "c0165's own spec changed since its audit key: $f"; bad=1; }
    done < <(cut -f1 <<<"$audit" | grep '/tests/acceptance/c0165/' | sort -u)
  fi
  [[ $n -gt 0 ]] || { echo "the E9 search found no spec file: the check is broken"; return 1; }
  return $bad
}
check "AC14: every spec file the E9 search hits and every spec with declared inputs is keyed, with its current blob, in audited.tsv (or the additions), as declared or as excluded, and every other spec file has a nohit line by path" e9_hits_accounted
# the two facts that hold of the core today and that c0238 (the second run waits) and c0239 (--full records) change on purpose:
# a script, before ./zn done only, never a promoted spec (design review 007 F3)
check "AC15: before ./zn done only, two runs that reach one fingerprint at once both run it, and --full neither reads nor writes the db (today's behaviour, which c0238 and c0239 change)" \
	bash -c "[ '$A' != '$HERE/acceptance' ] || lune run tests/run -- '$A/proof-interim.luau'"
# c0165's promoted files are scanned by tooling/repo-fence once `done` moves them into z-nile/tests/acceptance/c0165/, and the
# gate there is the first place a banned name without an ALLOWED entry shows (design review 009 F3). So each file of
# acceptance/*.luau that names a banned name (repo-fence's NAMES, case-insensitively, as the scan does) needs that name as a
# key of its own literal ALLOWED entry, which repo-fence's staleness case accepts before `done` (an unfinished item's spec).
fence_entries() {
  local ZH=z-nile fence f key names block name bad=0 n=0 hit
  fence="$ZN_ROOT/$ZH/tests/tooling/repo-fence.spec.luau"
  names=$(awk '/^local NAMES = \{/ { on = 1; next } on && /^\}/ { exit } on' "$fence" | sed -nE 's/^[[:space:]]*"(.*)",.*/\1/p')
  [[ -n $names ]] || { echo "no NAMES table in $fence: the check is broken"; return 1; }
  for f in "$A"/*.luau; do
    [[ -f $f ]] || continue
    n=$((n + 1))
    key="$ZH/tests/acceptance/c0165/$(basename "$f")"
    # the keys of this file's literal entry: `NAME = "reason",` or `["NAME"] = "reason",` up to the entry's closing brace
    block=$(awk -v k="[\"$key\"] = {" 'index($0, k) { on = 1; next } on && /^\t\},?$/ { exit } on' "$fence" |
      sed -nE 's/^[[:space:]]*(\["([^"]+)"\]|([A-Za-z_]+))[[:space:]]*=.*/\2\3/p')
    while IFS= read -r name; do
      grep -qiF -- "$name" "$f" || continue
      grep -qxF -- "$name" <<<"$block" || { echo "$key names $name, and repo-fence.spec has no ALLOWED entry for it"; bad=1; }
    done <<<"$names"
  done
  [[ $n -gt 0 ]] || { echo "no c0165 .luau file found: the check is broken"; return 1; }
  return $bad
}
check "AC16: every banned name that a c0165 file names has an ALLOWED entry for that file in tooling/repo-fence.spec, so the promoted copy passes the scan" fence_entries

finish
