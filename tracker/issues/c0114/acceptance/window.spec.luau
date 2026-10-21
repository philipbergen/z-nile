--!strict
-- c0114 AC13: the execution window. While c0114's own branch runs, origin/main has no registry and still counts in
-- tracker/next, and the branch has moved the counter to z-nile/next with a tombstone at tracker/next. The branch's
-- engine then reserves on origin's tracker/next (never pushing z-nile/next), a merge of origin/main keeps the tombstone
-- and raises z-nile/next to the higher counter, and audit reports a z-nile/next left below origin's tracker/next. Once
-- origin has a registry, tracker/next is never written again. Fixture under .cache/c0114-window (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOMB =
	"moved to z-nile/next (c0114): this file never parses, so a tracker engine from before the move refuses to number\n"
local f: trackerfix.Fixture
local wt = ""

local function originHas(path: string): boolean
	return fixture.exec(f.origin, "git", { "cat-file", "-e", `main:{path}` }).ok
end
local function originCounter(): string
	return fixture.git(f.origin, { "show", "main:tracker/next" })
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function counter(text: string): string
	return (string.gsub(string.gsub(text, " [%a%-]+\n", "\n"), " [%a%-]+$", ""))
end

return t.spec("c0114 the execution window", function(it)
	it("sets up an origin from before c0114 and a branch that has moved the counter", function()
		f = trackerfix.new("c0114-window", {
			["tracker/next"] = "issue 51 a-b-c\nraft 11 a-b-c\n",
			["tracker/issues/c0050/c0050.md"] = trackerfix.stub("c0050", "c0050", "new-a-b-c"),
		})
		-- origin as main is before c0114 lands: no registry
		fixture.git(f.other, { "rm", "-q", "z-nile/projects.toml" })
		fixture.git(f.other, { "commit", "-q", "-m", "main before c0114" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		wt = trackerfix.trOk(f, f.main, { "worktree", "work" })
		fixture.git(wt, { "config", "user.name", "c0114-window" })
		fixture.git(wt, { "config", "user.email", "c0114-window@example.invalid" })
		-- the branch after c0114's step 2 and 3: the counter moved, the tombstone written, the registry added
		fs.writeFile(`{wt}/z-nile/projects.toml`, fs.readFile("z-nile/projects.toml"))
		fixture.git(wt, { "mv", "tracker/next", "z-nile/next" })
		fs.writeFile(`{wt}/tracker/next`, TOMB)
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", "c0114: move the counter" })
	end)

	it("a new issue reserves on origin's tracker/next, and the merge after it raises z-nile/next", function()
		local r = trackerfix.tr(f, wt, { "new", "issue", "c", "in-window" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(r.stdout, "tracker/issues/c0051/c0051.md")).toBe(true)
		t.expect(counter(originCounter())).toBe("issue 52\nraft 11")
		t.expect(originHas("z-nile/next")).toBe(false)
		-- the publish merged origin/main back: the conflict on tracker/next was resolved, not left
		t.expect(fs.readFile(`{wt}/tracker/next`)).toBe(TOMB)
		t.expect(counter(fs.readFile(`{wt}/z-nile/next`))).toBe("issue 52\nraft 11\n")
		t.expect(fixture.git(wt, { "status", "--porcelain" })).toBe("")
	end)

	it(
		"a counter-only reservation raises origin's tracker/next too, and sync brings it into z-nile/next",
		function()
			local r = trackerfix.tr(f, wt, { "renumber", "c0051" })
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			t.expect(has(r.stdout, "c0051 -> c0052")).toBe(true)
			t.expect(counter(originCounter())).toBe("issue 53\nraft 11")
			t.expect(originHas("z-nile/next")).toBe(false)
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "renumber" })
			-- before the merge the branch's counter is behind origin's: audit says so
			local behind = trackerfix.tr(f, wt, { "audit" })
			t.expect(behind.ok).toBe(false)
			t.expect(has(behind.stdout, "error counter-behind z-nile/next")).toBe(true)
			trackerfix.trOk(f, wt, { "sync" })
			t.expect(counter(fs.readFile(`{wt}/z-nile/next`))).toBe("issue 53\nraft 11\n")
			t.expect(fs.readFile(`{wt}/tracker/next`)).toBe(TOMB)
			t.expect(has(trackerfix.tr(f, wt, { "audit" }).stdout, "counter-behind")).toBe(false)
		end
	)

	it("a merge that keeps the branch's side is caught by audit", function()
		trackerfix.elsewhere(
			f,
			{ ["tracker/next"] = "issue 70 g-h-i\nraft 12 g-h-i\n" },
			"main raises the counter"
		)
		fixture.git(wt, { "fetch", "-q", "origin" })
		fixture.git(wt, { "merge", "-q", "-X", "ours", "--no-edit", "origin/main" })
		t.expect(fs.readFile(`{wt}/tracker/next`)).toBe(TOMB)
		local r = trackerfix.tr(f, wt, { "audit" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "error counter-behind z-nile/next")).toBe(true)
		t.expect(has(r.stdout, "issue 70, raft 12")).toBe(true)
	end)

	it("once origin has a registry, tracker/next is never written and z-nile/next is the counter", function()
		trackerfix.elsewhere(f, {
			["z-nile/projects.toml"] = fs.readFile("z-nile/projects.toml"),
			["z-nile/next"] = "issue 80 j-k-l\nraft 20 j-k-l\n",
			["tracker/next"] = TOMB,
		}, "c0114 lands")
		local before = fixture.git(f.origin, { "rev-parse", "main" })
		local old = publish.commit(f.main, function()
			return { { path = "tracker/next", content = "issue 90 m-n-o\nraft 30 m-n-o\n" } }
		end, "tracker: probe")
		t.expect(old.ok).toBe(false)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
		-- nor created afresh where c0120 has removed the tombstone: an old engine would number from it
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "rm", "-q", "tracker/next" })
		fixture.git(f.other, { "commit", "-q", "-m", "no tombstone" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		local gone = fixture.git(f.origin, { "rev-parse", "main" })
		local fresh = publish.commit(f.main, function()
			return { { path = "tracker/next", content = "issue 90 m-n-o\nraft 30 m-n-o\n" } }
		end, "tracker: probe")
		t.expect(fresh.ok).toBe(false)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(gone)
		local new = publish.commit(f.main, function(_paths, _read, _roots, live)
			return { { path = live, content = "issue 81 m-n-o\nraft 20 m-n-o\n" } }
		end, "tracker: probe")
		t.expect(new.ok).toBe(true)
		t.expect(counter(fixture.git(f.origin, { "show", "main:z-nile/next" }))).toBe("issue 81\nraft 20")
		t.expect(publish.counterFor(true)).toBe("z-nile/next")
		t.expect(publish.counterFor(false)).toBe("tracker/next")
	end)
end)
