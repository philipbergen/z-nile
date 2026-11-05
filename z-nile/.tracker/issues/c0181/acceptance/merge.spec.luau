--!strict
-- c0181 AC8: `./zn lesson-merge <into> <from>...` folds lessons of one skill into one, losing no source: it rewrites
-- every harvest.md (backlog, active/, done/ and retired items) and every id in the skills' texts, unions the
-- frontmatter, deletes the merged files, records `merged:` on the survivor, and leaves a marker that the policy
-- refuses until the body is rewritten. It runs only in a worktree, and a refusal changes nothing. Re-running it
-- after the file is gone rewrites any leftover reference (a harvest line main added meanwhile).
local consolidate = require("@znile/engine/consolidate")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function skill(name: string, extra: string?): string
	return `---\nname: {name}\ndescription: x\n---\n\n# {name}\n{extra or ""}`
end
local function lesson(when: string, tags: string, body: string, extra: string?, state: string?): string
	-- each lesson has its own title and check (from its body), so a merge that drops one is seen
	return `---\ntitle: {body}\nwhen: {when}\ntags: [{tags}]\ncheck: Does {body} hold?\n{state or "not_codifiable: a judgement call\n"}{extra or ""}---\n{body}\n`
end
local function review(...: string): string
	local out = "# Review 001\n\n"
	for _, id in { ... } do
		out ..= `### {id} [low] claim\nEvidence: x\n\n`
	end
	return out .. "Verdict: changes\n"
end

-- a raft that grouped c0061 records a hash of c0061's design files (its document and harvest.md among them)
local PREPARED = "prepared-quiet-copper-falcon"
local C61_DOC =
	`---\nid: c0061\ntype: chore\ntitle: c0061\nslug: s-c0061\nraft: R0060\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 100\nstatus: {PREPARED}\n---\n\n# c0061\n`
local C61_HARVEST = "- review-001 F1: zz-test/old2\n"
local function grouped(harvest: string): string
	return raftplan.renderGrouped({
		c0061 = raftplan.recordHash("c0061", { ["c0061.md"] = C61_DOC, ["harvest.md"] = harvest }),
	})
end

local R = "pickman/.tracker/rafts"
local I = "pickman/.tracker/issues"
local SEED: { [string]: string } = {
	["z-nile/skills/zz-test/SKILL.md"] = skill("zz-test", "See `zz-test/old1`, not `zz-test/old10`.\n"),
	["z-nile/skills/zz-arch/SKILL.md"] = skill("zz-arch", "Lesson zz-test/old2 applies.\n"),
	["z-nile/skills/zz-test/lessons/keep.md"] = lesson(
		"design",
		"wiring, seams",
		"Keep body.",
		"distinct_from: zz-test/old1\n"
	),
	["z-nile/skills/zz-test/lessons/old1.md"] = lesson(
		"build",
		"wiring, ids",
		"Old one body.",
		"from: user 2026-10-20\n"
	),
	["z-nile/skills/zz-test/lessons/old2.md"] = lesson("both", "paths", "Old two body."),
	["z-nile/skills/zz-test/lessons/old10.md"] = lesson("both", "other", "Unrelated."),
	["z-nile/skills/zz-arch/lessons/foreign.md"] = lesson("both", "wiring", "Another skill.", "from: test\n"),
	["z-nile/skills/zz-test/lessons/third.md"] = lesson(
		"both",
		"other",
		"Third.",
		"distinct_from: zz-test/old1, zz-test/keep\nfrom: test\n"
	),
	-- an enforced survivor and a judged lesson folded into it (the survivor stops being "full": the folded rule is not checked)
	["z-nile/skills/zz-test/lessons/intoenf.md"] = lesson(
		"both",
		"enfs",
		"Enforced survivor.",
		nil,
		"enforced_by: z-nile/lints/intoenf.luau\nenforced: full\n"
	),
	[`{I}/c0070/review-001.md`] = review("F1"),
	[`{I}/c0070/harvest.md`] = "- review-001 F1: zz-test/intoenf\n",
	["z-nile/skills/zz-test/lessons/judged.md"] = lesson("both", "judges", "Judged rule.", "from: test\n"),
	["z-nile/skills/zz-test/lessons/enf.md"] = lesson(
		"both",
		"checks",
		"Enforced.",
		"from: test\n",
		"enforced_by: z-nile/lints/enf.luau\nenforced: full\n"
	),
	[`{R}/R0010/design-review-001.md`] = review("F1", "F2", "F3"),
	[`{R}/R0010/harvest.md`] = "- design-review-001 F1: zz-test/keep\n- design-review-001 F2: zz-test/old1\n",
	[`{I}/done/c0020/review-001.md`] = review("F1", "F2"),
	[`{I}/done/c0020/harvest.md`] = "- review-001 F1: zz-test/old1, zz-test/old2\n- review-001 F2: zz-test/old10\n"
		.. "- note a user correction: zz-test/old1, zz-test/old10\n",
	[`{R}/retired/R0030/review-001.md`] = review("F1"),
	[`{R}/retired/R0030/harvest.md`] = "- review-001 F1: zz-test/old2\n",
	-- a grouped raft: its member's harvest names old2, so the merge changes the member's record
	["pickman/.tracker/issues/c0061/c0061.md"] = C61_DOC,
	["pickman/.tracker/issues/c0061/review-001.md"] = review("F1"),
	["pickman/.tracker/issues/c0061/harvest.md"] = C61_HARVEST,
	[`{R}/R0060/R0060.md`] = `---\nid: R0060\ntype: chore\ntitle: grp\nslug: grp\nsingle: false\nissues: [c0061]\ndesign: ready\ncreated: 2026-10-20\ngrouped: {grouped(
		C61_HARVEST
	)}\nstatus: {PREPARED}\n---\n\n# R0060\n`,
	[`{R}/R0060/design-review-001.md`] = `# Coherence review\n\nGrouped: {grouped(C61_HARVEST)}\n\nVerdict: approve\n`,
	-- an active/ item, and an item of the other project's root
	[`{I}/active/c0040/review-001.md`] = review("F1"),
	[`{I}/active/c0040/harvest.md`] = "- review-001 F1: zz-test/old2\n",
	["z-nile/.tracker/issues/c0050/review-001.md"] = review("F1", "F2"),
	-- the second line is not canonical (extra spaces) and names no merged id: it must come out byte for byte
	["z-nile/.tracker/issues/c0050/harvest.md"] = "- review-001 F1: zz-test/old2\n- review-001 F2:   zz-test/third\n",
}

