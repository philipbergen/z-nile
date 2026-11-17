#!/usr/bin/env bash
# Acceptance checks for c0397. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0397 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0397"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# the published main AC1 compares against, printed outside `check` (a passing command's output is hidden): a swapped
# origin is review's to catch
echo "AC1 base: $(git -C "$ZN_ROOT" ls-remote --get-url origin) refs/heads/main"
check "AC1: f0201's promoted config.spec and receipts.spec are f0201's prepared files with exactly c0397's three cases narrowed, byte for byte, and every other file of f0201's promoted folder and its finished check.sh is unchanged" \
	bash -c 'test "$(shasum -a 256 < "$1" | cut -d" " -f1)" = 65f66165f8604cab287ca499ee274f9b835325cfb12c0a823fe570dbd5169217 \
		|| { echo "narrow.py is not the reviewed file (its sha256 is pinned here, so the approval binds it)"; exit 1; }
		python3 -I "$1" "$2"' _ "$A/narrow.py" "$ZN_ROOT"
check "AC2: f0201's acceptance checks pass from its finished folder, the three narrowed cases among them" \
	bash -c 'bash "$("$ZN_ROOT/zn" find f0201)/check.sh"'

finish
