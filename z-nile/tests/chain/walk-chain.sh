#!/usr/bin/env bash
# f0437 step 6, slice 1: the one-time real-data proof (check.sh only, never promoted). The engine writes the approval facts of the
# real waiting tickets into a throwaway folder under .cache/, the Go reader serves them as the daemon does, and the page's
# renderer runs over what was served; each contract section the page receives must equal the section on disk.
set -euo pipefail
HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TOP="$(git -C "$HOME_DIR" rev-parse --show-toplevel)"
D="$TOP/.cache/chain-$$"
mkdir -p "$D"
trap 'rm -rf "$D"' EXIT
ZN_LIVE=off ZN_LIVE_DIR="$D" "$TOP/zn" approve --queue >/dev/null
source "$HOME_DIR/lib/goenv.sh"
(cd "$HOME_DIR/go" && ZN_REAL_FACTS="$D/approvals.json" ZN_REAL_SERVED="$D/served.json" go test -count=1 -run TestRealFactsChain ./internal/web)
node "$HOME_DIR/tests/tooling/app-md-real.node.js" "$HOME_DIR/app" "$D/served.json" --oracle
