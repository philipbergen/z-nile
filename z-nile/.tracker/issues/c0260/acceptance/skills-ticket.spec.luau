--!strict
-- c0260 AC1/AC9: z-ticket describes the record, the interview and the confirmation. Shape rules over its text: the
-- order of its steps and what each says (the exact wording is not pinned: the skill can be reworded and stay green; a
-- step that moves or goes does not).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local SKILL = fs.readFile(`{ROOT}/z-nile/skills/z-ticket/SKILL.md`)
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
local function section(title: string): string
	local from = string.find(SKILL, `\n## {title}`, 1, true)
	if from == nil then
		error(`no section "{title}"`, 0)
	end
	local rest = string.sub(SKILL, from + 1)
	local to = string.find(rest, "\n## A capture under", 4, true)
		or string.find(rest, "\n## Headless", 4, true)
		or #rest
	return string.sub(rest, 1, to)
end
-- The numbered steps (before "## The capture record"): label ("0", "0a", "4b"...) -> its text.
local function steps(): { [string]: string }
	local out: { [string]: string } = {}
	local cur: string? = nil
	local main = string.sub(SKILL, 1, string.find(SKILL, "\n## The capture record", 1, true) :: number)
	for line in string.gmatch(main, "[^\n]*") do
		local n = string.match(line, "^(%d+%l?)%. ")
		if n then
			cur = n
			out[n] = line .. "\n"
		elseif cur then
			out[cur] ..= line .. "\n"
		end
	end
	return out
end