local f: trackerfix.Fixture
local wt: string
local function zn(args: { string }, cwd: string?): fixture.Result
	return trackerfix.tr(f, cwd or wt, args)
end
local function read(path: string): string
	return fs.readFile(`{wt}/{path}`)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function clean(): boolean
	return fixture.git(wt, { "status", "--porcelain" }) == ""
end

return t.spec("c0181 lesson-merge", function(it)
	it("sets up a fixture with a worktree", function()
		f = trackerfix.new("codify-merge", SEED, { noLessons = true })
		wt = trackerfix.trOk(f, f.main, { "worktree", "merge-wt" })
	end)

	it("the ledger rewrite renames and dedupes ids without touching a longer id", function()
		local text =
			"- review-001 F1: zz-test/old1, zz-test/old2\n- review-001 F2: zz-test/old10\n- note why: zz-test/old1, zz-test/keep\n"
		local out, n = consolidate.mergeLedger(text, { "zz-test/old1", "zz-test/old2" }, "zz-test/keep")
		t.expect(out)
			.toBe("- review-001 F1: zz-test/keep\n- review-001 F2: zz-test/old10\n- note why: zz-test/keep\n")
		t.expect(n).toBe(2)
	end)

	it(
		"refuses, changing nothing: in the main checkout, across skills, unknown or repeated ids, two from: notes",
		function()
			t.expect(zn({ "lesson-merge", "zz-test/keep", "zz-test/old2" }, f.main).code ~= 0).toBe(true)
			t.expect(
				has(
					zn({ "lesson-merge", "zz-test/keep", "zz-test/old2" }, f.main).stderr,
					"must run inside a worktree"
				)
			).toBe(true)
			for _, args in
				{
					{ "zz-test/keep", "zz-arch/foreign" },
					{ "zz-test/keep", "zz-test/enf" }, -- a check names its id: merge before codifying
					{ "zz-test/keep", "zz-test/ghost" },
					{ "zz-test/keep", "zz-test/keep" },
					{ "zz-test/keep", "zz-test/old2", "zz-test/old2" },
					{ "zz-test/keep" },
				}
			do
				local argv = { "lesson-merge" }
				for _, a in args do
					table.insert(argv, a)
				end
				t.expect(zn(argv).code ~= 0).toBe(true)
				t.expect(clean()).toBe(true)
			end
			-- both lessons carry a from: note: the notes are merged by hand
			fs.writeFile(
				`{wt}/z-nile/skills/zz-test/lessons/keep.md`,
				lesson("design", "wiring", "Keep body.", "from: user 2026-10-21\n")
			)
			local both = zn({ "lesson-merge", "zz-test/keep", "zz-test/old1" })
			t.expect(both.code ~= 0).toBe(true)
			-- nothing changed but the file this case rewrote itself
			t.expect(fixture.git(wt, { "status", "--porcelain" }))
				.toBe("M z-nile/skills/zz-test/lessons/keep.md") -- fixture.git trims the leading space
			fixture.git(wt, { "checkout", "--", "." })
			t.expect(clean()).toBe(true)
		end
	)

	it("merges two lessons into one and loses no source", function()
		local before = zn({ "lessons", "--full", "zz-test/keep" }).stdout
		t.expect(has(before, "R0010 design-review-001 F1")).toBe(true)
		local r = zn({ "lesson-merge", "zz-test/keep", "zz-test/old1", "zz-test/old2" })
		t.expect(r.code).toBe(0)
		t.expect(fs.isFile(`{wt}/z-nile/skills/zz-test/lessons/old1.md`)).toBe(false)
		t.expect(fs.isFile(`{wt}/z-nile/skills/zz-test/lessons/old2.md`)).toBe(false)
		local keep = read("z-nile/skills/zz-test/lessons/keep.md")
		t.expect(has(keep, "merged: zz-test/old1, zz-test/old2")).toBe(true)
		t.expect(has(keep, "when: both")).toBe(true) -- design + build + both
		for _, tag in { "wiring", "seams", "ids", "paths" } do
			t.expect(has(keep, tag)).toBe(true)
		end
		t.expect(has(keep, "from: user 2026-10-20")).toBe(true) -- the only from: note is carried
		t.expect(has(keep, "<!-- merged from zz-test/old1")).toBe(true)
		-- the merged lessons' own question and title are carried under their markers, to be folded in the rewrite
		for _, carried in
			{ "Does Old one body. hold?", "Does Old two body. hold?", "Old one body.", "Old two body." }
		do
			t.expect(has(keep, carried)).toBe(true)
		end
		t.expect(has(keep, "Old one body.") and has(keep, "Old two body.") and has(keep, "Keep body."))
			.toBe(true)
		-- every harvest.md now names the survivor, the longer id is untouched
		t.expect(read(`{R}/R0010/harvest.md`))
			.toBe("- design-review-001 F1: zz-test/keep\n- design-review-001 F2: zz-test/keep\n")
		t.expect(read(`{I}/done/c0020/harvest.md`)).toBe(
			"- review-001 F1: zz-test/keep\n- review-001 F2: zz-test/old10\n- note a user correction: zz-test/keep, zz-test/old10\n"
		)
		t.expect(read(`{R}/retired/R0030/harvest.md`)).toBe("- review-001 F1: zz-test/keep\n")
		t.expect(read(`{I}/active/c0040/harvest.md`)).toBe("- review-001 F1: zz-test/keep\n")
		t.expect(read("z-nile/.tracker/issues/c0050/harvest.md"))
			.toBe("- review-001 F1: zz-test/keep\n- review-001 F2:   zz-test/third\n")
		-- distinct_from: the survivor drops the merged ids, another lesson's list is rewritten and deduplicated
		t.expect(has(keep, "distinct_from")).toBe(false)
		t.expect(has(read("z-nile/skills/zz-test/lessons/third.md"), "distinct_from: zz-test/keep\n"))
			.toBe(true)
		-- the survivor's own merged: line and marker keep the old ids
		t.expect(has(keep, "<!-- merged from zz-test/old2")).toBe(true)
		-- every id in the skills' texts
		t.expect(has(read("z-nile/skills/zz-test/SKILL.md"), "See `zz-test/keep`, not `zz-test/old10`."))
			.toBe(true)
		t.expect(has(read("z-nile/skills/zz-arch/SKILL.md"), "Lesson zz-test/keep applies.")).toBe(true)
		-- the tree is valid and the survivor has all eight sources (the review findings and the note)
		t.expect(zn({ "lessons", "--check" }).code).toBe(0)
		local after = zn({ "lessons", "--full", "zz-test/keep" }).stdout
		for _, source in
			{
				"R0010 design-review-001 F1",
				"R0010 design-review-001 F2",
				"c0020 review-001 F1",
				"R0030 review-001 F1",
				"c0020 note a user correction",
				"c0040 review-001 F1",
				"c0050 review-001 F1",
				"c0061 review-001 F1",
			}
		do
			t.expect(has(after, source)).toBe(true)
		end
		-- the policy refuses the survivor until its body is rewritten
		local policy = zn({ "lessons", "--check", "--policy" })
		t.expect(policy.code).toBe(1)
		t.expect(has(policy.stdout .. policy.stderr, "tighten")).toBe(true) -- the marker rule, not only an overlap or a dangling id
	end)

	it(
		"a rafted member's record is kept: the raft's grouped line and its coherence review quote the new hash",
		function()
			local want = grouped("- review-001 F1: zz-test/keep\n")
			t.expect(want ~= grouped(C61_HARVEST)).toBe(true) -- the merge did change the member's design files
			t.expect(has(read(`{R}/R0060/R0060.md`), `grouped: {want}`)).toBe(true)
			t.expect(has(read(`{R}/R0060/design-review-001.md`), `Grouped: {want}`)).toBe(true)
		end
	)

	it("a judged lesson folded into an enforced one leaves it partly enforced, keeping its check", function()
		local r = zn({ "lesson-merge", "zz-test/intoenf", "zz-test/judged" })
		t.expect(r.code).toBe(0)
		local into = read("z-nile/skills/zz-test/lessons/intoenf.md")
		t.expect(has(into, "enforced: part")).toBe(true)
		t.expect(has(into, "enforced_by: z-nile/lints/intoenf.luau")).toBe(true)
		t.expect(has(into, "not_codifiable")).toBe(false)
		t.expect(has(into, "Does Judged rule. hold?")).toBe(true) -- the folded question is carried
	end)

	it("run again after the file is gone, it rewrites a reference main added meanwhile", function()
		local path = `{R}/R0010/harvest.md`
		fs.writeFile(`{wt}/{path}`, read(path) .. "- design-review-001 F3: zz-test/old1, zz-test/keep\n")
		local stale = zn({ "lessons", "--check" })
		t.expect(stale.code).toBe(1)
		t.expect(
			has(
				stale.stdout .. stale.stderr,
				"R0010/harvest.md: design-review-001 F3: no lesson zz-test/old1 (merged into zz-test/keep)"
			)
		).toBe(true)
		local r = zn({ "lesson-merge", "zz-test/keep", "zz-test/old1" })
		t.expect(r.code).toBe(0)
		t.expect(has(read(path), "zz-test/old1")).toBe(false)
		t.expect(zn({ "lessons", "--check" }).code).toBe(0)
	end)

	it(
		"./zn clean runs from the main checkout: it refuses an unlanded worktree, names the changed file, and removes a landed one",
		function()
			-- commit the worktree's rewrites so it is clean and unlanded: git itself would refuse a dirty one, not clean
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "merge work" })
			local refused = zn({ "clean", "merge-wt" }, f.main)
			t.expect(refused.code ~= 0).toBe(true)
			t.expect(has(refused.stdout .. refused.stderr, "z-nile/skills/zz-test/lessons/keep.md"))
				.toBe(true)
			t.expect(fs.isDir(wt)).toBe(true)
			-- a name must match `worktree`'s own rule and name a worktree under .worktree/: the main checkout cannot be named
			t.expect(zn({ "clean", "main" }, f.main).code ~= 0).toBe(true)
			t.expect(zn({ "clean", ".." }, f.main).code ~= 0).toBe(true)
			t.expect(fs.isDir(f.main)).toBe(true)
			-- a landed worktree (the second below) named from inside itself is refused by the called-from guard alone
			local ok = trackerfix.trOk(f, f.main, { "worktree", "clean-ok" })
			fs.writeFile(`{ok}/landed-note.txt`, "landed\n")
			fixture.git(ok, { "add", "-A" })
			fixture.git(ok, { "commit", "-q", "-m", "landed" })
			fixture.git(ok, { "push", "-q", "origin", "HEAD:main" })
			t.expect(zn({ "clean", "clean-ok" }, ok).code ~= 0).toBe(true)
			t.expect(fs.isDir(ok)).toBe(true)
			local removed = zn({ "clean", "clean-ok" }, f.main)
			t.expect(removed.code).toBe(0)
			t.expect(fs.isDir(ok)).toBe(false)
			t.expect(has(fixture.git(f.main, { "branch", "--list" }), "clean-ok")).toBe(false)
			-- a squash: two commits whose files reach origin/main as one different commit (the content test, not ancestry)
			local sq = trackerfix.trOk(f, f.main, { "worktree", "clean-squash" })
			fs.writeFile(`{sq}/sq-a.txt`, "a\n")
			fixture.git(sq, { "add", "-A" })
			fixture.git(sq, { "commit", "-q", "-m", "first" })
			fs.writeFile(`{sq}/sq-b.txt`, "b\n")
			fixture.git(sq, { "add", "-A" })
			fixture.git(sq, { "commit", "-q", "-m", "second" })
			trackerfix.elsewhere(f, { ["sq-a.txt"] = "a\n", ["sq-b.txt"] = "b\n" }, "squash of clean-squash")
			t.expect(zn({ "clean", "clean-squash" }, f.main).code).toBe(0)
			t.expect(fs.isDir(sq)).toBe(false)
		end
	)
end)
