--!strict
-- c0291 AC4: zz-rules (Items) states where a note goes, that notes merge, what --check refuses, and that an edit of a
-- lesson's own rule or check still conflicts. Reads the skill only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function items(): string
	local text = fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
	local a = string.find(text, "\n## Items\n", 1, true)
	local b = a and string.find(text, "\n## ", (a :: number) + 1, true)
	if not a or not b then
		error("zz-rules has no Items section")
	end
	return string.sub(text, a :: number, b :: number)
end

local function at(text: string, needle: string)
	if not string.find(text, needle, 1, true) then
		error(`zz-rules Items does not say: {needle}`, 2)
	end
end

local OLD = "It adds a note to an existing lesson when one fits, writes a new file only when none does"
local NEW = "It adds a note to an existing lesson when one fits (a file of its own in the lesson's notes folder, never a "
	.. "paragraph at the end of its file: zz-rules skill, Items), writes a new lesson only when none does, and commits "
	.. "both with its work."

-- every skill's SKILL.md, through the one reader of the skills folders (as c0111's skill-docs spec walks them)
local function skillDocs(): { string }
	local out: { string } = {}
	for _, folder in skills.folders(projects.load(TOP)) do
		local base = `{TOP}/{folder.path}`
		if fs.isDir(base) then
			local names = fs.readDir(base)
			table.sort(names)
			for _, name in names do
				if fs.isFile(`{base}/{name}/SKILL.md`) then
					table.insert(out, `{folder.path}/{name}/SKILL.md`)
				end
			end
		end
	end
	return out
end

-- the `## Lessons` section of a skill's text, up to the next `## ` heading
local function lessonsSection(text: string): string?
	local a = string.find(text, "\n## Lessons\n", 1, true)
	if not a then
		return nil
	end
	local b = string.find(text, "\n## ", (a :: number) + 1, true)
	return string.sub(text, a :: number, if b then b - 1 else #text)
end

return t.spec("c0291 lesson notes docs", function(it)
	it("AC4: Items says a note is its own file, never a paragraph at the end of the lesson", function()
		local s = items()
		at(s, "- **Lesson notes**: a note added to an existing lesson")
		at(s, "is a file of its own, `<skills folder>/<skill>/lessons/<slug>/<YYYY-MM-DD>-<label>.md`")
		at(s, "never a paragraph added to the end of `<slug>.md`")
		at(s, "so they merge without a conflict and keep both")
	end)

	it(
		"AC4: Items says how notes are read and checked, and that an edit of the rule or check still conflicts",
		function()
			local s = items()
			at(
				s,
				"`./zn lessons` reads a lesson's notes after its file, in name order (oldest first), and searches them"
			)
			at(s, "`--full` prints them after the file, under the file's path: the note files are the record")
			at(s, "`--check` refuses a notes folder with no lesson, a file in it not named that way, and an empty note")
			at(
				s,
				"An edit to the lesson's rule, `check` or other frontmatter is still an edit of `<slug>.md`, and two such edits still conflict"
			)
		end
	)

	it(
		"AC4: every skill's Lessons paragraph says a note is a file in the lesson's notes folder, and none keeps the old sentence",
		function()
			local n = 0
			for _, rel in skillDocs() do
				local section = lessonsSection(fs.readFile(`{TOP}/{rel}`))
				if section and string.find(section, "**The lead of a prep or raft**", 1, true) then
					n += 1
					if not string.find(section, NEW, 1, true) then
						error(`{rel}: its Lessons paragraph does not say: {NEW}`)
					end
				end
				if section and string.find(section, OLD, 1, true) then
					error(`{rel}: its Lessons paragraph still says: {OLD}`)
				end
			end
			t.expect(n >= 25).toBe(true)
		end
	)
end)
