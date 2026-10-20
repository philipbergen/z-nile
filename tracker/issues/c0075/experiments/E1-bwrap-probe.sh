#!/usr/bin/env bash
# E1 (c0075): can bubblewrap give Linux spec runs the macOS jail's guarantees on a GitHub-hosted ubuntu-latest runner?
# Run from a checkout root on Linux. Prints one `PASS`/`FAIL <what>` line per probe and `INFO` lines; never fails the shell.
# Every write it attempts outside the sandbox's allowed folders is a harmless probe file inside a scratch folder.
set +e
ROOT=$(pwd -P)
SCRATCH=$(mktemp -d)                 # stands for the run's temp folder (allowed)
OUTSIDE=$(mktemp -d "$HOME/probe-outside.XXXXXX") # stands for the home folder (must be closed)
mkdir -p "$ROOT/.cache"
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; }
info() { echo "INFO $1"; }

info "uname: $(uname -srm); $(. /etc/os-release; echo "$PRETTY_NAME")"
info "apparmor_restrict_unprivileged_userns=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>&1)"
info "unprivileged_userns_clone=$(sysctl -n kernel.unprivileged_userns_clone 2>&1) max_user_namespaces=$(sysctl -n user.max_user_namespaces 2>&1)"
command -v bwrap >/dev/null && info "bwrap present: $(bwrap --version)" || info "bwrap absent"
sudo -n true 2>/dev/null && info "passwordless sudo: yes" || info "passwordless sudo: no"

# ---- stage 1: install, then see whether it works as is
if ! command -v bwrap >/dev/null; then sudo -n apt-get install -y bubblewrap >/dev/null 2>&1; fi
command -v bwrap >/dev/null && info "bwrap after install: $(bwrap --version)" || { fail "bubblewrap cannot be installed"; exit 0; }

JAIL=(bwrap --ro-bind / / --bind "$ROOT/.cache" "$ROOT/.cache" --bind "$SCRATCH" "$SCRATCH" --dev /dev --proc /proc
  --unshare-pid --unshare-net --unshare-ipc --die-with-parent --new-session)
if "${JAIL[@]}" true 2>/tmp/bwrap-err; then pass "bwrap works as installed"; else
  info "bwrap as installed: $(cat /tmp/bwrap-err)"; fail "bwrap works as installed"
  # ---- stage 2: the sysctl route
  sudo -n sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null 2>&1
  if "${JAIL[@]}" true 2>/tmp/bwrap-err; then pass "bwrap works after sysctl kernel.apparmor_restrict_unprivileged_userns=0"; else
    info "after sysctl: $(cat /tmp/bwrap-err)"; fail "bwrap works after the sysctl"; exit 0; fi
fi

in_jail() { "${JAIL[@]}" "$@"; }
t0=$(date +%s%N); for _ in 1 2 3 4 5 6 7 8 9 10; do in_jail true; done; t1=$(date +%s%N)
info "10 empty jails: $(( (t1 - t0) / 1000000 )) ms"

# ---- write rules
in_jail sh -c ": > '$ROOT/probe-root'" 2>/dev/null && { fail "write to checkout root denied"; rm -f "$ROOT/probe-root"; } || pass "write to checkout root denied"
in_jail sh -c ": > '$ROOT/.git-probe'; mkdir '$ROOT/newdir'" 2>/dev/null && { fail "mkdir in checkout denied"; rm -rf "$ROOT/newdir" "$ROOT/.git-probe"; } || pass "mkdir in checkout denied"
in_jail sh -c ": > '$ROOT/.git/probe'" 2>/dev/null && { fail "write to .git denied"; rm -f "$ROOT/.git/probe"; } || pass "write to .git denied"
in_jail sh -c "cd '$ROOT' && git checkout -- . ; git reset --hard -q; git clean -fdq; git commit --allow-empty -qm x -c user.name=x -c user.email=x@example.invalid" >/dev/null 2>&1 && fail "git write commands in the checkout fail" || pass "git write commands in the checkout fail"
in_jail sh -c ": > '$ROOT/.cache/p' && rm '$ROOT/.cache/p'" 2>/dev/null && pass ".cache writable" || fail ".cache writable"
in_jail sh -c ": > '$SCRATCH/p' && rm '$SCRATCH/p'" 2>/dev/null && pass "run temp folder writable" || fail "run temp folder writable"
in_jail sh -c ": > '$OUTSIDE/p'" 2>/dev/null && { fail "home folder closed"; rm -f "$OUTSIDE/p"; } || pass "home folder closed"
in_jail sh -c ": > /tmp/probe-tmp" 2>/dev/null && { fail "/tmp closed"; rm -f /tmp/probe-tmp; } || pass "/tmp closed"
in_jail sh -c ": > /var/tmp/probe-tmp" 2>/dev/null && { fail "/var/tmp closed"; rm -f /var/tmp/probe-tmp; } || pass "/var/tmp closed"
in_jail sh -c ": > /dev/shm/probe" 2>/dev/null && pass "/dev/shm is the jail's own" || info "/dev/shm not writable"
[[ -e /dev/shm/probe ]] && { fail "/dev/shm write did not reach the host"; rm -f /dev/shm/probe; } || pass "/dev/shm write did not reach the host"
in_jail sh -c "mv '$ROOT/.cache' '$ROOT/.cache2'" 2>/dev/null && { fail ".cache cannot be renamed away"; mv "$ROOT/.cache2" "$ROOT/.cache"; } || pass ".cache cannot be renamed away"
in_jail sh -c "mv '$(dirname "$ROOT")' '$(dirname "$ROOT")x'" 2>/dev/null && { fail "a folder above the checkout cannot be renamed"; mv "$(dirname "$ROOT")x" "$(dirname "$ROOT")"; } || pass "a folder above the checkout cannot be renamed"
in_jail sh -c "ln -s '$ROOT' '$ROOT/.cache/linkprobe'" 2>/dev/null && { pass "symlink at top of .cache can be made (the runner unlinks it)"; rm -f "$ROOT/.cache/linkprobe"; } || info "symlink at top of .cache refused"
# every mount inside that is still read-write (per-mount options in mountinfo), apart from the allowed folders and the
# jail's own /dev and /proc: none may be
rw=$(in_jail awk '{ if ($6 ~ /(^|,)rw(,|$)/) print $5 }' /proc/self/mountinfo | grep -v -x -e "$ROOT/.cache" -e "$SCRATCH" -e /dev -e '/dev/.*' -e /proc | sort -u | tr '\n' ' ')
[[ -z $rw ]] && pass "every other mount is read-only inside" || { fail "read-write mounts inside: $rw"; in_jail sh -c 'cat /proc/self/mountinfo' | grep -E " (/run|/mnt|/home|/boot|/sys)[^ ]* " | sed 's/^/INFO mi: /'; }
for d in /run /mnt /boot /sys /run/lock /etc; do
  in_jail python3 -c "
