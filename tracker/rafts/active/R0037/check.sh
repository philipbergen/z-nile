#!/usr/bin/env bash
# Exit criteria for R0037. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0037); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0037

check "RC1: Awareness, HudView, Main.client, the project files and architecture.md are unchanged" bash -c 'git diff --quiet origin/main...HEAD -- src/shared/Logic/Awareness src/client/HudView.luau src/client/Main.client.luau tracker/architecture.md default.project.json lobby.project.json'

finish
