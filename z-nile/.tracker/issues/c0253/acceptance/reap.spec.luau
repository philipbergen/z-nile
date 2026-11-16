--!strict
-- c0253 AC10: `./zn reap` leaves the one supervisor the main checkout's state file names (its pid, and only when its command is
-- `lune … engine/main -- work run`) and nothing else: a process whose arguments merely say `work run`, a process of that
-- command the state file does not name, an orphan beside it, and what runs below it past its deadline are all still leaks.
-- Pure over the reaper's rules (reap.decide); no process is started.
local reap = require("@znile/engine/reap")
local t = require("@tests/lib/t")

local CWD = "/Users/me/code/pickman/.worktree/R0010"
local function options(keep: { number }?): reap.Options
	return {
		uid = 501,
		now = 1793500000,
		minAge = 60,
		grace = 5,
		roots = { "/Users/me/code/pickman" },
		scratch = {},
		self = { 7 },
		under = nil,
		keep = keep,
		sessionAnywhere = true,
	}
end

local function proc(pid: number, ppid: number, command: string, deadline: string?): reap.Proc
	return {
		pid = pid,
		ppid = ppid,
		uid = 501,
		age = 7200,
		cpu = 3000,
		start = "Sat Oct 31 13:00:00 2026",
		command = command,
		cwd = CWD,
		deadline = deadline,
	}
end

local SUPERVISOR = "lune run z-nile/engine/main -- work run --cli claude"

local function pidsOf(procs: { reap.Proc }, keep: { number }?): { number }
	local pids: { number } = {}
	for _, tg in reap.decide(procs, options(keep)) do
		table.insert(pids, tg.proc.pid)
	end
	return pids
end

return t.spec("c0253 the reaper leaves the supervisor alone", function(it)
	it("AC10: the supervisor is recognised by the command it runs, and only by that", function()
		t.expect(reap.isSupervisor(proc(10, 1, SUPERVISOR))).toBe(true)
		t.expect(reap.isSupervisor(proc(10, 1, "/x/lune/0.10.5/lune run z-nile/engine/main -- work run")))
			.toBe(true)
		t.expect(reap.isSupervisor(proc(10, 1, "lune run z-nile/engine/main -- work status"))).toBe(false)
		t.expect(reap.isSupervisor(proc(10, 1, "lune run probe -- work run"))).toBe(false)
		t.expect(reap.isSupervisor(proc(10, 1, "sh -c 'lune run z-nile/engine/main -- work run'")))
			.toBe(false)
	end)

	it(
		"AC10: the orphaned supervisor the state file names is kept, and a stray orphan beside it is not",
		function()
			local procs = { proc(10, 1, SUPERVISOR), proc(20, 1, "lune run probe.luau") }
			local kept = pidsOf(procs, { 10 })
			t.expect(table.find(kept, 10)).toBe(nil)
			t.expect(table.find(kept, 20) ~= nil).toBe(true)
		end
	)

	it(
		"AC10: a supervisor-looking process the state file does not name is a leak, and so is a named pid with another command",
		function()
			t.expect(table.find(pidsOf({ proc(10, 1, SUPERVISOR) }, nil), 10) ~= nil).toBe(true)
			t.expect(table.find(pidsOf({ proc(10, 1, SUPERVISOR) }, { 11 }), 10) ~= nil).toBe(true)
			t.expect(table.find(pidsOf({ proc(10, 1, "lune run probe.luau") }, { 10 }), 10) ~= nil).toBe(true)
		end
	)

	it("AC10: what runs below the supervisor keeps every rule, the deadline included", function()
		local procs = {
			proc(10, 1, SUPERVISOR),
			proc(11, 10, "sh -c ./zn check c0001", tostring(1793499000)), -- ZN_BOUNDED_DEADLINE long past
		}
		local gone = pidsOf(procs, { 10 })
		t.expect(table.find(gone, 10)).toBe(nil)
		t.expect(table.find(gone, 11) ~= nil).toBe(true)
	end)

	it(
		"AC10: a supervisor a session started in the background (the window way) ends with that session, the detached one does not",
		function()
			local shell =
				"/bin/zsh -c source /Users/me/.claude/shell-snapshots/snapshot-zsh-1.sh && ./zn work run"
			local procs = {
				proc(30, 5, shell), -- the ending session's tool shell (its parent, 5, is the session's claude)
				proc(31, 30, SUPERVISOR), -- the window supervisor below it
				proc(40, 1, SUPERVISOR), -- a detached one
			}
			local o = options({ 31, 40 })
			o.under = 5
			local pids: { number } = {}
			for _, tg in reap.decide(procs, o) do
				table.insert(pids, tg.proc.pid)
				for _, below in tg.tree do
					table.insert(pids, below.pid)
				end
			end
			t.expect(table.find(pids, 30) ~= nil).toBe(true)
			t.expect(table.find(pids, 31) ~= nil).toBe(true)
			t.expect(table.find(pids, 40)).toBe(nil)
		end
	)

	it(
		"AC10: the launcher shim above the named supervisor (the same command, its parent) is kept with it",
		function()
			local procs = {
				proc(9, 1, SUPERVISOR),
				proc(10, 9, "/x/lune/0.10.5/lune run z-nile/engine/main -- work run --cli claude"),
				proc(20, 1, "lune run probe.luau"),
			}
			local gone = pidsOf(procs, { 10 })
			t.expect(table.find(gone, 9)).toBe(nil)
			t.expect(table.find(gone, 10)).toBe(nil)
			t.expect(table.find(gone, 20) ~= nil).toBe(true)
		end
	)
end)
