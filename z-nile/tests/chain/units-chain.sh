#!/usr/bin/env bash
# f0437 step 6, slice 2: the one-time real-data proof (check.sh only, never promoted). The engine of THIS checkout writes the units
# index, the theme facts and the approval facts of the real tracker into a throwaway folder under .cache/, the Go reader serves them
# as the daemon does, and the page's own code (the renderer with the index's ids, the walk, the detail view) runs over what was
# served. Nothing is written into the main checkout: everything runs in a throwaway local clone of this checkout under .cache/
# (its origin is the real one), the way walk-chain.sh does.
# ZN_CHAIN_KEEP=<dir> keeps the served files there (to freeze a fixture).
set -euo pipefail
HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TOP="$(git -C "$HOME_DIR" rev-parse --show-toplevel)"
D="$TOP/.cache/chain-units-$$"
mkdir -p "$D"
trap 'rm -rf "$D"' EXIT
C="$D/clone"
git clone -q --local --no-hardlinks "$TOP" "$C"
git -C "$C" remote set-url origin "$(git -C "$TOP" remote get-url origin)"
git -C "$C" fetch -q origin main
(cd "$C" && ZN_LIVE=off ZN_LIVE_DIR="$D" ./zn approve --queue >/dev/null)
(cd "$C" && ZN_LIVE=off ZN_LIVE_DIR="$D" ./zn board -O --out "$D/board.html" >/dev/null)
source "$HOME_DIR/lib/goenv.sh"
(cd "$HOME_DIR/go" && ZN_REAL_FACTS="$D/approvals.json" ZN_REAL_SERVED="$D/served.json" ZN_REAL_UNITS="$D/units.json" ZN_REAL_UNITS_SERVED="$D/units.served.json" ZN_REAL_THEMES="$D/themes.json" ZN_REAL_THEMES_SERVED="$D/themes.served.json" go test -count=1 -run 'TestRealFactsChain|TestRealUnitsChain|TestRealThemesChain' ./internal/web)
if [[ -n ${ZN_CHAIN_KEEP:-} ]]; then mkdir -p "$ZN_CHAIN_KEEP" && cp "$D/served.json" "$D/units.served.json" "$D/themes.served.json" "$D/units.json" "$ZN_CHAIN_KEEP/"; fi
echo "units file on disk: $(wc -c < "$D/units.json") bytes"
node "$HOME_DIR/tests/tooling/app-md-real.node.js" "$HOME_DIR/app" "$D/served.json" --oracle --units="$D/units.served.json" --themes="$D/themes.served.json" --units-bytes="$(wc -c < "$D/units.json")"
