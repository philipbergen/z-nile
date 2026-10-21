--!strict
-- c0119 AC4: `scripts/tracker.sh capture <id>` prints an item's document as captured, read from origin/main, in a
-- tracker fixture under .cache/capture-cli (tests/lib/trackerfix). Another terminal (the fixture's `other` clone)
-- pushes every commit; the command only reads.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local f: trackerfix.Fixture
-- a legacy document name, built so the c0044 guard (no literal <ID>-<slug>.md in a spec) does not see it
local SLUG = "old-slug"
local LEGACY = `tracker/issues/c0020/c0020-{SLUG}.md`
local SHA: { [string]: string } = {}

local function doc(id: string, line: string): string
	return trackerfix.stub(id, id, "new-a-b-c") .. `\n## Problem\n{line}\n`
end

-- `other` commits `files` (nil text removes a path) with `message`, pushes, and remembers the sha under `key`
local function push(key: string, files: { [string]: string | false }, message: string)
	fixture.git(f.other, { "pull", "-q", "origin", "main" })
	for path, text in files do
		if text == false then
			fixture.git(f.other, { "rm", "-q", "-r", path })
		else
			local parent = string.match(path, "^(.*)/[^/]+$")
			if parent then
				fs.writeDir(`{f.other}/{parent}`)
			end
			fs.writeFile(`{f.other}/{path}`, text :: string)
		end
	end
	fixture.git(f.other, { "add", "-A" })
	fixture.git(f.other, { "commit", "-q", "-m", message })
	fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
	SHA[key] = fixture.git(f.other, { "rev-parse", "HEAD" })
end

local function capture(id: string): (number, string, string)
	fixture.git(f.main, { "fetch", "-q", "origin" })
	local r = trackerfix.tr(f, f.main, { "capture", id })
	return r.code, r.stdout, r.stderr
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0119 tracker.sh capture", function(it)
	it("sets up a fixture whose items were captured, prepped, migrated, compacted and moved", function()
		f = trackerfix.new("capture-cli", {})
		push(
			"stub",
			{ ["tracker/issues/c0010/c0010.md"] = doc("c0010", "stub line") },
			"tracker: new c0010 one"
		)
		push(
			"landed",
			{ ["tracker/issues/c0010/c0010.md"] = doc("c0010", "the user's words") },
			"tracker: new c0010 One"
		)
		push(
			"raft",
			{ ["tracker/rafts/R0010/R0010.md"] = trackerfix.stub("R0010", "r", "new-d-e-f") },
			"tracker: new raft R0010 r"
		)
		push(
			"prep",
			{ ["tracker/issues/c0010/c0010.md"] = doc("c0010", "a narrower rewrite") },
			"tracker: prep R0010 r"
		)
		push("done", {
			["tracker/issues/c0010"] = false,
			["tracker/issues/done/c0010/c0010.md"] = doc("c0010", "a narrower rewrite"),
		}, "R0010: done")
		-- a look-alike: the same text as c0010's capture, never captured itself
		push(
			"lookalike",
			{ ["tracker/issues/c0040/c0040.md"] = doc("c0010", "the user's words") },
			"R0040: prep"
		)
		-- a legacy document named by its slug, renamed by the layout migration
		push("legacy", { [LEGACY] = doc("c0020", "legacy words") }, "backlog")
		push("migrate", {
			[LEGACY] = false,
			["tracker/issues/c0020/c0020.md"] = doc("c0020", "legacy words"),
		}, "tracker: migrate")
		-- compaction renames c0300 to c0030, and a new item later takes the number c0300
		push(
			"old",
			{ ["tracker/issues/c0300/c0300.md"] = doc("c0300", "before compaction") },
			"tracker: new c0300 Old"
		)
		push("compact", {
			["tracker/issues/c0300"] = false,
			["tracker/issues/c0030/c0030.md"] = doc("c0030", "before compaction"),
			["tracker/compaction.txt"] = "# tracker.sh compact, test\nc0300 c0030\n",
		}, "tracker: compact ids")
		push(
			"reused",
			{ ["tracker/issues/c0300/c0300.md"] = doc("c0300", "a new item") },
			"tracker: new c0300 Reused"
		)
	end)

	it(
		"prints the newest `tracker: new <id>` version, not a later prep's rewrite, after a move to done/",
		function()
			local code, out = capture("c0010")
			t.expect(code).toBe(0)
			local first = string.match(out, "^[^\n]+") :: string
			t.expect(first).toBe(`capture {SHA.landed} tracker/issues/c0010/c0010.md tracker: new c0010 One`)
			t.expect(has(out, "the user's words")).toBe(true)
			t.expect(has(out, "a narrower rewrite")).toBe(false)
		end
	)

	it("falls back to the first add of a legacy slug-named document", function()
		local code, out = capture("c0020")
		t.expect(code).toBe(0)
		t.expect(has(out, `capture {SHA.legacy} {LEGACY} backlog`)).toBe(true)
	end)

	it("follows a compaction to the old id, and keeps a reused number to its own item", function()
		local _, renamed = capture("c0030")
		t.expect(has(renamed, `capture {SHA.old} tracker/issues/c0300/c0300.md tracker: new c0300 Old`))
			.toBe(true)
		t.expect(has(renamed, "before compaction")).toBe(true)
		local _, reused = capture("c0300")
		t.expect(has(reused, `capture {SHA.reused} tracker/issues/c0300/c0300.md`)).toBe(true)
		t.expect(has(reused, "a new item")).toBe(true)
	end)

	it("never takes a look-alike document for another item's", function()
		local _, out = capture("c0040")
		t.expect(has(out, `capture {SHA.lookalike} tracker/issues/c0040/c0040.md R0040: prep`)).toBe(true)
	end)

	it("refuses an unknown id and a malformed one, and changes nothing", function()
		local before = fixture.git(f.main, { "status", "--porcelain" })
		local code, _, err = capture("c0999")
		t.expect(code).toBe(1)
		t.expect(has(err, "no history for c0999")).toBe(true)
		local bad, _, berr = capture("nope")
		t.expect(bad).toBe(1)
		t.expect(has(berr, "usage: capture <id>")).toBe(true)
		t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe(before)
	end)
end)
