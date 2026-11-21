--!strict
-- R0138 review 001 (F5, F6, F7) and review 002 (F1, F3): the pure rules of the net's time, a net that ends before its
-- marker is reported with its log's path, the kick's time flags fall back to their defaults on a bad value, and a kick made under a bounded
-- run does not hand its deadline to the net. The cases that hold a suite on a marker are in watch-net-survives.spec.luau.
local cpulimit = require("@znile/lib/cpulimit")
local fence = require("@tests/lib/fence")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local process = require("@lune/process")
local reap = require("@znile/engine/reap")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")
local watch = require("@znile/lib/watch")

local has, read, trim = netfix.has, netfix.read, netfix.trim

return t.spec("the net's time rules, early exits and flags", function(it)
	it("a flag's seconds are a positive whole number, else the caller's default", function()
		t.expect(watch.waitSeconds("45")).toBe(45)
		t.expect(watch.waitSeconds("-5")).toBe(nil)
		t.expect(watch.waitSeconds("0")).toBe(nil)
		t.expect(watch.waitSeconds("abc")).toBe(nil)
		t.expect(watch.waitSeconds("2.5")).toBe(nil)
		t.expect(watch.waitSeconds("")).toBe(nil)
		t.expect(watch.waitSeconds(nil)).toBe(nil)
	end)

	it("a further round needs a request, a round to spare and time for the longest round so far", function()
		local margin = watch.ROUND_MARGIN_SECONDS
		t.expect(watch.again(false, 1, 4, { 100 }, 3000)).toBe(false)
		t.expect(watch.again(true, 1, 4, { 100 }, 100 + margin)).toBe(true)
		t.expect(watch.again(true, 3, 4, { 100, 50, 80 }, 3000)).toBe(true)
		t.expect(watch.again(true, 1, 4, { 100 }, 100 + margin - 1)).toBe(false)
		t.expect(watch.again(true, 1, 4, { 3300 }, 300)).toBe(false)
		t.expect(watch.again(true, 4, 4, { 1 }, 3000)).toBe(false)
		-- the longest round counts, not the last: a short tracker-only round after a long full one
		t.expect(watch.again(true, 2, 4, { 2000, 5 }, 1000)).toBe(false)
		t.expect(watch.again(true, 2, 4, { 2000, 5 }, 2000 + margin)).toBe(true)
		-- no time known: the count alone decides
		t.expect(watch.again(true, 1, 4)).toBe(true)
		t.expect(watch.again(true, 4, 4)).toBe(false)
	end)

	it("--limit can only lower the net's own bound", function()
		t.expect(watch.netLimit(7200, 3600)).toBe(3600)
		t.expect(watch.netLimit(nil, 3600)).toBe(3600)
		t.expect(watch.netLimit(1, 3600)).toBe(1)
		t.expect(watch.netLimit(3600, 3600)).toBe(3600)
	end)

	it("the net's script clears the kicker's deadline, the one marker the reaper reads", function()
		t.expect(string.sub(reap.NET_SCRIPT, 1, #"unset ZN_BOUNDED_DEADLINE;"))
			.toBe("unset ZN_BOUNDED_DEADLINE;")
	end)

	it("a CPU limit is enough at the floor or above it, or unlimited; unreadable is not", function()
		t.expect(cpulimit.ok("unlimited", 1200)).toBe(true)
		t.expect(cpulimit.ok("1200", 1200)).toBe(true)
		t.expect(cpulimit.ok("1800", 1200)).toBe(true)
		t.expect(cpulimit.ok("1199", 1200)).toBe(false)
		t.expect(cpulimit.ok("60", 1200)).toBe(false)
		t.expect(cpulimit.ok("", 1200)).toBe(false)
		t.expect(cpulimit.ok("abc", 1200)).toBe(false)
		-- the floor is the spec runner's default CPU limit per run (fence.specCpu spells it; this pins the two together)
		local set = process.env.PICKMAN_SPEC_CPU
		if set == nil or set == "" then
			t.expect(fence.specCpu()).toBe(cpulimit.SPEC_DEFAULT)
		end
	end)

	-- NET_SCRIPT run in a folder whose `./zn` is a stub that records what the script handed it, then ends 0: the script's
	-- whole effect on the net's environment and limits, readable without `ps`
	local function scriptEffect(name: string, wrapper: string): string
		local dir = `{fixture.physical(".")}/.cache/{name}`
		fs.writeDir(dir)
		for _, f in { "seen", "exit", "ready", "log" } do
			if fs.isFile(`{dir}/{f}`) then
				fs.removeFile(`{dir}/{f}`)
			end
		end
		fs.writeFile(
			`{dir}/zn`,
			'#!/bin/sh\necho "deadline=${ZN_BOUNDED_DEADLINE-unset} soft=$(ulimit -St) hard=$(ulimit -Ht)" > seen\n'
		)
		process.exec("chmod", { "+x", `{dir}/zn` })
		local r = process.exec("sh", {
			"-c",
			`{wrapper} exec bash -c "$0" {reap.NET_ARGV0} {dir} {dir}/log {dir}/ready {dir}/exit 120 ""`,
			reap.NET_SCRIPT,
		}, { env = { ZN_BOUNDED_DEADLINE = "123" } })
		t.expect(r.ok).toBe(true)
		t.expect(netfix.waitFor(`{dir}/exit`)).toBe(true)
		return trim(read(`{dir}/seen`))
	end

	it("the net's script hands its own `./zn` no deadline of its kicker", function()
		t.expect(has(scriptEffect("r0138-script-env", ""), "deadline=unset")).toBe(true)
	end)

	it("the net's script raises a soft CPU limit its kicker left to the hard one", function()
		local seen = scriptEffect("r0138-script-soft", "ulimit -St 100;")
		local soft, hard = string.match(seen, "soft=(%S+) hard=(%S+)")
		t.expect(soft ~= nil and soft ~= "100").toBe(true)
		t.expect(soft).toBe(hard)
	end)

	it("a kick from a dispatched step is refused: either variable, set and not empty", function()
		local line = watch.stepKick({ ZN_DISPATCH = "1" })
		t.expect(line ~= nil and has(line :: string, "a dispatched step cannot push the net's records"))
			.toBe(true)
		t.expect(watch.stepKick({ ZN_PUBLISH_BROKER = "/x/broker" }) ~= nil).toBe(true)
		t.expect(watch.stepKick({ ZN_DISPATCH = "1", ZN_PUBLISH_BROKER = "/x" }) ~= nil).toBe(true)
		t.expect(watch.stepKick({})).toBe(nil)
		t.expect(watch.stepKick({ ZN_DISPATCH = "", ZN_PUBLISH_BROKER = "" })).toBe(nil)
	end)

	it("a kick made inside a dispatched step starts no net and makes no folder", function()
		local w = netfix.world("r0138-step", { standing = true })
		local r = trackerfix.tr(
			w.f,
			w.raft,
			{ "watch-kick" },
			{ PICKMAN_WATCH_NET = "on", ZN_DISPATCH = "1" }
		)
		t.expect(r.code).toBe(1)
		t.expect(has(r.stderr, "watch-net: not started: a dispatched step cannot push the net's records"))
			.toBe(true)
		t.expect(fs.isDir(watch.filesDir(w.main))).toBe(false)
		t.expect(fs.isFile(`{w.hold}/runs`)).toBe(false)
	end)

	it("a refused kick still prints the no-pass line, and makes no folder", function()
		-- final review 001 F1: the line is owed on every way out of the kick. A pass commit, then a source commit more
		-- than the limit later (committer dates set here), then a kick from inside a dispatched step.
		local w = netfix.world("r0138-refused-stale", { standing = true })
		local passed = 1767960000 -- 2026-01-09 12:00:00 UTC
		local function commit(path: string, message: string, at: number)
			fs.writeFile(`{w.main}/{path}`, message .. "\n")
			fixture.git(w.f.main, { "add", "-A" })
			local stamp = os.date("!%Y-%m-%dT%H:%M:%SZ", at) :: string
			fixture.git(w.f.main, { "commit", "-q", "-m", message }, {
				env = { GIT_COMMITTER_DATE = stamp, GIT_AUTHOR_DATE = stamp },
			})
			fixture.git(w.f.main, { "push", "-q", "origin", "HEAD:main" })
		end
		commit("pass-marker.txt", "watch-net: the suite passed", passed)
		commit("source-later.txt", "a source change", passed + 24 * 3600 + 60)
		local r = trackerfix.tr(
			w.f,
			w.raft,
			{ "watch-kick" },
			{ PICKMAN_WATCH_NET = "on", ZN_DISPATCH = "1" }
		)
		t.expect(r.code).toBe(1)
		t.expect(has(r.stderr, "watch-net: not started: a dispatched step")).toBe(true)
		t.expect(has(r.stdout, "watch-net: no pass since 2026-01-09")).toBe(true)
		t.expect(fs.isDir(watch.filesDir(w.main))).toBe(false)
	end)

	it("a kick made with a deadline already past leaves the net's suite its own, still to come", function()
		local w = netfix.world("r0138-deadline", { standing = true })
		local past = os.time() - 100
		local r = trackerfix.tr(w.f, w.raft, { "watch-kick" }, {
			PICKMAN_WATCH_NET = "on",
			ZN_BOUNDED_DEADLINE = tostring(past),
		})
		t.expect(r.code).toBe(0)
		netfix.settle(netfix.logOf(r.stdout) :: string)
		local seen = string.match(read(`{w.hold}/env`), "ZN_BOUNDED_DEADLINE=(%d+)")
		t.expect(seen ~= nil).toBe(true)
		t.expect(tonumber(seen) :: number > os.time()).toBe(true)
	end)

	it("a net that ends before its marker is reported with the path of its log", function()
		local e = netfix.world("r0138-early", { standing = true })
		fixture.git(e.f.main, { "worktree", "remove", "--force", `{e.main}/.worktree/watch-net` })
		fs.writeDir(`{e.main}/.worktree/watch-net`)
		fs.writeFile(`{e.main}/.worktree/watch-net/stray.txt`, "x\n")
		local r = netfix.kick(e, e.raft)
		t.expect(r.ok).toBe(false)
		local path = string.match(r.stderr, "watch%-net: log at (%S+%.log)\n")
		t.expect(path ~= nil).toBe(true)
		t.expect(has(read(path :: string), "exists and is not a worktree")).toBe(true)
		t.expect(has(r.stderr, "exists and is not a worktree")).toBe(true)
	end)

	it("a bad --wait is the default, not a wait of no steps", function()
		local d = netfix.world("r0138-wait", { standing = true })
		local r = netfix.kick(d, d.raft, { "--wait", "-5" })
		t.expect(r.code).toBe(0)
		t.expect(has(r.stdout, "started")).toBe(true)
		t.expect(has(r.stderr, "no word from the net")).toBe(false)
		netfix.settle(netfix.logOf(r.stdout) :: string)
	end)
end)
