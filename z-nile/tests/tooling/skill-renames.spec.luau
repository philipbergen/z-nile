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
end)
