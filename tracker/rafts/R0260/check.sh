#!/usr/bin/env bash
# Exit criteria for R0260. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0260); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0260

# RC1: the guards together, in a real jailed suite. A fixture checkout holds a copy of the runner and its guards;
# this check.sh runs outside the jail, so the fixture's run jails itself. Its one probe spec leaves a process in a
# session of its own, tries to signal the run's top process, and swaps a symlink into the top of its .cache. After
# the run: no process is left, the signal was refused, and no symlink is left at the top of .cache.
guards_together() {
  [[ $(uname -s) == Darwin ]] || { echo "not macOS: no jail, nothing to check"; return 0; }
  local fx="$PWD/.cache/r0260-rc1" rel out rc pid
  rm -rf "$fx" && mkdir -p "$fx/repo" || return 1
  for rel in tests/run.luau tests/lib scripts/lib .luaurc rokit.toml .gitignore; do
    mkdir -p "$fx/repo/$(dirname "$rel")" && cp -R "$rel" "$fx/repo/$rel" || return 1
  done
  mkdir -p "$fx/repo/tests/probe" "$fx/repo/.cache/deep"
  cat > "$fx/repo/tests/probe/together.spec.luau" <<'LUAU'
--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
return t.spec("together", function(it)
	it("leaves a process, signals the top process, swaps a link into .cache", function()
		fs.writeFile(`{here}/.cache/jail.txt`, process.env.PICKMAN_TEST_JAIL or "unset")
		local leave = 'exit if fork; setpgrp(0, 0); exit if fork; open STDOUT, ">", "/dev/null"; '
			.. 'open STDERR, ">&STDOUT"; open my $f, ">", $ARGV[0] or die; print $f $$; close $f; '
			.. "select(undef, undef, undef, 60)"
		t.expect(process.exec("perl", { "-e", leave, `{here}/.cache/left.pid` }).ok).toBe(true)
		local top = (string.gsub(fs.readFile(`{here}/.cache/tests-run.lock/pid`), "%s+$", ""))
		local probe = process.exec("kill", { "-0", top })
		fs.writeFile(`{here}/.cache/signal.txt`, if probe.ok then "allowed" else probe.stderr)
		fs.writeFile(`{here}/.cache/top-file`, "plain")
		process.exec("ln", { "-s", "/nonexistent", `{here}/.cache/deep/link` })
		local swap = "syscall(488, -2, $ARGV[0], -2, $ARGV[1], 2) == 0 or die \"swap: $!\\n\""
		process.exec("perl", { "-e", swap, `{here}/.cache/deep/link`, `{here}/.cache/top-file` })
		process.exec("perl", { "-e", "select(undef, undef, undef, 0.3)" })
	end)
end)
LUAU
  git init -q -b main "$fx/repo" || return 1
  [[ $(git -C "$fx/repo" rev-parse --show-toplevel) == "$(cd "$fx/repo" && pwd -P)" ]] || { echo "not a fixture repository"; return 1; }
  git -C "$fx/repo" add -A && git -C "$fx/repo" -c user.name=dev -c user.email=dev@example.invalid commit -qm runner || return 1
  out=$(cd "$fx/repo" && lune run tests/run -- tests/probe/together.spec.luau 2>&1); rc=$?
  echo "$out" | tail -4
  [[ $rc -eq 0 ]] || { echo "the fixture's run failed ($rc)"; return 1; }
  case $(cat "$fx/repo/.cache/jail.txt" 2>/dev/null) in
    none* | outer* | unset | "") echo "the fixture's run was not jailed"; return 1 ;;
  esac
  pid=$(cat "$fx/repo/.cache/left.pid" 2>/dev/null)
  [[ $pid =~ ^[0-9]+$ ]] || { echo "the probe left no pid"; return 1; }
  if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid"; echo "process $pid outlived the run"; return 1; fi
  grep -qF "Operation not permitted" "$fx/repo/.cache/signal.txt" || { echo "the probe could signal the run's top process: $(cat "$fx/repo/.cache/signal.txt")"; return 1; }
  if [[ -n $(find "$fx/repo/.cache" -mindepth 1 -maxdepth 1 -type l) ]]; then
    echo "a symlink is left at the top of .cache:"; find "$fx/repo/.cache" -mindepth 1 -maxdepth 1 -type l; return 1
  fi
  rm -rf "$fx"
}
check "RC1: in a real jailed suite, a detached process is swept, the top process can't be signalled, and no symlink is left at the top of .cache" guards_together

finish
