--!strict
-- c0275: the background beater (`./zn run --time 3600 -- ./zn beat <id> --watch`, started detached by a claim) is not a
-- leak while it lives: the reaper's orphan rule spares it and what runs below it, and still stops it past its deadline
-- (the marked rule) and with its session (the session rule). Pure rules over a process table.
local reap = require("@znile/engine/reap")
local t = require("@tests/lib/t")

local NOW = 1793500000
local ME = 501
local ROOT = "/Users/me/code/pickman"
local WT = `{ROOT}/.worktree/prep-x`
local BEATER = `perl {WT}/z-nile/lib/bounded.pl --time 3600 -- {WT}/zn beat c0010 --watch --session 77`

local function p(over: { [string]: any }): reap.Proc
	local base: reap.Proc = {
		pid = 1000,
		ppid = 1,
		uid = ME,
		age = 600,
		cpu = 1,
		start = "Sat Oct 31 13:00:00 2026",
		command = "sleep 1000",
		cwd = WT,
	}
	for k, v in over do
		(base :: any)[k] = if v == false then nil else v
	end
	return base
end
local function opts(over: { [string]: any }?): reap.Options
	local base: reap.Options = {
		uid = ME,
		now = NOW,
		minAge = 60,
		grace = 5,
		roots = { ROOT },
		scratch = {},
		self = { 7, 8 },
		under = nil,
		sessionAnywhere = false,
	}
	for k, v in (over or {}) :: { [string]: any } do
		(base :: any)[k] = v
	end
	return base
end
local function pids(procs: { reap.Proc }, o: reap.Options?): { number }
	local out = {}
	for _, x in reap.decide(procs, o or opts()) do
		table.insert(out, x.proc.pid)
	end
	table.sort(out)
	return out
end

return t.spec("c0275 the background beater is not a leak", function(it)
	it("only a runner of beat <id> --watch is a beater", function()
		t.expect(reap.isBeater(BEATER)).toBe(true)
		t.expect(reap.isBeater(`perl {WT}/z-nile/lib/bounded.pl --time 3600 -- {WT}/zn beat R0010 --watch`)).toBe(true)
		t.expect(reap.isBeater(`perl {WT}/z-nile/lib/bounded.pl --time 60 -- sleep 50`)).toBe(false)
		t.expect(reap.isBeater(`perl {WT}/z-nile/lib/bounded.pl --time 3600 -- {WT}/zn beat c0010`)).toBe(false)
		t.expect(reap.isBeater(`{WT}/zn beat c0010 --watch`)).toBe(false) -- not under the runner: nothing bounds it
	end)

	it("a beater whose starter is gone, and what runs below it, are spared the orphan rule", function()
		local procs = {
			p({ pid = 100, ppid = 1, command = BEATER }),
			p({ pid = 101, ppid = 100, command = "lune run engine/main.luau beat c0010 --watch" }),
			p({ pid = 102, ppid = 101, command = "sleep 5" }),
		}
		t.expect(pids(procs)).toEqual({})
		-- the same shapes without the beater's command line are orphans, as before
		local plain = {
			p({ pid = 100, ppid = 1, command = `perl {WT}/z-nile/lib/bounded.pl --time 3600 -- sleep 9000` }),
			p({ pid = 102, ppid = 100, command = "sleep 5" }),
		}
		t.expect(pids(plain)).toEqual({ 100 })
	end)

	it("a beater past its deadline is stopped, as any marked process, and a session end stops what ran below its shell", function()
		local late = { p({ pid = 101, ppid = 100, command = "lune run engine/main.luau beat c0010 --watch", deadline = tostring(NOW - 100) }) }
		t.expect(pids({ p({ pid = 100, ppid = 1, command = BEATER }), late[1] })).toEqual({ 101 })
		local shell = p({ pid = 200, ppid = 50, command = "/bin/zsh -c source /Users/me/.claude/shell-snapshots/s.sh && ./zn status c0010" })
		local claude = p({ pid = 50, ppid = 1, command = "/Users/me/.local/bin/claude" })
		t.expect(pids({ claude, shell, p({ pid = 100, ppid = 1, command = BEATER }) }, opts({ under = 50 }))).toEqual({ 200 })
	end)
end)
