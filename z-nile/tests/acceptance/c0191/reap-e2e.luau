--!strict
-- c0191 AC4: `./zn reap` against real processes. `ps` and `lsof` cannot start inside the spec jail (they are setuid), so
-- this runs from check.sh, not through tests/run (`./zn run --time 180 -- lune run "$A/reap-e2e.luau"`), and so it has to
-- be safe on its own. It is, in layers:
--   - the reaper is given a throwaway folder under .cache as its only root (`--root`), which also switches off every
--     default scope, and the reaper itself refuses a root that is / or the home folder, an age under a minute and a
--     --under that is not a claude process unless a root is named;
--   - the first real step is a --dry-run, and the script goes on only if every process it names has its working folder
--     under that throwaway folder: a reaper that ignored --root would be caught there, before it signals anything;
--   - decoys are `perl -e sleep`, `sleep` and `lune` processes that end by themselves within two minutes, and are stopped
--     again at the end by pid and start time, so a pid that has been reused is never signalled.
-- Run outside check.sh the --auto line fails (nothing guards the repository there), which is the point of that line.
-- Prints one line per case; exit 1 on a failure.
local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local WORK =
	`{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/reap-run-{os.time()}-{math.random(
		1,
		1e9
	)}`
local NAMES = { "orphan", "outside", "live", "marked", "future", "sessA", "stubborn" }

-- Starts the decoys, runs the reaper in its modes, and prints `<name> <alive|dead>` after each step.
-- The live decoys are children of an awk, which is no tool and no shell: nothing above them is ownerless.
-- The session decoy sits below an awk's child shell whose command text names a Claude Code shell snapshot, which is
-- what the reaper takes for one of a session's tool shells; the awk plays the session's own process.
local SCRIPT = [=[
W="$1"; ZN="$2"
mkdir -p "$W/in" "$W/out"
echo 'local task = require("@lune/task") task.wait(100)' > "$W/in/sleeper.luau"
state() { # state <step>: one line per decoy
	for n in orphan outside live marked future sessA stubborn; do
		pid=$(cat "$W/$n.pid" 2>/dev/null)
		st=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')
		case "$st" in ""|Z*) echo "$1 $n dead" ;; *) echo "$1 $n alive" ;; esac
	done
}
( cd "$W/in"; perl -e 'sleep 120' >/dev/null 2>&1 & echo $! > "$W/orphan.pid" )
( cd "$W/in"; perl -e '$SIG{TERM} = "IGNORE"; sleep 119' >/dev/null 2>&1 & echo $! > "$W/stubborn.pid" )
( cd "$W/out"; perl -e 'sleep 121' >/dev/null 2>&1 & echo $! > "$W/outside.pid" )
cd "$W/in"
# the awks end when the script is done with them: when W/release exists, or W/in is gone (no wall-clock assumption)
awk -v w="$W" 'BEGIN { system("sh " w "/live.sh " w) }' >/dev/null 2>&1 &
awk -v w="$W" 'BEGIN { system("sh -c \": /.claude/shell-snapshots/decoy; sh " w "/sess.sh " w "\"") }' >/dev/null 2>&1 &
echo $! > "$W/root.pid"
# the orphan must have been handed to launchd, and both awks must have started their children
for i in $(seq 1 100); do
	pp=$(ps -o ppid= -p "$(cat "$W/orphan.pid" 2>/dev/null)" 2>/dev/null | tr -d ' ')
	[ "$pp" = 1 ] && [ -s "$W/sessA.pid" ] && [ -s "$W/future.pid" ] && break
	sleep 0.1
done
echo "orphan-parent $pp"
for n in orphan outside live marked future sessA stubborn; do ps -o lstart= -p "$(cat "$W/$n.pid" 2>/dev/null)" 2>/dev/null > "$W/$n.lstart"; done
root=$(cat "$W/root.pid")
"$ZN" reap --dry-run --min-age 0 --under "$root" --root "$W/in" > "$W/dry.out" 2>&1; echo "dry-code $?" ; state dry
# the gate: every process the dry run names must work under the throwaway folder, and there must be some
named=$(grep -c '^reap: would stop pid ' "$W/dry.out")
foreign=$(grep '^reap: would stop pid ' "$W/dry.out" | grep -vc ", cwd $W/in[:/]")
echo "gate-named $named"; echo "gate-foreign $foreign"
if [ "$named" -ge 1 ] && [ "$foreign" -eq 0 ]; then
	"$ZN" reap --auto --min-age 0 --under "$root" --root "$W/in" > "$W/auto.out" 2>&1; echo "auto-code $?"; state auto
	"$ZN" reap --min-age 0 --under "$root" --root "$W/in" --log "$W/reaped.log" > "$W/real.out" 2>&1; echo "real-code $?"; state real
	"$ZN" reap --min-age 0 --root "$W/in" > "$W/again.out" 2>&1; echo "again-code $?"; state again
fi
touch "$W/release"
]=]

-- stops a decoy only if it is still the process that was recorded (a pid may have been reused)
local function cleanup()
	for _, n in NAMES do
		local pidFile, stampFile = `{WORK}/{n}.pid`, `{WORK}/{n}.lstart`
		if fs.isFile(pidFile) and fs.isFile(stampFile) then
			local pid = (string.gsub(fs.readFile(pidFile), "%s+", ""))
			local recorded = (string.gsub(fs.readFile(stampFile), "^%s+", ""):gsub("%s+$", ""))
			if pid ~= "" and recorded ~= "" then
				local now = process.exec("ps", { "-o", "lstart=", "-p", pid })
				if (string.gsub(now.stdout, "^%s+", ""):gsub("%s+$", "")) == recorded then
					process.exec("kill", { "-KILL", pid })
				end
			end
		end
	end
