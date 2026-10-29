--!strict
-- c0166 AC6: the briefs name the filtered command and the five-round note, and the note is on the approve path.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(path: string): string
	return fs.readFile(`{TOP}/{path}`)
end

local function at(text: string, needle: string): number
	local i = string.find(text, needle, 1, true)
	if not i then
		error(`missing {needle}`, 2)
	end
	return i
end

local function section(text: string, heading: string): string
	local start = string.find(text, heading, 1, true)
	if not start then
		error(`no section {heading}`, 2)
	end
	local rest = string.sub(text, start + #heading)
	local nextAt = string.find(rest, "\n## ", 1, true)
	local stop = if nextAt then start + #heading + nextAt - 1 else #text
	return string.sub(text, start, stop)
end

return t.spec("c0166 briefs", function(it)
	it("the author's lessons pass names the filtered command and the five-round note", function()
		local text = read("z-nile/skills/z-design/SKILL.md")
		local s5 = section(text, "## 5. Adversarial design review")
		t.expect(at(s5, "./zn lessons --when design --full --for <id>") < at(s5, "`design: reviewed`"))
			.toBe(true)
		at(s5, "--mode design")
		at(s5, "./zn lessons --uncovered <id>")
		at(s5, "./zn lessons --stale")
		at(s5, "lesson-areas.md")
		at(s5, "same commit changes that lesson's check line")
		at(s5, "./zn lessons --rounds <id>")
		at(s5, "including when the verdict is approve")
		at(s5, "The crossing commit changes each named existing lesson's check line, or names a new lesson.")
		at(s5, "the skill that made the mistake")
	end)

	it("design, code, raft and stream briefs name the command", function()
		local text = read("z-nile/skills/zz-review/SKILL.md")
		local design = section(text, "## Design mode")
		at(design, "./zn lessons --when design --full --for <id> --mode design")
		at(design, "lessons --when design --full")
		local code = section(text, "## Code mode")
		at(code, "./zn lessons --when build --full --for <id> --diff")
		at(code, "--mode code")
		at(code, "lessons --when build")
		at(section(text, "## Raft mode"), "./zn lessons --when design --full --for <R-id> --mode raft")
		at(
			section(text, "## Stream mode"),
			"./zn lessons --when build --full --for <issue> --diff --mode stream"
		)
	end)

	it("ready, the prompt template and the lessons row keep their pins", function()
		local ready = read("z-nile/skills/z-ready/SKILL.md")
		at(ready, "build lessons")
		at(ready, "./zn lessons --when build --for <R-id>")
		at(ready, "--mode code")
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		at(rules, "\n| lessons | `./zn lessons")
		at(rules, "--for")
		at(rules, "--paths")
		at(rules, "--diff")
		at(rules, "--rounds")
		at(rules, "--mode")
		at(rules, "--stale")
		at(rules, "lesson-areas.md")
		at(rules, "paths:")
		local prompt = read("z-nile/templates/prompt.md")
		t.expect(at(prompt, "\n## Lessons") < at(prompt, "{{LESSONS}}")).toBe(true)
		t.expect(at(prompt, "{{LESSONS}}") < at(prompt, "\n## Work items")).toBe(true)
		at(prompt, "./zn lessons --when build --for")
	end)

	it("before the approve shortcut", function()
		local text = read("z-nile/skills/zz-execute/SKILL.md")
		local p4 = section(text, "## Phase 4")
		t.expect(
			at(
				p4,
				"When the raft folder's own design-round count, its own code-round count, or one member's own design-round count reaches 5"
			) < at(p4, "go to Phase 5")
		).toBe(true)
		at(p4, "the skill that made the mistake")
		at(p4, "The crossing commit changes each named existing lesson's check line, or names a new lesson.")
		at(p4, "same commit changes that lesson's check line")
		local raft = section(read("z-nile/skills/z-raft/SKILL.md"), "## 4. Coherence review")
		at(raft, "./zn lessons --rounds <R-id>")
		at(raft, "including when the verdict is approve")
		at(
			raft,
			"The crossing commit changes each named existing lesson's check line, or names a new lesson."
		)
		at(raft, "the skill that made the mistake")
	end)

	it("every skill that adds a note to an existing lesson points to the rewrite rule in zz-rules", function()
		local rules = read("z-nile/skills/zz-rules/SKILL.md")
		at(rules, "a later source of an existing lesson changes that lesson's check line in the same commit")
		local count = 0
		for _, base in { "z-nile/skills", "pickman/skills" } do
			for _, name in fs.readDir(`{TOP}/{base}`) do
				local path = `{base}/{name}/SKILL.md`
				if fs.isFile(`{TOP}/{path}`) then
					local text = read(path)
					if string.find(text, "adds a note to an existing lesson", 1, true) then
						at(text, "(zz-rules: a later source changes the check)")
						count += 1
					end
				end
			end
		end
		t.expect(count >= 14).toBe(true)
		local exec = read("z-nile/skills/zz-execute/SKILL.md")
		at(section(exec, "## Phase 2B"), "(zz-rules: a later source changes the check)")
		at(section(exec, "## Phase 5"), "(zz-rules: a later source changes the check)")
		local design = read("z-nile/skills/z-design/SKILL.md")
		at(section(design, "5. **Confirm the harvest**:"), "(zz-rules: a later source changes the check)")
	end)

	it("zz-stats names the recurrence and five-round reports", function()
		local text = read("z-nile/skills/zz-stats/SKILL.md")
		at(text, "Lesson recurrence")
		at(text, "Review rounds at 5")
		at(text, "unchanged")
		at(text, "since check")
		at(text, "missing")
	end)
end)
