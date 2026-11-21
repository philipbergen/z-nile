--!strict
-- d0383 F2: the reaper must not stop the net the kick detached. The kick's group shell (`bash -c <script> zn-watch-net-kick
-- <checkout> ...`) is an orphan by the reaper's rules, and so is everything below it; exactly that command shape, while
-- younger than the net's own limit, and its tree are exempt, and nothing else is. Pure cases over a process table, in the
-- style of c0191's reaper spec (whose own file is promoted and not edited).
local reap = require("@znile/engine/reap")
local t = require("@tests/lib/t")

local NOW = 1793500000
local ME = 501
local MAIN = "/Users/me/code/pickman"
local KICK_CWD = `{MAIN}/.worktree/R0101`

local function p(over: { [string]: any }): reap.Proc
	local base: reap.Proc = {
		pid = 1000,
		ppid = 1,
		uid = ME,
		age = 120,
		cpu = 1,
		start = "Sat Oct 31 13:00:00 2026",
		command = "sleep 600",
		cwd = KICK_CWD,
	}
	for k, v in over do
		(base :: any)[k] = if v == false then nil else v
	end
	return base
end

local function opts(): reap.Options
	return {
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
end

local function leaks(procs: { reap.Proc }): { number }
	local out = {}
	for _, x in reap.decide(procs, opts()) do
		table.insert(out, x.proc.pid)
	end
	table.sort(out)
	return out
end

local function kickCommand(script: string?, argv0: string?): string
	return `bash -c {script or reap.NET_SCRIPT} {argv0 or reap.NET_ARGV0} {KICK_CWD} /m/.cache/watch-net/1-2.log /m/.cache/watch-net/1-2.ready /m/.cache/watch-net/1-2.exit 120`
end

-- the net's tree as ps lists it: the group shell, `./zn run`'s perl, the net's lune, the suite's bash, a spec's lune
local function tree(shell: { [string]: any }?): { reap.Proc }
	return {
		p(shell or { pid = 500, command = kickCommand() }),
		p({ pid = 501, ppid = 500, command = "perl /m/z-nile/lib/bounded.pl --time 3600 -- ./zn watch-net" }),
		p({ pid = 502, ppid = 501, command = "lune run z-nile/engine/main.luau watch-net" }),
		p({ pid = 503, ppid = 502, command = "bash z-nile/check.sh --full" }),
		p({ pid = 504, ppid = 503, command = "lune run tests/run -- tests/x.spec.luau" }),
	}
end

return t.spec("the reaper leaves the watch net alone and nothing else", function(it)
	it("the net's group shell is recognised by the exact script the kick runs", function()
		t.expect(reap.isNet(p({ command = kickCommand() }))).toBe(true)
		t.expect(reap.isNet(p({ command = `/bin/{kickCommand()}` }))).toBe(true)
		t.expect(reap.isNet(p({ command = kickCommand("echo hi") }))).toBe(false)
		t.expect(reap.isNet(p({ command = kickCommand(nil, "watch-net") }))).toBe(false)
		t.expect(reap.isNet(p({ command = `bash -c {reap.NET_SCRIPT}` }))).toBe(false)
		t.expect(reap.isNet(p({ command = `sh -c {reap.NET_SCRIPT} {reap.NET_ARGV0} /x` }))).toBe(false)
		t.expect(reap.isNet(p({ command = `echo bash -c {reap.NET_SCRIPT} {reap.NET_ARGV0} /x` })))
			.toBe(false)
		-- the words alone, anywhere else in a command, are nothing
		t.expect(reap.isNet(p({ command = `bash -c 'sleep 9' {reap.NET_ARGV0} /x ./zn watch-net --ready` })))
			.toBe(false)
	end)

	it("a net two minutes after its kick, with its whole tree, is not a leak", function()
		t.expect(leaks(tree())).toEqual({})
	end)

	it(
		"the same tree one second short of the net's own limit is kept, one second past it is stopped",
		function()
			t.expect(leaks(tree({ pid = 500, command = kickCommand(), age = reap.NET_MAX_AGE }))).toEqual({})
			t.expect(leaks(tree({ pid = 500, command = kickCommand(), age = reap.NET_MAX_AGE + 1 })))
				.toEqual({ 500 })
		end
	)

	it("the same tree under any other command is still an orphan, and is listed once, at its root", function()
		t.expect(leaks(tree({ pid = 500, command = kickCommand("echo hi") }))).toEqual({ 500 })
		t.expect(leaks(tree({ pid = 500, command = kickCommand(nil, "watch-net") }))).toEqual({ 500 })
	end)

	it("an ordinary orphan of the same age beside the net is listed, the net's tree is not", function()
		local procs = tree()
		table.insert(procs, p({ pid = 900, command = "sleep 600", age = 120 }))
		table.insert(procs, p({ pid = 901, command = "bash -c ( sleep 25 ) &", age = 120 }))
		t.expect(leaks(procs)).toEqual({ 900, 901 })
	end)

	it("a process that merely sits below a net's group shell is exempt only through it", function()
		-- the net's shell is not in the table (gone): its orphaned children are ordinary orphans again
		local procs = tree()
		table.remove(procs, 1)
		for _, x in procs do
			if x.pid == 501 then
				x.ppid = 1
			end
		end
		t.expect(leaks(procs)).toEqual({ 501 })
	end)
end)
