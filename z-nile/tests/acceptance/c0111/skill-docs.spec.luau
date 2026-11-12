--!strict
-- c0111 AC6: every skill ends with the same role-based paragraph on new lessons (a subagent reports, a prep or
-- raft lead writes, any other lead captures an issue) and says to search lessons when one might cover the next step;
-- ticket-prep and execute-raft harvest the review; review, tracker, ready-raft, metrics, AGENTS.md and the prompt
-- template say what c0111's Design specifies. Reads the real files; writes nothing.
local fs = require("@lune/fs")
local projects = require("@znile/engine/projects")
local skills = require("@znile/engine/skills")
local t = require("@tests/lib/t")
-- c0120 override: specs run from their project's home (z-nile/); the repository's files are read from the checkout's top
local TOP = (
	string.gsub(require("@lune/process").exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
)

-- c0184 override: the skills' folders come from the one reader of them, over the registry's projects
local function skillBases(top: string): { string }
	local out: { string } = {}
	for _, folder in skills.folders(projects.load(top)) do
		table.insert(out, folder.path)
	end
	return out
end
-- c0115 override: the skills' real folders, every project's (never through the .claude/skills links), as
-- repository-relative folders ("z-nile/skills/zz-rules")
local function skillDirs(): { string }
	local out = {}
	for _, base in skillBases(TOP) do
		local names = fs.readDir(`{TOP}/{base}`)
		table.sort(names)
		for _, name in names do
			table.insert(out, `{base}/{name}`)
		end
	end
	return out
end

local function read(path: string): string
	return fs.readFile(path)
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

return t.spec("c0111 skills search lessons and route new ones by role", function(it)
	it("every skill ends with the same Lessons paragraph and the three roles", function()
		local first: string? = nil
		local n = 0
		for _, dir in skillDirs() do
			local doc = `{TOP}/{dir}/SKILL.md`
			if fs.isFile(doc) then
				n += 1
				local s = section(read(doc), "Lessons")
				at(
					s,
					"Search with `./zn lessons <terms>` when you are about to do something a lesson might cover."
				)
				t.expect(string.find(s, "--full", 1, true) == nil).toBe(true)
				at(s, "- **A subagent** (")
				at(s, "never writes a lesson file or runs `./zn new`")
				at(
					s,
					"- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md`"
				)
				at(s, "as `- note <what happened>: <lesson ids>`")
				at(s, "- **Any other lead** (")
				at(s, "./zn new issue c lesson-")
				t.expect(string.find(s, "never writes a lesson file itself", 1, true) == nil).toBe(true)
				if first == nil then
					first = s
				else
					t.expect(s).toBe(first) -- one paragraph, not one variant per skill
				end
			end
		end
		t.expect(n >= 11).toBe(true)
	end)

	it(
		"ticket-prep: search lessons before the review, harvest the one answer, confirm before prepared",
		function() -- c0116 override: z-design works on one issue, so its commands take <id>, not <R-id>
			local s5 = section(read(`{TOP}/z-nile/skills/z-design/SKILL.md`), "5.")
			t.expect(string.find(s5, "lessons --when design --full", 1, true) == nil).toBe(true)
			t.expect(at(s5, "Search with `./zn lessons <terms>`") < at(s5, "`design: reviewed`")).toBe(true)
			local three, four = at(s5, "\n3. "), at(s5, "\n4. ")
			local harvest = at(s5, "harvest.md")
			t.expect(harvest > three and harvest < four).toBe(true) -- in the answering step
			local rerun = at(s5, "rerun `./zn promote-check <id>`")
			t.expect(rerun > three and rerun < four).toBe(true)
			t.expect(
				at(s5, "first harvest anything `./zn lessons --uncovered <id>` still lists")
					< at(s5, "status <id> prepared`")
			).toBe(true)
			t.expect(at(s5, "lessons --uncovered <id>") < at(s5, "status <id> prepared`")).toBe(true)
			at(s5, "lessons --check")
		end
	)

	it(
		"execute-raft: streams report lessons, the lead writes and harvests each round, and confirms before done",
		function()
			local text = read(`{TOP}/z-nile/skills/zz-execute/SKILL.md`)
			local p2b = section(text, "Phase 2B")
			t.expect(at(p2b, "a candidate lesson goes in the final report too") < at(p2b, "\n3. ")).toBe(true) -- in the brief
			-- written as each report or stream review arrives, before step 1, so no later path can skip them
			t.expect(at(p2b, "**Candidate lessons are written as they arrive**") < at(p2b, "\n1. "))
				.toBe(true)
			at(p2b, "`- note ws-<issue>: <lesson ids>`")
			at(p2b, "`- note stream-review-<issue>-NNN: <lesson ids>`")
			local p4 = section(text, "Phase 4")
			t.expect(at(p4, "harvest.md") < at(p4, "\n6. ")).toBe(true) -- before the human, the one answer's harvest
			local p5 = section(text, "Phase 5")
			-- the confirmation harvests what is still uncovered (a raft prepped before lessons existed) before checking
			t.expect(
				at(p5, "first harvest anything `./zn lessons --uncovered R0010` still lists")
					< at(p5, "./zn done")
			).toBe(true)
			t.expect(at(p5, "lessons --uncovered") < at(p5, "./zn done")).toBe(true)
			at(p5, "lessons --check")
		end
	)

	it("review checks lessons in both modes, and a finding may name the lesson it repeats", function()
		local text = read(`{TOP}/z-nile/skills/zz-review/SKILL.md`)
		local design = section(text, "Design mode")
		at(design, "\n10. **Lessons**")
		at(design, "Search with `./zn lessons <terms>`")
		t.expect(string.find(design, "lessons --when design --full", 1, true) == nil).toBe(true)
		at(design, "judge the lessons the author added")
		at(section(text, "Code mode"), "Search with `./zn lessons <terms>`")
		local template = string.match(text, "```markdown\n(# Review NNN.-)```") :: string
		t.expect(at(template, "\nLesson:") > at(template, "\nRecommendation:")).toBe(true)
	end)

	it(
		"the tracker, ready-raft and metrics skills, AGENTS.md and the prompt template know lessons",
		function()
			local tracker = read(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
			t.expect(string.find(tracker, "\n| lessons | `./zn lessons", 1, true) ~= nil).toBe(true)
			at(tracker, "harvest.md")
			at(tracker, "`- note <text>: <lesson ids>`")
			at(section(tracker, "Worktrees"), "`lessons`") -- it may run in the main checkout
			at(read(`{TOP}/z-nile/skills/z-ready/SKILL.md`), "Lessons are not listed")
			at(read(`{TOP}/z-nile/skills/zz-stats/SKILL.md`), "./zn lessons")
			-- c0120 override: the spec runs from its home: the checkout's files are read from the top
			local agents = read(`{TOP}/AGENTS.md`)
			at(agents, "lessons/")
			at(agents, "./zn lessons")
			at(agents, "capture a new lesson as an issue")
			t.expect(string.find(agents, "records new ones when it finishes", 1, true) == nil).toBe(true)
			local prompt = read(`{TOP}/z-nile/templates/prompt.md`) -- c0120 override: read from the checkout's top
			at(
				prompt,
				"Search with `./zn lessons <terms>` when you are about to do something a lesson might cover."
			)
			t.expect(string.find(prompt, "{{LESSONS}}", 1, true) == nil).toBe(true)
			t.expect(string.find(prompt, "\n## Work items", 1, true) == nil).toBe(true)
			t.expect(at(prompt, "\n## Skills") < at(prompt, "{{SKILLS}}")).toBe(true)
		end
	)
end)
