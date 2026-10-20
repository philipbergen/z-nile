#!/usr/bin/env bash
# E8 (c0075, design review round 2 F1): binds under /run next to --tmpfs /run --remount-ro /run. Which order works?
# Run after E1's setup, from a checkout root. Prints PASS/FAIL/INFO lines.
set +e
ROOT=$(pwd -P); mkdir -p "$ROOT/.cache"
pass() { echo "PASS $1"; }; fail() { echo "FAIL $1"; }; info() { echo "INFO $1"; }
sudo -n apt-get install -y bubblewrap >/dev/null 2>&1; sudo -n sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null 2>&1
sudo mkdir -p /run/pickman-co && sudo chown "$USER" /run/pickman-co && echo hi > /run/pickman-co/f
RT=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pickman-run.$$; mkdir -p "$RT"
info "checkout stand-in /run/pickman-co, run temp folder $RT"
TAIL=(--dev /dev --proc /proc --unshare-pid --unshare-net --unshare-ipc --new-session --die-with-parent)
OLD=(bwrap --ro-bind / / --tmpfs /run --remount-ro /run --tmpfs /tmp --ro-bind /run/pickman-co /run/pickman-co
  --bind "$ROOT/.cache" "$ROOT/.cache" --bind "$RT" "$RT" "${TAIL[@]}")
NEW=(bwrap --ro-bind / / --tmpfs /run --tmpfs /tmp --ro-bind /run/pickman-co /run/pickman-co
  --bind "$ROOT/.cache" "$ROOT/.cache" --bind "$RT" "$RT" --remount-ro /run "${TAIL[@]}")
"${OLD[@]}" true 2>/tmp/old.err && fail "old order (remount before the binds) fails" || { pass "old order (remount before the binds) fails"; info "old: $(head -1 /tmp/old.err)"; }
"${NEW[@]}" true 2>/tmp/new.err && pass "new order starts" || { fail "new order starts"; info "new: $(head -1 /tmp/new.err)"; }
"${NEW[@]}" cat /run/pickman-co/f | sed 's/^/INFO rebind readable: /'
"${NEW[@]}" sh -c ": > /run/pickman-co/w" 2>/dev/null && fail "rebind under /run is read-only" || pass "rebind under /run is read-only"
"${NEW[@]}" sh -c ": > '$RT/w'" 2>/dev/null && pass "run temp folder under /run is writable" || fail "run temp folder under /run is writable"
"${NEW[@]}" sh -c ": > '$ROOT/.cache/w' && rm '$ROOT/.cache/w'" 2>/dev/null && pass ".cache is writable" || fail ".cache is writable"
"${NEW[@]}" sh -c ": > /run/other" 2>/dev/null && fail "the rest of /run is read-only" || pass "the rest of /run is read-only"
"${NEW[@]}" sh -c "ls -d /run/user /run/docker.sock 2>&1 | head -2" | sed 's/^/INFO rest of run: /'
rm -rf "$RT"; sudo rm -rf /run/pickman-co; echo DONE
