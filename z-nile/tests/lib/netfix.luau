--!strict
-- d0383: the fixture world of the watch-net specs, and the bounded waits they share. A world is a tracker fixture (its
-- own origin, a main checkout, a raft's worktree under it) whose `z-nile/check.sh` is a stub suite: it dumps its
-- environment, always fails, and when the spec has created `hold/hold-on` it first records `start` in `hold/runs`, creates
-- `hold/started` and waits (at most 20 s) for `hold/release` before it records `end`. A started net therefore ends by
-- itself, with exit 0, changes nothing on the fixture's origin, and a spec holds a run open on a marker file, never on a sleep.
-- Everything lives under the checkout's .cache/, which is where the runner's jail lets a spec write.
local cpulimit = require("@znile/lib/cpulimit")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local trackerfix = require("@tests/lib/trackerfix")

local netfix = {}

export type World = { f: trackerfix.Fixture, main: string, raft: string, hold: string, base: string }
export type Setup = { standing: boolean?, rafts: number? }

netfix.ON = { PICKMAN_WATCH_NET = "on" }

function netfix.has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

function netfix.trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

function netfix.read(path: string): string
	return if fs.isFile(path) then fs.readFile(path) else ""
end

local function gate(hold: string): string
	return "#!/usr/bin/env bash\n"
		.. `H='{hold}'\n`
		.. 'env > "$H/env"\n'
		.. 'ulimit -t > "$H/cpu"\n'
		.. 'if [[ -f "$H/hold-on" ]]; then\n'
		.. '  echo start >> "$H/runs"; : > "$H/started"\n'
		.. '  for _ in $(seq 1 200); do [[ -f "$H/release" ]] && break; sleep 0.1; done\n'
		.. '  echo end >> "$H/runs"\n'
		.. "fi\n"
		.. 'if [[ -f "$H/exit-code" ]]; then echo "gate: not started (stub)"; exit "$(cat "$H/exit-code")"; fi\n'
		.. 'echo "FAIL none.spec.luau :: the stub suite fails"\n'
		.. "exit 1\n"
end

-- `name` is unique to the spec file (the c0049 rule). `standing` adds the main checkout's net worktree on `watch-net`;
-- `rafts` (default 1) the raft worktrees R9999-fixture, R9998-fixture, ...
function netfix.world(name: string, setup: Setup?): World
	-- the kick refuses a net under a CPU limit below the floor: say why here, not as `expected 0, got 1` in the spec
	local hard = netfix.trim(process.exec("sh", { "-c", "ulimit -Ht" }).stdout)
	if not cpulimit.ok(hard, cpulimit.SPEC_DEFAULT) then
		error(
			`the watch-net specs need a CPU limit of at least {cpulimit.SPEC_DEFAULT} s per process (this one has {hard}): run them under ./zn run --cpu 1800 or without one`,
			2
		)
	end
	local root = fixture.physical(".") :: string
	local hold = `{root}/.cache/{name}/hold`
	local f = trackerfix.new(name, {
		["z-nile/next"] = "issue 1 fixture\nraft 1 fixture\n",
		["z-nile/check.sh"] = gate(hold),
		["z-nile/watch-passed"] = "",
	})
	fs.writeDir(hold)
	local main = fixture.physical(f.main) :: string
	if setup and setup.standing then
		fixture.git(
			f.main,
			{ "worktree", "add", "-q", "-b", "watch-net", `{main}/.worktree/watch-net`, "origin/main" }
		)
	end
	local first = ""
	for i = 1, (setup and setup.rafts) or 1 do
		local raft = `R{10000 - i}-fixture`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", raft, `{main}/.worktree/{raft}`, "origin/main" })
		first = if first == "" then `{main}/.worktree/{raft}` else first
	end
	return { f = f, main = main, raft = first, hold = hold, base = f.base }
end

-- `./zn watch-kick <extra>` from `dir`, the way a worker or a landing runs it.
function netfix.kick(w: World, dir: string, extra: { string }?): fixture.Result
	local args = { "watch-kick" }
	local more: { string } = extra or {}
	for _, a in more do
		table.insert(args, a)
	end
	return trackerfix.tr(w.f, dir, args, netfix.ON)
end

-- The log path a successful kick printed, or nil.
function netfix.logOf(stdout: string): string?
	return string.match(stdout, "log at (%S+%.log)")
end

-- Waits (at most 20 s, in tenths of a second) for a file; true when it came. The wait ends on the marker, not on the clock.
function netfix.waitFor(path: string): boolean
	for _ = 1, 200 do
		if fs.isFile(path) then
			return true
		end
		process.exec("sleep", { "0.1" })
	end
	return false
end

-- The exit file beside a kick's log (it exists once the net has ended), awaited.
function netfix.settle(log: string): string
	local exit = string.gsub(log, "%.log$", ".exit")
	netfix.waitFor(exit)
	return netfix.trim(netfix.read(exit))
end

-- The worktrees of the fixture that have `watch-net` checked out.
function netfix.netWorktrees(w: World): { string }
	local out: { string } = {}
	local path = ""
	for line in string.gmatch(fixture.git(w.f.main, { "worktree", "list", "--porcelain" }), "[^\n]+") do
		path = string.match(line, "^worktree (.+)$") or path
		if line == "branch refs/heads/watch-net" then
			table.insert(out, path)
		end
	end
	return out
end

-- Makes the hold stub hold its runs.
function netfix.holdOn(w: World)
	fs.writeFile(`{w.hold}/hold-on`, "on\n")
end

return netfix
