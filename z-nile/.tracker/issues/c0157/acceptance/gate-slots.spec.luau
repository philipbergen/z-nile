--!strict
-- c0157: a gate's spec stage holds one of the machine's gate slots (z-nile/tests/slot.luau over
-- z-nile/tests/lib/gateslot.luau), so concurrent gates queue instead of oversubscribing the CPUs, and a lone gate never
-- waits. Each "gate" here is a bash process that acquires a slot for itself, holds it, and releases it, as
-- z-nile/check.sh does around each project's spec stage. The slots live in this spec's own folder, .cache/c0157-slots
-- (ZN_GATE_SLOTS), never the user's. Which gate started first is read from start and end stamps; no case compares a
-- duration, and every gate that must hold its slot holds it 3 s, far above a loaded machine's start-up jitter.
local fs = require("@lune/fs")
local gateslot = require("@tests/lib/gateslot")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local SLOTS = `{here}/.cache/c0157-slots`
local STAMPS = `{here}/.cache/c0157-stamps`
local SLOT = `{root}/z-nile/tests/slot.luau`
local NOW = "perl -MTime::HiRes=time -e 'printf qq(%.3f), time'"

local GATE = table.concat({
	"#!/bin/bash",
	"# a gate: acquires a slot for this shell, stamps its start, holds $2 s, stamps its end, releases",
	`lune run {SLOT} -- acquire $$ 2> {STAMPS}/$1.err`,
	`{NOW} > {STAMPS}/$1.start`,
	"sleep $2",
	`{NOW} > {STAMPS}/$1.end`,
	`lune run {SLOT} -- release $$`,
	"",
}, "\n")
local function reset()
	for _, d in { SLOTS, STAMPS } do
		if fs.isDir(d) then
			fs.removeDir(d)
		end
	end
	fs.writeDir(STAMPS)
	fs.writeFile(`{STAMPS}/gate.sh`, GATE)
end
-- the shell line for a gate named `name` with `max` slots, holding `secs` (`extra`: more environment)
local function gate(name: string, max: number, secs: number, extra: string?): string
	return `ZN_GATE_SLOTS={SLOTS} ZN_GATE_SLOTS_MAX={max} {extra or ""} bash {STAMPS}/gate.sh {name} {secs}`
end
local function sh(line: string): boolean
	return process.exec("bash", { "-c", line }).ok
end
-- `line` in the background, stopped after `secs` if it is still running (a gate that never gets a slot)
local function bounded(line: string, secs: number)
	sh(
		`({line}) & w=$!; for i in $(seq {secs * 10}); do kill -0 $w 2>/dev/null || break; sleep 0.1; done; `
			.. "pkill -P $w 2>/dev/null; kill $w 2>/dev/null; wait"
	)
end
local function stamp(name: string, which: string): number
	return tonumber(fs.readFile(`{STAMPS}/{name}.{which}`)) :: number
end
local function ran(name: string): boolean
	return fs.isFile(`{STAMPS}/{name}.end`)
end
local function err(name: string): string
	return fs.readFile(`{STAMPS}/{name}.err`)
end
local function waited(name: string): boolean
	return string.find(err(name), "waiting for a gate slot", 1, true) ~= nil
end
local function slotsLeft(): number
	local n = 0
	if fs.isDir(SLOTS) then
		for _ in fs.readDir(SLOTS) do
			n += 1
		end
	end
	return n
end
local function own(owner: string)
	fs.writeDir(`{SLOTS}/slot-1`)
	fs.writeFile(`{SLOTS}/slot-1/owner`, owner)
end

