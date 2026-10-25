#!/usr/bin/env bash
# Exit criteria for R0035. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" ../z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(../zn members R0035); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ../zn promote-check R0035

# a sequestered issue spec before `./zn done`, its promoted copy after it
spec() { # $1 issue id, $2 spec name
  local f
  f="$(../zn find "$1")/acceptance/$2.spec.luau"
  [[ -f $f ]] || f="tests/acceptance/$1/$2.spec.luau"
  echo "$f"
}

hunt_end_to_end() {
  local i
  for i in 1 2 3; do
    lune run tests/run -- "$(spec f0104 hunt)" "$(spec f0100 shots)" "$(spec f0100 drops)" "$(spec f0104 aim)" \
      tests/acceptance/f0013/intents.spec.luau tests/acceptance/f0023/contacts.spec.luau \
      tests/acceptance/f0023/session-ghosts.spec.luau tests/acceptance/f0014/keys.spec.luau >/dev/null 2>&1 \
      || { echo "the ghost-hunt specs fail on repeat $i"; return 1; }
  done
}
check "RC1: a ghost hunt end to end, three times in a row, beside the promoted intent, contact and key-map specs" hunt_end_to_end

server_untouched() {
  git diff --quiet "$(git merge-base origin/main HEAD)" -- src/server default.project.json lobby.project.json src/lobby \
    || { echo "the server adapters, the place files or the lobby changed"; return 1; }
}
check "RC2: the server adapters, the remotes and the lobby are untouched: shots ride the Intent remote" server_untouched

promoted_only_added() {
  local changed
  changed="$(git diff --name-status "$(git merge-base origin/main HEAD)" -- tests/acceptance | grep -v '^A' || true)"
  [[ -z $changed ]] || { echo "promoted specs were changed: $changed"; return 1; }
}
check "RC3: no promoted acceptance spec was edited or removed (Overrides: none)" promoted_only_added

finish
