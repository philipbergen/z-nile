--!strict
-- c0316 AC1: the documents carry the statement of goals and its pointers. Reads the real files as text (read-only):
-- the README's Goals section is statement.md's statement word for word, AGENTS.md, every skill's Lessons section,
-- zz-rules, zz-review, zz-stats, z-ticket and the issue template carry their texts, and the first lesson parses.
-- statement.md is the issue's own file: beside the sequestered spec's acceptance/ folder while the issue is in the
-- backlog, in active/ or done/ after the raft starts and lands (the spec itself is promoted to tests/acceptance/c0316/).
local fs = require("@lune/fs")
local lessons = require("@znile/engine/lessons")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function at(text: string, needle: string, where: string): number
	local i = string.find(text, needle, 1, true)
	if not i then
		error(`{where} does not say: {needle}`, 2)
	end
	return i
end
-- every run of whitespace becomes one space, and the ends are trimmed
local function norm(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "%s+", " "), "^ ", ""), " $", ""))
end
-- the text of the `## <prefix>` section, up to the next `## ` heading
local function section(text: string, prefix: string, where: string): string
	local start = string.find("\n" .. text, "\n## " .. prefix, 1, true)
	if not start then
		error(`{where} has no "## {prefix}" section`, 2)
	end
	local body = string.sub("\n" .. text, start + 1)
	local after = string.find(body, "\n## ", 4, true)
	return string.sub(body, 1, if after then after - 1 else #body)
end
-- the line of `text` that starts with `prefix`
local function lineStarting(text: string, prefix: string, where: string): string
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, #prefix) == prefix then
			return line
		end
	end
	error(`{where} has no line starting {prefix}`, 2)
end

-- the issue's own statement.md: the sequestered spec's issue folder, then where the item goes after
local function statement(): string
	for _, state in { "", "active/", "done/" } do
		local rel = `z-nile/.tracker/issues/{state}c0316/statement.md`
		if fs.isFile(`{TOP}/{rel}`) then
			return read(rel)
		end
	end
	error("c0316's statement.md is in none of z-nile/.tracker/issues/{,active/,done/}c0316/", 2)
end
-- from "**z-nile's goals, in order." to the end of the "**Measure.**" paragraph
local function statementBlock(): string
	local text = statement()
	local from = at(text, "**z-nile's goals, in order.", "statement.md")
	local measure = at(text, "**Measure.**", "statement.md")
	local stop = string.find(text, "\n\n", measure, true) or #text + 1
	return string.sub(text, from, stop - 1)
end

local FOLLOWING =
	"The tracker sees an escape as a review finding marked with an earlier stage, a redesign after approval, a stop of a started raft, or an issue that reworks a merged one (zz-rules, Items); a recorded question is c0321's."
local AGENTS_SENTENCE =
	"What the system is for, in order, and what an escape is: `z-nile/README.md`, Goals; an agent never skips or shortens a check a design or a skill requires, only the human does."
local LESSONS_SENTENCE =
	"An escape (z-nile/README.md, Goals: a mistake found at a later stage than the one that made it) always leaves a lesson or a stated `one-off`, and work with an unharvested escape does not land."
local RULES_ESCAPE =
	"An escape the tracker sees outside a review (z-nile/README.md, Goals) has its own entry: `- escape redesign <n> (<stage>): <lesson ids>` for approval `<n>` of the item (2 or more), `- escape stop <n> (<stage>): …` in a raft's ledger for its stop `<n>` after it started, and `- escape rework 1 (<stage>): …` in an item with `reworks:`; `<stage>` is `idea`, `design` or `implementation`, the stage whose work held the mistake, and the target may be `one-off: <reason>`. A review finding names its stage in the review (`Stage:`), and one that names an earlier stage than its review's is an escape. `./zn status <id> prepared`, `./zn ready` (a stop) and `./zn done` refuse while one has no entry."
local RULES_ROW_END = "; `--uncovered` also lists an escape with no entry, and an unmarked finding"
local REVIEW_STAGE =
	"Stage: <idea | design | implementation: the stage whose work holds the mistake; an earlier stage than this review's is an escape>"
local REVIEW_ITEM10 =
	"Challenge every `one-off` in the item's `harvest.md` whose reason does not hold, and every escape entry (`- escape …`) whose stage or lesson does not fit what happened. Raise a high finding when the documents, the Verification log or the pull request show a check a design or a skill requires was skipped or shortened and no ruling of the user is quoted for it: only the human shortens a check (z-nile/README.md, Goals)."
local REVIEW_FINAL4 = "4. **Escapes**: design mode's item 10, on the raft's and its members' `harvest.md`."
local STATS_ESCAPES = "**escapes** (made in which stage, found at which; the target is none after a merge)"
local STATS_HISTORY = string.lower("the 20% target is history (z-nile/README.md, Goals)")
local TICKET_REWORKS =
	"`reworks: <id>` when the issue corrects something already merged (any type: a defect of a game, a chore that fixes the tooling)"

-- the real skill folders, every project's (never through the .claude/skills links), as repository-relative folders
local function skillDirs(): { string }
	local out: { string } = {}
	for _, folder in skills.folders(projects.load(TOP)) do
		local names = fs.readDir(`{TOP}/{folder.path}`)
		table.sort(names)
		for _, name in names do
			table.insert(out, `{folder.path}/{name}`)
		end
	end
	return out
end

return t.spec("c0316 the documents carry the goals and their pointers", function(it)
	it(
		"AC1: the README's Goals section is statement.md's statement word for word, after the opening paragraph and before How it should work",
		function()
			local readme = read("z-nile/README.md")
			local block = norm(statementBlock())
			local goals = section(readme, "Goals", "z-nile/README.md")
			local body = norm((string.gsub(goals, "^## Goals[^\n]*\n", ""))) -- the section without its heading
			t.expect(string.sub(body, 1, #block)).toBe(block) -- word for word, from its first sentence
			-- the one sentence after it, outside the quoted text
			local rest = norm(string.sub(body, #block + 1))
			t.expect(rest).toBe(FOLLOWING)
			-- the place: after the opening paragraph, before How it should work
			local opening = at(readme, "z-nile is the tooling that tracks", "z-nile/README.md")
			local heading = at(readme, "\n## Goals", "z-nile/README.md")
			local how = at(readme, "\n## How it should work", "z-nile/README.md")
			t.expect(opening < heading).toBe(true)
			t.expect(heading < how).toBe(true)
		end
	)

	it(
		"AC1: AGENTS.md, every skill's Lessons section, zz-rules, zz-review, zz-stats, z-ticket and the issue template carry their texts",
		function()
			-- AGENTS.md: the last sentence of the Non-negotiable paragraph
			local agents = read("AGENTS.md")
			local paragraph = lineStarting(agents, "**Non-negotiable:**", "AGENTS.md")
			t.expect(string.sub(paragraph, -#AGENTS_SENTENCE)).toBe(AGENTS_SENTENCE)

			-- every skill's Lessons section opens its second paragraph with the escape sentence
			local n = 0
			for _, dir in skillDirs() do
				local doc = `{TOP}/{dir}/SKILL.md`
				if not fs.isFile(doc) then
					continue
				end
				n += 1
				local s = section(fs.readFile(doc), "Lessons", dir)
				local paragraphs = string.split(s, "\n\n")
				t.expect(#paragraphs >= 2).toBe(true)
				local second = paragraphs[2]
				if string.sub(second, 1, #LESSONS_SENTENCE + 1) ~= LESSONS_SENTENCE .. " " then
					error(
						`{dir}: the Lessons section's second paragraph does not open with the escape sentence`
					)
				end
				at(second, "A new lesson (from a review finding", dir) -- the rest of the paragraph is unchanged
			end
			t.expect(n >= 11).toBe(true)

			-- zz-rules: the escape entry after "A note covers no finding.", and the lessons row of the commands table
			local rules = read("z-nile/skills/zz-rules/SKILL.md")
			local note = at(rules, "A note covers no finding.", "zz-rules")
			local escape = at(rules, RULES_ESCAPE, "zz-rules")
			t.expect(note < escape).toBe(true)
			t.expect(escape - note <= #"A note covers no finding. " + 1).toBe(true) -- right after it
			local row = lineStarting(rules, "| lessons |", "zz-rules")
			t.expect(string.sub(row, -#RULES_ROW_END - 2)).toBe(RULES_ROW_END .. " |")

			-- zz-review: the template's Stage line, item 10 and the Final mode's last item
			local review = read("z-nile/skills/zz-review/SKILL.md")
			local recommendation = at(review, "\nRecommendation: ", "zz-review")
			local stage = at(review, `\n{REVIEW_STAGE}`, "zz-review")
			local lesson = at(review, "\nLesson: <skill>/<slug>", "zz-review")
			t.expect(recommendation < stage and stage < lesson).toBe(true)
			local item10 = lineStarting(review, "10. **Lessons**", "zz-review")
			at(item10, REVIEW_ITEM10, "zz-review item 10")
			local finalMode = string.sub(review, at(review, "## Final mode", "zz-review"))
			local three = at(finalMode, "\n3. **Judge substance**", "zz-review Final mode")
			local four = at(finalMode, `\n{REVIEW_FINAL4}`, "zz-review Final mode")
			t.expect(three < four).toBe(true)
			-- items 10 and 11 keep their numbers (c0119/scope-docs pins them)
			lineStarting(review, "11. **Scope fidelity**", "zz-review")

			-- zz-stats: the report names the escapes, and the 20% line is history
			local stats = read("z-nile/skills/zz-stats/SKILL.md")
			at(stats, STATS_ESCAPES, "zz-stats")
			at(string.lower(stats), STATS_HISTORY, "zz-stats") -- the design gives it lowercase; the sentence may start with a capital
			t.expect(has(stats, "is **under 20%** on all three")).toBe(false)

			-- z-ticket: step 3 names reworks:
			local ticket = read("z-nile/skills/z-ticket/SKILL.md")
			local step3 = lineStarting(ticket, "3. **Fill in the frontmatter**", "z-ticket")
			at(step3, TICKET_REWORKS, "z-ticket step 3")

			-- the issue template: a reworks line after depends_on
			local template = read("z-nile/templates/issue/doc.md")
			local depends = at(template, "\ndepends_on:", "the issue template")
			local reworks = at(template, "\nreworks: ", "the issue template")
			t.expect(depends < reworks).toBe(true)
			t.expect(has(string.sub(template, depends + 1, reworks), "emergent:")).toBe(false) -- right after it
		end
	)

	it("AC1: the first lesson exists and parses", function()
		local rel = "z-nile/skills/zz-rules/lessons/asked-means-wait.md"
		t.expect(fs.isFile(`{TOP}/{rel}`)).toBe(true)
		local lesson, err = lessons.parse("zz-rules/asked-means-wait", read(rel))
		if not lesson then
			error(`{rel} does not parse: {err or "?"}`)
		end
		t.expect(lesson.id).toBe("zz-rules/asked-means-wait")
	end)
end)
