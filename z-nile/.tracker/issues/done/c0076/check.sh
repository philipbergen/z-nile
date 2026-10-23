#!/usr/bin/env bash
# Acceptance checks for c0076. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0076 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0076"

# The spec's cases share one setup, so it runs once (here, outside `check`: list mode refuses it); a check then
# requires its named cases to exist in the spec and not fail, and the spec to have loaded.
sweeper_out=$(lune run tests/run -- "$A/sweeper.spec.luau" 2>&1)
cases_in() { # $1: spec file, $2: its output, $3...: case-name prefixes that must exist and not fail
  local spec=$1 out=$2 c; shift 2
  [[ -f $spec ]] || { echo "missing $spec"; return 1; }
  if grep -q "could not load spec" <<<"$out"; then echo "$out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$out" || { echo "$out" | tail -20; return 1; }
  for c in "$@"; do
    tr -d "\n\t" < "$spec" | grep -qF "it(\"$c" || { echo "$spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$out" | grep -qF ":: $c"; then grep -F -A3 ":: $c" <<<"$out"; return 1; fi
  done
}
sweeper() { cases_in "$A/sweeper.spec.luau" "$sweeper_out" "$@"; }
jailed_cases() { # on macOS the jailed cases must have run, not returned early
  sweeper "$@" || return 1
  if [[ $(uname -s) == Darwin && ! -f .cache/c0076-sweeper/jailed-cases-ran ]]; then
    echo "the jailed cases did not run: run this check outside any other sandbox, so the specs are jailed"
    return 1
  fi
}

check "AC1: when jailed, the sweep stops a process left in another session, spares ancestors and outside processes, and passes the status through" jailed_cases \
  "when jailed, a process the command left in a session of its own is stopped by the sweep" \
  "when jailed, the sweep never stops its own ancestors or a process outside the jail" \
  "when jailed, the command's status passes through"
check "AC2: the sweep refuses, and stops nothing, when it can signal the outside pid or that pid is gone" sweeper \
  "the sweep refuses, and stops nothing, when it can signal the pid it was told is outside" \
  "the sweep refuses, and stops nothing, when the pid it was told is outside is gone" \
  "the launcher form refuses, and stops nothing, when its parent is already gone"
check "AC3: the launcher fails a run whose sweeper died of a signal" sweeper \
  "the launcher fails a run whose sweeper died of a signal"
check "AC4: the runner starts the real sweeper without the caller's PICKMAN_SWEEP_ONLY, and its launcher settings stop at the launcher" sweeper \
  "a real run's sweeper is started without the caller's PICKMAN_SWEEP_ONLY" \
  "a launcher a spec starts inherits none of the run's launcher settings"

# AC5: a real jailed suite, in a fixture checkout holding a copy of the runner and its guards, with one probe spec
# that leaves a process in a session of its own. This check.sh runs outside the jail, so the fixture's run jails
# itself, sweeper included. The caller's PICKMAN_SWEEP_ONLY names a file listing nothing: the real sweep ignores it.
real_sweep() {
  [[ $(uname -s) == Darwin ]] || { echo "not macOS: no jail, nothing to check"; return 0; }
  local fx="$PWD/.cache/c0076-real" rel out rc pid
  rm -rf "$fx" && mkdir -p "$fx/repo" || return 1
  for rel in tests/run.luau tests/lib scripts/lib z-nile/lib .luaurc rokit.toml .gitignore; do
    mkdir -p "$fx/repo/$(dirname "$rel")" && cp -R "$rel" "$fx/repo/$rel" || return 1
  done
  mkdir -p "$fx/repo/tests/probe" "$fx/repo/.cache"
  cat > "$fx/repo/tests/probe/leave.spec.luau" <<'LUAU'
--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
return t.spec("leave", function(it)
	it("leaves a process in a session of its own", function()
		fs.writeFile(`{here}/.cache/jail.txt`, process.env.PICKMAN_TEST_JAIL or "unset")
		local script = 'exit if fork; setpgrp(0, 0); exit if fork; open STDOUT, ">", "/dev/null"; '
			.. 'open STDERR, ">&STDOUT"; open my $f, ">", $ARGV[0] or die; print $f $$; close $f; '
			.. "select(undef, undef, undef, 60)"
		t.expect(process.exec("perl", { "-e", script, `{here}/.cache/left.pid` }).ok).toBe(true)
		process.exec("perl", { "-e", "select(undef, undef, undef, 0.3)" })
	end)
end)
LUAU
  git init -q -b main "$fx/repo" || return 1
  [[ $(git -C "$fx/repo" rev-parse --show-toplevel) == "$(cd "$fx/repo" && pwd -P)" ]] || { echo "not a fixture repository"; return 1; }
  git -C "$fx/repo" add -A && git -C "$fx/repo" -c user.name=dev -c user.email=dev@example.invalid commit -qm runner || return 1
  : > "$fx/only-nothing"
  out=$(cd "$fx/repo" && PICKMAN_SWEEP_ONLY="$fx/only-nothing" lune run tests/run -- tests/probe/leave.spec.luau 2>&1); rc=$?
  echo "$out" | tail -4
  [[ $rc -eq 0 ]] || { echo "the fixture's run failed ($rc)"; return 1; }
  case $(cat "$fx/repo/.cache/jail.txt" 2>/dev/null) in
    none* | outer* | unset | "") echo "the fixture's run was not jailed: $(cat "$fx/repo/.cache/jail.txt" 2>/dev/null)"; return 1 ;;
  esac
  pid=$(cat "$fx/repo/.cache/left.pid" 2>/dev/null)
  [[ $pid =~ ^[0-9]+$ ]] || { echo "the probe left no pid"; return 1; }
  if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid"; echo "process $pid outlived the run"; return 1; fi
  grep -q "stopped 1" <<<"$out" || { echo "the sweeper did not report the process it stopped"; return 1; }
  rm -rf "$fx"
}
check "AC5: a real jailed suite leaves no process behind, even one in a session of its own" real_sweep

