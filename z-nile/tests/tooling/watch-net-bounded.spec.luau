--!strict
-- R0138 review 002 F1, the coordinator's ruling: a net kicked from under `./zn run` survives that command. The kick starts
-- the net in a process group of its own (reap.NET_DETACH), so `bounded.pl`'s group kill of the kicker's command, when it ends
-- or when its deadline passes, does not reach it. `ps` is denied in the spec jail, so the group is proved by behaviour: the
-- kicker's `./zn run` has ended (its deadline passed in the second case), the net's suite is held on a marker, and after
-- the release the net still finishes and writes its exit file, which a killed net never does.
local cpulimit = require("@znile/lib/cpulimit")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local watch = require("@znile/lib/watch")

local has, read, trim = netfix.has, netfix.read, netfix.trim

local function runs(w: netfix.World): string
	return string.gsub(trim(read(`{w.hold}/runs`)), "\n", " ") :: string
end

-- `./zn run --time <limit> --cpu <cpu> -- bash -c <command>` in the raft's worktree, the kick's own `./zn` being the fixture's
local function bounded(w: netfix.World, limit: number, cpu: number, command: string): fixture.Result
	local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
	local argv = { "run", "--time", tostring(limit), "--cpu", tostring(cpu), "--", "bash", "-c", command }
	return fixture.exec(w.raft, `{top}/zn`, argv, { env = netfix.ON })
end

-- the CPU limit the net's stub suite saw (the runner's own 1200 holds when it is lower than the --cpu asked for)
local function cpuSeen(w: netfix.World): number
	return tonumber(trim(read(`{w.hold}/cpu`))) or 0
end

return t.spec("a net kicked from under ./zn run outlives that command", function(it)
	local w = netfix.world("r0138-bounded", { standing = true })

	it("the kicker's command ends normally: the held net goes on and finishes", function()
		netfix.holdOn(w)
		local r = bounded(w, 60, 1800, "bash scripts/tracker.sh watch-kick")
		t.expect(r.code).toBe(0)
		t.expect(has(r.stdout, "started")).toBe(true)
		local log = netfix.logOf(r.stdout) :: string
		t.expect(netfix.waitFor(`{w.hold}/started`)).toBe(true)
		-- the kicker's `./zn run` is over: its group kill has happened
		t.expect(fs.isFile((string.gsub(log, "%.log$", ".exit")))).toBe(false)
		fs.writeFile(`{w.hold}/release`, "go\n")
		t.expect(netfix.settle(log)).toBe("0")
		t.expect(runs(w)).toBe("start end")
		-- the net's suite runs under a CPU limit that is not the kicker's short one
		t.expect(cpuSeen(w) >= cpulimit.SPEC_DEFAULT).toBe(true)
	end)

	it("the kicker's deadline passes while the net runs: the net is not stopped with it", function()
		fs.removeFile(`{w.hold}/release`)
		fs.removeFile(`{w.hold}/started`)
		fs.removeFile(`{w.hold}/runs`)
		-- the command kicks, then keeps running past its limit of 10 s, so `./zn run` stops it by its deadline
		local r = bounded(w, 10, 1800, "bash scripts/tracker.sh watch-kick; sleep 40")
		t.expect(r.code ~= 0).toBe(true)
		t.expect(has(r.stdout, "started")).toBe(true)
		local log = netfix.logOf(r.stdout) :: string
		t.expect(netfix.waitFor(`{w.hold}/started`)).toBe(true)
		t.expect(fs.isFile((string.gsub(log, "%.log$", ".exit")))).toBe(false)
		fs.writeFile(`{w.hold}/release`, "go\n")
		t.expect(netfix.settle(log)).toBe("0")
		t.expect(runs(w)).toBe("start end")
		-- the net's suite runs under a CPU limit that is not the kicker's short one
		t.expect(cpuSeen(w) >= cpulimit.SPEC_DEFAULT).toBe(true)
	end)

	it("a kicker under a CPU limit below the floor gets no net, and the reason on stderr", function()
		local v = netfix.world("r0138-cpu", { standing = true })
		netfix.holdOn(v)
		-- a stale history (final review 002 F1): a pass commit, then a source commit more than the limit later, so the
		-- refused kick owes the no-pass line too
		local passed = 1767960000 -- 2026-01-09 12:00:00 UTC
		for _, c in
			{
				{ path = "pass-marker.txt", message = "watch-net: the suite passed", at = passed },
				{ path = "source-later.txt", message = "a source change", at = passed + 24 * 3600 + 60 },
			}
		do
			fs.writeFile(`{v.main}/{c.path}`, c.message .. "\n")
			fixture.git(v.f.main, { "add", "-A" })
			local stamp = os.date("!%Y-%m-%dT%H:%M:%SZ", c.at) :: string
			fixture.git(v.f.main, { "commit", "-q", "-m", c.message }, {
				env = { GIT_COMMITTER_DATE = stamp, GIT_AUTHOR_DATE = stamp },
			})
			fixture.git(v.f.main, { "push", "-q", "origin", "HEAD:main" })
		end
		local r = bounded(v, 60, 60, "bash scripts/tracker.sh watch-kick")
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "watch-net: no pass since 2026-01-09")).toBe(true)
		t.expect(has(r.stderr, "watch-net: not started: this command runs under a CPU limit of 60 s"))
			.toBe(true)
		t.expect(has(r.stderr, `the net needs {cpulimit.SPEC_DEFAULT} s`)).toBe(true)
		-- the refusal comes before the net's folder is made (a net started first and refused after would leave it)
		local files = watch.filesDir(v.main)
		t.expect(fs.isDir(files)).toBe(false)
		t.expect(fs.isFile(`{v.hold}/runs`)).toBe(false)
	end)
end)
