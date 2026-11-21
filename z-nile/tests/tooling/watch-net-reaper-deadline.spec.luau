--!strict
-- R0138 review 001 F4: the watch net's shelter is from the reaper's orphan rule only. A process below the net's group shell
-- that is past its own `./zn run` deadline is still stopped; the same process with a deadline still to come is not.
local reap = require("@znile/engine/reap")
local t = require("@tests/lib/t")

local NOW = 1793500000
local ME = 501
local MAIN = "/Users/me/code/pickman"

local function p(over: { [string]: any }): reap.Proc
	local base: reap.Proc = {
		pid = 1000,
		ppid = 1,
		uid = ME,
		age = 120,
		cpu = 1,
		start = "Sat Oct 31 13:00:00 2026",
		command = "sleep 600",
		cwd = `{MAIN}/.worktree/R0101`,
	}
	for k, v in over do
		(base :: any)[k] = if v == false then nil else v
	end
	return base
end

local function leaks(procs: { reap.Proc }): { number }
	local out = {}
	local opts: reap.Options = {
		uid = ME,
		now = NOW,
		minAge = 60,
		grace = 5,
		roots = { MAIN },
		scratch = {},
		self = { 7, 8 },
		under = nil,
		sessionAnywhere = true,
	}
	for _, x in reap.decide(procs, opts) do
		table.insert(out, x.proc.pid)
	end
	table.sort(out)
	return out
end

local SHELL =
	`bash -c {reap.NET_SCRIPT} {reap.NET_ARGV0} {MAIN}/.worktree/R0101 /m/a.log /m/a.ready /m/a.exit 120`

-- The net as a bounded kicker produces it: the group shell carries the kicker's deadline (past by now; its exec-time
-- environment), NET_SCRIPT cleared it for the outer `./zn run` perl, so that perl and everything below carry only the
-- deadline the net's own `./zn run` set (`own`).
local function net(shellDeadline: number, own: number): { reap.Proc }
	return {
		p({ pid = 500, command = SHELL, deadline = tostring(shellDeadline) }),
		p({ pid = 501, ppid = 500, command = "perl /m/z-nile/lib/bounded.pl --time 3600 -- ./zn watch-net" }),
		p({
			pid = 502,
			ppid = 501,
			command = "lune run z-nile/engine/main.luau watch-net",
			deadline = tostring(NOW + 3000),
		}),
		p({ pid = 503, ppid = 502, command = "bash z-nile/check.sh --full", deadline = tostring(own) }),
	}
end

return t.spec("the watch net is sheltered from the orphan rule only", function(it)
	it(
		"a young net kicked under a bounded run, whose own deadline is still to come, is not stopped",
		function()
			t.expect(leaks(net(NOW - 100, NOW + 3000))).toEqual({})
		end
	)

	it("a process below the net past the net's OWN deadline by more than the grace is stopped", function()
		t.expect(leaks(net(NOW - 100, NOW - 6))).toEqual({ 503 })
		t.expect(leaks(net(NOW - 100, NOW - 5))).toEqual({})
	end)

	it(
		"the outer wrapper carrying the kicker's past deadline would be stopped: why the script clears it",
		function()
			local procs = net(NOW - 100, NOW + 3000)
			local outer: any = procs[2]
			outer.deadline = tostring(NOW - 100)
			t.expect(leaks(procs)).toEqual({ 501 })
		end
	)

	it("an old net is an ordinary orphan again", function()
		local procs = net(NOW - 100, NOW + 3000)
		local shell: any = procs[1]
		shell.age = reap.NET_MAX_AGE + 1
		t.expect(leaks(procs)).toEqual({ 500 })
	end)
end)
