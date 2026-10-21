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
-- the one old-id rule (skills.oldLessonIds, shared with the rename script and AC4): every token in a ledger, and in a
-- lesson body only a token whose renamed lesson exists
local function oldIds(text: string, existing: { [string]: boolean }, ledger: boolean): { string }
	local out: { string } = {}
	for _, id in skills.oldLessonIds(text, existing, ledger) do
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
		"the old-id rule: every token in a ledger, only renamed lessons in prose, never a look-alike path",
		function()
			local existing = { ["zz-test/no-vacuous-pass"] = true, ["z-design/x"] = true }
			-- a ledger: every token is an id, known or not
			t.expect(
				oldIds(
					"- design-review-001 F1: testing/no-vacuous-pass, ticket-prep/x, testing/unknown-slug\n",
					existing,
					true
				)
			).toEqual({ "testing/no-vacuous-pass", "ticket-prep/x", "testing/unknown-slug" })
			-- a lesson body: look-alikes and unknown slugs pass, a renamed lesson's old id fails
			local prose =
				"Read `tracker/next`, scripts/tracker/x and testing/unknown-slug; z-nile/.tracker/issues too."
			t.expect(oldIds(prose, existing, false)).toEqual({})
			t.expect(oldIds("as testing/no-vacuous-pass says", existing, false))
				.toEqual({ "testing/no-vacuous-pass" })
			t.expect(oldIds("- review-001 F1: zz-test/no-vacuous-pass, z-design/x\n", existing, true))
				.toEqual({})
			-- the rename the script makes from the same rule
			local out, n, unknown =
				skills.renameLessonIds("- r F1: testing/no-vacuous-pass, testing/gone\n", existing, true)
			t.expect(out).toBe("- r F1: zz-test/no-vacuous-pass, testing/gone\n")
			t.expect(n).toBe(1)
			t.expect(unknown).toEqual({ "testing/gone" })
		end
	)

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
