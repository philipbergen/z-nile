#!/usr/bin/env bash
# E2 (c0075): bubblewrap's interplay with the runner's launcher: nesting, signals, parent death. Run after E1's setup
# (bubblewrap installed, kernel.apparmor_restrict_unprivileged_userns=0). Prints PASS/FAIL/INFO lines; never fails the shell.
set +e
ROOT=$(pwd -P); mkdir -p "$ROOT/.cache/inner"; SCRATCH=$(mktemp -d)
pass() { echo "PASS $1"; }; fail() { echo "FAIL $1"; }; info() { echo "INFO $1"; }
sudo -n apt-get install -y bubblewrap >/dev/null 2>&1; sudo -n sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null 2>&1
JAIL=(bwrap --ro-bind / / --bind "$ROOT/.cache" "$ROOT/.cache" --bind "$SCRATCH" "$SCRATCH" --dev /dev --proc /proc
  --unshare-pid --unshare-net --unshare-ipc --die-with-parent)
procs() { ps -eo pid,ppid,pgid,args | grep -E "sleep 3[0-9][0-9]" | grep -v -E "grep|pgrep" ; }
gone() { for _ in 1 2 3 4 5 6; do [[ -z $(procs) ]] && return 0; sleep 0.5; done; return 1; }
sweep() { pkill -9 -f "sleep 3[0-9][0-9]" 2>/dev/null; sleep 0.3; }
# 1. nesting: a jail inside the jail, narrower
INNER=(bwrap --ro-bind / / --bind "$ROOT/.cache/inner" "$ROOT/.cache/inner" --dev /dev --proc /proc --unshare-pid --unshare-net --die-with-parent)
"${JAIL[@]}" "${INNER[@]}" sh -c "touch '$ROOT/.cache/inner/p'" 2>/tmp/nest-err && pass "a jail nests in a jail" || { info "nesting: $(cat /tmp/nest-err)"; fail "a jail nests in a jail"; }
"${JAIL[@]}" "${INNER[@]}" sh -c "touch '$ROOT/.cache/outer-p'" 2>/dev/null && fail "the inner jail is narrower (the outer .cache is closed)" || pass "the inner jail is narrower (the outer .cache is closed)"
info "pidns inner $("${JAIL[@]}" "${INNER[@]}" readlink /proc/self/ns/pid), outer $("${JAIL[@]}" readlink /proc/self/ns/pid), host $(readlink /proc/self/ns/pid)"
# 2. the launcher shape (tests/lib/fence.luau REAPER): the child makes its own process group and execs; the parent
# forwards INT/TERM to that group, waits, then kills the group
launch() { exec perl -e 'my $pid = fork; if ($pid == 0) { setpgrp(0,0); $SIG{$_}="DEFAULT" for qw(INT TERM HUP); exec @ARGV or die } setpgrp($pid,$pid); for my $s (qw(INT TERM HUP)) { $SIG{$s}=sub{kill $s,-$pid} } waitpid($pid,0); my $st=$?; kill "KILL",-$pid; exit($st & 127 ? 128 + ($st & 127) : $st >> 8)' -- "$@"; }
for sig in INT TERM HUP; do
  sweep; ( launch "${JAIL[@]}" sh -c 'sleep 300' ) & L=$!; sleep 1
  kill -$sig $L; wait $L; code=$?
  gone && pass "$sig to the launcher stops the jail and leaves nothing (exit $code)" || { fail "$sig to the launcher leaves processes"; procs | sed 's/^/INFO left: /'; }
done
# 2b. the launcher is killed outright
sweep; ( launch "${JAIL[@]}" sh -c '(setsid sleep 301 </dev/null >/dev/null 2>&1 &) ; sleep 302' ) & L=$!; sleep 1
info "tree before: $(ps -eo pid,ppid,pgid,args | grep -E "bwrap|sleep 30[12]|perl -e my" | grep -v grep | cut -c1-120 | tr '\n' '|')"
kill -9 $L; wait $L 2>/dev/null
gone && pass "SIGKILL of the launcher takes the jail with it" || { fail "SIGKILL of the launcher leaves processes"; procs | sed 's/^/INFO left: /'; }
# 2c. same, with the watchdog of tests/lib/fence.luau REAPER semantics: the watchdog is in the specs' group
sweep
# 3. SIGKILL of bwrap itself, and of its parent only
sweep; "${JAIL[@]}" sh -c '(setsid sleep 303 </dev/null >/dev/null 2>&1 &) ; sleep 304' & B=$!; sleep 1; kill -9 $B; wait $B 2>/dev/null
gone && pass "SIGKILL of bwrap takes its processes with it" || { fail "SIGKILL of bwrap leaves processes"; procs | sed 's/^/INFO left: /'; }
# 4. toolchain chain and mktemp
export PATH="$HOME/.rokit/bin:$PATH"
"${JAIL[@]}" bash -c 'perl -e "print qq(perl ok\n)"; git --version | head -1; echo a | sh -c "cat"' | sed 's/^/INFO chain: /'
TMPDIR="$SCRATCH" "${JAIL[@]}" bash -c 'd=$(mktemp -d) && echo "$d" && touch "$d/f" && echo wrote' | sed 's/^/INFO mktemp: /'
# 5. a git worktree of the checkout
git -C "$ROOT" worktree add -q "$ROOT/.cache/wt" HEAD 2>/dev/null
"${JAIL[@]}" sh -c "cd '$ROOT/.cache/wt' && git -c user.name=x -c user.email=x@example.invalid commit --allow-empty -qm x" 2>/dev/null && fail "commit in a worktree of the checkout fails" || pass "commit in a worktree of the checkout fails"
git -C "$ROOT" worktree remove --force "$ROOT/.cache/wt" 2>/dev/null
rm -rf "$SCRATCH"; echo DONE
