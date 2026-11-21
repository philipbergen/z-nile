--!strict
-- f0421 AC12: the skill files carry the round wording (the risk paragraph, "These are maximums", "Find everything now",
-- "Then the next round, or the human", the [rounds] bullet and "a later round only checks the answers") and none of
-- z-design, zz-review, zz-execute and zz-rules still says there is one round only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function skill(name: string): string
	return fs.readFile(`{TOP}/z-nile/skills/{name}/SKILL.md`)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("f0421: the skills describe rounds as maximums", function(it)
	it("z-design carries the risk paragraph and the maximums sentence", function()
		local s = skill("z-design")
		t.expect(has(s, "**Risk.** When the draft is complete, set `risk:` in the frontmatter")).toBe(true)
		t.expect(has(s, "a raft takes its highest member's")).toBe(true)
		t.expect(has(s, "These are maximums: the aim is one round")).toBe(true)
		t.expect(has(s, "Do not start a reviewer past the maximum")).toBe(true)
	end)

	it("zz-review and zz-execute carry the round wording", function()
		t.expect(has(skill("zz-review"), "Find everything now")).toBe(true)
		t.expect(has(skill("zz-review"), "a later round only checks the answers")).toBe(true)
		t.expect(has(skill("zz-execute"), "Then the next round, or the human")).toBe(true)
		t.expect(has(skill("zz-execute"), "a later round only checks the answers")).toBe(true)
		t.expect(has(skill("zz-execute"), "final-review-NNN.md")).toBe(true)
	end)

	it("zz-rules names the [rounds] bullet", function()
		t.expect(has(skill("zz-rules"), "`[rounds]` sets the maximum review rounds")).toBe(true)
	end)

	it("none of the four still says there is only one round", function()
		for _, name in { "z-design", "zz-review", "zz-execute", "zz-rules" } do
			local s = skill(name)
			for _, gone in { "There is no second reviewer", "This is the only round", "The one round" } do
				t.expect(has(s, gone)).toBe(false)
			end
		end
	end)
end)