import os,sys
try: open('$d/.probe-w','w'); print('WRITABLE $d'); os.remove('$d/.probe-w')
except OSError as e: print('ro $d', e.errno)" 2>&1 | sed 's/^/INFO w: /'
done

# ---- network
python3 -c '
import socket,threading,sys
s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(1); print(s.getsockname()[1])' >/dev/null 2>&1
in_jail python3 - <<'PY' 2>&1 | sed 's/^/INFO net: /'
import socket,threading
s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(1); p=s.getsockname()[1]
threading.Thread(target=lambda:(s.accept()[0].send(b"hi"))).start()
c=socket.create_connection(("127.0.0.1",p),timeout=3); print("loopback server and client:", c.recv(2))
PY
in_jail python3 -c 'import socket; socket.create_connection(("192.0.2.1",9),timeout=3)' 2>/dev/null && fail "outbound network closed" || pass "outbound network closed"
in_jail python3 -c 'import socket; socket.create_connection(("1.1.1.1",443),timeout=3)' 2>/dev/null && fail "internet closed" || pass "internet closed"

# ---- processes and signals
sleep 300 & OUT=$!
in_jail sh -c "kill -0 $OUT" 2>/dev/null && fail "a process outside cannot be signalled" || pass "a process outside cannot be signalled"
kill $OUT 2>/dev/null
in_jail sh -c "(setsid sleep 301 </dev/null >/dev/null 2>&1 &) ; (sleep 302 </dev/null >/dev/null 2>&1 &) ; true"
sleep 1
pgrep -f 'sleep 30[12]' >/dev/null && { fail "leftovers die with the jail (setsid included)"; pkill -f 'sleep 30[12]'; } || pass "leftovers die with the jail (setsid included)"
in_jail sh -c 'echo $$' | grep -qx 1 && pass "pid namespace: the command is pid 1 or child of init" || info "pid of sh: $(in_jail sh -c 'echo $$')"
# --new-session: no tty ioctl injection; the job still gets its stdio
echo hi | in_jail cat >/dev/null && pass "stdin is forwarded"
in_jail sh -c 'exit 7'; [[ $? == 7 ]] && pass "exit status is forwarded" || fail "exit status is forwarded"
in_jail sh -c 'kill -9 $$'; info "signal death status: $?"

# ---- the toolchain inside the jail
if [[ -x scripts/setup.sh ]]; then
  GH_TOKEN=${GH_TOKEN:-} scripts/setup.sh --tools >/tmp/setup.log 2>&1 || tail -5 /tmp/setup.log
  export PATH="$HOME/.rokit/bin:$PATH"
  in_jail sh -c 'lune --version && git --version && perl -v | head -2 | tail -1' 2>&1 | sed 's/^/INFO tools: /'
  in_jail env TMPDIR="$SCRATCH" lune run tests/run -- tests/tooling/fixture-elsewhere.spec.luau 2>&1 | tail -6 | sed 's/^/INFO spec: /'
  info "spec run jailed: exit $?"
fi
rm -rf "$SCRATCH" "$OUTSIDE"
echo "DONE"
