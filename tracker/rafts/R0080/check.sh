#!/usr/bin/env bash
# Exit criteria for R0080. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0080); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0080

# the beta job's text: from `  beta:` to the end of the file (it is the last job)
beta_job() { sed -n '/^  beta:$/,$p' .github/workflows/check.yml; }

# RC1: the version the deploy step publishes is what the comment and the runtime tests use, in that order
version_flows() {
  local job; job=$(beta_job)
  grep -q 'id: deploy' <<<"$job" || { echo "no step with id: deploy"; return 1; }
  [ "$(grep -c 'steps.deploy.outputs.version' <<<"$job")" -ge 3 ] || { echo "comment and runtime tests don't use the deploy's version"; return 1; }
  local d c r
  d=$(grep -n 'scripts/deploy-beta' <<<"$job" | head -1 | cut -d: -f1)
  c=$(grep -n 'gh pr comment' <<<"$job" | head -1 | cut -d: -f1)
  r=$(grep -n 'scripts/runtime-test' <<<"$job" | head -1 | cut -d: -f1)
  [ -n "$d" ] && [ -n "$c" ] && [ -n "$r" ] && [ "$d" -lt "$c" ] && [ "$c" -lt "$r" ] || { echo "order is not deploy, comment, runtime tests"; return 1; }
}
check "RC1: the published version flows deploy -> PR comment -> runtime tests, in that order" version_flows

# RC2: the Roblox API key is named in exactly two places, the env of the deploy step and of the runtime step,
# both inside the beta job, and nowhere is it echoed
secret_scoped() {
  [ "$(grep -c 'secrets.ROBLOX_API_KEY' .github/workflows/check.yml)" = 2 ] || { echo "secret should be named exactly twice"; return 1; }
  [ "$(beta_job | grep -c 'secrets.ROBLOX_API_KEY')" = 2 ] || { echo "secret named outside the beta job"; return 1; }
  ! grep -rnE 'echo[^#]*ROBLOX_API_KEY|set -x' .github/workflows scripts/deploy-beta.luau scripts/runtime-test.luau scripts/lib/opencloud.luau
}
check "RC2: the API key is named only in the env of the deploy and runtime steps, and never echoed" secret_scoped

# RC3: with nothing configured both commands succeed with a warning, so a fork or a fresh clone is not red
unconfigured() {
  local out
  out=$(ROBLOX_API_KEY= ROBLOX_BETA_UNIVERSE_ID= ROBLOX_BETA_PLACE_ID= lune run scripts/deploy-beta 2>&1) || { echo "$out"; return 1; }
  grep -q 'not configured' <<<"$out" || { echo "$out"; return 1; }
  out=$(ROBLOX_API_KEY= ROBLOX_BETA_UNIVERSE_ID= ROBLOX_BETA_PLACE_ID= lune run scripts/runtime-test -- 1 2>&1) || { echo "$out"; return 1; }
  grep -q 'not configured' <<<"$out" || { echo "$out"; return 1; }
}
check "RC3: unconfigured, deploy-beta and runtime-test skip with a warning and exit 0" unconfigured

finish
