#!/usr/bin/env bash
# c0287 AC2: a slow machine, simulated. Every CLI fake waits FAKE_DELAY = 3 s before its first output (c0279's knob),
# and an author waits FAKE_START_DELAY = 12 s more before it starts its nested review (longer than the 10 s limit of
# the cases that test a stall); control-cli and trackerstate still pass. Run from the z-nile home, bounded:
#   ./zn run --time 900 -- bash <item>/acceptance/slow.sh        (check.sh runs it as AC2; E3 took 366 s)
# Without a dispatched step's variables (every ZN_ variable but ./zn run's ZN_BOUNDED_DEADLINE unset, z-nile/bin off
# PATH): they reach a spec's fixtures under ./zn dispatch, and the agent's git wrapper turns trackerstate's broker
# cases red on main too (c0287 experiments/unfixed-dispatched-env.txt); d0355 owns that leak. The fence still clears
# the GitHub settings of every spec process, and the jail still guards the repository: only the step's variables go.
set -u
for v in $(compgen -e | grep '^ZN_' | grep -vx 'ZN_BOUNDED_DEADLINE'); do unset "$v"; done
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)
export PATH
if env | grep '^ZN_' | grep -qv '^ZN_BOUNDED_DEADLINE='; then echo "slow.sh: a ZN_ variable survived" >&2; exit 2; fi
FAKE_DELAY=3 FAKE_START_DELAY=12 exec lune run tests/run -- \
  tests/acceptance/c0117/control-cli.spec.luau tests/acceptance/c0117/trackerstate.spec.luau
