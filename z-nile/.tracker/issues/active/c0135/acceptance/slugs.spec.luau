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
	["pickman/.tracker/issues/c0008/c0008.md"] = doc("c0008", "another-member"),
	-- a prepared chore whose slug a retired raft holds (design review 001 F2)
	["pickman/.tracker/issues/c0030/c0030.md"] = (string.gsub(
		doc("c0030", "lone-chore", "size: 100\n"),
		"design: draft\ncreated: 2026%-01%-01\nstatus: new%-a%-b%-c",
		"design: ready\ncreated: 2026-01-01\nstatus: prepared-a-b-c"
	)),
	["pickman/.tracker/rafts/retired/R0031/R0031.md"] = raftDoc("R0031", "lone-chore", "retired: R0004\n"),
	-- an active raft, for an emergent issue made on its branch (design review 001 F3)
	["pickman/.tracker/rafts/active/R0040/R0040.md"] = raftDoc("R0040", "the-active"),
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
		"raft-plan's commands give a new raft a free slug: its first issue's, or with -2, -3, … distinct in the plan",
		function()
			local raftplan = require("@znile/engine/raftplan")
			local ops: { any } = {
				{ kind = "new", type = "chore", issues = { "c0001" }, root = "pickman/.tracker" },
				{ kind = "new", type = "chore", issues = { "c0002" }, root = "pickman/.tracker" },
			}
			local runs = raftplan.commands(ops, { c0001 = "same", c0002 = "same" }, function(): string?
				return "pickman"
			end, { same = true }) :: { { string } }
			t.expect(runs[1][4]).toBe("same-2")
			t.expect(runs[2][4]).toBe("same-3")
			-- a suffix a raft already has is skipped, per slug (review 002 F1: `-2` itself taken)
			local one = raftplan.commands({ ops[1] }, { c0001 = "same" }, function(): string?
				return "pickman"
			end, { same = true, ["same-2"] = true }) :: { { string } }
			t.expect(one[1][4]).toBe("same-3")
			-- two different bases, both taken: each gets its own -2 (review 003 F2: no counter shared across the plan)
			local two = raftplan.commands(ops, { c0001 = "a", c0002 = "b" }, function(): string?
				return "pickman"
			end, { a = true, b = true }) :: { { string } }
			t.expect({ two[1][4], two[2][4] }).toEqual({ "a-2", "b-2" })
		end
	)

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
				"issue c0008 another-member",
				"issue c0030 lone-chore",
				"issue f0001 taken-done",
				"raft R0003 old-raft",
				"raft R0004 keeper",
				"raft R0031 lone-chore",
				"raft R0040 the-active",
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
		-- a raft retired on origin/main only, after this worktree was cut: the publish path reads origin's tree
		trackerfix.elsewhere(f, {
			["pickman/.tracker/rafts/retired/R0035/R0035.md"] = raftDoc(
				"R0035",
				"retired-elsewhere",
				"retired: R0004\n"
			),
		}, "a raft retired elsewhere")
		local far = trackerfix.tr(
			f,
			wt,
			{ "new", "raft", "chore", "retired-elsewhere", "c0005", "--project", "pickman" }
		)
		t.expect(far.ok).toBe(false)
		t.expect(has(far.stderr .. far.stdout, "taken by R0035")).toBe(true)
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

	it("new raft's local path refuses a live or retired raft's slug and writes no raft", function()
		local before = #fs.readDir(`{wt}/pickman/.tracker/rafts`)
		for _, case in { { slug = "keeper", owner = "R0004" }, { slug = "old-raft", owner = "R0003" } } do
			local r = trackerfix.tr(
				f,
				wt,
				{ "new", "raft", "chore", case.slug, "c0008", "--project", "pickman" },
				{ PICKMAN_PUBLISH = "0" }
			)
			t.expect({ slug = case.slug, ok = r.ok }).toEqual({ slug = case.slug, ok = false })
			t.expect({ slug = case.slug, named = has(r.stderr .. r.stdout, `taken by {case.owner}`) })
				.toEqual({ slug = case.slug, named = true })
		end
		t.expect(#fs.readDir(`{wt}/pickman/.tracker/rafts`)).toBe(before)
	end)

	it("raft-plan gives a planned raft a slug no raft has (a retired raft keeps its slug)", function()
		local out = trackerfix.trOk(f, wt, { "raft-plan" })
		t.expect(has(out, "./zn new raft chore lone-chore-2 c0030 --project pickman")).toBe(true)
	end)

	it(
		"a publishing new checks origin/main and this checkout: an emergent issue sees origin, a capture sees its tree",
		function()
			-- origin/main gains an issue after the raft's branch was cut
			local rw = trackerfix.trOk(f, f.main, { "worktree", "R0040" })
			trackerfix.elsewhere(
				f,
				{ ["z-nile/.tracker/issues/c0090/c0090.md"] = doc("c0090", "origin-only") },
				"x"
			)
			local r = trackerfix.tr(f, rw, { "new", "issue", "c", "origin-only", "--raft", "R0040" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr .. r.stdout, "taken by c0090")).toBe(true)
			-- a capture worktree's own tree holds an item origin/main doesn't
			fs.writeDir(`{wt}/pickman/.tracker/issues/c0091`)
			fs.writeFile(`{wt}/pickman/.tracker/issues/c0091/c0091.md`, doc("c0091", "local-only"))
			local r2 = trackerfix.tr(f, wt, { "new", "issue", "c", "local-only", "--project", "pickman" })
			t.expect(r2.ok).toBe(false)
			t.expect(has(r2.stderr .. r2.stdout, "taken by c0091")).toBe(true)
			fs.removeDir(`{wt}/pickman/.tracker/issues/c0091`)
		end
	)

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
			t.expect(lines).toEqual({
				"error slug-duplicate z-nile/.tracker/issues/c0099: issue taken-done: c0099, f0001 (edit slug: in all but one; branch and worktree names need not follow)",
			})
			-- a raft clash says which raft may take the new slug (review 003 F1)
			fs.writeDir(`{wt}/pickman/.tracker/rafts/R0098`)
			fs.writeFile(`{wt}/pickman/.tracker/rafts/R0098/R0098.md`, raftDoc("R0098", "keeper"))
			local rafts = trackerfix.tr(f, wt, { "audit" })
			t.expect(
				has(
					rafts.stdout .. rafts.stderr,
					"error slug-duplicate pickman/.tracker/rafts/R0004: raft keeper: R0004, R0098 (edit slug: in all but one, never in a raft that has its <id>-<slug> branch: the branch name is derived from it)"
				)
			).toBe(true)
			fs.removeDir(`{wt}/pickman/.tracker/rafts/R0098`)
			-- the stated fix: edit slug: in one of them (review 002 F3)
			fs.writeFile(`{wt}/z-nile/.tracker/issues/c0099/c0099.md`, doc("c0099", "renamed-by-hand"))
			local fixed = trackerfix.tr(f, wt, { "audit" })
			t.expect(has(fixed.stdout .. fixed.stderr, "slug-duplicate")).toBe(false)
			-- audit ran to its summary: "not reported" is not "not run" (review 003 F3)
			t.expect(has(fixed.stdout .. fixed.stderr, "audit: ")).toBe(true)
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
		t.expect(
			has(
				rules,
				"Two copies of one id with one slug are one item twice: remove the stray copy rather than renumbering it."
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
