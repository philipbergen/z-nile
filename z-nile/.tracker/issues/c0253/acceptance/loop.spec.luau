--!strict
-- c0253 AC2, AC3, AC4, AC7, AC8, AC9: the worker's pull loop (workloop.luau) over a fake World that answers only what the
-- layers below document: `./zn next` prints a pick line (exit 0), c0249's `next: nothing to take` (exit 1) or an error (any
-- other outcome), and `./zn dispatch` takes only the argument forms supervise.dispatchArgs builds and exits with the
-- dispatcher's codes (0 done, 1 failure, 3 blocked, 4 gate, 5 tripwire). Nothing starts a process and no model runs.
local supervise = require("@znile/engine/supervise")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")
local workloop = require("@znile/engine/workloop")

type Reply = { out: string, err: string, code: number }
type Cfg = {
	nexts: { string }?, -- per call: "<id> <kind> <why>", "none", "fail" (a fetch that failed), "trace" (a Lune error); after the last, none
	dispatches: { [string]: { number } }?, -- per id: the exit codes of its dispatch runs in order; after the last, 0
	refuse: { [string]: boolean }?, -- ids whose lock is held elsewhere
	stopAfterDispatches: number?,
	stopAfterSleeps: number?,
	held: string?,
	cli: string?,
	noRun: boolean?,
	dispatchSeconds: number?, -- how far the clock moves in a dispatch run
}
type Fake = {
	world: workloop.World,
	calls: { string }, -- every ./zn dispatch argument list, joined
	nextCalls: number,
	sleeps: { number },
	said: { string },
	states: { supervise.State },
	clock: { now: number },
}

