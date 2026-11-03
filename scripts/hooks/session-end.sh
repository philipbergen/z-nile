#!/usr/bin/env bash
# Claude Code SessionEnd hook (c0191): stop what this session left running (`./zn reap --session-end`: every tool process
# started by one of the session's own tool shells, under the repository or the session scratch folders), and any other
# orphan older than a minute. The session's children are not orphans yet while it ends, so the orphan rule alone would
# miss them. Nothing is shown to anyone at this point, so what it stops is also appended to a log. Bounded: fifteen
# seconds of CPU, inside the hook's own twenty-second budget.
export PATH="$HOME/.rokit/bin:$PATH"
input=$(cat)
reason=$(printf '%s' "$input" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[[ $reason == resume ]] && exit 0 # the session goes on
cd "$(dirname "$0")/../.." || exit 0
log="${XDG_STATE_HOME:-$HOME/.local/state}/z-nile"
mkdir -p "$log" 2>/dev/null
source "$PWD/z-nile/lib/cpu.sh"
zn_lower_cpu 15
./zn reap --session-end --min-age 60 --log "$log/reaped.log" >/dev/null 2>&1
exit 0
