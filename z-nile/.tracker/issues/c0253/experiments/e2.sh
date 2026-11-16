#!/bin/sh
cd "$(dirname "$0")/main" || exit 2
trap './zn work stop >/dev/null 2>&1; touch .cache/work/stop' EXIT
rm -f .cache/work/state .cache/work/stop
./zn work --detach
sleep 4
./zn work status
echo "--- processes"; ps -axo pid,ppid,command | grep "[e]ngine/main" | head -3
echo "--- reap dry-run (min-age 0)"; ./zn reap --dry-run --min-age 0 --root "$PWD" 2>&1 | tail -3
echo "--- reap session-end dry-run"; ./zn reap --session-end --dry-run 2>&1 | tail -3
./zn work stop
sleep 3
./zn work status
echo "--- log"; tail -4 .cache/work/log
echo "--- processes after"; ps -axo pid,ppid,command | grep "[e]ngine/main" | head -3
