--!strict
-- c0458 AC3 (docs): the skills say the new rules. Rule-shaped pins: names and headings, not whole sections.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

return t.spec("c0458: the skills carry the collapsed reviews", function(it)
	it(
		"AC3: zz-review keeps every Code check under a `## Code mode` heading, has no Stream mode, and Final mode applies the checks to every raft",
		function()
			local text = read("z-nile/skills/zz-review/SKILL.md")
			t.expect(has(text, "## Stream mode")).toBe(false)
			local code = string.find(text, "\n## Code mode", 1, true)
			local final = string.find(text, "\n## Final mode", 1, true)
			t.expect(code ~= nil and final ~= nil and (code :: number) < (final :: number)).toBe(true)
			local section = string.sub(text, code :: number, final :: number)
			for _, name in
				{
					"**Correctness**",
					"**Sequestration**",
					"**Weak tests**",
					"**Design adherence**",
					"**Architecture rules**",
					"**Performance**",
					"**Judged criteria**",
					"**Repository safety**",
					"**Everything in the first round**",
					"**Lessons**",
					"**A ruling line in the diff**",
					"**Bounded commands**",
					"Overrides check",
				}
			do
				t.expect(has(section, name)).toBe(true)
			end
			t.expect(has(section, "one layer")).toBe(false)
			local finalText = string.sub(text, final :: number)
			t.expect(has(finalText, "ONLY review")).toBe(false)
			t.expect(has(finalText, "Level: <ticket> <level>")).toBe(true)
			t.expect(
				has(finalText, "applies the Code mode checks to `git diff origin/main...HEAD` for every raft")
			)
				.toBe(true)
		end
	)

	it(
		"AC3: z-design requires a passing design review only for a risky ticket, and no skill names the removed modes or the removed engine answers",
		function()
			local design = read("z-nile/skills/z-design/SKILL.md")
			t.expect(has(design, "A passing design review is required only for a `risk: risky` ticket"))
				.toBe(true)
			t.expect(has(design, "`ready` refuses an easy ticket with no design review")).toBe(false)
			t.expect(has(design, "answers `draft` for it")).toBe(false)
			-- every skill, the README and AGENTS.md: no `--mode <list>` names code or stream, in any order or spelling
			local paths: { string } = { "z-nile/README.md", "AGENTS.md" }
			for _, name in fs.readDir(`{TOP}/z-nile/skills`) do
				if fs.isFile(`{TOP}/z-nile/skills/{name}/SKILL.md`) then
					table.insert(paths, `z-nile/skills/{name}/SKILL.md`)
				end
			end
			for _, path in paths do
				local text = read(path)
				for list in string.gmatch(text, "%-%-mode ([%w|]+)") do
					for part in string.gmatch(list, "[^|]+") do
						t.expect(`{path}: --mode {part}`).toBe(
							if part == "code" or part == "stream"
								then `{path}: gone`
								else `{path}: --mode {part}`
						)
					end
				end
				t.expect(has(text, "./zn model code-review")).toBe(false)
				t.expect(has(text, "2, 5 and 9")).toBe(false)
			end
		end
	)
end)
