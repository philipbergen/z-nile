--!strict
-- c0306 AC9: zz-review, z-design, z-raft, zz-execute and zz-rules each carry a "Review models" paragraph that states
-- the four review kinds, the stamped record (Model: and Effort:), the --model and --effort record lines and the three
-- refusals (prepared, ready and work next, done), and no skill says `on Opus 5.5`.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function skill(name: string): string
	return fs.readFile(`{TOP}/z-nile/skills/{name}/SKILL.md`)
end

-- The paragraph that opens with `**Review models.**` (to the end of its line, or of its list item).
local function paragraph(text: string, where: string): string
	local a = string.find(text, "**Review models.**", 1, true)
	if not a then
		error(`{where} has no "**Review models.**" paragraph`, 2)
	end
	local b = string.find(text, "\n", a :: number, true)
	return string.sub(text, a :: number, (b or #text + 1) - 1)
end

local function at(text: string, needle: string, where: string)
	if not string.find(text, needle, 1, true) then
		error(`{where} does not say: {needle}`, 2)
	end
end

local SKILLS = { "zz-review", "z-design", "z-raft", "zz-execute", "zz-rules" }

return t.spec("c0306 docs", function(it)
	it("AC9: each of the five skills states the four review kinds", function()
		for _, name in SKILLS do
			local p = paragraph(skill(name), name)
			for _, needle in { "`claude-opus-`", "`claude-fable-`", "`kimi-code-k3`", "`grok-`", "`xhigh`" } do
				at(p, needle, `{name} Review models`)
			end
		end
	end)

	it("AC9: each states the stamped record and the --model and --effort record lines", function()
		for _, name in SKILLS do
			local p = paragraph(skill(name), name)
			for _, needle in
				{
					"`Model: <id>`",
					"`Effort: <level>`",
					"first 12 lines",
					"reviewer never writes them",
					"./zn spend",
					"--phase design-review --note design-review-NNN --model <id> --effort <level>",
					"./zn commit",
					"--phase code-review --model <id> --effort <level>",
				}
			do
				at(p, needle, `{name} Review models`)
			end
		end
	end)

	it("AC9: each states the three refusals and the mark that scopes them", function()
		for _, name in SKILLS do
			local p = paragraph(skill(name), name)
			for _, needle in
				{
					"`reviews: judged`",
					"./zn status <id> prepared",
					"./zn ready",
					"./zn work next",
					"./zn done",
					"stream review",
				}
			do
				at(p, needle, `{name} Review models`)
			end
		end
	end)

	it(
		"AC9: zz-rules lists the mark among the Items front matter and zz-review says the reviewer never writes the record",
		function()
			local rules = skill("zz-rules")
			at(rules, "`reviews: judged`", "zz-rules")
			local review = skill("zz-review")
			at(review, "The reviewer never writes the `Model:` and `Effort:` lines", "zz-review")
		end
	)

	it("AC9: no skill, z-nile's or a project's, says `on Opus 5.5`", function()
		local roots = { `{TOP}/z-nile/skills` }
		local reg = fs.readFile(`{TOP}/z-nile/projects.toml`)
		for name in string.gmatch(reg, '\nname = "([%w%-]+)"') do
			table.insert(roots, `{TOP}/{name}/skills`)
		end
		local seen = 0
		for _, root in roots do
			if not fs.isDir(root) then
				continue
			end
			for _, name in fs.readDir(root) do
				local file = `{root}/{name}/SKILL.md`
				if fs.isFile(file) then
					seen += 1
					local text = fs.readFile(file)
					if
						string.find(text, "on Opus 5.5", 1, true)
						or string.find(text, "on **Opus 5.5**", 1, true)
					then
						error(`{file} still says on Opus 5.5`)
					end
				end
			end
		end
		t.expect(seen > 10).toBe(true)
	end)
end)
