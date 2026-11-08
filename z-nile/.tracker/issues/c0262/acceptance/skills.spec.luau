--!strict
-- c0262 AC5: the skills state the final review. Reads the checkout's own texts.
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

return t.spec("c0262 AC5 the skills state the final review", function(it)
	it("AC5: zz-review, zz-execute and zz-rules state the final review", function()
		local review = read("z-nile/skills/zz-review/SKILL.md")
		at(review, "## Final mode (from zz-execute Phase 4B)", "zz-review")
		at(review, "Off course:", "zz-review")
		at(review, "`./zn final-view <issue> --out <folder>`", "zz-review")
		local exec = read("z-nile/skills/zz-execute/SKILL.md")
		at(exec, "## Phase 4B: Final review, one per ticket, limited view", "zz-execute")
		at(exec, "./zn dispatch zz-review <issue> --mode final", "zz-execute")
		at(exec, "`final-refute-<issue>-NNN.md`", "zz-execute")
		at(exec, "BLOCKED", "zz-execute")
		at(exec, "go to Phase 4B", "zz-execute Phase 4")
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		at(rules, "(modes `design`, `raft`, `code`, `stream` and `final`)", "zz-rules Dispatch")
		at(rules, "`./zn done` also needs", "zz-rules Merging")
	end)
end)
