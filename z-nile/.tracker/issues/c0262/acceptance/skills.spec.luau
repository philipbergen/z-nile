--!strict
-- c0262 AC6: the skills state the final review. Reads the checkout's own texts.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function at(text: string, needle: string, where: string)
	if not has(text, needle) then
		error(`{where} is missing: {needle}`, 0)
	end
end

return t.spec("c0262 AC6 the skills state the final review", function(it)
	it("AC6: zz-review, zz-execute and zz-rules state the final review and what a failed one does", function()
		local review = read("z-nile/skills/zz-review/SKILL.md")
		at(review, "## Final mode (from zz-execute Phase 4B)", "zz-review")
		at(review, "Off course:", "zz-review")
		at(review, "`./zn final-view <issue> --out <folder>`", "zz-review")
		at(review, "`--mode final` runs Final mode, from zz-execute Phase 4B", "zz-review Who reviews")
		-- c0117 pins this sentence byte for byte; it is not edited
		at(review, "`./zn dispatch zz-review <id> --mode design|raft|code|stream`", "zz-review Who reviews")
		local exec = read("z-nile/skills/zz-execute/SKILL.md")
		at(exec, "## Phase 4B: Final review, one per ticket, limited view", "zz-execute")
		at(exec, "./zn dispatch zz-review <issue> --mode final", "zz-execute")
		at(exec, "go to Phase 4B", "zz-execute Phase 4")
		at(exec, "a final review that does not approve is BLOCKED", "zz-execute Phase 4B")
		at(exec, "a new round", "zz-execute Phase 4B")
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		at(rules, "(modes `design`, `raft`, `code`, `stream` and `final`)", "zz-rules Dispatch")
		at(rules, "`./zn done` also needs", "zz-rules Merging")
		at(read("z-nile/templates/prompt.md"), "final review", "the prompt template")
	end)
end)
