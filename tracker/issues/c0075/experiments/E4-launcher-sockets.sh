#!/usr/bin/env bash
# E4 (c0075): (a) the real launcher (fence.REAPER) with the jail, with and without --new-session: signals, parent death,
# a group-wide signal from inside; (b) host Unix sockets inside the jail, with and without --tmpfs on /run and /tmp;
# (c) the TIOCSTI sysctl. Run after E1's setup, from a checkout root with lune on PATH. Prints PASS/FAIL/INFO lines.
set +e
ROOT=$(pwd -P); mkdir -p "$ROOT/.cache"; SCRATCH=$(mktemp -d)
pass() { echo "PASS $1"; }; fail() { echo "FAIL $1"; }; info() { echo "INFO $1"; }
sudo -n apt-get install -y bubblewrap >/dev/null 2>&1; sudo -n sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null 2>&1
export PATH="$HOME/.rokit/bin:$PATH"
info "dev.tty.legacy_tiocsti=$(sysctl -n dev.tty.legacy_tiocsti 2>&1) kernel=$(uname -r)"
info "config: $(grep -h LEGACY_TIOCSTI /boot/config-$(uname -r) 2>&1 | head -1)"
lune run tracker/issues/c0075/experiments/print-reaper.luau > "$SCRATCH/reaper.pl" 2>"$SCRATCH/reaper.err" || cat "$SCRATCH/reaper.err"
info "reaper program: $(wc -c < "$SCRATCH/reaper.pl") bytes"
BASE=(bwrap --ro-bind / / --bind "$ROOT/.cache" "$ROOT/.cache" --bind "$SCRATCH" "$SCRATCH" --dev /dev --proc /proc
  --unshare-pid --unshare-net --unshare-ipc --die-with-parent)
procs() { ps -eo pid,ppid,pgid,sid,args | grep -E "sleep 3[0-9][0-9]" | grep -v -E "grep"; }
gone() { for _ in 1 2 3 4 5 6 7 8; do [[ -z $(procs) ]] && return 0; sleep 0.5; done; return 1; }
sweep() { pkill -9 -f "sleep 3[0-9][0-9]" 2>/dev/null; sleep 0.3; }
reaper() { exec perl -e "$(cat "$SCRATCH/reaper.pl")" "$@"; } # the launcher form: perl -e REAPER command args...

for variant in plain newsession; do
  FLAGS=(); [[ $variant == newsession ]] && FLAGS=(--new-session)
  echo "== variant: $variant"
  for sig in INT TERM HUP; do
    sweep; ( reaper "${BASE[@]}" "${FLAGS[@]}" sh -c 'sleep 300' ) & L=$!; sleep 1
    kill -$sig $L; wait $L; code=$?
    gone && pass "$variant: $sig to the launcher stops the jail and leaves nothing (exit $code)" || { fail "$variant: $sig leaves processes"; procs | sed 's/^/INFO left: /'; }
  done
  sweep; ( reaper "${BASE[@]}" "${FLAGS[@]}" sh -c '(setsid sleep 301 </dev/null >/dev/null 2>&1 &); sleep 302' ) & L=$!; sleep 1
  kill -9 $L; wait $L 2>/dev/null
  gone && pass "$variant: SIGKILL of the launcher leaves nothing" || { fail "$variant: SIGKILL of the launcher leaves processes"; procs | sed 's/^/INFO left: /'; }
  # a group-wide signal from inside: does it reach the launcher's watchdog or the outer bwrap?
  sweep; ( reaper "${BASE[@]}" "${FLAGS[@]}" sh -c 'sleep 303 & echo "inside pgid $(ps -o pgid= -p $$) sid $(ps -o sid= -p $$)" >&2; kill -TERM 0; kill -KILL 0; sleep 5' ) 2>"$SCRATCH/grp.err" & L=$!; sleep 3
  cat "$SCRATCH/grp.err" | sed 's/^/INFO /'
  if kill -0 $L 2>/dev/null; then info "$variant: the launcher is still alive after a group-wide TERM/KILL from inside"; kill -9 $L; else info "$variant: the launcher is gone after a group-wide TERM/KILL from inside"; fi
  ps -eo pid,ppid,pgid,sid,args | grep -E "bwrap|perl -e" | grep -v grep | cut -c1-110 | sed 's/^/INFO ps after: /'
  wait $L 2>/dev/null; sweep
done

echo "== host sockets"
SOCKTEST='python3 - <<PY
import socket,os
for p in ["/run/docker.sock", "/var/run/docker.sock", os.environ.get("XDG_RUNTIME_DIR","/nonexistent")+"/bus", "/run/dbus/system_bus_socket"]:
    s=socket.socket(socket.AF_UNIX)
    try: s.connect(p); print("CONNECTED", p)
    except OSError as e: print("no", p, e.errno)
PY'
info "outside:"; bash -c "$SOCKTEST" | sed 's/^/INFO out: /'
info "jail as designed:"; "${BASE[@]}" bash -c "$SOCKTEST" | sed 's/^/INFO base: /'
"${BASE[@]}" docker version >/dev/null 2>&1 && info "docker works in the base jail" || info "docker fails in the base jail"
HID=(bwrap --ro-bind / / --tmpfs /run --remount-ro /run --tmpfs /tmp --bind "$ROOT/.cache" "$ROOT/.cache" --bind "$SCRATCH" "$SCRATCH" --dev /dev --proc /proc
  --unshare-pid --unshare-net --unshare-ipc --die-with-parent)
info "jail with /run and /tmp hidden:"; "${HID[@]}" bash -c "$SOCKTEST" | sed 's/^/INFO hid: /'
"${HID[@]}" bash -c "docker version" >/dev/null 2>&1 && fail "docker fails with /run hidden" || pass "docker fails with /run hidden"
"${HID[@]}" sh -c ": >/run/probe" 2>/dev/null && fail "/run is read-only when hidden" || pass "/run is read-only when hidden"
"${HID[@]}" sh -c "touch /tmp/probe" 2>/dev/null && info "/tmp is a writable tmpfs of its own (no host effect: $( [[ -e /tmp/probe ]] && echo LEAKED || echo none))" || info "/tmp not writable"
TMPDIR="$SCRATCH" "${HID[@]}" bash -c 'd=$(mktemp -d) && touch "$d/f" && echo "mktemp ok $d"' | sed 's/^/INFO hid: /'
"${HID[@]}" sh -c "cd '$ROOT' && git status --short | head -1; git --version" 2>&1 | sed 's/^/INFO hid git: /'
"${HID[@]}" bash -c "lune --version; perl -v | sed -n 2p; ls -ld /run /run/user 2>&1 | head -2" 2>&1 | sed 's/^/INFO hid tools: /'
"${HID[@]}" lune run tests/run -- tests/tooling/fixture-elsewhere.spec.luau 2>&1 | tail -2 | sed 's/^/INFO hid spec: /'
rm -rf "$SCRATCH"; echo DONE
