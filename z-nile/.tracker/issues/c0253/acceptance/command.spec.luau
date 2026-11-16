--!strict
-- c0253 AC3, AC9, AC10: the command line of `./zn work`, on a fixture under .cache/c0253-command whose origin/main holds a
-- `.models.toml` that names only claude. A supervisor flag or `run` is the supervisor; a bare `./zn work` and
-- `./zn work <R-id>` still print the z-work skill (#318); a boolean flag before a positional leaves the positional in place;
-- the supervisor refuses to start outside the main checkout, inside a headless session, detached inside a check, and with a
-- CLI the roles do not name; `stop` and `status` speak for the main checkout's supervisor. No CLI is started: nothing is
-- claimable.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local runner = require("@znile/engine/runner")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[roles.implementation]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "high"
fallbacks = []

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "high"
fallbacks = []

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = []
]]

local f: trackerfix.Fixture

local function said(r: { ok: boolean, stdout: string, stderr: string }): string
	return r.stdout .. r.stderr
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0253 ./zn work's command line", function(it)
	it("sets up a tracker fixture whose origin/main names claude only", function()
		f = trackerfix.new("c0253-command", { [".models.toml"] = MODELS })
	end)

	it("AC9: a bare ./zn work and ./zn work <R-id> print the z-work skill, as before", function()
		local bare = trackerfix.tr(f, f.main, { "work" })
		t.expect(bare.ok).toBe(true)
		t.expect(has(bare.stdout, "You are the worker")).toBe(true)
		local named = trackerfix.tr(f, f.main, { "work", "R0010" })
		t.expect(named.ok).toBe(true)
		t.expect(has(named.stdout, "This session's raft is R0010")).toBe(true)
	end)

	it("AC9: a boolean supervisor flag before a positional leaves the positional in place", function()
		-- if --once or --detach took R0010 as its value, nothing would be left to refuse and the supervisor would start
		for _, flag in { "--once", "--detach" } do
			local r = trackerfix.tr(f, f.main, { "work", flag, "R0010" })
			t.expect(r.ok).toBe(false)
			t.expect(has(said(r), "usage: ./zn work run")).toBe(true)
		end
		local stop = trackerfix.tr(f, f.main, { "work", "--once", "stop" })
		t.expect(stop.ok).toBe(false)
		t.expect(has(said(stop), "usage")).toBe(true)
	end)

	it(
		"AC9: refuses a bad --max-items, an unknown option, and a CLI the roles do not name, before any claim",
		function()
			local zero = trackerfix.tr(f, f.main, { "work", "--max-items", "0" })
			t.expect(zero.ok).toBe(false)
			t.expect(has(said(zero), "--max-items")).toBe(true)
			local odd = trackerfix.tr(f, f.main, { "work", "--bogus", "x" })
			t.expect(odd.ok).toBe(false)
			t.expect(has(said(odd), "--bogus")).toBe(true)
			local zed = trackerfix.tr(f, f.main, { "work", "--cli", "zed", "--once" })
			t.expect(zed.ok).toBe(false)
			t.expect(has(said(zed), "zed")).toBe(true)
			-- kimi is a supported CLI, but no role of this .models.toml tries it
			local kimi = trackerfix.tr(f, f.main, { "work", "run", "--cli", "kimi", "--once" })
			t.expect(kimi.ok).toBe(false)
			t.expect(has(said(kimi), "kimi") and has(said(kimi), "design") and has(said(kimi), "claude"))
				.toBe(true)
			t.expect(fs.isFile(`{f.main}/.cache/work/state`)).toBe(false)
		end
	)

	it("AC9: the supervisor runs only in the main checkout", function()
		local wt = `{f.base}/wt`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "wt-branch", wt, "HEAD" })
		local r = trackerfix.tr(f, wt, { "work", "run", "--once" })
		t.expect(r.ok).toBe(false)
		t.expect(has(said(r), "the supervisor runs in the main checkout")).toBe(true)
		t.expect(fs.isFile(`{wt}/.cache/work/state`)).toBe(false)
	end)

	it(
		"AC9: it does not start inside a headless or dispatched session, and never detached inside a check",
		function()
			local headless = trackerfix.tr(f, f.main, { "work", "run", "--once" }, { ZN_HEADLESS = "1" })
			t.expect(headless.ok).toBe(false)
			t.expect(has(said(headless), "headless")).toBe(true)
			local dispatched = trackerfix.tr(f, f.main, { "work", "--detach" }, { ZN_DISPATCH = "1" })
			t.expect(dispatched.ok).toBe(false)
			t.expect(has(said(dispatched), "dispatched")).toBe(true)
			local detach = trackerfix.tr(f, f.main, { "work", "--detach" })
			t.expect(detach.ok).toBe(false)
			t.expect(has(said(detach), "check run")).toBe(true)
			t.expect(fs.isFile(`{f.main}/.cache/work/log`)).toBe(false)
		end
	)

	it("AC3: --once with nothing claimable prints the summary and ends, starting no CLI", function()
		local r = trackerfix.tr(f, f.main, { "work", "--once" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "worker stopped: nothing claimable (--once)")).toBe(true)
		t.expect(has(r.stdout, "moved: nothing")).toBe(true)
		t.expect(has(r.stdout, "blocked: nothing")).toBe(true)
		local state = fs.readFile(`{f.main}/.cache/work/state`)
		t.expect(has(state, "state: stopped")).toBe(true)
		t.expect(fs.isFile(`{f.main}/.cache/work/stop`)).toBe(false)
	end)

	it("AC9: work run is the same supervisor without a flag, and takes the CLI the roles name", function()
		local r = trackerfix.tr(f, f.main, { "work", "run", "--once", "--cli", "claude" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "worker stopped")).toBe(true)
	end)

	it("AC10: a stale stop file does not stop the next supervisor", function()
		fs.writeFile(`{f.main}/.cache/work/stop`, "stop\n")
		local r = trackerfix.tr(f, f.main, { "work", "--once" })
		t.expect(has(r.stdout, "nothing claimable (--once)")).toBe(true)
		t.expect(has(r.stdout, "stop asked")).toBe(false)
	end)

	it("AC10: stop with no supervisor says so and writes nothing; status calls a dead one ended", function()
		fs.writeFile(
			`{f.main}/.cache/work/state`,
			"pid: 99999999\nstate: working\nitem: R0010\ncli: claude\nsince: t\nmoved: 1\nblocked: 0\nheld: R0010\n"
		)
		if fs.isFile(`{f.main}/.cache/work/stop`) then
			fs.removeFile(`{f.main}/.cache/work/stop`)
		end
		local stop = trackerfix.tr(f, f.main, { "work", "stop" })
		t.expect(stop.ok).toBe(true)
		t.expect(has(stop.stdout, "no supervisor runs")).toBe(true)
		t.expect(fs.isFile(`{f.main}/.cache/work/stop`)).toBe(false)
		local status = trackerfix.tr(f, f.main, { "work", "status" })
		t.expect(status.ok).toBe(true)
		t.expect(has(status.stdout, "supervisor pid 99999999: ended without a summary")).toBe(true)
		t.expect(has(status.stdout, "holds R0010: ./zn work run resumes it")).toBe(true)
	end)

	it("AC10: a second supervisor in one clone is refused while the first holds the lock", function()
		-- the lock is an flock a running supervisor holds; the spec holds it the same way, through the bounded perl helper
		local holder = runner.holdLock(`{f.main}/.cache/work/supervisor.lock`)
		t.expect(holder ~= nil).toBe(true)
		local r = trackerfix.tr(f, f.main, { "work", "--once" })
		if holder then
			holder:kill()
		end
		t.expect(r.ok).toBe(false)
		t.expect(has(said(r), "already runs")).toBe(true)
	end)

	it("AC9: .models.toml is read from origin/main, never from the working tree", function()
		-- an edit of the main checkout's file that adds kimi to a role changes nothing the supervisor trusts
		local path = `{f.main}/.models.toml`
		local original = fs.readFile(path)
		fs.writeFile(path, (string.gsub(original, "fallbacks = %[%]", 'fallbacks = ["kimi"]')))
		local r = trackerfix.tr(f, f.main, { "work", "run", "--cli", "kimi", "--once" })
		fs.writeFile(path, original)
		t.expect(r.ok).toBe(false)
		t.expect(has(said(r), "kimi")).toBe(true)
	end)

	it(
		"AC9: the dispatcher's own flags are booleans too: --worker and --no-run before a positional leave it in place",
		function()
			local r = trackerfix.tr(f, f.main, { "dispatch", "--worker", "--no-run", "status", "R0010" })
			t.expect(r.ok).toBe(true)
			t.expect(has(said(r), "usage")).toBe(false)
		end
	)

	it(
		"AC2: a run that finds the previous run's held raft in the state file dispatches it before it asks next",
		function()
			fs.writeFile(
				`{f.main}/.cache/work/state`,
				"pid: 99999999\nstate: working\nitem: R0010\ncli: claude\nsince: t\nmoved: 0\nblocked: 0\nheld: R0010\n"
			)
			local r = trackerfix.tr(f, f.main, { "work", "run", "--once" })
			t.expect(has(said(r), "R0010")).toBe(true)
			t.expect(has(r.stdout, "nothing claimable")).toBe(false)
		end
	)
end)