end

local function lines(path: string): string
	return if fs.isFile(path) then fs.readFile(path) else ""
end

fs.writeDir(WORK) -- a folder of this run's own: a concurrent run, or one that crashed, is never touched
-- the decoys that have a live owner, started by two small scripts (the second's owner is a fake tool shell)
local WAIT = 'until [ -f "$1/release" ] || [ ! -d "$1/in" ]; do sleep 0.2; done\n'
fs.writeFile(
	`{WORK}/live.sh`,
	'cd "$1/in"\nperl -e \'sleep 122\' >/dev/null 2>&1 & echo $! > "$1/live.pid"\n'
		.. 'ZN_BOUNDED_DEADLINE=1000000000 lune run sleeper.luau >/dev/null 2>&1 & echo $! > "$1/marked.pid"\n'
		.. 'ZN_BOUNDED_DEADLINE=9999999999 lune run sleeper.luau >/dev/null 2>&1 & echo $! > "$1/future.pid"\n'
		.. WAIT
)
fs.writeFile(
	`{WORK}/sess.sh`,
	'cd "$1/in"\nperl -e \'sleep 125\' >/dev/null 2>&1 & echo $! > "$1/sessA.pid"\n' .. WAIT
)
local ran, r = pcall(process.exec, "sh", { "-c", SCRIPT, "sh", WORK, `{ROOT}/zn` })
cleanup()
if not ran then
	print(`FAIL the script did not run: {r}`)
	process.exit(1)
end
local report: { [string]: string } = {}
for line in string.gmatch(r.stdout, "[^\n]+") do
	local a, b = string.match(line, "^(.-) (%S+)$")
	if a and b then
		report[a] = b
	end
end

local failed = 0
local function expect(name: string, ok: boolean)
	print(`{if ok then "ok  " else "FAIL"} {name}`)
	if not ok then
		failed += 1
	end
end
local function state(step: string, name: string): string
	return report[`{step} {name}`] or "missing"
end
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

expect("the decoy orphan really is orphaned (the premise of the cases below)", report["orphan-parent"] == "1")

local allAlive = true
for _, n in NAMES do
	allAlive = allAlive and state("dry", n) == "alive"
end
expect("AC4: --dry-run signals nothing", allAlive and report["dry-code"] == "0")
expect("AC4: --dry-run says what it would stop", has(lines(`{WORK}/dry.out`), "would stop pid"))
expect(
	"AC4: the dry run names only processes working under the throwaway folder (the gate for the steps below)",
	report["gate-named"] ~= nil and report["gate-named"] ~= "0" and report["gate-foreign"] == "0"
)
if report["auto-code"] == nil then
	print(
		"FAIL the steps that stop processes did not run: the dry run named a process outside the throwaway folder"
	)
	process.exit(1)
end

expect(
	"AC4: --auto inside a check run stops nothing and says nothing (the guards protect this repository)",
	state("auto", "orphan") == "alive"
		and state("auto", "marked") == "alive"
		and state("auto", "sessA") == "alive"
		and report["auto-code"] == "0"
		and lines(`{WORK}/auto.out`) == ""
)

expect("AC4: an orphan under the root is stopped", state("real", "orphan") == "dead")
expect(
	"AC4: an orphan that ignores TERM is stopped too (the KILL after the shared wait)",
	state("real", "stubborn") == "dead"
)
expect("AC4: an orphan outside the root is not", state("real", "outside") == "alive")
expect("AC4: a process with a live owner is not", state("real", "live") == "alive")
expect("AC4: a process past its ./zn run deadline is stopped", state("real", "marked") == "dead")
expect("AC4: a process before its deadline is not", state("real", "future") == "alive")
expect("AC4: --under stops what the ending session's tool shell started", state("real", "sessA") == "dead")

local out = lines(`{WORK}/real.out`)
local pid = (string.gsub(lines(`{WORK}/orphan.pid`), "%s+", ""))
expect("AC4: each stop is reported with pid", has(out, `stopped pid {pid}`))
expect("AC4: and its reason", has(out, "orphaned (its parent is gone)"))
expect("AC4: and its folder and command", has(out, "cwd ") and has(out, "perl -e sleep 120"))
expect(
	"AC4: all three reasons are reported",
	has(out, "past its ./zn run deadline") and has(out, "started by the session that is ending")
)
expect(
	"AC4: the environment is never printed",
	not has(out, "CLAUDE_CODE_SESSION_ID") and not has(out, "ZN_BOUNDED_DEADLINE=")
)
expect(
	"AC4: --log appends each report with a time",
	string.match(lines(`{WORK}/reaped.log`), "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d reap: stopped pid ") ~= nil
)
expect("AC4: a stop exits 0", report["real-code"] == "0")
expect(
	"AC4: a second run finds nothing more and says so",
	report["again-code"] == "0" and has(lines(`{WORK}/again.out`), "no leaked processes")
)

if fs.isDir(WORK) then
	fs.removeDir(WORK)
end
process.exit(if failed == 0 then 0 else 1)
