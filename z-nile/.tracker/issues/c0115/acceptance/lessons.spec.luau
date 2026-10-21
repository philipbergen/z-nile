--!strict
-- c0115 AC5: lessons live in their skill's real folder (z-nile/skills/<skill>/lessons/ or
-- <project>/skills/<skill>/lessons/), keep the id <skill>/<slug> with the new skill names, and `lessons --full` prints
-- the real path. A tree without either folder (from before c0115) still reads .claude/skills. One skill name in two
-- folders is a problem. On the real tree, no harvest.md entry and no lesson names an old skill's id. Fixtures under
-- .cache/c0115-lessons (tests/lib/trackerfix) and .cache/c0115-lessons-load (lessons.load on hand-made trees).
local fs = require("@lune/fs")
local lessons = require("@znile/engine/lessons")
local process = require("@lune/process")
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function lesson(check: string): string
	return `---\ntitle: A lesson\nwhen: build\ntags: [wiring]\ncheck: {check}\n---\nBody.\n`
end
local function doc(name: string): string
	return `---\nname: {name}\ndescription: d\n---\n`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(parent)
	end
	fs.writeFile(path, text)
end
-- the old-id rules the rename script uses: a ledger through lessons.ledgerOldIds (every id parseHarvest reads; notes
-- and one-off reasons as prose), anything else through skills.oldLessonIds (only a renamed lesson's old id)
local function oldIds(text: string, existing: { [string]: boolean }, ledger: boolean): { string }
	if ledger then
		return (lessons.ledgerOldIds(text, existing))
	end
	local out: { string } = {}
	for _, id in skills.oldLessonIds(text, existing) do
		table.insert(out, `{id.old}/{id.slug}`)
	end
	return out
end

local f: trackerfix.Fixture
local LOAD = ".cache/c0115-lessons-load"

return t.spec("c0115 lessons live in the skills' real folders", function(it)
	it(
		"lessons.load reads z-nile's and a project's skills folders, with each skill's folder and project",
		function()
			if fs.isDir(LOAD) then
				fs.removeDir(LOAD)
			end
			local root = `{LOAD}/new`
			write(
				`{root}/z-nile/projects.toml`,
				'retired = []\n\n[[project]]\nname = "pickman"\nroot = "tracker"\n'
			)
			write(`{root}/z-nile/skills/zz-test/SKILL.md`, doc("zz-test"))
			write(`{root}/z-nile/skills/zz-test/lessons/pin.md`, lesson("Pinned?"))
			write(`{root}/pickman/skills/pickman-play/SKILL.md`, doc("pickman-play"))
			write(`{root}/pickman/skills/pickman-play/lessons/feel.md`, lesson("Fair?"))
			-- a stray old folder through a link path is never read once the real folders exist
			write(`{root}/.claude/skills/testing/lessons/old.md`, lesson("Old?"))
			local tree = lessons.load(root)
			t.expect(tree.lessons["zz-test/pin"] ~= nil).toBe(true)
			t.expect(tree.lessons["pickman-play/feel"] ~= nil).toBe(true)
			t.expect(tree.lessons["testing/old"]).toBe(nil)
			t.expect(lessons.folderOf(tree, "zz-test")).toBe("z-nile/skills/zz-test")
			t.expect(lessons.folderOf(tree, "pickman-play")).toBe("pickman/skills/pickman-play")
			t.expect((tree.owners :: { [string]: string })["pickman-play"]).toBe("pickman")
			t.expect((tree.owners :: { [string]: string })["zz-test"]).toBe("z-nile")
			t.expect(tree.skills["zz-test"] and tree.skills["pickman-play"]).toBe(true)
		end
	)

	it("a tree with neither folder keeps reading .claude/skills, as before c0115", function()
		local root = `{LOAD}/old`
		write(`{root}/.claude/skills/testing/SKILL.md`, doc("testing"))
		write(`{root}/.claude/skills/testing/lessons/pin.md`, lesson("Pinned?"))
		local tree = lessons.load(root)
		t.expect(tree.lessons["testing/pin"] ~= nil).toBe(true)
		t.expect(lessons.folderOf(tree, "testing")).toBe(".claude/skills/testing")
	end)

	it(
		"a lesson in a folder with no SKILL.md names the skill and every skills folder, not .claude/skills",
		function()
			local root = `{LOAD}/noskill`
			write(
				`{root}/z-nile/projects.toml`,
				'retired = []\n\n[[project]]\nname = "pickman"\nroot = "tracker"\n'
			)
			write(`{root}/z-nile/skills/zz-gone/lessons/pin.md`, lesson("Pinned?") .. "")
			local joined = table.concat(lessons.check(lessons.load(root)), "\n")
			t.expect(has(joined, "zz-gone/pin: no skill zz-gone (no zz-gone/SKILL.md in any skills folder)"))
				.toBe(true)
			t.expect(has(joined, ".claude/")).toBe(false)
		end
	)

	it("one skill name in two folders is a problem naming both", function()
		local root = `{LOAD}/dup`
		write(
			`{root}/z-nile/projects.toml`,
			'retired = []\n\n[[project]]\nname = "pickman"\nroot = "tracker"\n'
		)
		write(`{root}/z-nile/skills/zz-x/SKILL.md`, doc("zz-x"))
		write(`{root}/pickman/skills/zz-x/SKILL.md`, doc("zz-x"))
		local tree = lessons.load(root)
		local joined = table.concat(lessons.check(tree), "\n")
		t.expect(has(joined, "z-nile/skills/zz-x") and has(joined, "pickman/skills/zz-x")).toBe(true)
		fs.removeDir(LOAD)
	end)

	it("sets up a tracker fixture with a z-nile and a pickman lesson and their harvest", function()
		f = trackerfix.new("c0115-lessons", {
			["z-nile/skills/zz-test/lessons/pin.md"] = lesson("Are the inputs pinned?"),
			["pickman/skills/pickman-play/SKILL.md"] = doc("pickman-play"),
			["pickman/skills/pickman-play/lessons/feel.md"] = lesson("Does it feel fair?"),
			["tracker/rafts/R0010/design-review-001.md"] = "# Review 001\n\n### F1 [low] a\n\n### F2 [low] b\n\nVerdict: changes\n",
			["tracker/rafts/R0010/harvest.md"] = "- design-review-001 F1: zz-test/pin\n- design-review-001 F2: pickman-play/feel\n",
		})
	end)

	it("--full prints each lesson's real path, and --check passes", function()
		local full = trackerfix.trOk(f, f.main, { "lessons", "--full" })
		t.expect(has(full, "== z-nile/skills/zz-test/lessons/pin.md\n")).toBe(true)
		t.expect(has(full, "== pickman/skills/pickman-play/lessons/feel.md\n")).toBe(true)
		t.expect(has(full, ".claude/")).toBe(false)
		t.expect(has(trackerfix.trOk(f, f.main, { "lessons", "--check" }), "ok")).toBe(true)
		t.expect(
			has(trackerfix.trOk(f, f.main, { "lessons", "--skill", "pickman-play" }), "pickman-play/feel")
		)
			.toBe(true)
	end)

	it("a harvest entry that still names an old skill's id fails --check", function()
		local h = `{f.main}/tracker/rafts/R0010/harvest.md`
		fs.writeFile(h, "- design-review-001 F1: testing/pin\n- design-review-001 F2: pickman-play/feel\n")
		local r = trackerfix.tr(f, f.main, { "lessons", "--check" })
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "testing/pin")).toBe(true)
	end)

	it(
		"a ledger's parsed ids all count; its notes and one-off reasons are prose; look-alikes never count",
		function()
			local existing = { ["zz-test/no-vacuous-pass"] = true, ["z-design/x"] = true }
			-- every parsed id of an old skill counts, known or not
			local found, unknown = lessons.ledgerOldIds(
				"- design-review-001 F1: testing/no-vacuous-pass, ticket-prep/x, testing/gone\n",
				existing
			)
			t.expect(found).toEqual({ "testing/no-vacuous-pass", "ticket-prep/x", "testing/gone" })
			t.expect(unknown).toEqual({ "testing/gone" })
			-- a note's text and a one-off's reason are prose: paths there never count, valid ids beside them pass
			local notes = "- note c0115 prep: a spec wrote under review/x and tracker/rafts/R0010: zz-test/no-vacuous-pass\n"
				.. "- review-001 F2: one-off: a stale testing/fixtures link and a review/round path\n"
			t.expect((lessons.ledgerOldIds(notes, existing))).toEqual({})
			-- an old id in a note's id list is an id, and a renamed lesson's old id in its prose is caught too
			t.expect(
				(
					lessons.ledgerOldIds(
						"- note it said testing/no-vacuous-pass: testing/no-vacuous-pass\n",
						existing
					)
				)
			).toEqual({ "testing/no-vacuous-pass", "testing/no-vacuous-pass" })
			-- a lesson body: look-alikes and unknown slugs pass, a renamed lesson's old id fails
			local prose =
				"Read `tracker/next`, scripts/tracker/x and testing/unknown-slug; z-nile/.tracker/issues too."
			t.expect(oldIds(prose, existing, false)).toEqual({})
			t.expect(oldIds("as testing/no-vacuous-pass says", existing, false))
				.toEqual({ "testing/no-vacuous-pass" })
			t.expect(oldIds("- review-001 F1: zz-test/no-vacuous-pass, z-design/x\n", existing, true))
				.toEqual({})
		end
	)

	it(
		"the script's ledger rename: parsed ids by the list, prose by the prose rule, nothing else changed",
		function()
			local existing = { ["zz-test/no-vacuous-pass"] = true }
			local text = "# Harvest: c0010\n- design-review-001 F1: testing/no-vacuous-pass, testing/gone\n"
				.. "- note under review/x, see testing/no-vacuous-pass: testing/no-vacuous-pass\n"
				.. "- review-001 F2: one-off: a review/x path\n"
			local out, n, unknown = lessons.renameLedger(text, existing)
			t.expect(out).toBe(
				"# Harvest: c0010\n- design-review-001 F1: zz-test/no-vacuous-pass, testing/gone\n"
					.. "- note under review/x, see zz-test/no-vacuous-pass: zz-test/no-vacuous-pass\n"
					.. "- review-001 F2: one-off: a review/x path\n"
			)
			t.expect(n).toBe(3)
			t.expect(unknown).toEqual({ "testing/gone" })
			local clean = "- note a spec wrote under review/x: zz-test/no-vacuous-pass\n"
			local same, zero, none = lessons.renameLedger(clean, existing)
			t.expect(same).toBe(clean)
			t.expect(zero).toBe(0)
			t.expect(none).toEqual({})
		end
	)

	it(
		"every part of a ledger takes a rule: each row with a renamed id is found and renamed, with a look-alike untouched",
		function()
			local existing = { ["zz-test/no-vacuous-pass"] = true }
			local OLD, NEW = "testing/no-vacuous-pass", "zz-test/no-vacuous-pass"
			-- one row per kind of part a harvest.md has; `alike` is a token the row's rule must leave alone
			local rows: { { part: string, line: (string) -> string, alike: string } } = {
				{
					part = "id list",
					line = function(x)
						return `- design-review-001 F1: {x}`
					end,
					alike = "zz-test/fixtures",
				},
				{
					part = "note text",
					line = function(x)
						return `- note it mentions {x} here: zz-test/no-vacuous-pass`
					end,
					alike = "review/x",
				},
				{
					part = "one-off reason",
					line = function(x)
						return `- review-001 F2: one-off: see {x} for why`
					end,
					alike = "testing/fixtures",
				},
				{
					part = "heading",
					line = function(x)
						return `# Harvest: {x}`
					end,
					alike = "review/x",
				},
				{
					part = "paragraph",
					line = function(x)
						return `Rounds 001 to 005 reviewed it; see {x}.`
					end,
					alike = "tracker/rafts/R0010",
				},
				{
					part = "sub-bullet",
					line = function(x)
						return `  - also {x}`
					end,
					alike = "review/x",
				},
				{
					part = "refused line",
					line = function(x)
						return `- not an entry naming {x}`
					end,
					alike = "testing/fixtures",
				},
			}
			for _, row in rows do
				local text = row.line(OLD) .. "\n"
				local found = lessons.ledgerOldIds(text, existing)
				if #found ~= 1 or found[1] ~= OLD then
					error(`{row.part}: {OLD} not found once: {table.concat(found, ", ")}`)
				end
				local out, n = lessons.renameLedger(text, existing)
				if out ~= row.line(NEW) .. "\n" or n ~= 1 then
					error(`{row.part}: not renamed in place: {out} ({n})`)
				end
				local alike = row.line(row.alike) .. "\n"
				local none = lessons.ledgerOldIds(alike, existing)
				local same, zero = lessons.renameLedger(alike, existing)
				if #none ~= 0 or same ~= alike or zero ~= 0 then
					error(
						`{row.part}: the look-alike {row.alike} was touched: {same} ({table.concat(none, ", ")})`
					)
				end
			end
			-- a one-off naming an old id with no renamed lesson is prose: never reported, so the script's exit stays 0
			local quiet, unknown =
				lessons.ledgerOldIds("- review-001 F3: one-off: see testing/never-a-lesson\n", existing)
			t.expect(quiet).toEqual({})
			t.expect(unknown).toEqual({})
			local _, _, none =
				lessons.renameLedger("- review-001 F3: one-off: see testing/never-a-lesson\n", existing)
			t.expect(none).toEqual({})
			-- a refused line is still a problem for lessons --check after its rename
			local refused = lessons.renameLedger("- not an entry naming testing/no-vacuous-pass\n", existing)
			local _, problems = lessons.parseHarvest("c0010", refused)
			t.expect(#problems).toBe(1)
		end
	)

	it("an id list keeps its separators and spaces byte for byte", function()
		local existing = { ["zz-test/no-vacuous-pass"] = true }
		local text = "- design-review-001 F1: testing/no-vacuous-pass,zz-test/b  \n"
			.. "- design-review-001 F2: zz-test/a,zz-test/b\n"
			.. "- note n:  zz-test/a ,testing/no-vacuous-pass\n"
		local out, n = lessons.renameLedger(text, existing)
		t.expect(out).toBe(
			"- design-review-001 F1: zz-test/no-vacuous-pass,zz-test/b  \n"
				.. "- design-review-001 F2: zz-test/a,zz-test/b\n"
				.. "- note n:  zz-test/a ,zz-test/no-vacuous-pass\n"
		)
		t.expect(n).toBe(2)
	end)

	it("no harvest.md under any root, and no lesson, names an old skill's id", function()
		local r = process.exec("git", { "ls-files" })
		local existing = skills.lessonIndex(".")
		local bad: { string } = {}
		local n = 0
		for path in string.gmatch(r.stdout, "[^\n]+") do
			local ledger = string.match(path, "/harvest%.md$") ~= nil
			local lessonFile = string.match(path, "^[%w%-]+/skills/[^/]+/lessons/[^/]+%.md$") ~= nil
			if (ledger or lessonFile) and fs.isFile(path) then
				n += 1
				for _, id in oldIds(fs.readFile(path), existing, ledger) do
					table.insert(bad, `{path}: {id}`)
				end
			end
		end
		t.expect(n > 10).toBe(true)
		if #bad > 0 then
			error("old lesson ids:\n" .. table.concat(bad, "\n"))
		end
	end)
end)
