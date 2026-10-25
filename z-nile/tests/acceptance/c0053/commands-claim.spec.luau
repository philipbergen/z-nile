--!strict
-- c0062: one part of c0510's commands spec, split so that `tests/run` runs the parts concurrently.
-- This part: claiming members with `new raft`, `status`, and the carried move to prepared. Its seed holds issues up to c0230.
-- Driven through `scripts/tracker.sh` in a worktree, exactly as a terminal would. Cases share this part's fixture
-- and run in order.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local git = fixture.git
local f: trackerfix.Fixture = { base = "", origin = "", main = "", other = "" }
local origin, main = "", ""

local function tr(cwd: string, args: { string }, env: { [string]: string }?): fixture.Result
	return trackerfix.tr(f, cwd, args, env)
end
local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function onOrigin(path: string): string? -- the file's text on origin's main, or nil
	local r = fixture.exec(origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
-- another terminal pushes a commit straight to origin's main
local function elsewhere(files: { [string]: string }, message: string)
	trackerfix.elsewhere(f, files, message)
end
local stub = trackerfix.stub

local cap = "" -- the capture worktree

return t.spec("tracker commands publish state to origin/main (claim)", function(it)
	it("sets up the claim fixture", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		-- issues up to c0230 exist, so `new issue` returns c0240 and c0250
		local seed = { ["pickman/.tracker/issues/c0230/c0230.md"] = stub("c0230", "seed", "new") }
		f = trackerfix.new("c0053-commands-claim", seed)
		origin, main = f.origin, f.main
		cap = trOk(main, { "worktree", "cap-a" })
		t.expect(git(cap, { "branch", "--show-current" })).toBe("cap-a")
	end)

	it("new raft claims its members in one commit, or none of them", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		trOk(cap, { "new", "issue", "c", "delta", "--project", "pickman" }) -- c0240
		trOk(cap, { "new", "issue", "c", "epsilon", "--project", "pickman" }) -- c0250
		-- another terminal claims c0250 first
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		elsewhere({
			["pickman/.tracker/issues/c0250/c0250.md"] = (
				onOrigin("pickman/.tracker/issues/c0250/c0250.md") :: string
			):gsub("status: new", "status: preparing"),
		}, "other claims c0250")
		local before = git(origin, { "rev-parse", "main" })
		local r = tr(cap, { "new", "raft", "chore", "demo", "c0240", "c0250", "--project", "pickman" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "c0250")).toBe(true)
		t.expect(has(r.stderr, "preparing")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(onOrigin("pickman/.tracker/issues/c0240/c0240.md"), "status: new")).toBe(true)
		t.expect(onOrigin("pickman/.tracker/rafts/R0010/R0010.md")).toBe(nil)
		trOk(cap, { "new", "raft", "chore", "demo", "c0240", "--single", "--project", "pickman" })
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local raft = onOrigin("pickman/.tracker/rafts/R0010/R0010.md")
		t.expect(has(raft, "status: preparing")).toBe(true)
		t.expect(has(raft, "issues: [c0240]")).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local member = onOrigin("pickman/.tracker/issues/c0240/c0240.md")
		t.expect(has(member, "status: preparing")).toBe(true)
		t.expect(has(member, "raft: R0010")).toBe(false) -- origin never carries `raft:`: it sits beside depends_on
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(fs.readFile(`{cap}/pickman/.tracker/issues/c0240/c0240.md`), "raft: R0010")).toBe(true)
		t.expect(git(cap, { "log", "-1", "--format=%s" })).toBe("tracker: R0010 members")
		t.expect(git(cap, { "status", "--porcelain" })).toBe("")
	end)

	it("status lists what origin says, even when this checkout is stale", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		elsewhere(
			{ ["pickman/.tracker/issues/f0300/f0300.md"] = stub("f0300", "remote-only", "new") },
			"other f0300"
		)
		t.expect(fs.isFile(`{cap}/pickman/.tracker/issues/f0300/f0300.md`)).toBe(false)
		local list = trOk(cap, { "status" })
		t.expect(has(list, "f0300 new remote-only")).toBe(true)
		t.expect(has(list, "c0240 preparing")).toBe(true)
		t.expect(has(list, "R0010 preparing")).toBe(true)
		t.expect(trOk(cap, { "status", "c0240" })).toBe("preparing")
	end)

	it("a status move refuses to run in the main checkout, which is never edited", function()
		local r = tr(main, { "status", "c0240", "prepared" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "worktree")).toBe(true)
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("a move to prepared is carried by the PR: local edit only, nothing published", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local before = git(origin, { "rev-parse", "main" })
		-- it refuses while the design is not ready: the two fields move together
		local early = tr(cap, { "status", "c0240", "prepared" })
		t.expect(early.ok).toBe(false)
		t.expect(has(early.stderr, "design: ready")).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(fs.readFile(`{cap}/pickman/.tracker/issues/c0240/c0240.md`), "status: prepared"))
			.toBe(false)
		local c0240 = `{cap}/pickman/.tracker/issues/c0240/c0240.md`
		fs.writeFile(c0240, (string.gsub(fs.readFile(c0240), "design: draft", "design: ready")))
		trOk(cap, { "status", "c0240", "prepared" })
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(fs.readFile(`{cap}/pickman/.tracker/issues/c0240/c0240.md`), "status: prepared"))
			.toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(onOrigin("pickman/.tracker/issues/c0240/c0240.md"), "status: preparing")).toBe(true)
	end)

	it("a move is checked against origin, not the local file; invalid moves change nothing", function()
		-- locally c0240 says prepared (prepared>preparing would be legal), origin says preparing (it would not)
		local before = git(origin, { "rev-parse", "main" })
		local r = tr(cap, { "status", "c0240", "preparing" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "is preparing on origin/main")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		local bad = tr(cap, { "status", "c0240", "done" })
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stderr, "prepared")).toBe(false) -- names the origin status, not the local one
		local unknown = tr(cap, { "status", "c0240", "ready" })
		t.expect(unknown.ok).toBe(false)
	end)
end)
