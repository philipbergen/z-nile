--!strict
-- c0114 AC13: the counter across the landing. The branch that lands c0114 never touches tracker/next. While origin/main
-- has no registry (c0114's own execution), the branch's engine reserves on origin's tracker/next, and a merge of
-- origin/main is a plain merge. Once origin has the registry but no z-nile/next (c0114 has landed), the first publish
-- moves the counter in its own commit and lease push: z-nile/next with tracker/next's counters at the leased base
-- (raised, if it reserves) and the tombstone at tracker/next. Every later publish counts on z-nile/next, and
-- tracker/next is never written again. Fixture under .cache/c0114-window (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ids = require("@znile/engine/ids")
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local f: trackerfix.Fixture
local wt = ""

local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function originHas(path: string): boolean
	return fixture.exec(f.origin, "git", { "cat-file", "-e", `main:{path}` }).ok
end
local function originText(path: string): string
	return fixture.git(f.origin, { "show", `main:{path}` })
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- the counter lines without their phrases
local function counter(text: string): string
	return (string.gsub(string.gsub(text, " [%a%-]+\n", "\n"), " [%a%-]+$", ""))
end
-- the paths the tip commit changed, sorted
local function changed(): { string }
	local out = string.split(fixture.git(f.origin, { "diff", "--name-only", "main~1", "main" }), "\n")
	table.sort(out)
	return out
end

return t.spec("c0114 the counter across the landing", function(it)
	it("sets up a pre-c0114 origin and a branch with the registry", function()
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
		fs.writeFile(`{wt}/z-nile/projects.toml`, fs.readFile("z-nile/projects.toml"))
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", "c0114: the registry" })
	end)

	it("in the window the branch reserves on tracker/next, and merges are plain", function()
		local r = trackerfix.tr(f, wt, { "new", "issue", "c", "in-window" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(r.stdout, "tracker/issues/c0051/c0051.md")).toBe(true)
		t.expect(counter(originText("tracker/next"))).toBe("issue 52\nraft 11")
		t.expect(originHas("z-nile/next")).toBe(false)
		local n = trackerfix.tr(f, wt, { "renumber", "c0051" })
		if not n.ok then
			error(n.stderr .. n.stdout)
		end
		t.expect(counter(originText("tracker/next"))).toBe("issue 53\nraft 11")
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", "renumber" })
		-- main keeps raising the counter; the branch never changed it, so a merge never conflicts on it
		trackerfix.elsewhere(
			f,
			{ ["tracker/next"] = "issue 64 g-h-i\nraft 12 g-h-i\n" },
			"main raises the counter"
		)
		trackerfix.trOk(f, wt, { "sync" })
		t.expect(fs.readFile(`{wt}/tracker/next`)).toBe("issue 64 g-h-i\nraft 12 g-h-i\n")
		t.expect(fs.isFile(`{wt}/z-nile/next`)).toBe(false)
		-- offline, the local copy of the live counter numbers (not the old rule's next multiple of 10, c0060)
		local off = trackerfix.tr(f, wt, { "new", "issue", "c", "offline" }, { PICKMAN_PUBLISH = "0" })
		if not off.ok then
			error(off.stderr .. off.stdout)
		end
		t.expect(has(off.stdout, "tracker/issues/c0064/c0064.md")).toBe(true)
		fs.removeDir(`{wt}/tracker/issues/c0064`)
		-- an unmoved counter is a warning, not an error
		local a = trackerfix.tr(f, wt, { "audit" })
		t.expect(has(a.stdout, "warning counter-unmigrated tracker/next")).toBe(true)
		t.expect(has(a.stdout, " 0 errors")).toBe(true)
	end)

	it("the first publish after landing moves the counter in its lease push", function()
		-- the landing: origin gains the registry, and tracker/next is still the counter
		trackerfix.elsewhere(
			f,
			{ ["z-nile/projects.toml"] = fs.readFile("z-nile/projects.toml") },
			"c0114 lands"
		)
		fixture.git(wt, { "fetch", "-q", "origin" })
		fixture.git(wt, { "merge", "-q", "--no-edit", "origin/main" })
		-- an old engine raises tracker/next while this publish builds: the lease refuses the push, and the retry
		-- moves the raised counters, not the ones it first read
		local raced = false
		local doc = originText("tracker/issues/c0050/c0050.md") .. "\n"
		local edited = (string.gsub(doc, "status: [^\n]+", "status: preparing"))
		local r = publish.commit(wt, function()
			if not raced then
				raced = true
				trackerfix.elsewhere(
					f,
					{ ["tracker/next"] = "issue 70 j-k-l\nraft 14 j-k-l\n" },
					"an old engine"
				)
			end
			return { { path = "tracker/issues/c0050/c0050.md", content = edited } }
		end, "tracker: c0050 preparing")
		if not r.ok then
			error(r.reason)
		end
		t.expect(raced).toBe(true)
		-- one commit on the raced tip: the status change, z-nile/next with the raised counters, the tombstone
		t.expect(fixture.git(f.origin, { "log", "-1", "--format=%s", "main~1" })).toBe("an old engine")
		t.expect(changed()).toEqual({ "tracker/issues/c0050/c0050.md", "tracker/next", "z-nile/next" })
		t.expect(originText("z-nile/next")).toBe("issue 70 j-k-l\nraft 14 j-k-l")
		t.expect(originText("tracker/next") .. "\n").toBe(ids.TOMBSTONE)
	end)

	it("later publishes count on z-nile/next, and tracker/next is never written again", function()
		local r = trackerfix.tr(f, wt, { "new", "issue", "c", "after" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(r.stdout, "tracker/issues/c0070/c0070.md")).toBe(true)
		t.expect(counter(originText("z-nile/next"))).toBe("issue 71\nraft 14")
		t.expect(originText("tracker/next") .. "\n").toBe(ids.TOMBSTONE)
		t.expect(table.find(changed(), "tracker/next")).toBe(nil)
		local before = tip()
		local overTomb = publish.commit(f.main, function()
			return { { path = "tracker/next", content = "issue 90 m-n-o\nraft 30 m-n-o\n" } }
		end, "tracker: probe")
		t.expect(overTomb.ok).toBe(false)
		local tomb = publish.commit(f.main, function()
			return { { path = "tracker/next", content = ids.TOMBSTONE } }
		end, "tracker: probe")
		t.expect(tomb.ok).toBe(false)
		t.expect(tip()).toBe(before)
		-- nor created afresh where c0120 has removed the tombstone: an old engine would number from it
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "rm", "-q", "tracker/next" })
		fixture.git(f.other, { "commit", "-q", "-m", "no tombstone" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		before = tip()
		local fresh = publish.commit(f.main, function()
			return { { path = "tracker/next", content = "issue 90 m-n-o\nraft 30 m-n-o\n" } }
		end, "tracker: probe")
		t.expect(fresh.ok).toBe(false)
		t.expect(tip()).toBe(before)
		-- the choice, from the base alone: (has a registry, has z-nile/next, tracker/next's text) -> counter, migrate
		local function choice(reg: boolean, new: boolean, old: string?): string
			local file, migrate = publish.counterOf(reg, new, old)
			return `{file} {migrate}`
		end
		local live = "issue 1 a\nraft 1 a\n"
		t.expect(choice(true, true, nil)).toBe("z-nile/next false")
		t.expect(choice(true, true, live)).toBe("z-nile/next false")
		t.expect(choice(false, false, live)).toBe("tracker/next false")
		t.expect(choice(true, false, live)).toBe("z-nile/next true")
		t.expect(choice(true, false, ids.TOMBSTONE)).toBe("z-nile/next false")
	end)
end)
