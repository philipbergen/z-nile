--!strict
-- c0135: a slug names one item of its kind. `new issue` and `new raft` refuse a slug another item of the same kind
-- already uses, in any project root and any state (backlog, active/, done/, and retired/ for rafts), on the publish
-- path and the local one, and create nothing; an issue and a raft may share a slug. `./zn audit` reports a slug two
-- items of one kind share (`slug-duplicate`), so a duplicate that arrives by a merge is caught too. One rule, in
-- @znile/engine/audit (slugOwner, slugClashes), used by both. Fixtures under .cache/c0135-slugs (tests/lib/trackerfix).
local audit = require("@znile/engine/audit")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function doc(id: string, slug: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\n{extra or ""}raft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-01-01\nstatus: new-a-b-c\n---\n\n# {id}\n`
end
local function raftDoc(id: string, slug: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: []\ndesign: draft\ncreated: 2026-01-01\n{extra or ""}status: new-a-b-c\n---\n\n# {id}\n`
end

local SEED = {
	["pickman/.tracker/issues/done/f0001/f0001.md"] = doc("f0001", "taken-done"),
	["z-nile/.tracker/issues/c0002/c0002.md"] = doc("c0002", "in-the-other-root"),
	["pickman/.tracker/issues/c0005/c0005.md"] = doc("c0005", "a-member"),
	["pickman/.tracker/rafts/R0004/R0004.md"] = raftDoc("R0004", "keeper"),
	["pickman/.tracker/rafts/retired/R0003/R0003.md"] = raftDoc("R0003", "old-raft", "retired: R0004\n"),
}

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local f: trackerfix.Fixture
local wt = ""

return t.spec("c0135 a slug names one item of its kind", function(it)
	it("slugOwner finds the item of the same kind with the slug, and nothing else", function()
		local items: { audit.Slugged } = {
			{ kind = "issue", slug = "x", id = "c0001", path = "a" },
			{ kind = "raft", slug = "y", id = "R0002", path = "b" },
		}
		t.expect((audit.slugOwner(items, "issue", "x") :: audit.Slugged).id).toBe("c0001")
		t.expect(audit.slugOwner(items, "raft", "x")).toBe(nil)
		t.expect(audit.slugOwner(items, "issue", "y")).toBe(nil)
		t.expect(audit.slugOwner({ { kind = "issue", slug = "", id = "c0003", path = "c" } }, "issue", ""))
			.toBe(nil)
	end)

	it("slugClashes reports each shared slug of a kind once, ids sorted, and never across kinds", function()
		local clashes = audit.slugClashes({
			{ kind = "issue", slug = "s", id = "c0009", path = "p9" },
			{ kind = "issue", slug = "s", id = "c0002", path = "p2" },
			{ kind = "raft", slug = "s", id = "R0001", path = "r1" },
			{ kind = "issue", slug = "u", id = "c0004", path = "p4" },
		})
		t.expect(#clashes).toBe(1)
		t.expect(clashes[1].kind).toBe("issue")
		t.expect(clashes[1].ids).toEqual({ "c0002", "c0009" })
		-- one id in two folders is one item twice (audit's `duplicate`), not a slug two items share
		t.expect(audit.slugClashes({
			{ kind = "issue", slug = "d", id = "c0007", path = "issues/c0007" },
			{ kind = "issue", slug = "d", id = "c0007", path = "issues/done/c0007" },
		})).toEqual({})
	end)

	it(
		"sluggedFromTree reads every root and every state folder, retired rafts included, and nothing else",
		function()
			local texts: { [string]: string } = table.clone(SEED)
			texts["pickman/.tracker/issues/active/c0006/c0006.md"] = doc("c0006", "active-one")
			texts["pickman/.tracker/issues/c0005/notes.md"] = "slug: not-an-item\n"
			local paths: { string } = {}
			for p in texts do
				table.insert(paths, p)
			end
			local got: { string } = {}
			for _, s in
				audit.sluggedFromTree(paths, { "pickman/.tracker", "z-nile/.tracker" }, function(p: string)
					return texts[p]
				end)
			do
				table.insert(got, `{s.kind} {s.id} {s.slug}`)
			end
			table.sort(got)
			t.expect(got).toEqual({
				"issue c0002 in-the-other-root",
				"issue c0005 a-member",
				"issue c0006 active-one",
				"issue f0001 taken-done",
				"raft R0003 old-raft",
				"raft R0004 keeper",
			})
		end
	)

	it("sets up a fixture with items in both roots and every state", function()
		f = trackerfix.new("c0135-slugs", SEED)
		wt = trackerfix.trOk(f, f.main, { "worktree", "prep-slugs" })
		t.expect(fs.isDir(wt)).toBe(true)
	end)

	it(
		"new issue refuses a slug an issue uses in any state or root, publishes nothing and creates nothing",
		function()
			local before = fixture.git(f.origin, { "rev-parse", "main" })
			for _, case in
				{ { slug = "taken-done", owner = "f0001" }, { slug = "in-the-other-root", owner = "c0002" } }
			do
				local r = trackerfix.tr(f, wt, { "new", "issue", "c", case.slug, "--project", "pickman" })
				t.expect({ slug = case.slug, ok = r.ok }).toEqual({ slug = case.slug, ok = false })
				t.expect({ slug = case.slug, named = has(r.stderr .. r.stdout, `taken by {case.owner}`) })
					.toEqual({ slug = case.slug, named = true })
			end
			t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
		end
	)

	it("an issue may take a slug only a raft uses", function()
		local r = trackerfix.tr(f, wt, { "new", "issue", "c", "old-raft", "--project", "pickman" })
		t.expect({ ok = r.ok, err = r.stderr }).toEqual({ ok = true, err = r.stderr })
		local r2 = trackerfix.tr(f, wt, { "new", "issue", "c", "keeper", "--project", "pickman" })
		t.expect(r2.ok).toBe(true)
	end)

	it("new raft refuses a slug a live or retired raft uses, and takes a fresh one", function()
		for _, case in { { slug = "keeper", owner = "R0004" }, { slug = "old-raft", owner = "R0003" } } do
			local r =
				trackerfix.tr(f, wt, { "new", "raft", "chore", case.slug, "c0005", "--project", "pickman" })
			t.expect({ slug = case.slug, ok = r.ok }).toEqual({ slug = case.slug, ok = false })
			t.expect({ slug = case.slug, named = has(r.stderr .. r.stdout, `taken by {case.owner}`) })
				.toEqual({ slug = case.slug, named = true })
		end
		local ok =
			trackerfix.tr(f, wt, { "new", "raft", "chore", "fresh-raft", "c0005", "--project", "pickman" })
		t.expect({ ok = ok.ok, err = ok.stderr }).toEqual({ ok = true, err = ok.stderr })
	end)

	it("the local path (no publishing) refuses a used slug too and writes no folder", function()
		local before = #fs.readDir(`{wt}/pickman/.tracker/issues`)
		local r = trackerfix.tr(
			f,
			wt,
			{ "new", "issue", "c", "taken-done", "--project", "pickman" },
			{ PICKMAN_PUBLISH = "0" }
		)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr .. r.stdout, "taken by f0001")).toBe(true)
		t.expect(#fs.readDir(`{wt}/pickman/.tracker/issues`)).toBe(before)
	end)

	it(
		"audit reports a slug two issues share, once, naming both; an issue and a raft sharing one is fine",
		function()
			fs.writeDir(`{wt}/z-nile/.tracker/issues/c0099`)
			fs.writeFile(`{wt}/z-nile/.tracker/issues/c0099/c0099.md`, doc("c0099", "taken-done"))
			local r = trackerfix.tr(f, wt, { "audit" })
			t.expect(r.ok).toBe(false)
			local lines: { string } = {}
			for l in string.gmatch(r.stdout .. r.stderr, "[^\n]+") do
				if has(l, "slug-duplicate") then
					table.insert(lines, l)
				end
			end
			t.expect(#lines).toBe(1)
			t.expect(has(lines[1], "issue taken-done: c0099, f0001")).toBe(true)
			fs.removeDir(`{wt}/z-nile/.tracker/issues/c0099`)
			-- the issue `old-raft` made above shares its slug with the retired raft R0003: not a clash
			local clean = trackerfix.tr(f, wt, { "audit" })
			t.expect(has(clean.stdout .. clean.stderr, "slug-duplicate")).toBe(false)
		end
	)

	it("zz-rules states the slug rule and z-ticket says what to do when a slug is refused", function()
		local process = require("@lune/process")
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local rules = fs.readFile(`{top}/z-nile/skills/zz-rules/SKILL.md`)
		t.expect(
			has(
				rules,
				"A slug names one item of its kind, in every project root and every state (retired rafts included): `new issue` and `new raft` refuse a slug another item of the same kind uses, and `./zn audit` reports a shared one (`slug-duplicate`)."
			)
		).toBe(true)
		local ticket = fs.readFile(`{top}/z-nile/skills/z-ticket/SKILL.md`)
		t.expect(
			has(
				ticket,
				"When `new issue` refuses the slug as taken, the error names the item that has it: if that item is the same work, it is a duplicate (step 5); otherwise choose another slug."
			)
		).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(f.base)
		t.expect(fs.isDir(f.base)).toBe(false)
	end)
end)
