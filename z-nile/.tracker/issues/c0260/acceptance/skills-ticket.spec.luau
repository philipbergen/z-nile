--!strict
-- c0260 AC1: z-ticket describes the interview, the clean idea, the review and the confirmation. Shape rules over its text:
-- the order of its steps and what each says (the exact wording is not pinned: the skill can be reworded and stay green;
-- a step that moves or goes does not).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local SKILL = fs.readFile(`{ROOT}/z-nile/skills/z-ticket/SKILL.md`)
local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end
-- The text of "## <title>" up to the next "## " heading (a heading inside a ```` fence is not one).
local function section(title: string): string
	local from = string.find(SKILL, `\n## {title}`, 1, true)
	if from == nil then
		error(`no section "{title}"`, 0)
	end
	local rest = string.sub(SKILL, from + 1)
	local to = string.find(rest, "\n## Headless", 4, true) or #rest
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

return t.spec("c0260 z-ticket describes the interview, the review and the confirmation", function(it)
	it(
		"AC1: the existing steps keep their numbers, labels and pinned sentences (c0135 and c0247 pin 'step 5')",
		function()
			for _, pinned in
				{
					"\n0. **Open a capture worktree first**",
					"\n1. **Classify the work**",
					"\n2. **Create it**",
					"\n3. **Fill in the frontmatter**",
					"\n4. **Fill in only these sections**",
					"\n5. **Duplicates**",
					"\n6. **Land it.**",
					"Under the dispatcher, land without asking (the user started it)",
				}
			do
				t.expect(has(SKILL, pinned)).toBe(true)
			end
		end
	)

	it(
		"AC1: the new steps run ask, interview, classify, create, clean idea, review, confirm, land in that order",
		function()
			local s = steps()
			local want: { { n: string, text: string } } = {
				{ n = "0a", text = "verbatim" },
				{ n = "0b", text = "Interview the user" },
				{ n = "1", text = "Classify the work" },
				{ n = "2", text = "./zn new issue" },
				{ n = "3a", text = "## Idea" },
				{ n = "4a", text = "./zn dispatch zz-review <id> --mode idea" },
				{ n = "4b", text = "confirm" },
				{ n = "6", text = "./zn land" },
			}
			for _, w in want do
				t.expect(s[w.n] ~= nil and has(s[w.n], w.text)).toBe(true)
			end
			-- the order of every label in the file
			local seen = {}
			for label in
				string.gmatch(
					string.sub(SKILL, 1, string.find(SKILL, "\n## The capture record", 1, true) :: number),
					"\n(%d+%l?)%. "
				)
			do
				table.insert(seen, label)
			end
			t.expect(table.concat(seen, ",")).toBe("0,0a,0b,1,2,2a,3,3a,4,4a,4b,5,6")
		end
	)

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
		"AC1: the review is a clean reviewer on the z-ticket-review activity's model, seeing three sections, answered before the user sees the idea",
		function()
			local s = steps()
			t.expect(has(s["4a"], "7200000")).toBe(true)
			t.expect(has(s["4a"], "z-ticket-review")).toBe(true)
			t.expect(has(s["4a"], "only `## Ask (verbatim)`, `## Interview` and `## Idea`")).toBe(true)
			t.expect(has(s["4a"], "Do not review the idea yourself")).toBe(true)
			t.expect(has(s["4a"], "before the user sees the idea")).toBe(true)
			t.expect(has(s["4a"], 'model: "opus"')).toBe(true) -- the interactive form, where the dispatcher cannot run
			t.expect(has(s["4a"], "--note idea-review-NNN")).toBe(true)
			t.expect(has(s["4a"], "At most three rounds")).toBe(true)
		end
	)

	it(
		"AC1: only the user's confirmation ends the capture; a change they ask for gets one more round; no tier word anywhere",
		function()
			local s = steps()
			t.expect(has(s["4b"], "Only the user's confirmation ends the capture")).toBe(true)
			t.expect(has(s["4b"], "one more round")).toBe(true)
			t.expect(has(s["4b"], "asked as Qn")).toBe(true)
			t.expect((string.find(string.lower(SKILL), "sharp tier", 1, true))).toBe(nil)
		end
	)

	it(
		"AC1: a dispatched capture does not stop, records the interview and confirmation as unattended and leaves the real one to z-design",
		function()
			local h = section("A capture under the dispatcher")
			t.expect(has(h, "Keep headless, confirm later")).toBe(true)
			t.expect(has(h, "does not stop for the user")).toBe(true)
			t.expect(has(h, "`### Q1`")).toBe(true) -- the restatement and its reply are the interview a dispatched capture holds
			t.expect(has(h, "Unconfirmed (unattended")).toBe(true)
			t.expect(has(h, "you never write `Confirmed`")).toBe(true)
			t.expect(has(h, "z-design confirms with the user before it designs")).toBe(true)
		end
	)

	it(
		"AC9: z-ticket says what an agent filing a ticket does: the marker section, the source and the scope decision line",
		function()
			local r = section("The capture record")
			t.expect(has(r, "## Filed by (agent)")).toBe(true)
			t.expect(has(r, "Source:")).toBe(true)
			t.expect(has(r, "Scope decision (user, 2026-11-08)")).toBe(true)
			t.expect(has(r, "cannot claim the exemption")).toBe(true)
		end
	)

	it("AC1: the restatement and its approval are Q1, the plan-mode messages are copied into the ask", function()
		local s = steps()
		t.expect(has(s["0b"], "`### Q1`")).toBe(true)
		t.expect(has(s["0b"], "the restatement as shown")).toBe(true)
		t.expect(has(s["0b"], "dispatch retry")).toBe(true)
		t.expect(has(s["0a"], "plan file")).toBe(true)
		t.expect(has(s["0a"], "each dated")).toBe(true)
	end)

	it("AC1: every `step N` reference in z-ticket and zz-review names a step that exists", function()
		local labels: { [string]: boolean } = {}
		for label in string.gmatch(SKILL, "\n(%d+%l?)%. ") do
			labels[label] = true
		end
		for ref in string.gmatch(SKILL, "[%(%s]step (%d+%l?)[%s%),.;:]") do
			t.expect(labels[ref] == true).toBe(true)
		end
		local review = fs.readFile(`{ROOT}/z-nile/skills/zz-review/SKILL.md`)
		for ref in string.gmatch(review, "z%-ticket step (%d+%l?)") do
			t.expect(labels[ref] == true).toBe(true)
		end
	end)

	it(
		"AC9: every skill's lesson-filing line passes --filed-by <source>, and the source is explained once in zz-rules",
		function()
			local bad = {}
			for _, dir in { "z-nile", "pickman", "arcade", "portal", "snake", "invaders", "asteroids" } do
				for _, skill in fs.readDir(`{ROOT}/{dir}/skills`) do
					local path = `{ROOT}/{dir}/skills/{skill}/SKILL.md`
					if fs.isFile(path) then
						local text = fs.readFile(path)
						if string.find(text, "new issue c lesson-<slug> --project z-nile --desc", 1, true) then
							table.insert(bad, path)
						end
					end
				end
			end
			t.expect(table.concat(bad, "\n")).toBe("")
			local rules = fs.readFile(`{ROOT}/z-nile/skills/zz-rules/SKILL.md`)
			t.expect(has(rules, "--filed-by <source>")).toBe(true)
			t.expect(has(rules, "review:<item id>/<review file> F<n>")).toBe(true)
			t.expect(has(rules, "lesson:<skill>/<slug>")).toBe(true)
			t.expect(has(rules, "agent:<item id>/<slug>")).toBe(true)
		end
	)
end)
