--!strict
-- c0114 AC6, AC8: what a tracker-only publish may write is decided by origin/main's registry alone (lesson
-- architecture/guards-trust-only-origin): a root only the working tree lists is refused, a registry that does not
-- parse publishes nothing, and an origin/main without one has the legacy root alone. A published move stays in its
-- root. And paths.rewrite takes a root only where it starts a path segment, so `tracker/` inside `z-nile/.tracker/` is
-- never read as the root `tracker`. Fixture under .cache/c0114-publish (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local paths = require("@znile/engine/paths")
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local Z = "z-nile/.tracker"
local f: trackerfix.Fixture

local function stub(id: string): string
	return trackerfix.stub(id, id, "new-a-b-c")
end
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function onOrigin(path: string): boolean
	return fixture.exec(f.origin, "git", { "cat-file", "-e", `main:{path}` }).ok
end
local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end
-- publishes `changes` from the main checkout, as every tracker command does
local function push(changes: { publish.Change }): publish.Result
	return publish.commit(f.main, function()
		return changes
	end, "tracker: c0114 probe")
end
local function refusedPush(changes: { publish.Change }, needle: string)
	local before = tip()
	local r = push(changes)
	t.expect(r.ok).toBe(false)
	if not has(r.reason, needle) then
		error(`reason lacks "{needle}": {r.reason}`)
	end
	t.expect(tip()).toBe(before)
end

return t.spec("c0114 publish roots come from origin/main", function(it)
	it("sets up an origin whose registry lists tracker and z-nile/.tracker", function()
		f = trackerfix.new("c0114-publish", {
			["tracker/issues/c0010/c0010.md"] = stub("c0010"),
			[`{Z}/issues/c0020/c0020.md`] = stub("c0020"),
		})
	end)

	it("an item file under any root of origin/main's registry is published", function()
		local r = push({ { path = `{Z}/issues/c0030/c0030.md`, content = stub("c0030") } })
		t.expect(r.ok).toBe(true)
		t.expect(onOrigin(`{Z}/issues/c0030/c0030.md`)).toBe(true)
		t.expect(push({ { path = "tracker/issues/c0040/c0040.md", content = stub("c0040") } }).ok).toBe(true)
	end)

	it("a root only the working tree's registry lists is refused, whatever that tree says", function()
		local reg = fs.readFile(`{f.main}/z-nile/projects.toml`)
		fs.writeFile(
			`{f.main}/z-nile/projects.toml`,
			reg .. '\n[[project]]\nname = "evil"\nroot = "evil/.tracker"\n'
		)
		refusedPush(
			{ { path = "evil/.tracker/issues/c0050/c0050.md", content = stub("c0050") } },
			"evil/.tracker"
		)
		refusedPush({ { path = "src/c0050/c0050.md", content = stub("c0050") } }, "not a tracker item file")
		fs.writeFile(`{f.main}/z-nile/projects.toml`, reg)
	end)

	it("a published move stays in its root", function()
		refusedPush({
			{
				path = `{Z}/issues/active/c0010/c0010.md`,
				from = "tracker/issues/c0010/c0010.md",
				content = stub("c0010"),
			},
		}, "keeps the id, the root and the relative path")
	end)

	it("a registry on origin/main that does not parse publishes nothing", function()
		trackerfix.elsewhere(f, { ["z-nile/projects.toml"] = "[[project]\n" }, "break the registry")
		refusedPush({ { path = "tracker/issues/c0060/c0060.md", content = stub("c0060") } }, "not valid TOML")
	end)

	it("an origin/main with no registry has the legacy root tracker alone", function()
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "rm", "-q", "z-nile/projects.toml" })
		fixture.git(f.other, { "commit", "-q", "-m", "no registry" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		refusedPush(
			{ { path = `{Z}/issues/c0070/c0070.md`, content = stub("c0070") } },
			"not a tracker item file"
		)
		t.expect(push({ { path = "tracker/issues/c0080/c0080.md", content = stub("c0080") } }).ok).toBe(true)
	end)

	it("allowed takes the counter, and item files only under the roots it is given", function()
		t.expect(publish.allowed("z-nile/next", { "tracker" })).toBe(true)
		t.expect(publish.allowed("tracker/next", { "tracker", Z })).toBe(false) -- the tombstone is never written
		t.expect(publish.allowed(`{Z}/issues/c0001/c0001.md`, { "tracker", Z })).toBe(true)
		t.expect(publish.allowed(`{Z}/issues/c0001/c0001.md`, { "tracker" })).toBe(false)
		t.expect(publish.allowed(`{Z}/rafts/active/R0001/check.sh`, { Z })).toBe(true)
		t.expect(publish.allowed(`{Z}/issues/c0001/acceptance/x.spec.luau`, { Z })).toBe(false)
		t.expect(publish.allowed("x/../tracker/issues/c0001/c0001.md", { "tracker" })).toBe(false)
		t.expect({ publish.itemPath(`{Z}/issues/done/c0001/review-001.md`) })
			.toEqual({ "c0001", "review-001.md", Z })
		t.expect((publish.itemPath("src/issues/c0001/c0001.md"))).toBe(nil)
	end)

	it(
		"paths.rewrite moves an item's own paths within its root, and never inside .tracker for tracker",
		function()
			local active = { c0130 = `{Z}/issues/active/c0130` }
			t.expect(paths.rewrite(`A="{Z}/issues/c0130/acceptance"`, active))
				.toBe(`A="{Z}/issues/active/c0130/acceptance"`)
			t.expect(paths.rewrite(`bash {Z}/issues/c0130/check.sh`, active))
				.toBe(`bash {Z}/issues/active/c0130/check.sh`)
			-- the old matcher found `tracker/issues/` inside this path and wrote z-nile/.z-nile/.tracker/...
			t.expect(paths.rewrite(`{Z}/issues/c0130`, { c0130 = "tracker/issues/active/c0130" }))
				.toBe(`{Z}/issues/c0130`)
			local legacy = { c0001 = "tracker/issues/done/c0001" }
			t.expect(paths.rewrite('test -d "$PWD/tracker/issues/c0001"', legacy))
				.toBe('test -d "$PWD/tracker/issues/done/c0001"')
			t.expect(paths.rewrite("pickman/.tracker/issues/c0001", legacy))
				.toBe("pickman/.tracker/issues/c0001")
			t.expect(paths.rewrite("tracker/issues/c00010 tracker/issues/c0001-x", legacy))
				.toBe("tracker/issues/c00010 tracker/issues/c0001-x")
			t.expect(
				paths.rewrite(`{Z}/rafts/R0010 tracker/rafts/R0010`, { R0010 = `{Z}/rafts/active/R0010` })
			)
				.toBe(`{Z}/rafts/active/R0010 tracker/rafts/R0010`)
			-- two roots among the targets: a path under one root is never moved to the other root\'s folder
			local both = { c0130 = `{Z}/issues/active/c0130`, c0140 = "tracker/issues/active/c0140" }
			t.expect(paths.rewrite("tracker/issues/c0130 tracker/issues/c0140", both))
				.toBe("tracker/issues/c0130 tracker/issues/active/c0140")
			t.expect(paths.rootOf(`{Z}/issues/active/c0130`)).toBe(Z)
			t.expect(paths.rootOf("tracker/rafts/R0001")).toBe("tracker")
		end
	)
end)