local function fake(cfg: Cfg): Fake
	local f: Fake = {
		world = nil :: any,
		calls = {},
		nextCalls = 0,
		sleeps = {},
		said = {},
		states = {},
		clock = { now = 1000000 },
	}
	local runs: { [string]: number } = {}
	f.world = {
		next = function()
			f.nextCalls += 1
			local what = (cfg.nexts or {})[f.nextCalls] or "none"
			if what == "none" then
				return "", "next: nothing to take: no claimable raft", 1
			elseif what == "fail" then
				return "", "fatal: unable to access origin: could not resolve host", 128
			elseif what == "trace" then
				return "", "error: tracker next: main.luau:7790: attempt to index nil", 1
			end
			return what .. "\n", "", 0
		end,
		dispatch = function(args)
			local joined = table.concat(args, " ")
			-- only the documented forms: dispatch [retry] <id> --worker [--cli <name>] [--no-run]
			local ok = string.match(joined, "^dispatch [R%a%d]+ %-%-worker") ~= nil
				or string.match(joined, "^dispatch retry [R%a%d]+ %-%-worker") ~= nil
			if not ok then
				error(`the fake ./zn dispatch does not know: {joined}`)
			end
			table.insert(f.calls, joined)
			local id = string.match(joined, "^dispatch retry (%S+)")
				or string.match(joined, "^dispatch (%S+)") :: string
			runs[id] = (runs[id] or 0) + 1
			f.clock.now += cfg.dispatchSeconds or 1
			local codes = (cfg.dispatches or {})[id] or {}
			return codes[runs[id]] or 0
		end,
		lock = function(id)
			return not (cfg.refuse and cfg.refuse[id])
		end,
		unlock = function() end,
		now = function()
			return f.clock.now
		end,
		sleep = function(seconds)
			table.insert(f.sleeps, seconds)
			f.clock.now += seconds
		end,
		stopped = function()
			return (cfg.stopAfterSleeps ~= nil and #f.sleeps >= cfg.stopAfterSleeps)
				or (cfg.stopAfterDispatches ~= nil and #f.calls >= cfg.stopAfterDispatches)
		end,
		state = function(s)
			table.insert(f.states, s)
		end,
		say = function(line)
			table.insert(f.said, line)
		end,
		held = cfg.held or "",
		cli = cfg.cli,
		noRun = cfg.noRun or false,
		idleSeconds = nil,
	}
	return f
end

local function has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) then
			return true
		end
	end
	return false
end

local ONCE: workloop.Options = { once = true }
local FOREVER: workloop.Options = { once = false }

return t.spec("c0253 the worker's pull loop", function(it)
	it(
		"AC2: a pick goes to the dispatcher's chain with the person's CLI, and a finished chain is moved",
		function()
			local f = fake({ nexts = { "R0010 raft rank unset" }, cli = "kimi" })
			local s = workloop.run(f.world, ONCE)
			t.expect(f.calls).toEqual({ "dispatch R0010 --worker --cli kimi" })
			t.expect(s.moved).toEqual({ "R0010" })
			t.expect(#s.blocked).toBe(0)
		end
	)

	it("AC2: a draft, a rafting and a lost pick each go through the chain the same way", function()
		local f = fake({
			nexts = {
				"c0300 draft the idea is confirmed",
				"c0301 rafting approved, in no raft",
				"R0020 lost its heartbeat is stale",
			},
		})
		local s = workloop.run(f.world, { once = false, maxItems = 3 })
		t.expect(f.calls)
			.toEqual({ "dispatch c0300 --worker", "dispatch c0301 --worker", "dispatch R0020 --worker" })
		t.expect(s.moved).toEqual({ "c0300", "c0301", "R0020" })
	end)

	it("AC2: a raft the previous run held is carried on before next is asked", function()
		local f = fake({ held = "R0010", nexts = { "R0020 raft rank unset" } })
		workloop.run(f.world, { once = false, maxItems = 2 })
		t.expect(f.calls[1]).toBe("dispatch R0010 --worker")
		t.expect(f.calls[2]).toBe("dispatch R0020 --worker")
		-- next was asked once, for the second item: the held raft came first
		t.expect(f.nextCalls).toBe(1)
	end)

	it(
		"AC2: the state file names the item held while its chain runs, and nothing held when it ends",
		function()
			local f = fake({ nexts = { "R0010 raft rank unset" } })
			workloop.run(f.world, ONCE)
			local sawHeld, last = false, f.states[#f.states]
			for _, s in f.states do
				if s.held == "R0010" and s.state == "working" then
					sawHeld = true
				end
			end
			t.expect(sawHeld).toBe(true)
			t.expect(last.state).toBe("stopped")
			t.expect(last.held).toBe("")
		end
	)

	it(
		"AC3: with nothing claimable the loop waits between polls with no dispatch run, and --once does not wait",
		function()
			local f = fake({ stopAfterSleeps = 3 })
			local s = workloop.run(f.world, FOREVER)
			t.expect(#f.calls).toBe(0)
			t.expect(f.sleeps).toEqual({ 60, 60, 60 })
			t.expect(f.nextCalls).toBe(3)
			t.expect(s.stopped).toBe("stop asked")
			local g = fake({})
			local o = workloop.run(g.world, ONCE)
			t.expect(#g.sleeps).toBe(0)
			t.expect(string.find(o.stopped, "--once", 1, true) ~= nil).toBe(true)
		end
	)

	it("AC3: --max-items N ends the loop after N items", function()
		local f = fake({ nexts = { "R0010 raft rank 1", "R0020 raft rank 2", "R0030 raft rank 3" } })
		local s = workloop.run(f.world, { once = false, maxItems = 2 })
		t.expect(s.moved).toEqual({ "R0010", "R0020" })
		t.expect(#f.calls).toBe(2)
		t.expect(string.find(s.stopped, "--max-items 2", 1, true) ~= nil).toBe(true)
	end)

	it(
		"AC3: a stop asked ends the worker after the dispatch run in progress and the raft stays held",
		function()
			local f = fake({
				nexts = { "R0010 raft rank 1", "R0020 raft rank 2" },
				dispatches = { R0010 = { 4, 4 } },
				stopAfterDispatches = 1,
			})
			local s = workloop.run(f.world, FOREVER)
			t.expect(s.stopped).toBe("stop asked")
			t.expect(f.calls).toEqual({ "dispatch R0010 --worker" })
			t.expect(#s.moved + #s.blocked).toBe(0)
			t.expect(f.states[#f.states].held).toBe("R0010")
			t.expect(has(f.said, "stays held")).toBe(true)
		end
	)

	it("AC3: an item another worker holds is not taken, and the loop waits instead of spinning", function()
		local f = fake({
			nexts = { "R0010 raft rank 1", "R0010 raft rank 1" },
			refuse = { R0010 = true },
			stopAfterSleeps = 2,
		})
		local s = workloop.run(f.world, FOREVER)
		t.expect(#f.calls).toBe(0)
		t.expect(#s.moved + #s.blocked).toBe(0)
		t.expect(#f.sleeps >= 2).toBe(true)
	end)

	it("AC9: a failed read of next is retried after a wait, never read as a pick or as nothing", function()
		local f = fake({ nexts = { "fail", "trace", "R0010 raft rank 1" } })
		local s = workloop.run(f.world, ONCE)
		t.expect(f.calls).toEqual({ "dispatch R0010 --worker" })
		t.expect(f.sleeps).toEqual({ 60, 60 })
		t.expect(s.moved).toEqual({ "R0010" })
	end)

	it("AC9: reads that keep failing stop the worker naming the error", function()
		local f = fake({ nexts = { "fail", "fail", "fail", "fail", "fail", "fail" } })
		local s = workloop.run(f.world, FOREVER)
		t.expect(#f.calls).toBe(0)
		t.expect(f.nextCalls).toBe(supervise.READ_RETRIES)
		t.expect(string.find(s.stopped, "could not resolve host", 1, true) ~= nil).toBe(true)
	end)

	it("AC9: a Lune error that exits 1 is a failed read, not an empty stack", function()
		local f = fake({ nexts = { "trace", "trace", "trace", "trace", "trace" } })
		local s = workloop.run(f.world, FOREVER)
		t.expect(string.find(s.stopped, "attempt to index nil", 1, true) ~= nil).toBe(true)
		t.expect(#f.sleeps).toBe(supervise.READ_RETRIES - 1)
	end)

	it("AC4: a blocked item is counted and the loop goes on to the next raft, which is taken", function()
		local f =
			fake({ nexts = { "R0010 raft rank 1", "R0020 raft rank 2" }, dispatches = { R0010 = { 3 } } })
		local s = workloop.run(f.world, { once = false, maxItems = 2 })
		t.expect(s.blocked).toEqual({ "R0010" })
		t.expect(s.moved).toEqual({ "R0020" })
		t.expect(f.calls).toEqual({ "dispatch R0010 --worker", "dispatch R0020 --worker" })
	end)

	it("AC4: two blocked items in a row stop the worker", function()
		local f = fake({
			nexts = { "R0010 raft rank 1", "R0020 raft rank 2", "R0030 raft rank 3" },
			dispatches = { R0010 = { 3 }, R0020 = { 3 } },
		})
		local s = workloop.run(f.world, FOREVER)
		t.expect(s.blocked).toEqual({ "R0010", "R0020" })
		t.expect(s.stopped).toBe(work.blockedWhy())
		t.expect(#f.calls).toBe(2)
	end)

	it(
		"AC4: a failed chain is run again once with retry, and a second failure stops the worker naming the item",
		function()
			local f = fake({ nexts = { "R0010 raft rank 1" }, dispatches = { R0010 = { 1, 0 } } })
			local s = workloop.run(f.world, ONCE)
			t.expect(f.calls).toEqual({ "dispatch R0010 --worker", "dispatch retry R0010 --worker" })
			t.expect(s.moved).toEqual({ "R0010" })
			local g = fake({
				nexts = { "R0010 raft rank 1", "R0020 raft rank 2" },
				dispatches = { R0010 = { 1, 1 } },
			})
			local stopped = workloop.run(g.world, FOREVER)
			t.expect(g.calls).toEqual({ "dispatch R0010 --worker", "dispatch retry R0010 --worker" })
			t.expect(string.find(stopped.stopped, "R0010", 1, true) ~= nil).toBe(true)
			t.expect(g.states[#g.states].held).toBe("R0010")
		end
	)

	it("AC4: a tripwire stops the worker, keeps the item held and names it", function()
		local f =
			fake({ nexts = { "R0010 raft rank 1", "R0020 raft rank 2" }, dispatches = { R0010 = { 5 } } })
		local s = workloop.run(f.world, FOREVER)
		t.expect(#f.calls).toBe(1)
		t.expect(string.find(s.stopped, "tripwire", 1, true) ~= nil).toBe(true)
		t.expect(f.states[#f.states].held).toBe("R0010")
	end)

	it(
		"AC7: a raft's pending gate is waited for and dispatched again, bounded by the clock, not by the number of runs",
		function()
			local codes: { number } = {}
			for _ = 1, 200 do
				table.insert(codes, 4)
			end
			local f = fake({
				nexts = { "R0010 raft rank 1" },
				dispatches = { R0010 = codes },
				dispatchSeconds = 600,
			})
			local s = workloop.run(f.world, FOREVER)
			-- each run takes 600 s on the clock, each wait 60: the 7200 s bound is reached after about eleven runs
			t.expect(#f.calls >= 10 and #f.calls <= 13).toBe(true)
			t.expect(string.find(s.stopped, "gate stayed pending", 1, true) ~= nil).toBe(true)
			t.expect(f.states[#f.states].held).toBe("R0010")
		end
	)

	it("AC7: a pending gate that clears ends the item as moved with no second session of ours", function()
		local f =
			fake({ nexts = { "c0301 rafting approved, in no raft" }, dispatches = { c0301 = { 4, 4, 0 } } })
		local s = workloop.run(f.world, ONCE)
		t.expect(s.moved).toEqual({ "c0301" })
		t.expect(f.calls)
			.toEqual({ "dispatch c0301 --worker", "dispatch c0301 --worker", "dispatch c0301 --worker" })
		t.expect(f.sleeps).toEqual({ 60, 60 })
	end)

	it(
		"AC7: a draft that waits for the person's approval is parked and the loop takes the next pick",
		function()
			local f = fake({
				nexts = { "c0300 draft the idea is confirmed", "R0020 raft rank 2" },
				dispatches = { c0300 = { 4 } },
			})
			local s = workloop.run(f.world, { once = false, maxItems = 2 })
			t.expect(f.calls).toEqual({ "dispatch c0300 --worker", "dispatch R0020 --worker" })
			t.expect(s.moved).toEqual({ "R0020" })
			t.expect(#f.sleeps).toBe(0)
		end
	)

	it("AC8: a host that does not land passes --no-run, so the run gate (the landing) stays off", function()
		local f = fake({ nexts = { "R0010 raft rank 1" }, noRun = true, cli = "claude" })
		workloop.run(f.world, ONCE)
		t.expect(f.calls).toEqual({ "dispatch R0010 --worker --cli claude --no-run" })
	end)
end)
