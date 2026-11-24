--!strict
-- c0436: z-ticket became z-idea and z-run became z-code. The old names stay as one-line alias skills, so a person
-- mid-session who types /z-run or /z-ticket is handed over; the old records (harvest ledgers) that name
-- `z-ticket/<lesson>` still read as the lesson that moved to z-idea; a dispatched step keeps its stored key but reads
-- the renamed skill's file; the model tables answer to both names. Pure over texts, plus the committed skill files.
local boardview = require("@znile/engine/boardview")
local dispatch = require("@znile/engine/dispatch")
local fs = require("@lune/fs")
local lessons = require("@znile/engine/lessons")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function doc(name: string): string
	return `---\nname: {name}\ndescription: d\n---\n\n# {name}\n`
end

return t.spec("c0436: z-idea and z-code, with aliases for the old names", function(it)
	it("a skill is named for its stage, and the old name is a one-line alias that hands over", function()
		t.expect(has(read("z-nile/skills/z-idea/SKILL.md"), "name: z-idea\n")).toBe(true)
		t.expect(has(read("z-nile/skills/z-code/SKILL.md"), "name: z-code\n")).toBe(true)
		for _, pair in { { "z-ticket", "z-idea" }, { "z-run", "z-code" } } do
			local alias = read(`z-nile/skills/{pair[1]}/SKILL.md`)
			t.expect(has(alias, `name: {pair[1]}\n`)).toBe(true)
			t.expect(has(alias, `z-nile/skills/{pair[2]}/SKILL.md`)).toBe(true)
			t.expect(has(alias, `Renamed to {pair[2]}`)).toBe(true)
			t.expect(select(2, string.gsub(alias, "\n", "\n")) < 12).toBe(true) -- thin: it holds nothing else
			t.expect(fs.isDir(`{TOP}/z-nile/skills/{pair[1]}/lessons`)).toBe(false)
		end
		t.expect(fs.isDir(`{TOP}/z-nile/skills/z-idea/lessons`)).toBe(true)
	end)

	it("the skill planner accepts the aliases beside the renamed skills", function()
		local folder: skills.Folder = { project = "z-nile", path = "z-nile/skills" }
		local entries = {}
		for _, n in { "z-idea", "z-ticket", "z-code", "z-run" } do
			table.insert(entries, { name = n, text = doc(n) })
		end
		local list, problems = skills.plan({ { folder = folder, entries = entries } })
		t.expect(problems).toEqual({})
		t.expect(#list).toBe(4)
	end)

	it("an old lesson id of a renamed skill reads as the lesson that moved", function()
		t.expect(skills.movedId("z-ticket/split-designs-name-each-owner"))
			.toBe("z-idea/split-designs-name-each-owner")
		t.expect(skills.movedId("z-run/x")).toBe("z-code/x")
		t.expect(skills.movedId("z-design/x")).toBe("z-design/x")
		local lesson =
			"---\ntitle: T\nwhen: both\ntags: [wiring]\ncheck: Is it pinned?\nfrom: a user\n---\nBody.\n"
		local tree: lessons.Tree = {
			lessons = { ["z-idea/b"] = lesson },
			found = {},
			skills = { ["z-idea"] = true, ["z-ticket"] = true, ["z-design"] = true },
			items = {
				{
					id = "R0010",
					reviews = {},
					harvest = "- note a capture erred (erred z-ticket): z-ticket/b\n",
				},
			},
			problems = {},
		}
		t.expect(lessons.check(tree)).toEqual({})
		t.expect(lessons.sources(tree.items)["z-idea/b"] ~= nil).toBe(true)
	end)

	it("a dispatched step keeps its stored key and reads the renamed skill", function()
		t.expect(dispatch.skillName("z-ticket")).toBe("z-idea")
		t.expect(dispatch.skillName("z-run")).toBe("z-code")
		t.expect(dispatch.skillName("z-design")).toBe("z-design")
		t.expect(dispatch.STEPS["z-run"] ~= nil).toBe(true)
		-- a person may type either name: both reach the one step
		t.expect(dispatch.stepKey("z-code")).toBe("z-run")
		t.expect(dispatch.stepKey("z-idea")).toBe("z-ticket")
		t.expect(dispatch.stepKey("z-run")).toBe("z-run")
		t.expect(dispatch.step("z-code")).toBe(dispatch.step("z-run"))
		t.expect(dispatch.step("z-idea")).toBe(dispatch.step("z-ticket"))
	end)

	it("the model tables answer to the new skill names as to the old", function()
		t.expect(models.roleFor("z-code")).toBe(models.roleFor("z-run"))
		t.expect(models.roleFor("z-idea")).toBe("idea")
		t.expect(models.activityFor("z-code", nil)).toBe("code")
		t.expect(models.activityFor("z-idea", nil)).toBe("idea")
	end)

	it("the board shows the stage names, and AGENTS.md names the new skills", function()
		t.expect(boardview.LABELS.ticket).toBe("Idea")
		t.expect(boardview.LABELS.raft).toBe("Bundle")
		t.expect(boardview.LABELS.run).toBe("Code")
		t.expect(boardview.LABELS.done).toBe("Landed")
		local agents = read("AGENTS.md")
		t.expect(has(agents, "`z-nile/skills/z-idea/SKILL.md`")).toBe(true)
		t.expect(has(agents, "`z-nile/skills/z-code/SKILL.md`")).toBe(true)
		t.expect(has(agents, "`z-nile/skills/z-ticket/SKILL.md`")).toBe(false)
		t.expect(has(agents, "`z-nile/skills/z-run/SKILL.md`")).toBe(false)
	end)

	-- c0436 fix round: lesson checks and old-id reads
	local LESSON =
		"---\ntitle: T\nwhen: both\ntags: [wiring]\ncheck: Is it pinned?\nfrom: a user\n---\nBody.\n"
	local BUILD = "---\ntitle: T\nwhen: build\ntags: [wiring]\ncheck: Is it pinned?\n---\nBody.\n"
	local function treeOf(files: { [string]: string }, harvest: string?): lessons.Tree
		return {
			lessons = files,
			found = {},
			skills = {
				["z-idea"] = true,
				["z-ticket"] = true,
				["z-code"] = true,
				["z-run"] = true,
				["z-design"] = true,
			},
			items = if harvest then { { id = "R0010", reviews = {}, harvest = harvest } } else {},
			problems = {},
		}
	end
	local function anyHas(problems: { string }, needle: string): boolean
		for _, p in problems do
			if has(p, needle) then
				return true
			end
		end
		return false
	end

	it("a lesson filed under an alias folder is refused, whatever else the tree holds", function()
		local alone = lessons.check(treeOf({ ["z-ticket/b"] = LESSON }))
		t.expect(anyHas(alone, "z-ticket/b is filed under z-ticket, an alias of z-idea")).toBe(true)
		local both = lessons.check(
			treeOf(
				{ ["z-ticket/b"] = LESSON, ["z-idea/b"] = BUILD },
				"- note a capture erred (erred z-ticket): z-ticket/b\n"
			)
		)
		t.expect(#both > 0).toBe(true)
		t.expect(anyHas(both, "an alias of z-idea")).toBe(true)
	end)

	it(
		"an old id read as the moved lesson is judged on that lesson, and an alias is not the other skill",
		function()
			-- a `when: build` lesson named by its old id under a design step fails
			local build = lessons.check(
				treeOf({ ["z-idea/b"] = BUILD }, "- note a capture erred (erred z-ticket): z-ticket/b\n")
			)
			t.expect(anyHas(build, "z-idea/b is when: build")).toBe(true)
			-- z-ticket (z-idea) is not z-code
			local wrong = lessons.check(
				treeOf({ ["z-code/x"] = LESSON }, "- note a capture erred (erred z-ticket): z-code/x\n")
			)
			t.expect(anyHas(wrong, "lesson z-code/x is filed under z-code, which the line does not name"))
				.toBe(true)
		end
	)

	it("a lesson id of the oldest skill name is found under the skill's newest name", function()
		local OLD = "make" .. "-issue" -- the oldest name of z-idea, which c0115's absence guard keeps out of live files
		local found = skills.oldLessonIds(`see {OLD}/split-it here`, { ["z-idea/split-it"] = true })
		t.expect(#found).toBe(1)
		t.expect(found[1].new).toBe("z-idea")
		local text, n = skills.renameLessonIds(`see {OLD}/split-it here`, { ["z-idea/split-it"] = true })
		t.expect(text).toBe("see z-idea/split-it here")
		t.expect(n).toBe(1)
		local ledger = lessons.renameLedger(
			`- note a capture erred (erred {OLD}): {OLD}/split-it\n`,
			{ ["z-idea/split-it"] = true }
		)
		t.expect(ledger).toBe("- note a capture erred (erred z-idea): z-idea/split-it\n")
	end)

	it("no live file names a moved skill's lesson by its old id", function()
		local ids: { [string]: boolean } = {}
		for _, dir in { "z-idea", "z-code" } do
			local path = `{TOP}/z-nile/skills/{dir}/lessons`
			if fs.isDir(path) then
				for _, f in fs.readDir(path) do
					ids[`{dir}/{string.gsub(f, "%.md$", "")}`] = true
				end
			end
		end
		local hits: { string } = {}
		local listing = process.exec("git", { "ls-files" }, { cwd = TOP }).stdout
		for file in string.gmatch(listing, "[^\n]+") do
			local live = not string.find(file, "%.tracker/")
				and not string.find(file, "^z%-nile/tests/")
				and file ~= "z-nile/engine/skills.luau"
				and file ~= "z-nile/engine/lessons.luau"
				and (
					string.match(file, "%.md$")
					or string.match(file, "%.luau$")
					or string.match(file, "%.html$")
				)
			if live and fs.isFile(`{TOP}/{file}`) then
				local text = fs.readFile(`{TOP}/{file}`)
				for old, new in skills.MOVED do
					for slug in string.gmatch(text, old .. "/([%w][%w%-]*)") do
						if ids[`{new}/{slug}`] then
							table.insert(hits, `{file}: {old}/{slug}`)
						end
					end
				end
			end
		end
		t.expect(hits).toEqual({})
	end)

	it(
		"a skill folder that is an alias is the only kind the lessons docs specs skip, and it is thin",
		function()
			for old in skills.MOVED do
				local alias = read(`z-nile/skills/{old}/SKILL.md`)
				t.expect(select(2, string.gsub(alias, "\n", "\n")) < 12).toBe(true)
				t.expect((string.find(alias, "\n## ", 1, true))).toBe(nil)
				t.expect(has(alias, "is the only place the old name stays")).toBe(false)
			end
		end
	)

	it("the watch file of this spec names the board and dispatcher it covers", function()
		local watch = read("z-nile/tests/tooling/skill-renames.watch.txt")
		t.expect(has(watch, "z-nile/engine/boardview.luau\n")).toBe(true)
		t.expect(has(watch, "z-nile/engine/dispatcher.luau\n")).toBe(true)
	end)

	it("dispatch reads the one table of renames", function()
		t.expect(dispatch.skillName("z-ticket")).toBe(skills.MOVED["z-ticket"])
		t.expect(dispatch.skillName("z-run")).toBe(skills.MOVED["z-run"])
		t.expect((dispatch :: any).SKILL_OF).toBe(nil)
	end)
end)
