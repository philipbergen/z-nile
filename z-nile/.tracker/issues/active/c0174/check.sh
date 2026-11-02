#!/usr/bin/env bash
# Acceptance checks for c0174. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# This chore edits another item's files, so no spec is promoted: the claims about the delivered edits run here, at
# `./zn done`, and never again (c0183's pattern). The files are found with `./zn find`, never by a path of the backlog.

# The prep landed with the patch applied (the user's decision), so the merge base must hold it and the document must be
# that text, byte for byte. A merge base without the patch (a re-prep got there first, or the prep did not carry it), or
# any edit to the document, is red. The base is the branch's merge base.
exactdoc() { # $1 the file, $2 the patch; run inside bash -c with ZN_ROOT set
  local top=$ZN_ROOT file rel base tmp
  file=$(cd "$(dirname "$1")" && printf "%s/%s" "$(pwd -P)" "$(basename "$1")") || return 1
  rel=${file#"$top/"}
  base=$(git -C "$top" merge-base origin/main HEAD) || { echo "no origin/main to compare with"; return 1; }
  tmp=$(mktemp -d) || return 1
  if ! git -C "$top" show "$base:$rel" > "$tmp/in" 2>/dev/null; then echo "$rel is not in the merge base"; rm -rf "$tmp"; return 1; fi
  if ! patch -R -f -F 0 --dry-run -s "$tmp/in" < "$2" > /dev/null 2>&1; then echo "the merge base does not hold $2 for $rel (a re-prep got there first, or the prep did not carry it)"; rm -rf "$tmp"; return 1; fi
  if ! cmp -s "$tmp/in" "$file"; then echo "$rel differs from its merge-base text:"; diff "$tmp/in" "$file" | head -10; rm -rf "$tmp"; return 1; fi
  rm -rf "$tmp"
}
export -f exactdoc

# Work outside `check` is limited to cheap reads (`./zn find`); everything else goes inside `check`.
W="$("$ZN_ROOT/zn" find c0083)/acceptance/suites.spec.luau"
[[ -f $W ]] || W="$PWD/tests/acceptance/c0083/suites.spec.luau" # promoted, once c0083 is done
C83="$("$ZN_ROOT/zn" find c0083)/c0083.md"

# the two titles c0083's own check.sh names by prefix (its `cases_in`, which strips newlines and tabs before it looks)
check "AC1: c0083's suites.spec is exactly the patched file, names no check.yml and keeps the case titles c0083's check.sh names" \
	bash -c 'patch -R -f --dry-run -s "$1" < "$2" >/dev/null || { echo "$1 is not the patched file ($2 does not reverse-apply)"; exit 1; }
		! grep -n "check\.yml" "$1" || exit 1
		# the whole file: the blob of today'"'"'s suites.spec (a6be6e73) with the patch applied; cannot be moved by the author
		[[ ! -x $1 ]] || { echo "$1 is executable: a spec keeps its mode"; exit 1; }
		got=$(git hash-object "$1")
		[[ $got == db255a0a23b3d3336062daeeca725dec1cfd8da6 ]] || { echo "$1 is blob $got, not the patched file db255a0a..."; exit 1; }
		flat=$(tr -d "\n\t" < "$1")
		for title in "a file a spec reads as text selects that spec, and a spec change selects the specs that scan every spec" \
			"a deleted or renamed file still selects the specs that named it"; do
			grep -qF "it(\"$title" <<<"$flat" || { echo "no case titled \"$title\""; exit 1; }
		done' \
	ac1 "$W" "$HERE/experiments/suites.patch"
check "AC2: the pair holds on this tree and the folder block selects ci-workflow against the model, and fails when the model or the block is wrong" \
	lune run "$HERE/experiments/folder-case.luau" "$W"
check "AC3: c0083.md is unchanged from a merge base that holds the patch, and no longer names check.yml" \
	bash -c 'exactdoc "$1" "$2" && ! grep -n "check\.yml" "$1"' \
	ac3 "$C83" "$HERE/experiments/c0083-doc.patch"
# The prep commit carries the edit to the other item's sequestered spec (the user's decision), and AC1's blob pin proves
# the file is patched. A legitimate execution therefore changes no sequestered file, whoever else is in the raft: only
# R100 renames (the move to active/). The files AC1 to AC3 read or run that are not sequestered (this item's patches and
# harness, c0083.md) must not change either, or the branch could rewrite what the checks judge them by.
check "AC4: no sequestered file, and none of this item's experiments or c0083.md, differs from the merge base (only R100 renames)" \
	bash -c 'cd "$ZN_ROOT" && base=$(git merge-base origin/main HEAD) || { echo "no origin/main to compare with"; exit 1; }
		got=$(git diff --find-renames=100% --name-status "$base" -- "*/.tracker/**/check.sh" "*/.tracker/**/acceptance/**" "*/.tracker/**/c0174/experiments/**" "*/.tracker/**/c0083/c0083.md" | grep -v "^R100") || true
		[[ -z $got ]] || { printf "differing files:\n%s\n" "$got"; exit 1; }'
check "AC5: the tracker audit finds no error" "$ZN_ROOT/zn" audit

finish
