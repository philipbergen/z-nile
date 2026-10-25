--!strict
-- c0114 AC6: compaction renumbers every item of every project root from one counter, rewrites ids in every root's
-- documents, refuses while a branch changes z-nile's root, writes the map to z-nile/compaction.txt and the counter to
-- z-nile/next, and leaves z-nile/templates/ alone. A compaction before origin has moved the counter moves it too: the
-- old counter file becomes the tombstone, so the two never both parse. Fixture under .cache/c0114-compact (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ids = require("@znile/engine/ids")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local Z = "z-nile/.tracker"
local TA = "tests/" .. "acceptance/" -- spelled in two parts, so a real compaction never rewrites this spec
local f: trackerfix.Fixture
local wt = ""

local function doc(id: string, body: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\n{extra or "raft: \n"}depends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-10-20\nstatus: new-a-b-c\n---\n\n# {id}\n\n{body}\n`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function read(path: string): string
	return fs.readFile(`{wt}/{path}`)
end

return t.spec("c0114 compaction spans every project root", function(it)
	it("sets up items in both roots, a promoted spec folder and a template naming an id", function()
		f = trackerfix.new("c0114-compact", {
			["tracker/next"] = "issue 401 a-b-c\nraft 301 a-b-c\n", -- not moved yet
			-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout); tracker/ keeps only the counter
			["pickman/.tracker/issues/c0100/c0100.md"] = doc("c0100", "Blocks c0200."),
			[`{Z}/issues/c0200/c0200.md`] = doc("c0200", "See c0100 and R0300."),
			[`{Z}/issues/c0200/check.sh`] = `A="{Z}/issues/c0200/acceptance"\n`,
			[`{Z}/rafts/R0300/R0300.md`] = doc("R0300", "Holds c0200.", "single: true\nissues: [c0200]\n"),
			-- c0120 override: a z-nile item's promoted specs are in its home's tests/, z-nile/tests/acceptance
			[`z-nile/{TA}c0200/x.spec.luau`] = "return 1\n",
			["z-nile/templates/issue/example.md"] = `For example c0200, R0300 and {TA}c0200/x.spec.luau.\n`,
		})
	end)

	it("refuses while a branch on origin changes z-nile's root, and names it", function()
		fixture.git(f.other, { "switch", "-q", "-c", "prep-busy" })
		fs.writeFile(`{f.other}/{Z}/issues/c0200/notes.md`, "busy\n")
		fixture.git(f.other, { "add", "-A" })
		fixture.git(f.other, { "commit", "-q", "-m", "busy" })
		fixture.git(f.other, { "push", "-q", "origin", "prep-busy" })
		wt = trackerfix.trOk(f, f.main, { "worktree", "compact-a" })
		local r = trackerfix.tr(f, wt, { "compact" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "prep-busy")).toBe(true)
		fixture.git(f.other, { "push", "-q", "origin", "--delete", "prep-busy" })
		fixture.git(f.other, { "switch", "-q", "main" })
	end)

	it("renumbers both roots from one sequence and rewrites the ids in every root's documents", function()
		local r = trackerfix.tr(f, wt, { "compact" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(r.stdout, "compacted 2 issues and 1 rafts")).toBe(true)
		-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
		t.expect(has(read("pickman/.tracker/issues/c0001/c0001.md"), "Blocks c0002.")).toBe(true)
		t.expect(has(read(`{Z}/issues/c0002/c0002.md`), "See c0001 and R0001.")).toBe(true)
		t.expect(read(`{Z}/issues/c0002/check.sh`)).toBe(`A="{Z}/issues/c0002/acceptance"\n`)
		t.expect(has(read(`{Z}/rafts/R0001/R0001.md`), "issues: [c0002]")).toBe(true)
		-- c0120 override: a z-nile item's promoted specs are in its home's tests/, z-nile/tests/acceptance
		t.expect(fs.isFile(`{wt}/z-nile/{TA}c0002/x.spec.luau`)).toBe(true)
		t.expect(fs.isDir(`{wt}/{Z}/issues/c0200`)).toBe(false)
		t.expect(has(read("z-nile/compaction.txt"), "\nc0200 c0002\n")).toBe(true)
		t.expect(string.match(read("z-nile/next"), "^issue 3 %S+\nraft 2 %S+\n$") ~= nil).toBe(true)
		t.expect(read("tracker/next")).toBe(ids.TOMBSTONE)
		t.expect(fs.isFile(`{wt}/tracker/compaction.txt`)).toBe(false)
		t.expect(read("z-nile/templates/issue/example.md"))
			.toBe(`For example c0200, R0300 and {TA}c0200/x.spec.luau.\n`)
		t.expect(trackerfix.tr(f, wt, { "audit" }).ok).toBe(true)
	end)
end)