return t.spec("c0157 concurrent gates share the machine's gate slots", function(it)
	it(
		"as many slots as a gate's 8 lanes fit in the CPUs, at least one; the folder is the user's state",
		function()
			t.expect(gateslot.slotsFor(18, 8)).toBe(2)
			t.expect(gateslot.slotsFor(8, 8)).toBe(1)
			t.expect(gateslot.slotsFor(4, 8)).toBe(1)
			t.expect(gateslot.slotsFor(32, 8)).toBe(4)
			t.expect(gateslot.LANES).toBe(8)
			t.expect(gateslot.dir({ ZN_GATE_SLOTS = "/x", XDG_STATE_HOME = "/s", HOME = "/h" })).toBe("/x")
			t.expect(gateslot.dir({ XDG_STATE_HOME = "/s", HOME = "/h" })).toBe("/s/zn/gate-slots")
			t.expect(gateslot.dir({ HOME = "/h" })).toBe("/h/.local/state/zn/gate-slots")
			t.expect(gateslot.dir({})).toBe(nil)
		end
	)

	it("a lone gate takes a slot at once and gives it back; release frees only the holder's slot", function()
		reset()
		t.expect(sh(gate("lone", 1, 0))).toBe(true)
		t.expect(ran("lone")).toBe(true)
		t.expect(waited("lone")).toBe(false)
		t.expect(slotsLeft()).toBe(0)
		own("999999 1.1 other")
		t.expect(sh(`ZN_GATE_SLOTS={SLOTS} ZN_GATE_SLOTS_MAX=1 lune run {SLOT} -- release 1`)).toBe(true)
		t.expect(fs.isDir(`{SLOTS}/slot-1`)).toBe(true)
		t.expect(sh(`ZN_GATE_SLOTS={SLOTS} ZN_GATE_SLOTS_MAX=1 lune run {SLOT} -- release 999999`)).toBe(true)
		t.expect(fs.isDir(`{SLOTS}/slot-1`)).toBe(false)
		t.expect(sh(`lune run {SLOT} -- take 1`)).toBe(false)
	end)

	it("with one slot, a second gate waits until the first ends; with two, both run at once", function()
		reset()
		t.expect(sh(`({gate("a", 1, 3)}) & sleep 1; {gate("b", 1, 3)}; wait`)).toBe(true)
		t.expect(stamp("b", "start") >= stamp("a", "end")).toBe(true)
		t.expect(waited("b")).toBe(true)
		t.expect((string.find(err("b"), "1 of 1 held", 1, true)) ~= nil).toBe(true)
		reset()
		t.expect(sh(`({gate("c", 2, 3)}) & sleep 1; {gate("d", 2, 3)}; wait`)).toBe(true)
		t.expect(stamp("d", "start") < stamp("c", "end")).toBe(true)
		t.expect(waited("d")).toBe(false)
		t.expect(slotsLeft()).toBe(0)
	end)

	it(
		"a slot whose holder is gone, or is a reused pid, or never wrote its owner, is free; a live holder's is not",
		function()
			reset()
			own("999999 1.1 gone")
			bounded(gate("dead", 1, 0), 5)
			t.expect(ran("dead")).toBe(true)
			t.expect(waited("dead")).toBe(false)
			-- a slot whose taker died before writing its owner, older than the wait for one (5 s)
			fs.writeDir(`{SLOTS}/slot-1`)
			t.expect(process.exec("touch", { "-t", "202001010000", `{SLOTS}/slot-1` }).ok).toBe(true)
			bounded(gate("unowned", 1, 0), 5)
			t.expect(ran("unowned")).toBe(true)
			-- a live pid (this spec's runner) recorded with another process's start id: a reused pid
			local fence = require("@tests/lib/fence")
			local me = fence.myPid()
			own(`{me} 1.1 reused`)
			bounded(gate("reused", 1, 0), 5)
			t.expect(ran("reused")).toBe(true)
			t.expect(waited("reused")).toBe(false)
			-- the same live pid with its own start id holds the slot: the gate waits (stopped after 3 s)
			own(`{me} {fence.startOf(me)} live`)
			bounded(gate("live", 1, 0), 3)
			t.expect(waited("live")).toBe(true)
			t.expect(ran("live")).toBe(false)
			fs.removeDir(`{SLOTS}/slot-1`)
		end
	)

	it("a gate killed while it holds its slot leaves it to the next gate", function()
		reset()
		-- the holder: acquires for itself, then is killed (signal 9) before it can release
		sh(
			`export ZN_GATE_SLOTS={SLOTS} ZN_GATE_SLOTS_MAX=1; bash -c 'lune run {SLOT} -- acquire $$; sleep 30' & h=$!; `
				.. `for i in $(seq 100); do [ -d {SLOTS}/slot-1 ] && break; sleep 0.1; done; pkill -9 -P $h; pkill -9 -P $h; kill -9 $h; wait`
		)
		t.expect(slotsLeft()).toBe(1)
		bounded(gate("next", 1, 0), 8)
		t.expect(ran("next")).toBe(true)
		t.expect(waited("next")).toBe(false)
	end)

	it("a gate run inside a guarded test run (a fixture's gate) takes no slot", function()
		-- this spec runs guarded (inside the fence): with no ZN_GATE_SLOTS the slot is not taken, even though the
		-- folder it would use has one slot, held
		reset()
		local r = process.exec("lune", { "run", SLOT, "--", "acquire", "1" }, {
			env = { ZN_GATE_SLOTS = "", XDG_STATE_HOME = `{SLOTS}/state`, ZN_GATE_SLOTS_MAX = "1" },
		})
		t.expect(r.ok).toBe(true)
		t.expect(fs.isDir(`{SLOTS}/state`)).toBe(false)
	end)

	it("a bounded wait (the Stop hook's) returns without a slot once it runs out, and says so", function()
		reset()
		local fence = require("@tests/lib/fence")
		local me = fence.myPid()
		own(`{me} {fence.startOf(me)} live`)
		bounded(gate("hook", 1, 0, "ZN_GATE_SLOT_WAIT=1"), 8)
		t.expect(ran("hook")).toBe(true)
		t.expect((string.find(err("hook"), "no gate slot after 1s; running without one", 1, true)) ~= nil)
			.toBe(true)
		fs.removeDir(`{SLOTS}/slot-1`)
		local hook = fs.readFile(`{root}/scripts/hooks/stop.sh`)
		t.expect((string.find(hook, "ZN_GATE_SLOT_WAIT=120 scripts/check.sh --affected", 1, true)) ~= nil)
			.toBe(true)
	end)

	it(
		"z-nile/check.sh takes a slot for its shell around each project's spec stage, and gives it back on exit",
		function()
			local text = fs.readFile(`{root}/z-nile/check.sh`)
			local body = string.match(text, "\nrun_specs%(%) {(.-)\n}") or ""
			local function at(needle: string): number?
				return (string.find(body, needle, 1, true))
			end
			t.expect((string.find(text, 'slot="$PWD/z-nile/tests/slot.luau"', 1, true)) ~= nil).toBe(true)
			t.expect(
				(string.find(text, "trap 'lune run \"$slot\" -- release $$ || true' EXIT", 1, true)) ~= nil
			)
				.toBe(true)
			local acquire = at('lune run "$slot" -- acquire $$')
			local first = at("lune run tests/run")
			local release = at('lune run "$slot" -- release $$')
			t.expect(acquire ~= nil and first ~= nil and release ~= nil).toBe(true)
			t.expect((acquire :: number) < (first :: number) and (first :: number) < (release :: number))
				.toBe(true)
		end
	)
end)
