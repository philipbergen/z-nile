#!/usr/bin/env bash
# c0288 prep E2: write a slow-machine variant of c0260's provenance.spec.luau into the same folder: every claude stub
# call is silent for 35 s before its first output (over the old 30 s limit, under the new 120 s), the fixture is renamed
# so it does not share c0260's, and the stall limit is <limit>. The actor the spec expects follows the fixture's name.
# Run on a prototype only (never on main); delete the variant after the run.
#   bash delay-variant.sh <prototype>/z-nile/.tracker/issues/c0260/acceptance <limit>
set -euo pipefail
dir=$1 lim=$2
sed -e "s/^stall_seconds = 30$/stall_seconds = $lim/" -e "s/^stall_seconds = 120$/stall_seconds = $lim/" \
  -e 's/^local CLAUDE = \[=\[#!\/bin\/bash$/&\nsleep 35/' \
  -e "s/\"c0260-provenance\"/\"c0288-delay-$lim\"/" -e "s/human:c0260-provenance/human:c0288-delay-$lim/" \
  "$dir/provenance.spec.luau" > "$dir/delay35-limit$lim.spec.luau"
