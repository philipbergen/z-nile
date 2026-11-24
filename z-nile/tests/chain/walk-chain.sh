#!/usr/bin/env bash
# f0437 step 6, slice 1: the one-time real-data proof (check.sh only, never promoted). The engine of THIS checkout writes the
# approval facts of the real waiting tickets (as origin/main holds them) into a throwaway folder under .cache/, the Go reader
# serves them as the daemon does, and the page's renderer runs over what was served. Nothing is written into the main checkout:
# `./zn approve --queue` keeps its run folder under the first worktree of the repository it runs in, so it runs in a throwaway
# local clone of this checkout (under .cache/), whose origin is the real one.
# ZN_CHAIN_KEEP=<dir> keeps the served facts there (to freeze a fixture).
set -euo pipefail
HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TOP="$(git -C "$HOME_DIR" rev-parse --show-toplevel)"
D="$TOP/.cache/chain-$$"
mkdir -p "$D"
trap 'rm -rf "$D"' EXIT
C="$D/clone"
git clone -q --local --no-hardlinks "$TOP" "$C"
git -C "$C" remote set-url origin "$(git -C "$TOP" remote get-url origin)"
git -C "$C" fetch -q origin main
(cd "$C" && ZN_LIVE=off ZN_LIVE_DIR="$D" ./zn approve --queue >/dev/null)
source "$HOME_DIR/lib/goenv.sh"
(cd "$HOME_DIR/go" && ZN_REAL_FACTS="$D/approvals.json" ZN_REAL_SERVED="$D/served.json" go test -count=1 -run TestRealFactsChain ./internal/web)
if [[ -n ${ZN_CHAIN_KEEP:-} ]]; then mkdir -p "$ZN_CHAIN_KEEP" && cp "$D/served.json" "$ZN_CHAIN_KEEP/served.json"; fi
node "$HOME_DIR/tests/tooling/app-md-real.node.js" "$HOME_DIR/app" "$D/served.json" --oracle
