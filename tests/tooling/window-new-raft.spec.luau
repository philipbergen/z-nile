--!strict
-- c0114 (R0043 code review 005): in c0114's execution window (origin/main without z-nile/projects.toml, a branch with
-- it) `new raft` makes no raft, offline included: an offline raft would take its number from the local tracker/next,
-- the number main's next `new raft` takes. The window is decided after the fetch, so right after the landing a
-- publishing `new raft` sees the registry and works; offline it says origin/main is as last fetched. At the root
-- without --project, the project refusal comes first. Fixture under .cache/window-new-raft (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local f: trackerfix.Fixture
local wt = ""
local WINDOW = "capture from the main checkout until it does, never offline here"

local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function raft(env: { [string]: string }?): fixture.Result
	return trackerfix.tr(f, wt, { "new", "raft", "chore", "probe", "c0050", "--project", "pickman" }, env)
end
-- refused, naming `needle`, with no raft made and origin untouched
local function refused(r: fixture.Result, needle: string, before: string)
	t.expect(r.ok).toBe(false)
	if not has(r.stderr, needle) then
		error(`stderr lacks "{needle}": {r.stderr}`)
	end
	t.expect(has(r.stderr, "PICKMAN_PUBLISH=0 creates it locally")).toBe(false)
	t.expect(fs.isDir(`{wt}/tracker/rafts/R0011`)).toBe(false)
	t.expect(tip()).toBe(before)
	t.expect(fixture.git(f.origin, { "show", "main:tracker/next" })).toBe("issue 51 a-b-c\nraft 11 a-b-c")
end

return t.spec("new raft in c0114's execution window", function(it)
	it("sets up a pre-c0114 origin and a branch with the registry", function()
		f = trackerfix.new("window-new-raft", {
			["tracker/next"] = "issue 51 a-b-c\nraft 11 a-b-c\n",
			["tracker/issues/c0050/c0050.md"] = trackerfix.stub("c0050", "c0050", "new-a-b-c"),
		})
		fixture.git(f.other, { "rm", "-q", "z-nile/projects.toml" })
		fixture.git(f.other, { "commit", "-q", "-m", "main before c0114" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		wt = trackerfix.trOk(f, f.main, { "worktree", "work" })
		fixture.git(wt, { "config", "user.name", "window-new-raft" })
		fixture.git(wt, { "config", "user.email", "window-new-raft@example.invalid" })
		fs.writeFile(`{wt}/z-nile/projects.toml`, fs.readFile("z-nile/projects.toml"))
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", "c0114: the registry" })
	end)

	it("refuses offline and publishing, and makes no raft", function()
		local before = tip()
		refused(raft({ PICKMAN_PUBLISH = "0" }), WINDOW, before)
		refused(raft(), WINDOW, before)
	end)

	it("at the root without --project, the project refusal comes first", function()
		local before = tip()
		local r = trackerfix.tr(f, wt, { "new", "raft", "chore", "probe", "c0050" })
		refused(r, "no project holds the checkout's root", before)
	end)

	it(
		"right after the landing, offline says origin is as last fetched, and publishing fetches and works",
		function()
			trackerfix.elsewhere(
				f,
				{ ["z-nile/projects.toml"] = fs.readFile("z-nile/projects.toml") },
				"c0114 lands"
			)
			local before = tip()
			local off = raft({ PICKMAN_PUBLISH = "0" })
			t.expect(off.ok).toBe(false)
			t.expect(has(off.stderr, "origin/main as last fetched has no z-nile/projects.toml")).toBe(true)
			t.expect(has(off.stderr, "fetch (./zn sync --fetch) if c0114 has landed")).toBe(true)
			t.expect(tip()).toBe(before)
			local r = raft()
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			t.expect(has(r.stdout, "tracker/rafts/R0011/R0011.md")).toBe(true)
			t.expect(tip() ~= before).toBe(true)
		end
	)
end)
