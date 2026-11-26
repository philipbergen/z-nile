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
		t.expect(has(s, "**Risk.** Set `risk:` in the frontmatter as the first step of design")).toBe(true)
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

	it("the sentences a reviewer could remove unnoticed are pinned (F14)", function()
		local review = skill("zz-review")
		t.expect(
			has(
				review,
				"Round 1 reviews everything. Round N+1 is given the previous round's findings and the answers"
			)
		).toBe(true)
		t.expect(
			has(
				review,
				"it raises a new finding only for a defect in those changes or one it can show round 1 could not have seen: a later round only checks the answers."
			)
		).toBe(true)
		t.expect(
			has(review, "A round the item's maximum does not allow is refused, before any reviewer starts")
		)
			.toBe(true)
		t.expect(
			has(
				review,
				"Between rounds the author answers every finding in the refute file and nothing goes to the human"
			)
		).toBe(true)
		local design = skill("z-design")
		t.expect(has(design, "each round is the next number")).toBe(true)
		t.expect(has(design, "a round the maximum does not allow is refused before the reviewer starts"))
			.toBe(true)
		t.expect(has(design, "A further round is due only after a high, medium or untagged finding"))
			.toBe(true)
		t.expect(
			has(design, "every finding gets a line, fixed or refuted, also when the fix is in the document")
		)
			.toBe(true)
		t.expect(
			has(
				design,
				"Between rounds the author answers every finding in the refute file and nothing goes to the human"
			)
		).toBe(true)
		t.expect(has(design, "`- design-review-002 F2: ...`")).toBe(true)
		t.expect(has(design, "`./zn rounds <id> [--kind design]`")).toBe(true)
		t.expect(has(design, "`./zn guess <id> --step design`")).toBe(true)
		local execute = skill("zz-execute")
		t.expect(has(execute, "Between rounds the author answers every finding in the refute file"))
			.toBe(true)
		t.expect(has(execute, "`- review-002 F2: ...`")).toBe(true)
		t.expect(has(execute, "`./zn guess <id> --step build`")).toBe(true)
		t.expect(has(execute, "`./zn rounds <R-id> [--kind code|final]`")).toBe(true)
		local rules = skill("zz-rules")
		t.expect(
			has(
				rules,
				"challenges up to `[rounds]` `idea` times, one `idea-review-NNN.md` and `idea-refute-NNN.md` per round"
			)
		).toBe(true)
		t.expect(has(rules, "The table is optional")).toBe(true)
		t.expect(has(skill("z-idea"), "challenges up to `[rounds]` `idea` times")).toBe(true)
		t.expect(has(skill("z-idea"), "challenges once")).toBe(false)
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
