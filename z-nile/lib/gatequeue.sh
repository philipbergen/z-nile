#!/usr/bin/env bash
# d0426 step 2: the machine-wide gate queue, for z-nile/check.sh's outermost block. Sourced.
# gatequeue_run <mode> <checkout> <command...> runs the command once no other gate runs on this machine (the lock and
# the waiting are z-nile/lib/gatequeue.pl's). --plan and an inner gate (ZN_MEASURED set) take no lock;
# ZN_GATE_QUEUE=off skips the queue and says so. The command's exit status is returned.
gatequeue_run() {
  local mode="$1" checkout="$2" here
  shift 2
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  if [[ "$mode" == plan || -n "${ZN_MEASURED:-}" ]]; then
    "$@"
    return
  fi
  if [[ "${ZN_GATE_QUEUE:-}" == off ]]; then
    echo "gate: ZN_GATE_QUEUE=off: not queuing behind other gates on this machine" >&2
    "$@"
    return
  fi
  perl "$here/gatequeue.pl" --mode "$mode" --checkout "$checkout" -- "$@"
}