# AC6: the same fixture, interrupted the way a terminal's Ctrl-C is: INT to the whole process group of the run (the
# top process dies at once, the launcher forwards it to the specs). The probe spec leaves a process in a session of its
# own, then waits; the run is interrupted while it waits. The sweeper, whose interlock watches the launcher (not the
# top process), must still sweep (design review 001 F2).
interrupted_sweep() {
  [[ $(uname -s) == Darwin ]] || { echo "not macOS: no jail, nothing to check"; return 0; }
  local fx="$PWD/.cache/c0076-interrupted" rel job pid waited
  rm -rf "$fx" && mkdir -p "$fx/repo" || return 1
  for rel in tests/run.luau tests/lib scripts/lib z-nile/lib .luaurc rokit.toml .gitignore; do
    mkdir -p "$fx/repo/$(dirname "$rel")" && cp -R "$rel" "$fx/repo/$rel" || return 1
  done
  mkdir -p "$fx/repo/tests/probe" "$fx/repo/.cache"
  cat > "$fx/repo/tests/probe/wait.spec.luau" <<'LUAU'
--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
return t.spec("wait", function(it)
	it("leaves a process in a session of its own, then waits", function()
		local script = 'exit if fork; setpgrp(0, 0); exit if fork; open STDOUT, ">", "/dev/null"; '
			.. 'open STDERR, ">&STDOUT"; open my $f, ">", $ARGV[0] or die; print $f $$; close $f; '
			.. "select(undef, undef, undef, 60)"
		t.expect(process.exec("perl", { "-e", script, `{here}/.cache/left.pid` }).ok).toBe(true)
		fs.writeFile(`{here}/.cache/waiting`, "")
		process.exec("perl", { "-e", "select(undef, undef, undef, 30)" })
	end)
end)
LUAU
  git init -q -b main "$fx/repo" || return 1
  [[ $(git -C "$fx/repo" rev-parse --show-toplevel) == "$(cd "$fx/repo" && pwd -P)" ]] || { echo "not a fixture repository"; return 1; }
  git -C "$fx/repo" add -A && git -C "$fx/repo" -c user.name=dev -c user.email=dev@example.invalid commit -qm runner || return 1
  set -m # the run gets a process group of its own, like a terminal's foreground job
  (cd "$fx/repo" && exec lune run tests/run -- tests/probe/wait.spec.luau >"$fx/out.txt" 2>&1) &
  job=$!
  set +m
  waited=0
  while [[ ! -f $fx/repo/.cache/waiting && $waited -lt 300 ]]; do perl -e 'select(undef, undef, undef, 0.1)'; waited=$((waited + 1)); done
  [[ -f $fx/repo/.cache/waiting ]] || { kill -KILL -- "-$job" 2>/dev/null; cat "$fx/out.txt"; echo "the probe never started"; return 1; }
  kill -INT -- "-$job"
  wait "$job"
  pid=$(cat "$fx/repo/.cache/left.pid" 2>/dev/null)
  [[ $pid =~ ^[0-9]+$ ]] || { echo "the probe left no pid"; return 1; }
  waited=0
  while kill -0 "$pid" 2>/dev/null && [[ $waited -lt 50 ]]; do perl -e 'select(undef, undef, undef, 0.1)'; waited=$((waited + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid"; tail -5 "$fx/out.txt"; echo "process $pid outlived the interrupted run"; return 1; fi
  rm -rf "$fx"
}
check "AC6: an interrupted jailed suite still leaves no process behind" interrupted_sweep

finish
