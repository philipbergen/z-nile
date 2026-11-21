--!strict
-- f0424 AC14 to AC18: the live layer's contract through `./zn live`, by argv only, against a real daemon the helper
-- starts inside the spec's fixture (tests/lib/live.luau: its own state, a short idle limit, shut down at the end).
local fs = require("@lune/fs")
local live = require("@tests/lib/live")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local task = require("@lune/task")

local function decode(text: string): { [string]: any }
	local first = string.match(text, "^[^\n]+") or ""
	local ok, v = pcall(serde.decode, "json" :: "json", first)
	return if ok and type(v) == "table" then v else {}
end

local function ok(r: live.Result, what: string): { [string]: any }
	if r.code ~= 0 then
		error(`{what}: exit {r.code}: {r.stdout}{r.stderr}`, 2)
	end
	return decode(r.stdout)
end

-- A long-lived process of its own (the fixture's "worker"): returns its pid. It is killed with `kill`, and reparented to
-- init, so it never lingers as a zombie that signal 0 still finds.
local function sleeper(): number
	local r = process.exec("sh", { "-c", "sleep 60 </dev/null >/dev/null 2>&1 & echo $!" })
	return tonumber((string.gsub(r.stdout, "%s+", ""))) :: number
end

local function register(l: live.Live, worker: string, pid: number, can: string?)
	local args = { "register", "--worker", worker, "--cli", "fake", "--pid", tostring(pid) }
	if can then
		table.insert(args, "--can")
		table.insert(args, can)
	end
	ok(l:zn(args), `register {worker}`)
end

return t.spec("f0424 ./zn live: the contract by argv", function(it)
	it(
		"AC14: two claims of one unit started together, 20 times, give one exit 0 and one exit 1 naming the winner",
		function()
			live.with("f0424-cli-race", nil, function(l)
				local pid = sleeper()
				register(l, "A", pid)
				register(l, "B", pid)
				for round = 1, 20 do
					local unit = `c{round}`
					local rs = l:together({
						{ "claim", "--worker", "A", "--unit", unit, "--activity", "design" },
						{ "claim", "--worker", "B", "--unit", unit, "--activity", "design" },
					})
					local won, lost = rs[1], rs[2]
					local winner = "A"
					if rs[1].code ~= 0 then
						won, lost, winner = rs[2], rs[1], "B"
					end
					t.expect(won.code).toBe(0)
					t.expect(lost.code).toBe(1)
					local reply = decode(lost.stdout)
					t.expect(reply.refused).toBe("held")
					t.expect(string.find(lost.stdout, winner, 1, true) ~= nil).toBe(true)
					ok(l:zn({ "release", "--worker", winner }), "release")
				end
				process.exec("kill", { tostring(pid) })
			end)
		end
	)

	it(
		"AC15: a wait started before another worker's release exits 0 printing that release's seq; with nothing it exits 75",
		function()
			live.with("f0424-cli-wait", nil, function(l)
				local pid = sleeper()
				register(l, "A", pid)
				register(l, "B", pid)
				ok(l:zn({ "claim", "--worker", "B", "--unit", "u1", "--activity", "design" }), "claim")
				ok(l:zn({ "claims", "--worker", "A" }), "claims") -- sets A's `seen`: the wait starts after it
				local waited: live.Result? = nil
				task.spawn(function()
					waited = l:zn({ "wait", "--worker", "A", "--timeout", "10" })
				end)
				task.wait(0.4)
				t.expect(waited == nil).toBe(true) -- still blocked
				local released = ok(l:zn({ "release", "--worker", "B" }), "release")
				for _ = 1, 100 do
					if waited then
						break
					end
					task.wait(0.05)
				end
				t.expect(waited ~= nil).toBe(true)
				local w = waited :: live.Result
				t.expect(w.code).toBe(0)
				t.expect(decode(w.stdout).seq).toBe((released.event :: any).seq)
				local t0 = os.clock()
				local idle = l:zn({ "wait", "--worker", "A", "--timeout", "1" })
				t.expect(idle.code).toBe(75)
				t.expect(os.clock() - t0 >= 0.9).toBe(true)
				process.exec("kill", { tostring(pid) })
			end)
		end
	)

	it(
		"AC16: a killed worker's claim is released (lost) and removed, and another worker takes the unit",
		function()
			live.with("f0424-cli-lost", nil, function(l)
				local pid = sleeper()
				register(l, "A", pid, "design/draft")
				register(l, "B", sleeper(), "design/draft")
				ok(l:zn({ "claim", "--worker", "A", "--unit", "u1", "--activity", "design" }), "claim")
				t.expect(#(ok(l:zn({ "claims" }), "claims").claims :: any)).toBe(1)
				process.exec("kill", { "-9", tostring(pid) })
				local gone = false
				for _ = 1, 60 do
					if #(ok(l:zn({ "claims" }), "claims").claims :: any) == 0 then
						gone = true
						break
					end
					task.wait(0.1)
				end
				t.expect(gone).toBe(true)
				local events = l:zn({ "events", "--since", "0" }).stdout
				t.expect(string.find(events, '"kind":"released"[^\n]*"outcome":"lost"') ~= nil).toBe(true)
				t.expect(string.find(events, '"kind":"gone"', 1, true) ~= nil).toBe(true)
				t.expect(l:zn({ "claim", "--worker", "B", "--unit", "u1", "--activity", "design" }).code)
					.toBe(0)
				local workers = ok(l:zn({ "workers" }), "workers").workers :: { any }
				t.expect(#workers).toBe(1)
				t.expect(workers[1].id).toBe("B")
				local bpid = workers[1].pid
				process.exec("kill", { tostring(bpid) })
			end)
		end
	)

	it(
		"AC17: the first write op starts a daemon, a read op with none exits 3 and starts none, status names the daemon",
		function()
			live.with("f0424-cli-start", nil, function(l)
				for _, op in { "status", "workers", "claims", "events", "poke" } do
					local r = l:zn({ op })
					t.expect(r.code).toBe(3)
					t.expect(r.stderr ~= "").toBe(true)
				end
				t.expect(l:zn({ "wait", "--worker", "A", "--timeout", "1" }).code).toBe(3)
				t.expect(#l:pids()).toBe(0)
				local pid = sleeper()
				register(l, "A", pid)
				t.expect(#l:pids()).toBe(1)
				local status = ok(l:zn({ "status" }), "status")
				t.expect(status.pid).toBe(l:pids()[1])
				t.expect(type(status.build)).toBe("string")
				t.expect(status.proto).toBe(1)
				t.expect(string.find(status.dir :: string, ".cache/live", 1, true) ~= nil).toBe(true)
				t.expect(status.workers).toBe(1)
				process.exec("kill", { tostring(pid) })
			end)
		end
	)

	it("AC18: an op from a second worktree of the fixture repository answers from the same daemon", function()
		live.with("f0424-cli-worktree", { noDirEnv = true }, function(l)
			local fixture = require("@tests/lib/fixture")
			fixture.git(l.repo, { "commit", "-q", "--allow-empty", "-m", "seed" })
			local tree = `{l.repo}/.worktree/second`
			fixture.git(l.repo, { "worktree", "add", "-q", tree, "-b", "second" })
			local pid = sleeper()
			register(l, "A", pid) -- from the main checkout: starts the daemon
			local fromMain = ok(l:zn({ "status" }), "status main")
			local fromTree = ok(l:zn({ "status" }, tree), "status worktree")
			t.expect(fromTree.pid).toBe(fromMain.pid)
			t.expect(fromTree.dir).toBe(fromMain.dir)
			local workers = ok(l:zn({ "workers" }, tree), "workers worktree").workers :: { any }
			t.expect(#workers).toBe(1)
			t.expect(#l:pids()).toBe(1)
			process.exec("kill", { tostring(pid) })
		end)
	end)

	it("F8: ./zn live run from a folder outside every repository serves the main checkout's state", function()
		live.with("f0424-cli-outside", nil, function(l)
			-- ZN_LIVE_ROOT names the fixture repository as the main checkout; ZN_LIVE_DIR is unset, so `zn` derives it
			local env = table.clone(l.env)
			env.ZN_LIVE_DIR = ""
			env.ZN_LIVE_ROOT = l.repo
			env.ZN_LIVE_SOCKDIR = process.env.TMPDIR or "/tmp" -- the default directory's socket would be in the closed user temp
			local function fromOutside(args: { string }): process.ExecResult
				local argv = { `{l.root}/zn`, "live" }
				for _, a in args do
					table.insert(argv, a)
				end
				return process.exec("bash", argv, { cwd = "/", env = env })
			end
			local pid = sleeper()
			local started =
				fromOutside({ "register", "--worker", "A", "--cli", "fake", "--pid", tostring(pid) })
			if started.code ~= 0 then
				error(`register from outside: {started.code} {started.stdout}{started.stderr}`, 0)
			end
			local status = decode(fromOutside({ "status" }).stdout)
			t.expect(status.dir).toBe(`{l.repo}/.cache/live`)
			process.exec("kill", { tostring(pid) })
		end)
	end)

	it(
		"F5: a worktree whose .git file holds a relative gitdir leads to its main checkout, from / and from inside",
		function()
			live.with("f0424-cli-relative", nil, function(l)
				local main = `{l.base}/main`
				local wt = `{l.base}/wt`
				fs.writeDir(`{main}/.git/worktrees/x`)
				fs.writeFile(`{main}/.git/worktrees/x/commondir`, "../..\n")
				fs.writeDir(wt)
				fs.writeFile(`{wt}/.git`, "gitdir: ../main/.git/worktrees/x\n")
				process.exec("cp", { `{l.root}/zn`, `{wt}/zn` })
				local env = table.clone(l.env)
				env.ZN_LIVE_DIR = ""
				env.ZN_LIVE_ROOT = ""
				for _, cwd in { "/", wt } do
					local r = process.exec("bash", { `{wt}/zn`, "live", "status" }, { cwd = cwd, env = env })
					t.expect(r.code).toBe(3) -- no daemon: a read op
					t.expect(string.find(r.stderr, `{main}/.cache/live`, 1, true) ~= nil).toBe(true)
				end
			end)
		end
	)
end)
