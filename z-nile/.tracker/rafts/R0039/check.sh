#!/usr/bin/env bash
# Exit criteria for R0039. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0039); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0039

# a Linux host without bubblewrap fails here instead of installing a package from a check
check "RC1: this host can run the spec jail" bash -c '{ [[ $(uname -s) != Linux ]] || command -v bwrap >/dev/null; } && bash scripts/linux-jail.sh'

finish
