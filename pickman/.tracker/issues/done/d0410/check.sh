#!/usr/bin/env bash
# Acceptance checks for d0410. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home

# The spec is z-nile's (it drives ./zn finish in a fixture), so it runs from z-nile's home.
finish_spec() {
	(cd "$ZN_ROOT/z-nile" && lune run tests/run -- "$ZN_ROOT/z-nile/tests/tooling/finish-deleted.spec.luau")
}
check "AC1: ./zn finish captures no deleted path: a deleted spec gets no watch file and its folder is not made again, a deleted source is in no list, and a layer with no deletion captures what it did" finish_spec

finish
