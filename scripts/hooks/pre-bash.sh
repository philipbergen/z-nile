#!/usr/bin/env bash
# Claude Code PreToolUse hook on Bash and Monitor (c0191): a command that starts an interpreter with no time limit (a bare
# `lune run` of a probe, say), a loop or follow that never ends, or a background call nothing bounds is refused with the
# wrapper to use instead. Exit 2 refuses and the reason goes to the agent; any other exit lets the command run, so a broken
# hook never stops work. The rules are z-nile/engine/boundcmd.luau's. The hook is bounded itself: two seconds of CPU.
export PATH="$HOME/.rokit/bin:$PATH"
# the checkout this hook lives in, whatever folder the session is in
cd "$(dirname "$0")/../.." || exit 0
ZN_CHECKOUT=$PWD
export ZN_CHECKOUT
source "$PWD/z-nile/lib/cpu.sh"
zn_lower_cpu 2
exec lune run z-nile/guard-bash
