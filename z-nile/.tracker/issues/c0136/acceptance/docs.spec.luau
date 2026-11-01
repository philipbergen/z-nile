--!strict
-- c0136 AC5: the skills say where a lesson goes. Every skill's Lessons section carries one identical paragraph that
-- names the step that erred; zz-review asks the reviewer for `Erred:` and `Upstream:` on every finding and has a
-- stream and a focused mode; z-design, z-raft and zz-execute confirm `--unattributed` beside `--uncovered`; zz-rules
-- spells the step group and the two new review stems; AGENTS.md says it. This spec is promoted, so it pins the
-- rules, not today's wording: check.sh's AC5 holds the exact sentences on the day c0136 is done. Reads the real
-- files from the checkout's top (these specs run from z-nile/); writes nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end

-- the text of the `## <prefix>` section of a document, up to the next `## ` heading
local function section(text: string, prefix: string): string
	local start = string.find(text, "\n## " .. prefix, 1, true)
	if not start then
		error(`no "## {prefix}" section`, 2)
	end
	local after = string.find(text, "\n## ", start + 1, true)
	return string.sub(text, start, if after then after - 1 else #text)
end

local function at(text: string, phrase: string): number
	local i = string.find(text, phrase, 1, true)
	if not i then
		error(`missing: {phrase}`, 2)
	end
	return i
end

-- `phrase` appears in the sentence that ends with the last `anchor`: after the last ". " (or "), ") before it
local function before(text: string, anchor: string, phrase: string)
	local last: number? = nil
	local from = 1
	while true do
		local i = string.find(text, anchor, from, true)
		if not i then
			break
		end
		last = i
		from = i + 1
	end
	if not last then
		error(`missing: {anchor}`, 2)
	end
	local head = string.sub(text, 1, last - 1)
	local start = 1
	for _, mark in { ". ", "\n" } do
		local at_ = 1
		while true do
			local a, b = string.find(head, mark, at_, true)
			if not a or not b then
				break
			end
			start = math.max(start, b + 1)
			at_ = b + 1
		end
	end
	if not string.find(string.sub(head, start), phrase, 1, true) then
		error(`"{phrase}" is not in the sentence that ends "{anchor}"`, 2)
	end
end

local function skillDocs(): { string }
	local out = {}
	for _, base in { "z-nile/skills", "pickman/skills" } do
		local names = fs.readDir(`{TOP}/{base}`)
		table.sort(names)
		for _, name in names do
			if fs.isFile(`{TOP}/{base}/{name}/SKILL.md`) then
				table.insert(out, `{base}/{name}/SKILL.md`)
			end
		end
	end
	return out
end

return t.spec("c0136 the skills send a lesson to the step that erred", function(it)
	it(
		"every skill's Lessons section has the same paragraph naming the step, before its role bullets",
		function()
			local first: string? = nil
			local n = 0
			for _, rel in skillDocs() do
				local s = section(read(rel), "Lessons")
				local line = string.match(s, "\n(A lesson goes to the step that erred[^\n]*)\n")
				if not line then
					error(`{rel}: no "A lesson goes to the step that erred" paragraph in its Lessons section`)
				end
				at(line, "(erred <skill>[, upstream <skill>])")
				at(line, "`- note`")
				at(line, "`<the skill the lesson improves>`") -- the bullets below say where it is written
				t.expect(at(s, "A lesson goes to the step that erred") < at(s, "- **A subagent**")).toBe(true)
				if first == nil then
					first = line
				else
					t.expect(line).toBe(first) -- one paragraph, not fourteen variants
				end
				n += 1
			end
			t.expect(n >= 14).toBe(true)
		end
	)

	it(
		"zz-review asks for Erred and Upstream on every finding, and reviews streams and focused work",
		function()
			local text = read("z-nile/skills/zz-review/SKILL.md")
			local template = string.match(text, "```markdown\n(# Review NNN.-)```") :: string
			t.expect(at(template, "\nErred:") > at(template, "\nRecommendation:")).toBe(true)
			t.expect(at(template, "\nUpstream:") > at(template, "\nErred:")).toBe(true)
			at(text, "which step made this mistake, and which earlier step should have caught it")
			at(section(text, "Stream mode"), "`Erred:` and `Upstream:`")
			local focused = section(text, "Focused mode")
			at(focused, "focused-review-NNN.md")
			at(focused, "`./zn done` and `metrics` ignore")
			at(section(text, "Design mode"), "Check each lesson's `when:` against its origin")
			at(focused, "`- note ")
			at(text, "`./zn lessons --check-review <the file you wrote>`") -- the reviewer checks its own lines before it ends
			at(text, "Every finding of a design review is a mistake made in design") -- the c0140 outcome, for a design reviewer
			at(text, "a mistake an earlier round missed names the step that made it") -- not zz-review
			at(text, "when the mistake sits in something design wrote") -- ... and for a code reviewer: Upstream names z-design
			at(text, "A round with no step lines at all is not finished")
			at(focused, "(focused mode, design)")
			at(focused, "`./zn lessons --check-review`") -- the lead checks the reviewer's text before it writes the file
			at(focused, "the raft's during a raft's execution") -- where the file goes
			at(
				section(text, "Design mode"),
				"except a lesson filed under `zz-review` for the reviewer's own mistake"
			)
			at(text, "(folder: zz-rules skill, Items)") -- the focused review's folder has one owner
		end
	)

	it(
		"z-design, z-raft and zz-execute confirm unattributed entries where they confirm uncovered ones",
		function()
			local design = section(read("z-nile/skills/z-design/SKILL.md"), "5.")
			t.expect(at(design, "lessons --unattributed <id>") < at(design, "status <id> prepared`"))
				.toBe(true)
			at(design, "`Erred:` and `Upstream:`")
			before(design, "must all pass", "lessons --unattributed <id>")
			at(design, "`when: design` or `both`")
			at(design, "goes back to its reviewer")
			at(design, "for the reviewer's own mistake") -- the exemption is for lessons filed under zz-review
			at(design, "`./zn lessons --check-review")
			at(read("z-nile/skills/z-raft/SKILL.md"), "lessons --unattributed <R-id>")
			at(read("z-nile/skills/z-raft/SKILL.md"), "`./zn lessons --check-review`")
			local execute = read("z-nile/skills/zz-execute/SKILL.md")
			local p4 = section(execute, "Phase 4")
			at(p4, "lessons --unattributed R0010")
			at(p4, "names `Upstream: z-design`") -- a finding about something design wrote
			at(p4, "goes back to its reviewer")
			at(p4, "`./zn lessons --check-review")
			before(p4, "lessons --check", "lessons --unattributed R0010")
			local p5 = section(execute, "Phase 5")
			t.expect(at(p5, "lessons --unattributed R0010") < at(p5, "./zn done")).toBe(true)
			before(p5, "must pass", "lessons --unattributed R0010")
			local p2b = section(execute, "Phase 2B")
			at(p2b, "`- note ws-<issue> (erred <skill>): <lesson ids>`") -- a report's candidate names its step too
			at(p2b, "stream-review-<issue>-NNN F<n>") -- a stream review's findings are entries, as they arrive
			at(p2b, "goes back to its reviewer")
			at(p2b, "`./zn lessons --check-review")
			t.expect(at(p2b, "stream-review-<issue>-NNN F<n>") < at(p2b, "\n1. ")).toBe(true)
			t.expect((string.find(p2b, "- note stream-review-<issue>-NNN:", 1, true))).toBe(nil)
		end
	)

	it(
		"zz-rules spells the step group, the new stems and the command; AGENTS.md says where a lesson goes",
		function()
			local rules = read("z-nile/skills/zz-rules/SKILL.md")
			local items = section(rules, "Items")
			at(items, "(erred <skill>)")
			at(items, "(erred <skill>, upstream <skill>)")
			at(items, "`stream-review-<issue>-NNN`")
			at(items, "`focused-review-NNN`")
			at(items, "`erred none`")
			at(items, "`./zn lessons --unattributed")
			at(items, "refuses one that is not")
			at(items, "`z-ticket`, `z-design`, `z-raft`") -- the design steps
			at(items, "`when: design` or `both`")
			at(rules, "focused-review-NNN.md") -- the item folder's file list
			local row = string.match(rules, "\n(| lessons | [^\n]*)\n") :: string
			at(row, "--unattributed [<id>...]")
			at(row, "--check-review <path>")
			at(read("AGENTS.md"), "each under the step that erred")
			at(read("AGENTS.md"), "z-design, z-raft and zz-execute harvest")
			at(items, "step lines invalid") -- the waiver note for a review that cannot be edited
			at(items, "`./zn lessons --check-review <path>`")
			at(items, "the raft's during a raft's execution") -- the one owner of where a focused review goes
			at(items, "for the reviewer's own mistake")
			at(items, "- note <stem> F<n> <text>") -- a note about a finding
		end
	)
end)