return t.spec("c0260 z-ticket describes the record, the interview and the confirmation", function(it)
	it("AC1: the existing steps keep their numbers, labels and pinned sentences", function()
		for _, pinned in
			{
				"\n0. **Open a capture worktree first**",
				"\n1. **Classify the work**",
				"\n2. **Create the shell**",
				"\n3. **Fill in the frontmatter**",
				"\n4. **Write the idea**: `./zn idea <id> --text",
				"\n5. **Duplicates**",
				"\n6. **Land it.**",
				"Under the dispatcher, land without asking (the user started it)",
			}
		do
			t.expect(has(SKILL, pinned)).toBe(true)
		end
	end)

	it("AC1: the new steps are sub-steps in order: ask, interview, record, show, confirm", function()
		local seen = {}
		for label in
			string.gmatch(
				string.sub(SKILL, 1, string.find(SKILL, "\n## The capture record", 1, true) :: number),
				"\n(%d+%l?)%. "
			)
		do
			table.insert(seen, label)
		end
		t.expect(table.concat(seen, ",")).toBe("0,0a,0b,1,2,2a,3,4,4a,4b,5,6")
		local s = steps()
		t.expect(has(s["2a"], "./zn idea <id> --record")).toBe(true)
		t.expect(has(s["4a"], "idea-review-NNN.md")).toBe(true)
		t.expect(has(s["4a"], "dropped, added or bent")).toBe(true)
		t.expect(has(s["4a"], "the next round")).toBe(false) -- a run after a change numbers on; there is no "next round" file name
		t.expect(has(s["4b"], '--confirm "<their words>"')).toBe(true)
		t.expect(has(s["4b"], "Only the user confirms")).toBe(true)
		t.expect(has(s["4a"], "as the next `### Qn` of the Interview")).toBe(true) -- a round rewrites the idea whole; the words are kept
		t.expect(has(s["4a"], "Step 4 is round 1")).toBe(true)
		t.expect(has(s["4a"], "Where step 4 says the command challenges once and names `-001`, it now loops"))
			.toBe(true)
		t.expect(has(s["4a"], "never followed by a revision")).toBe(true)
		t.expect(has(s["4a"], "(7200000 ms)")).toBe(true) -- the long Bash timeout of a command that makes up to six model calls
		t.expect(has(s["4a"], "beats into the step's folder")).toBe(true)
		t.expect(has(s["4a"], "the passes already written stay and a rerun numbers on")).toBe(true)
		t.expect(has(s["4a"], "`idea-review-003.md`")).toBe(true) -- after a first loop of two passes
		t.expect(has(s["4a"], "Ask the user each `ask:` question")).toBe(true)
		t.expect(has(s["4b"], "--unattended")).toBe(true)
	end)

	it("AC1: the ask is kept verbatim and dated, the interview keeps every question and answer in order", function()
		local s = steps()
		t.expect(has(s["0a"], "every message")).toBe(true)
		t.expect(has(s["0a"], "### Message YYYY-MM-DD")).toBe(true)
		t.expect(has(s["0a"], "never edited")).toBe(true)
		t.expect(has(s["0b"], "hallenge the idea")).toBe(true)
		t.expect(has(s["0b"], "**every** question")).toBe(true)
		t.expect(has(s["0b"], "in order")).toBe(true)
		t.expect(has(s["0b"], "own words")).toBe(true)
		t.expect(has(s["0b"], "AskUserQuestion")).toBe(true)
	end)

	it(
		"AC1: a dispatched capture does not stop, records unattended and leaves the real confirmation to z-design",
		function()
			local h = section("A capture under the dispatcher")
			t.expect(has(h, "ask nothing")).toBe(true)
			t.expect(has(h, "--unattended")).toBe(true)
			t.expect(has(steps()["4b"], "z-design asks the user before it designs")).toBe(true)
			t.expect(has(steps()["4b"], "`--confirm` is refused there")).toBe(true)
		end
	)

	it("AC9: z-ticket says what an agent filing a ticket does, and how a stub is continued or recreated", function()
		local r = section("The capture record")
		t.expect(has(r, "--filed-by")).toBe(true)
		t.expect(has(r, "## Filed by (agent)")).toBe(true)
		t.expect(has(r, "`lesson:<skill>/<slug>`")).toBe(true)
		t.expect(has(r, "**A stub an agent made without `--filed-by`** cannot be exempted afterwards")).toBe(true)
		t.expect(has(r, "**A marked stub with no record yet**")).toBe(true)
		t.expect(has(r, "steps 0a to 4b")).toBe(true)
	end)

	it("AC1: the restatement and its approval are Q1, the plan-mode messages are copied into the ask", function()
		local s = steps()
		t.expect(has(s["0b"], "the next `### Qn`")).toBe(true)
		t.expect(has(s["0b"], "a correction makes a second restatement")).toBe(true)
		t.expect(has(s["0b"], "dispatch retry")).toBe(true)
		t.expect(has(s["0a"], "plan file")).toBe(true)
		-- c0260's reword of c0247's plan-file sentence (its own pin): the whole sentence
		t.expect(
			has(
				SKILL,
				"call it, write the user's messages of this request to the plan file first, verbatim and each dated, under the heading `Ask (verbatim)`, then every restatement you have shown and each reply of the user to it, in order and dated, under the heading `Restatements` (the plan file is the source of the original messages and of the whole exchange once approval clears the context), then the current restatement, ending with the line `Next: capture with the z-ticket skill, steps 0 to 6; build nothing.`"
			)
		).toBe(true)
	end)

	it("AC1: every `step N` reference in z-ticket names a step that exists", function()
		local labels: { [string]: boolean } = {}
		for label in string.gmatch(SKILL, "\n(%d+%l?)%. ") do
			labels[label] = true
		end
		for ref in string.gmatch(SKILL, "[%(%s]step (%d+%l?)[%s%),.;:]") do
			t.expect(labels[ref] == true).toBe(true)
		end
	end)

	it("AC9: every skill's lesson-filing line passes --filed-by <source>, and zz-rules explains the sources", function()
		local bad = {}
		for _, dir in { "z-nile", "pickman", "arcade", "portal", "snake", "invaders", "asteroids" } do
			for _, skill in fs.readDir(`{ROOT}/{dir}/skills`) do
				local path = `{ROOT}/{dir}/skills/{skill}/SKILL.md`
				if fs.isFile(path) then
					if string.find(fs.readFile(path), "new issue c lesson-<slug> --project z-nile --desc", 1, true) then
						table.insert(bad, path)
					end
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
		local rules = fs.readFile(`{ROOT}/z-nile/skills/zz-rules/SKILL.md`)
		t.expect(has(rules, '--filed-by "<source>"')).toBe(true)
		t.expect(has(rules, "review:<item id>/<review file> F<n>")).toBe(true)
		t.expect(has(rules, "lesson:<skill>/<slug>")).toBe(true)
		t.expect(has(rules, "agent:<item id>/<slug>")).toBe(true)
	end)
end)
